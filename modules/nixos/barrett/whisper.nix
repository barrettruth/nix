{
  config,
  pkgs,
  lib,
  act,
  ...
}:
let
  cfg = config.barrett.whisper;
  user = config.barrett.user;
  XDG_DATA_HOME = "${user.homeDirectory}/.local/share";
  whisper = pkgs.whisper-cpp.override { cudaSupport = true; };
in
{
  options.barrett.whisper.enable = lib.mkEnableOption "Whisper dictation server";

  config = lib.mkIf cfg.enable {
    users.users.${user.name}.packages = [ whisper ];

    systemd.user.services.whisper-dictation = {
      description = "Whisper dictation server";
      unitConfig.ConditionPathExists = "${XDG_DATA_HOME}/whisper-models/ggml-large-v3-turbo-q5_0.bin";
      serviceConfig = {
        Type = "simple";
        ExecStart = "${whisper}/bin/whisper-server --model ${XDG_DATA_HOME}/whisper-models/ggml-large-v3-turbo-q5_0.bin --host 127.0.0.1 --port 8178";
      };
    };

    system.activationScripts.barrettWhisperConfig.text = ''
      ${act.installDir "${XDG_DATA_HOME}/whisper-models"}
    '';
  };
}
