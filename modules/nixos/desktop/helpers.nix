{ hostConfig, pkgs }:
let
  inherit (hostConfig)
    username
    homeDirectory
    XDG_CONFIG_HOME
    XDG_DATA_HOME
    XDG_STATE_HOME
    XDG_CACHE_HOME
    ;
  repo = "${XDG_CONFIG_HOME}/nix";
  runUser = "${pkgs.util-linux}/bin/runuser -u ${username} --";
in
{
  inherit
    username
    homeDirectory
    XDG_CONFIG_HOME
    XDG_DATA_HOME
    XDG_STATE_HOME
    XDG_CACHE_HOME
    repo
    runUser
    ;

  mkSymlink = target: link: ''
    ${runUser} ${pkgs.coreutils}/bin/ln -sfnT "${target}" "${link}"
  '';

  mkMutableConfig = source: target: ''
    if [ -L "${target}" ]; then
      targetPath="$(readlink -f "${target}" || true)"
      sourcePath="$(readlink -f "${source}")"
      if [ "$targetPath" = "$sourcePath" ]; then
        rm -f "${target}"
        install -Dm600 -o ${username} -g users "${source}" "${target}"
      fi
    elif [ ! -e "${target}" ]; then
      install -Dm600 -o ${username} -g users "${source}" "${target}"
    fi
  '';

  mkDir = dir: ''
    install -d -o ${username} -g users "${dir}"
  '';

  readTheme = ''
    theme="$(cat "${XDG_STATE_HOME}/theme" 2>/dev/null)" || theme="midnight"
    [ -z "$theme" ] && theme="midnight"
  '';
}
