[
  (final: prev: {
    chromium = final.callPackage ../../pkgs/chromium-bin { };
    ghostty = prev.ghostty-bin;
  })
]
