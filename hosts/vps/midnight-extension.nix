{
  config,
  lib,
  pkgs,
  inputs,
  identity,
  themeGenerators,
  mkSecret,
  ...
}:
let
  inherit (identity) midnight;

  host = "www.${identity.domain}";
  stateDir = "/var/lib/midnight-crx";
  crxName = "midnight.crx";

  stamp = inputs.self.lastModified;
  version = "1.${toString (stamp / 86400)}.${toString (lib.mod stamp 86400 / 2)}";

  extension = pkgs.callPackage ../../pkgs/midnight-extension {
    themeCss = pkgs.writeText "chromium-theme.css" themeGenerators.mkChromeThemeCss;
    themeJs = pkgs.writeText "chromium-theme.js" themeGenerators.mkChromeThemeJs;
    inherit version;
    inherit (midnight) updateUrl;
  };

  crx3-pack = pkgs.callPackage ../../pkgs/crx3-pack { };
in
{
  sops.secrets."midnight-crx-key" = mkSecret "midnight-crx-key" { };

  # Signing happens here rather than in a derivation because the key is the
  # extension's identity: a store path would be world readable, and losing the
  # key means every installed copy has to be reinstalled under a new id.
  systemd.services.midnight-crx = {
    description = "Sign and publish the Midnight extension CRX";
    wantedBy = [ "multi-user.target" ];
    before = [ "nginx.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StateDirectory = "midnight-crx";
      StateDirectoryMode = "0755";
      UMask = "0022";
    };
    script = ''
      ${crx3-pack}/bin/crx3-pack \
        --key ${config.sops.secrets."midnight-crx-key".path} \
        --source ${extension} \
        --output ${stateDir}/${crxName}

      cat >${stateDir}/update.xml <<'EOF'
      <?xml version='1.0' encoding='UTF-8'?>
      <gupdate xmlns='http://www.google.com/update2/response' protocol='2.0'>
        <app appid='${midnight.extensionId}'>
          <updatecheck codebase='${midnight.crxUrl}' version='${version}' />
        </app>
      </gupdate>
      EOF
    '';
  };

  services.nginx.virtualHosts.${host}.locations."/ext/" = {
    alias = "${stateDir}/";
    extraConfig = ''
      types {
        application/x-chrome-extension crx;
        application/xml xml;
      }
      # Chrome polls the update manifest every few hours and must not be told
      # to hold a stale one, or a bumped version never reaches the browser.
      add_header Cache-Control "no-cache" always;
    '';
  };
}
