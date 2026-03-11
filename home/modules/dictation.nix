{
  lib,
  pkgs,
  config,
  hostConfig,
  whisper-dictation,
  ...
}:

let
  modelDir = "${config.home.homeDirectory}/.local/share/whisper-models";
  model = "ggml-base.bin";
  modelUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${model}";
in
{
  home.packages = [
    whisper-dictation.packages.${hostConfig.platform}.default
  ];

  home.activation.downloadWhisperModel = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -f "${modelDir}/${model}" ]; then
      run mkdir -p "${modelDir}"
      run ${pkgs.curl}/bin/curl -L -o "${modelDir}/${model}" "${modelUrl}"
    fi
  '';

  xdg.configFile."whisper-dictation/config.yaml".text = builtins.toJSON {
    whisper = {
      model = "base";
      language = "auto";
    };
    hotkey = {
      key = "KEY_DOT";
      modifiers = [ "KEY_LEFTMETA" ];
    };
  };

  systemd.user.services.whisper-dictation = {
    Unit = {
      Description = "Whisper Dictation speech-to-text daemon";
      After = [ "graphical-session.target" "ydotoold.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${whisper-dictation.packages.${hostConfig.platform}.default}/bin/whisper-dictation";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
