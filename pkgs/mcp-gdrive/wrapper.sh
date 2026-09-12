umask 077

config="${XDG_CONFIG_HOME:-$HOME/.config}"
credentials="${GOOGLE_OAUTH_CREDENTIALS:-$config/mcp-gtasks/oauth.json}"

CLIENT_ID="$(jq -er '(.installed // .web).client_id | strings | select(length > 0)' "$credentials")"
CLIENT_SECRET="$(jq -er '(.installed // .web).client_secret | strings | select(length > 0)' "$credentials")"
GDRIVE_CREDS_DIR="${GDRIVE_CREDS_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mcp-gdrive}"
export CLIENT_ID CLIENT_SECRET GDRIVE_CREDS_DIR

exec @mcpGdrive@/bin/mcp-gdrive "$@"
