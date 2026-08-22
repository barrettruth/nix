# imc: Google MCP setup

One-off. Delete this file once imc is working.

Brings gmail, gdrive and gcalendar MCP servers up on imc. Run every command **on
imc** unless a step says otherwise.

Refresh tokens are minted locally on imc and never leave the machine that owns
them. The only things copied from `mac` are the OAuth *client* files, which
Google classifies as non-confidential for Desktop-type clients.

## 0. On mac, not imc

Enable inbound ssh, and turn it back off when this is done:

    System Settings > General > Sharing > Remote Login

`mac` is `100.64.0.4` on the tailnet.

## 1. Rebuild first

Activation creates `~/.config/devin`, which step 3 writes into.

    just rebuild-imc

## 2. Pull the OAuth client files from mac

    mkdir -p ~/.gmail-mcp ~/.config/mcp-google ~/.config/mcp-gdrive \
             ~/.config/google-calendar-mcp

    scp mac:.gmail-mcp/gcp-oauth.keys.json            ~/.gmail-mcp/
    scp mac:.config/mcp-google/client_id              ~/.config/mcp-google/
    scp mac:.config/mcp-google/client_secret          ~/.config/mcp-google/
    scp mac:.config/mcp-google/gcp-oauth.keys.json    ~/.config/mcp-google/
    scp mac:.config/mcp-gdrive/gcp-oauth.keys.json    ~/.config/mcp-gdrive/
    scp mac:.config/devin/mcp_config.json             ~/.config/devin/

    chmod 600 ~/.gmail-mcp/* ~/.config/mcp-google/* ~/.config/mcp-gdrive/* \
              ~/.config/devin/mcp_config.json

Do **not** copy `credentials.json`, `.gdrive-server-credentials.json` or
`tokens.json`. Those are the refresh tokens; step 4 mints imc's own.

## 3. Write the minting script

    cat > /tmp/gauth.py <<'PYEOF'
    #!/usr/bin/env python3
    """usage: gauth.py <out.json> <scope> [scope ...]"""
    import http.server, json, os, sys, time
    import urllib.error, urllib.parse, urllib.request

    KEYS = os.path.expanduser("~/.gmail-mcp/gcp-oauth.keys.json")
    REDIRECT = "http://localhost:3000/oauth2callback"
    out, scopes = os.path.expanduser(sys.argv[1]), " ".join(sys.argv[2:])
    k = json.load(open(KEYS))["installed"]
    CID, CSEC = k["client_id"], k["client_secret"]

    print("\nOpen this URL:\n")
    print("https://accounts.google.com/o/oauth2/v2/auth?" + urllib.parse.urlencode({
        "client_id": CID, "redirect_uri": REDIRECT, "response_type": "code",
        "scope": scopes, "access_type": "offline", "prompt": "consent"}))
    print(f"\n-> {out}\nWaiting on :3000 ...\n", flush=True)
    res = {}

    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            u = urllib.parse.urlparse(self.path)
            if not u.path.startswith("/oauth2callback"):
                self.send_response(404); self.end_headers(); return
            q = urllib.parse.parse_qs(u.query)
            self.send_response(200); self.end_headers()
            if "error" in q:
                res["error"] = q["error"][0]
                self.wfile.write(b"Error - check terminal."); return
            body = urllib.parse.urlencode({
                "code": q["code"][0], "client_id": CID, "client_secret": CSEC,
                "redirect_uri": REDIRECT, "grant_type": "authorization_code"}).encode()
            try:
                with urllib.request.urlopen(urllib.request.Request(
                        "https://oauth2.googleapis.com/token", data=body)) as r:
                    t = json.load(r)
            except urllib.error.HTTPError as e:
                res["error"] = e.read().decode()[:400]
                self.wfile.write(b"Token exchange failed - check terminal."); return
            res["ok"] = {
                "access_token": t["access_token"],
                "refresh_token": t.get("refresh_token"),
                "scope": t.get("scope"),
                "token_type": t.get("token_type", "Bearer"),
                "expiry_date": int(time.time() * 1000)
                               + int(t.get("expires_in", 3600)) * 1000}
            self.wfile.write(b"Authenticated. Close this tab.")
        def log_message(self, *a): pass

    srv = http.server.HTTPServer(("127.0.0.1", 3000), H)
    while not res:
        srv.handle_request()
    if "error" in res:
        print("FAILED:", res["error"]); raise SystemExit(1)
    c = res["ok"]
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump(c, open(out, "w")); os.chmod(out, 0o600)
    print("SUCCESS")
    print("  refresh_token:", "PRESENT" if c["refresh_token"] else "*** MISSING ***")
    print("  scope        :", c["scope"])
    PYEOF

## 4. Mint the credentials

Each run prints a URL, waits on `:3000`, and writes the credential when you
finish in the browser. Expect **"Google hasn't verified this app"** →
**Advanced** → **Go to … (unsafe)**. `refresh_token: PRESENT` is the success
condition; `MISSING` means the grant is not durable and something is wrong.

Run them one at a time — they all bind port 3000.

Gmail. Read-only is the recommended scope on a corporate-managed machine; see
the note at the bottom before choosing:

    python3 /tmp/gauth.py ~/.gmail-mcp/credentials.json \
        'https://www.googleapis.com/auth/gmail.readonly'

Drive:

    python3 /tmp/gauth.py ~/.config/mcp-gdrive/.gdrive-server-credentials.json \
        'https://www.googleapis.com/auth/drive' \
        'https://www.googleapis.com/auth/spreadsheets'

Calendar, which needs reshaping afterwards because its store is keyed by account
nickname:

    python3 /tmp/gauth.py /tmp/cal_raw.json \
        'https://www.googleapis.com/auth/calendar' \
        'https://www.googleapis.com/auth/calendar.events'

    python3 - <<'EOF'
    import json, os
    raw = json.load(open('/tmp/cal_raw.json'))
    p = os.path.expanduser('~/.config/google-calendar-mcp/tokens.json')
    json.dump({"normal": raw}, open(p, 'w'))
    os.chmod(p, 0o600)
    print('calendar written, scope:', raw['scope'])
    EOF

    rm -f /tmp/cal_raw.json /tmp/gauth.py

## 5. Verify

In a Devin session on imc, call `list_email_labels`, `gdrive_search` and
`list-calendars`. If one reports `invalid_grant`, the server is holding a stale
credential from startup — kill it and let Devin respawn:

    pkill -f server-gmail-autoauth
    pkill -f mcp-gdrive
    pkill -f google-calendar-mcp

## 6. Clean up

Turn Remote Login back off on mac, then delete this file and commit the deletion.

## Why the scopes look like this

Every Gmail scope is **restricted**, Google's strictest tier. The OAuth app is
External and unverified, so it relies on the personal-use click-through — which
permits exactly **one restricted scope per grant**. Two (`mail.google.com +
gmail.settings.basic`) makes the consent screen return a bare HTTP 500. Sensitive
scopes do not count against that limit, which is why Calendar takes two and Drive
pairs restricted `drive` with sensitive `spreadsheets`.

If a consent screen 500s, that is the cause. It is not an outage.

`https://mail.google.com/` is full mailbox access, including permanent delete,
and the token does not expire. On a corporate-managed device that means disk
imaging, MDM and IT recovery all reach your personal mail. `gmail.readonly`
above keeps the blast radius small. Use `https://mail.google.com/` only if you
genuinely need to send or delete from imc, and understand the tradeoff.
