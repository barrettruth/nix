{ config, pkgs, ... }:
let
  username = config.barrett.user.name;
  group = "staff";
  runAsUser = "/usr/bin/sudo -u ${username} --";
in
{
  _module.args.act = {
    inherit runAsUser group;

    mkSymlink = target: link: ''
      ${runAsUser} ${pkgs.coreutils}/bin/ln -sfnT "${target}" "${link}"
    '';

    installDir = dir: ''
      ${pkgs.coreutils}/bin/install -d -o ${username} -g ${group} "${dir}"
    '';

    installDirMode = mode: dir: ''
      ${pkgs.coreutils}/bin/install -d -m ${mode} -o ${username} -g ${group} "${dir}"
    '';
  };
}
