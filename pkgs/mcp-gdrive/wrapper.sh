config="${XDG_CONFIG_HOME:-$HOME/.config}"

CLIENT_ID="$(cat "$config/mcp-google/client_id")"
CLIENT_SECRET="$(cat "$config/mcp-google/client_secret")"
GDRIVE_CREDS_DIR="$config/mcp-gdrive"
export CLIENT_ID CLIENT_SECRET GDRIVE_CREDS_DIR

exec @mcpGdrive@/bin/mcp-gdrive "$@"
