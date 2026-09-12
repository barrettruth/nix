{
  buildNpmPackage,
  fetchFromGitHub,
  lib,
  writeShellApplication,
}:
let
  upstream = buildNpmPackage {
    pname = "mcp-gtasks";
    version = "0.2.0";

    src = fetchFromGitHub {
      owner = "scottie-will";
      repo = "google-tasks-mcp";
      rev = "b35577dbe66079c787710dd0cd14d3c54c47a16c";
      hash = "sha256-lNE8FIMJPoxyG//w7DAMkuC4A3N7rQlcXWcnooaI95U=";
    };

    patches = [ ./hardening.patch ];

    npmDepsFetcherVersion = 2;
    npmDepsHash = "sha256-yPIhw0Px3LFJfmecJFYaF7SzuPhETwdzavngRrgkseM=";
  };
in
writeShellApplication {
  name = "mcp-gtasks";
  text = lib.replaceStrings [ "@mcpGtasks@" ] [ "${upstream}" ] (builtins.readFile ./wrapper.sh);

  meta = {
    description = "MCP server for Google Tasks";
    homepage = "https://github.com/scottie-will/google-tasks-mcp";
    license = lib.licenses.mit;
    mainProgram = "mcp-gtasks";
  };
}
