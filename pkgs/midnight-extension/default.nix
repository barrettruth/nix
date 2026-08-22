{
  lib,
  runCommand,
  jq,
  themeCss,
  themeJs,
  version,
  updateUrl ? null,
}:

let
  source = lib.cleanSourceWith {
    src = ../../config/chromium/extension;
    filter = path: _: !(lib.hasSuffix "/theme.css" path || lib.hasSuffix "/theme.js" path);
  };
in
runCommand "midnight-extension-${version}"
  {
    nativeBuildInputs = [ jq ];
  }
  ''
    cp -R --no-preserve=mode,ownership ${source} $out
    install -m 0644 ${themeCss} $out/theme.css
    install -m 0644 ${themeJs} $out/theme.js

    edit() {
      jq "$@" $out/manifest.json >$out/manifest.json.tmp
      mv $out/manifest.json.tmp $out/manifest.json
    }

    edit --arg version ${lib.escapeShellArg version} '.version = $version'

    ${lib.optionalString (updateUrl != null) ''
      edit --arg url ${lib.escapeShellArg updateUrl} '.update_url = $url'
    ''}
  ''
