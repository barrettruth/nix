{
  applyPatches,
  buildNpmPackage,
  fetchFromGitHub,
  lib,
  writeShellApplication,
}:
let
  upstream = buildNpmPackage {
    pname = "mcp-gdrive";
    version = "0.2.0";

    src = applyPatches {
      name = "mcp-gdrive-source";
      src = fetchFromGitHub {
        owner = "isaacphi";
        repo = "mcp-gdrive";
        rev = "bd79fde46faff9e3d520b4a42ea787cfd7ab026c";
        hash = "sha256-CapRi/ylb2RRSIqf1xPcWFw74oHksDdYqfddKgGYlyA=";
      };
      patches = [ ./package-lock.patch ];
    };

    npmDepsFetcherVersion = 2;
    npmDepsHash = "sha256-/oedYVCOvEzmAvblj78VhwJNBb2v1UiDDp2jmda9xNE=";
  };
in
writeShellApplication {
  name = "mcp-gdrive";
  text = lib.replaceStrings [ "@mcpGdrive@" ] [ "${upstream}" ] (builtins.readFile ./wrapper.sh);

  meta = {
    description = "MCP server for interacting with Google Drive and Sheets";
    homepage = "https://github.com/isaacphi/mcp-gdrive";
    license = lib.licenses.mit;
    mainProgram = "mcp-gdrive";
  };
}
