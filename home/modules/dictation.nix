{
  lib,
  pkgs,
  config,
  hostConfig,
  ...
}:

let
  whisper = pkgs.whisper-cpp.override { cudaSupport = hostConfig.gpu == "nvidia"; };
  modelDir = "${config.home.homeDirectory}/.local/share/whisper-models";
  model = "ggml-medium.bin";
  modelUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${model}";
in
{
  home.packages = [ whisper ];

  home.activation.downloadWhisperModel = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -f "${modelDir}/${model}" ]; then
      run mkdir -p "${modelDir}"
      run ${pkgs.curl}/bin/curl -L -o "${modelDir}/${model}" "${modelUrl}"
    fi
  '';
}
