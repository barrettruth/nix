{
  lib,
  pkgs,
  config,
  hostConfig,
  whisperPkgs ? pkgs,
  ...
}:

let
  whisper = whisperPkgs.whisper-cpp.override { cudaSupport = hostConfig.gpu == "nvidia"; };
  modelDir = "${config.home.homeDirectory}/.local/share/whisper-models";
  model = "ggml-large-v3-turbo-q5_0.bin";
  modelUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${model}";
  port = "8178";
in
{
  # home.packages = [ whisper ];

  # home.activation.downloadWhisperModel = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  #   if [ ! -f "${modelDir}/${model}" ]; then
  #     run mkdir -p "${modelDir}"
  #     run ${pkgs.curl}/bin/curl -L -o "${modelDir}/${model}" "${modelUrl}"
  #   fi
  # '';

  # systemd.user.services.whisper-dictation = {
  #   Unit.Description = "Whisper dictation server";
  #   Service = {
  #     Type = "simple";
  #     ExecStart = "${whisper}/bin/whisper-server --model ${modelDir}/${model} --host 127.0.0.1 --port ${port}";
  #   };
  # };
}
