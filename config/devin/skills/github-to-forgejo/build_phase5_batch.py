#!/usr/bin/env python3
# usage: build_phase5_batch.py <repo-name> > batch-payload.json
# stderr emits report fields: ports=N drops_no_eq=N drops_flag_workflow=N drops_flag_review=N
#
# Reference implementation for `github-to-forgejo` skill v5.0+ Phase 5a (port) + 5c (delete).
# Run from the local clone's root. If no local clone, falls back to enumerating via gh api.
# Validated 2026-04-30 against diffs.nvim, tmux-mosaic, http-codes.nvim, midnight.nvim, blink-cmp-tmux.

import base64, json, os, subprocess, sys

repo = sys.argv[1]
fj_owner = "barrettruth"
fj_path = f"/repos/{fj_owner}/{repo}"

PORT_RULES = [
    (lambda p: p.startswith(".github/ISSUE_TEMPLATE/"),
       lambda p: f".forgejo/issue_template/{os.path.basename(p)}"),
    (lambda p: p == ".github/pull_request_template.md",
       lambda p: ".forgejo/pull_request_template.md"),
    (lambda p: p.startswith(".github/PULL_REQUEST_TEMPLATE/") and p.endswith(".md"),
       lambda p: f".forgejo/pull_request_template/{os.path.basename(p)}"),
    (lambda p: p == ".github/FUNDING.yml",
       lambda p: ".forgejo/FUNDING.yml"),
    (lambda p: p == ".github/CODEOWNERS",
       lambda p: ".forgejo/CODEOWNERS"),
    (lambda p: p == ".github/CONTRIBUTING.md",
       lambda p: "CONTRIBUTING.md"),
    (lambda p: p == ".github/SECURITY.md",
       lambda p: "SECURITY.md"),
]

DROP_NO_FJ_EQ = [
    lambda p: p.startswith(".github/DISCUSSION_TEMPLATE/"),
    lambda p: p == ".github/dependabot.yml",
    lambda p: p == ".github/release.yml",
    lambda p: p in (".github/workflows/quality.yaml", ".github/workflows/quality.yml",
                    ".github/workflows/format.yaml",  ".github/workflows/format.yml",
                    ".github/workflows/lint.yaml",    ".github/workflows/lint.yml",
                    ".github/workflows/test.yaml",    ".github/workflows/test.yml"),
]

def is_non_quality_workflow(p):
    return (p.startswith(".github/workflows/") and p.endswith((".yml", ".yaml"))
            and not any(rule(p) for rule in DROP_NO_FJ_EQ))

def classify(path):
    for matches, dst_fn in PORT_RULES:
        if matches(path):
            return ("port", dst_fn(path))
    if any(rule(path) for rule in DROP_NO_FJ_EQ):
        return ("drop_no_eq", None)
    if is_non_quality_workflow(path):
        return ("drop_flag_workflow", None)
    return ("drop_flag_review", None)

if os.path.isdir(".github"):
    local_files = []
    for root, _, names in os.walk(".github"):
        for n in names:
            local_files.append(os.path.join(root, n))
    local_files.sort()
else:
    out = subprocess.check_output(
        ["gh", "api", f"repos/{fj_owner}/{repo}/git/trees/HEAD?recursive=1",
         "--jq", '.tree[] | select(.type == "blob" and (.path | startswith(".github/"))) | .path'],
        text=True)
    local_files = sorted(out.strip().splitlines())

fj_tree = json.loads(subprocess.check_output(
    ["tea", "api", "-l", "vps", f"{fj_path}/git/trees/main?recursive=true"], text=True))
fj_dotgithub = {n["path"]: n["sha"] for n in fj_tree["tree"]
                if n["type"] == "blob" and n["path"].startswith(".github/")}

files = []
report = {"ports": [], "drops_no_eq": [], "drops_flag_workflow": [], "drops_flag_review": []}

for src in local_files:
    cls, dst = classify(src)
    if cls == "port":
        with open(src, "rb") as f:
            content_b64 = base64.b64encode(f.read()).decode()
        try:
            existing = json.loads(subprocess.check_output(
                ["tea", "api", "-l", "vps", f"{fj_path}/contents/{dst}"], text=True,
                stderr=subprocess.DEVNULL))
            entry = {"operation": "update", "path": dst, "content": content_b64, "sha": existing["sha"]}
        except (subprocess.CalledProcessError, json.JSONDecodeError, KeyError):
            entry = {"operation": "create", "path": dst, "content": content_b64}
        files.append(entry)
        report["ports"].append(f"{src} -> {dst}")
    elif cls == "drop_no_eq":
        report["drops_no_eq"].append(src)
    elif cls == "drop_flag_workflow":
        report["drops_flag_workflow"].append(src)
    elif cls == "drop_flag_review":
        report["drops_flag_review"].append(src)

for path, sha in sorted(fj_dotgithub.items()):
    files.append({"operation": "delete", "path": path, "sha": sha})

payload = {
    "message": "ci(forgejo): port .github/ to .forgejo/ + drop .github/",
    "branch": "main",
    "files": files,
}
json.dump(payload, sys.stdout, indent=2)

print(f"\nports: {len(report['ports'])}", file=sys.stderr)
for p in report["ports"]: print(f"  + {p}", file=sys.stderr)
print(f"drops (no fj eq): {len(report['drops_no_eq'])}", file=sys.stderr)
for p in report["drops_no_eq"]: print(f"  - {p}", file=sys.stderr)
print(f"drops (FLAG: non-quality workflow): {len(report['drops_flag_workflow'])}", file=sys.stderr)
for p in report["drops_flag_workflow"]: print(f"  - {p} (see AGENTS 'Non-quality workflow port backlog')", file=sys.stderr)
print(f"drops (FLAG: manual review): {len(report['drops_flag_review'])}", file=sys.stderr)
for p in report["drops_flag_review"]: print(f"  - {p} (skill cannot auto-decide destination)", file=sys.stderr)
print(f"deletes from .github/: {len(fj_dotgithub)}", file=sys.stderr)
