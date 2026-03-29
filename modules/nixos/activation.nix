{ pkgs, lib, config, palettes, themeGenerators, hostConfig, ... }:
let
  cfg = "/home/barrett/.config";
  repo = "/home/barrett/.config/nix";
  home = "/home/barrett";

  themes = pkgs.runCommand "theme-files" {} ''
    mkdir -p $out/fzf/themes
    mkdir -p $out/hypr/themes
    mkdir -p $out/waybar/themes
    mkdir -p $out/fuzzel/themes
    mkdir -p $out/dunst/themes
    mkdir -p $out/sioyek/themes

    cat > $out/fzf/themes/midnight << 'FZFMIDNIGHT'
    ${themeGenerators.mkFzfTheme palettes.midnight}
    FZFMIDNIGHT

    cat > $out/fzf/themes/daylight << 'FZFDAYLIGHT'
    ${themeGenerators.mkFzfTheme palettes.daylight}
    FZFDAYLIGHT

    cat > $out/hypr/themes/midnight.conf << 'HYPRMIDNIGHT'
    ${themeGenerators.mkHyprTheme palettes.midnight}
    HYPRMIDNIGHT

    cat > $out/hypr/themes/daylight.conf << 'HYPRDAYLIGHT'
    ${themeGenerators.mkHyprTheme palettes.daylight}
    HYPRDAYLIGHT

    cat > $out/waybar/themes/midnight.css << 'WAYBARMIDNIGHT'
    ${themeGenerators.mkWaybarTheme palettes.midnight}
    WAYBARMIDNIGHT

    cat > $out/waybar/themes/daylight.css << 'WAYBARDAYLIGHT'
    ${themeGenerators.mkWaybarTheme palettes.daylight}
    WAYBARDAYLIGHT

    cat > $out/fuzzel/themes/midnight.ini << 'FUZZELMIDNIGHT'
    ${themeGenerators.mkFuzzelTheme palettes.midnight}
    FUZZELMIDNIGHT

    cat > $out/fuzzel/themes/daylight.ini << 'FUZZELDAYLIGHT'
    ${themeGenerators.mkFuzzelTheme palettes.daylight}
    FUZZELDAYLIGHT

    cat > $out/dunst/themes/midnight.conf << 'DUNSTMIDNIGHT'
    ${themeGenerators.mkDunstTheme palettes.midnight}
    DUNSTMIDNIGHT

    cat > $out/dunst/themes/daylight.conf << 'DUNSTDAYLIGHT'
    ${themeGenerators.mkDunstTheme palettes.daylight}
    DUNSTDAYLIGHT

    cat > $out/sioyek/themes/midnight.config << 'SIOYEKMIDNIGHT'
    ${themeGenerators.mkSioyekTheme palettes.midnight true}
    SIOYEKMIDNIGHT

    cat > $out/sioyek/themes/daylight.config << 'SIOYEKDAYLIGHT'
    ${themeGenerators.mkSioyekTheme palettes.daylight false}
    SIOYEKDAYLIGHT
  '';

  zshInit = pkgs.writeText "zsh-init" ''
    source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    ZSH_AUTOSUGGEST_STRATEGY=(history completion)
    fpath+=(${pkgs.pure-prompt}/share/zsh/site-functions)
    source ${pkgs.fzf}/share/fzf/key-bindings.zsh
    source ${pkgs.fzf}/share/fzf/completion.zsh
    eval "$(${pkgs.zoxide}/bin/zoxide init zsh)"
    alias ls="${pkgs.eza}/bin/eza --git"
  '';

  tmuxConf = pkgs.writeText "tmux-wrapper" ''
    run-shell ${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/resurrect.tmux
    set -g @resurrect-dir '/home/barrett/.local/state/tmux/resurrect'
    set -g @resurrect-capture-pane-contents on
    run-shell ${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum/continuum.tmux
    set -g @continuum-restore 'on'
    set -g @continuum-save-interval '10'
    set -g status-right '#{E:@bar-content}'
    source /home/barrett/.config/nix/config/tmux/tmux.conf
  '';

  hyprlandConf = pkgs.writeText "hyprland-wrapper" ''
    env = XCURSOR_SIZE,24
    env = HYPRCURSOR_SIZE,24
    env = HYPRCURSOR_THEME,macOS
    env = LIBVA_DRIVER_NAME,nvidia
    env = __GLX_VENDOR_LIBRARY_NAME,nvidia
    env = NVD_BACKEND,direct
    env = GBM_BACKEND,nvidia-drm
    env = GSK_RENDERER,ngl
    env = __NV_PRIME_RENDER_OFFLOAD,1
    env = __VK_LAYER_NV_optimus,NVIDIA_only
    source = /home/barrett/.config/nix/config/hypr/hyprland.conf
  '';

  mkSymlink = target: link: ''
    ln -sfn "${target}" "${link}"
    chown -h barrett:users "${link}"
  '';

  mkDir = dir: ''
    install -d -o barrett -g users "${dir}"
  '';
in
{
  systemd.tmpfiles.rules = [
    "L+ /home/barrett/.local/share/fonts - - - - /home/barrett/.config/nix/fonts"
    "d /home/barrett/dev 0755 barrett users -"
    "d /home/barrett/Pictures/Screensavers 0755 barrett users -"
    "d /home/barrett/Pictures/Screenshots 0755 barrett users -"
    "d /home/barrett/Pictures/wp 0755 barrett users -"
  ];

  system.activationScripts.userConfig.text = ''
    ${mkDir "${cfg}/fzf/themes"}
    ${mkDir "${cfg}/hypr/themes"}
    ${mkDir "${cfg}/waybar/themes"}
    ${mkDir "${cfg}/fuzzel/themes"}
    ${mkDir "${cfg}/dunst/themes"}
    ${mkDir "${cfg}/dunst/dunstrc.d"}
    ${mkDir "${cfg}/sioyek/themes"}
    ${mkDir "${cfg}/ghostty"}
    ${mkDir "${cfg}/ghostty/themes"}
    ${mkDir "${cfg}/git"}
    ${mkDir "${cfg}/gh"}
    ${mkDir "${cfg}/jj"}
    ${mkDir "${cfg}/rg"}
    ${mkDir "${cfg}/fd"}
    ${mkDir "${cfg}/npm"}
    ${mkDir "${cfg}/python"}
    ${mkDir "${cfg}/luarocks"}
    ${mkDir "${cfg}/latexmk"}
    ${mkDir "${cfg}/github"}
    ${mkDir "${cfg}/direnv"}
    ${mkDir "${cfg}/claude"}
    ${mkDir "${cfg}/zsh"}
    ${mkDir "${cfg}/tmux/themes"}
    ${mkDir "${home}/.ssh"}

    ${mkSymlink "${themes}/fzf/themes/midnight" "${cfg}/fzf/themes/midnight"}
    ${mkSymlink "${themes}/fzf/themes/daylight" "${cfg}/fzf/themes/daylight"}
    ${mkSymlink "${themes}/hypr/themes/midnight.conf" "${cfg}/hypr/themes/midnight.conf"}
    ${mkSymlink "${themes}/hypr/themes/daylight.conf" "${cfg}/hypr/themes/daylight.conf"}
    ${mkSymlink "${themes}/waybar/themes/midnight.css" "${cfg}/waybar/themes/midnight.css"}
    ${mkSymlink "${themes}/waybar/themes/daylight.css" "${cfg}/waybar/themes/daylight.css"}
    ${mkSymlink "${themes}/fuzzel/themes/midnight.ini" "${cfg}/fuzzel/themes/midnight.ini"}
    ${mkSymlink "${themes}/fuzzel/themes/daylight.ini" "${cfg}/fuzzel/themes/daylight.ini"}
    ${mkSymlink "${themes}/dunst/themes/midnight.conf" "${cfg}/dunst/themes/midnight.conf"}
    ${mkSymlink "${themes}/dunst/themes/daylight.conf" "${cfg}/dunst/themes/daylight.conf"}
    ${mkSymlink "${themes}/sioyek/themes/midnight.config" "${cfg}/sioyek/themes/midnight.config"}
    ${mkSymlink "${themes}/sioyek/themes/daylight.config" "${cfg}/sioyek/themes/daylight.config"}

    ${mkSymlink "${zshInit}" "${cfg}/zsh/.zshrc"}
    ${mkSymlink "${tmuxConf}" "${cfg}/tmux/tmux.conf"}
    ${mkSymlink "${hyprlandConf}" "${cfg}/hypr/hyprland.conf"}

    ${mkSymlink "${repo}/config/nvim" "${cfg}/nvim"}
    ${mkSymlink "${repo}/config/ghostty/config" "${cfg}/ghostty/config"}
    ${mkSymlink "${repo}/config/ghostty/themes" "${cfg}/ghostty/themes"}
    ${mkSymlink "${repo}/config/git/config" "${cfg}/git/config"}
    ${mkSymlink "${repo}/config/git/ignore" "${cfg}/git/ignore"}
    ${mkSymlink "${repo}/config/ssh/config" "${home}/.ssh/config"}
    ${mkSymlink "${repo}/config/gh/config.yml" "${cfg}/gh/config.yml"}
    ${mkSymlink "${repo}/config/jj/config.toml" "${cfg}/jj/config.toml"}
    ${mkSymlink "${repo}/config/waybar/config.jsonc" "${cfg}/waybar/config"}
    ${mkSymlink "${repo}/config/waybar/style.css" "${cfg}/waybar/style.css"}
    ${mkSymlink "${repo}/config/dunst/dunstrc" "${cfg}/dunst/dunstrc"}
    ${mkSymlink "${repo}/config/fuzzel/fuzzel.ini" "${cfg}/fuzzel/fuzzel.ini"}
    ${mkSymlink "${repo}/config/hypr/hyprpaper.conf" "${cfg}/hypr/hyprpaper.conf"}
    ${mkSymlink "${repo}/config/hypr/hypridle.conf" "${cfg}/hypr/hypridle.conf"}
    ${mkSymlink "${repo}/config/hypr/hyprlock.conf" "${cfg}/hypr/hyprlock.conf"}
    ${mkSymlink "${repo}/config/sioyek/keys_user.config" "${cfg}/sioyek/keys_user.config"}
    ${mkSymlink "${repo}/config/sioyek/prefs_user.config" "${cfg}/sioyek/prefs_user.config"}
    ${mkSymlink "${repo}/config/mimeapps.list" "${cfg}/mimeapps.list"}
    ${mkSymlink "${repo}/config/electron-flags.conf" "${cfg}/electron-flags.conf"}
    ${mkSymlink "${repo}/config/rg/config" "${cfg}/rg/config"}
    ${mkSymlink "${repo}/config/fd/ignore" "${cfg}/fd/ignore"}
    ${mkSymlink "${repo}/config/npm/npmrc" "${cfg}/npm/npmrc"}
    ${mkSymlink "${repo}/config/python/pythonrc" "${cfg}/python/pythonrc"}
    ${mkSymlink "${repo}/config/wgetrc" "${cfg}/wgetrc"}
    ${mkSymlink "${repo}/config/luarocks/config.lua" "${cfg}/luarocks/config.lua"}
    ${mkSymlink "${repo}/config/latexmk/latexmkrc" "${cfg}/latexmk/latexmkrc"}
    ${mkSymlink "${repo}/config/github/ruleset.json" "${cfg}/github/ruleset.json"}
    ${mkSymlink "${repo}/config/direnv/direnvrc" "${cfg}/direnv/direnvrc"}
    ${mkSymlink "${repo}/config/direnv/config.toml" "${cfg}/direnv/config.toml"}
    ${mkSymlink "${repo}/config/claude/settings.json" "${cfg}/claude/settings.json"}
    ${mkSymlink "${repo}/config/claude/CLAUDE.md" "${cfg}/claude/CLAUDE.md"}
    ${mkSymlink "${repo}/config/claude/rules" "${cfg}/claude/rules"}
    ${mkSymlink "${repo}/config/claude/skills" "${cfg}/claude/skills"}
    ${mkSymlink "${repo}/config/claude/hooks" "${cfg}/claude/hooks"}
    ${mkSymlink "${repo}/config/tmux/themes/midnight.conf" "${cfg}/tmux/themes/midnight.conf"}
    ${mkSymlink "${repo}/config/tmux/themes/daylight.conf" "${cfg}/tmux/themes/daylight.conf"}

    theme="midnight"
    ln -sf "${cfg}/hypr/themes/$theme.conf" "${cfg}/hypr/themes/theme.conf"
    chown -h barrett:users "${cfg}/hypr/themes/theme.conf"
    ln -sf "${cfg}/waybar/themes/$theme.css" "${cfg}/waybar/themes/theme.css"
    chown -h barrett:users "${cfg}/waybar/themes/theme.css"
    ln -sf "${cfg}/fuzzel/themes/$theme.ini" "${cfg}/fuzzel/themes/theme.ini"
    chown -h barrett:users "${cfg}/fuzzel/themes/theme.ini"
    ln -sf "${cfg}/dunst/themes/$theme.conf" "${cfg}/dunst/dunstrc.d/theme.conf"
    chown -h barrett:users "${cfg}/dunst/dunstrc.d/theme.conf"
    ln -sf "${cfg}/sioyek/themes/$theme.config" "${cfg}/sioyek/themes/theme.config"
    chown -h barrett:users "${cfg}/sioyek/themes/theme.config"
    ln -sf "${cfg}/fzf/themes/$theme" "${cfg}/fzf/themes/theme"
    chown -h barrett:users "${cfg}/fzf/themes/theme"

    src="${repo}/config/screen"
    dest="${home}/Pictures/Screensavers"
    if [ -d "$src" ]; then
      for f in "$src"/*; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        [ -L "$dest/$name" ] || ln -sf "$f" "$dest/$name"
      done
      chown -h barrett:users "$dest"/* 2>/dev/null || true
    fi

    if [ -d ${home}/.ssh ]; then
      chmod 700 ${home}/.ssh
      for f in ${home}/.ssh/*; do
        [ -f "$f" ] || continue
        [ -L "$f" ] && continue
        case "$f" in
          *.pub|*/known_hosts|*/known_hosts.old) chmod 644 "$f" ;;
          *) chmod 600 "$f" ;;
        esac
      done
    fi
    if [ -d ${home}/.gnupg ]; then
      find ${home}/.gnupg -type d -exec chmod 700 {} +
      find ${home}/.gnupg -type f -exec chmod 600 {} +
    fi

    dir="${cfg}/aws"
    mkdir -p "$dir"
    if [ ! -f "$dir/config" ]; then
      cat > "$dir/config" << 'AWSEOF'
    [default]
    [profile barrett]
    region = us-east-2
    output = json
    AWSEOF
      chown barrett:users "$dir/config"
    fi
    chown barrett:users "$dir"

    model_dir="${home}/.local/share/whisper-models"
    model="ggml-large-v3-turbo-q5_0.bin"
    if [ ! -f "$model_dir/$model" ]; then
      mkdir -p "$model_dir"
      ${pkgs.curl}/bin/curl -L -o "$model_dir/$model" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$model"
      chown -R barrett:users "$model_dir"
    fi

    zen_config="${home}/.zen"
    repo_zen="${repo}/config/zen"
    if [ -d "$zen_config" ]; then
      profile=""
      for d in "$zen_config"/*.Default\ Profile; do
        [ -d "$d" ] && profile="$d" && break
      done
      if [ -n "$profile" ]; then
        mkdir -p "$profile/chrome"
        for f in userChrome.css user.js containers.json handlers.json zen-keyboard-shortcuts.json; do
          src="$repo_zen/$f"
          if [ "$f" = "userChrome.css" ]; then
            dest="$profile/chrome/$f"
          else
            dest="$profile/$f"
          fi
          [ -f "$src" ] || continue
          [ -L "$dest" ] && continue
          [ -f "$dest" ] && rm "$dest"
          ln -s "$src" "$dest"
        done
      fi
    fi

    for link in ${home}/.nix-profile ${home}/.nix-defexpr; do
      [ -L "$link" ] && [ ! -e "$link" ] && rm "$link"
    done

    [ -L ${home}/.zshenv ] && rm ${home}/.zshenv || true

    if [ ! -d ${repo}/fonts ] || [ -z "$(ls -A ${repo}/fonts 2>/dev/null)" ]; then
      echo "WARNING: ~/.config/nix/fonts is missing or empty"
    fi
  '';
}
