{ config, pkgs, ... }:
let
  username = config.barrett.user.name;
  group = "users";
  runAsUser = "${pkgs.util-linux}/bin/runuser -u ${username} --";
in
{
  _module.args.act = {
    inherit runAsUser group;

    mkSymlink = target: link: ''
      if [ "$(${pkgs.coreutils}/bin/readlink "${link}" 2>/dev/null)" != "${target}" ]; then
        ${runAsUser} ${pkgs.coreutils}/bin/ln -sfnT "${target}" "${link}"
      fi
    '';

    installDir = dir: ''
      install -d -o ${username} -g ${group} "${dir}"
    '';

    installDirMode = mode: dir: ''
      install -d -m ${mode} -o ${username} -g ${group} "${dir}"
    '';
  };
}
