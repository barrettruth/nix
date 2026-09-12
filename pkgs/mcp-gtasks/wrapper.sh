umask 077

export GOOGLE_OAUTH_CREDENTIALS="${GOOGLE_OAUTH_CREDENTIALS:-${XDG_CONFIG_HOME:-$HOME/.config}/mcp-gtasks/oauth.json}"
export GOOGLE_TASKS_MCP_TOKEN_PATH="${GOOGLE_TASKS_MCP_TOKEN_PATH:-${XDG_STATE_HOME:-$HOME/.local/state}/mcp-gtasks/tokens.json}"

exec @mcpGtasks@/bin/google-tasks-mcp "$@"
