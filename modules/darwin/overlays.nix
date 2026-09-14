[
  (_: prev: {
    ghostty = prev.ghostty-bin;
    ivpn-bin = prev.callPackage ../../pkgs/ivpn-bin { };
    ungoogled-chromium = prev.callPackage ../../pkgs/ungoogled-chromium-bin { };
  })
]
