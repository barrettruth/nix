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
      ${runAsUser} ${pkgs.coreutils}/bin/ln -sfnT "${target}" "${link}"
    '';

    installDir = dir: ''
      install -d -o ${username} -g ${group} "${dir}"
    '';

    installDirMode = mode: dir: ''
      install -d -m ${mode} -o ${username} -g ${group} "${dir}"
    '';
  };
}
