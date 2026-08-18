{
  lib,
  runCommand,
  jq,
  themeCss,
  themeJs,
  updateUrl ? null,
}:

let
  # theme.css and theme.js exist in the working tree as symlinks into the
  # store, written by activation, so they are dropped here and re-materialised
  # as real files: the CRX is a zip, which would otherwise capture the links.
  source = lib.cleanSourceWith {
    src = ../../config/chromium/extension;
    filter = path: _: !(lib.hasSuffix "/theme.css" path || lib.hasSuffix "/theme.js" path);
  };
in
runCommand "midnight-extension"
  {
    nativeBuildInputs = lib.optional (updateUrl != null) jq;
  }
  ''
    cp -R --no-preserve=mode,ownership ${source} $out
    install -m 0644 ${themeCss} $out/theme.css
    install -m 0644 ${themeJs} $out/theme.js
    ${lib.optionalString (updateUrl != null) ''
      # Chrome takes the update url for the first install from policy, but
      # every later check reads it out of the packed manifest.
      jq --arg url ${lib.escapeShellArg updateUrl} '.update_url = $url' \
        $out/manifest.json >$out/manifest.json.tmp
      mv $out/manifest.json.tmp $out/manifest.json
    ''}
  ''
