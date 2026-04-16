{
  pkgs,
  lib,
  palettes,
  themeGenerators,
  hostConfig,
  identity,
  ...
}:
let
  inherit (hostConfig)
    username
    homeDirectory
    XDG_CONFIG_HOME
    XDG_DATA_HOME
    XDG_STATE_HOME
    XDG_CACHE_HOME
    ;
  repo = "${XDG_CONFIG_HOME}/nix";

  themes = pkgs.runCommand "theme-files" { } ''
    mkdir -p $out/fzf/themes
    mkdir -p $out/hypr/themes
    mkdir -p $out/waybar/themes
    mkdir -p $out/fuzzel/themes
    mkdir -p $out/dunst/themes
    mkdir -p $out/zathura/themes


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

    cat > $out/zathura/themes/midnight << 'ZATHURAMIDNIGHT'
    ${themeGenerators.mkZathuraTheme palettes.midnight}
    ZATHURAMIDNIGHT

    cat > $out/zathura/themes/daylight << 'ZATHURADAYLIGHT'
    ${themeGenerators.mkZathuraTheme palettes.daylight}
    ZATHURADAYLIGHT

    mkdir -p $out/chromium

    cat > $out/chromium/theme.css << 'CHROMECSS'
    ${themeGenerators.mkChromeThemeCss}
    CHROMECSS

    cat > $out/chromium/theme.js << 'CHROMEJS'
    ${themeGenerators.mkChromeThemeJs}
    CHROMEJS


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
    source ${repo}/config/zsh/zshrc
  '';

  tmuxConf = pkgs.writeText "tmux-wrapper" ''
    set -g @resurrect-dir '${XDG_STATE_HOME}/tmux/resurrect'
    set -g @resurrect-capture-pane-contents on
    run-shell ${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/resurrect.tmux
    set -g @continuum-restore 'on'
    set -g @continuum-save-interval '10'
    run-shell ${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum/continuum.tmux
    set -g status-right '#(${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum/scripts/continuum_save.sh)#{E:@bar-content}'
    source ${repo}/config/tmux/tmux.conf
  '';

  hyprlandConf = pkgs.writeText "hyprland-wrapper" ''
    env = XCURSOR_SIZE,24
    env = HYPRCURSOR_SIZE,24
    env = HYPRCURSOR_THEME,macOS
    env = GSK_RENDERER,ngl
    source = ${repo}/config/hypr/hyprland.conf
  '';

  hyprpaperConf = pkgs.writeText "hyprpaper-conf" ''
    splash = 0

    wallpaper {
      monitor =
      path = ${homeDirectory}/Pictures/Screensavers/wallpaper.jpg
    }
  '';

  hyprlockConf = pkgs.writeText "hyprlock-conf" ''
    general {
      hide_cursor = true
      grace = 0
    }

    background {
      monitor =
      path = ${homeDirectory}/Pictures/Screensavers/lock.jpg
    }

    animations {
      enabled = false
    }

    input-field {
      monitor =
      size = 600, 50
      outline_thickness = 0
      dots_text_format = *
      dots_size = 0.9
      dots_spacing = 0.3
      dots_center = true
      outer_color = rgba(00000000)
      inner_color = rgba(00000000)
      font_color = rgb(ffffff)
      font_family = Berkeley Mono
      check_color = rgb(98c379)
      fail_color = rgb(ff6b6b)
      fail_text = $FAIL
      rounding = 0
      placeholder_text =
      position = 0, 0
      halign = center
      valign = center
    }
  '';

  jjConf = pkgs.writeText "jj-config" ''
    [user]
    name = "${identity.fullName}"
    email = "${identity.email}"

    [signing]
    behavior = "own"
    backend = "gpg"
    key = "${identity.gpgKey}"

    [ui]
    editor = "nvim"
    pager = "less -FRX"
    diff-editor = ":builtin"
    merge-editor = "vimdiff"

    [git]
    sign-on-push = true

    [merge-tools.vimdiff]
    program = "nvim"
  '';

  gitConf = pkgs.writeText "git-wrapper" ''
    [user]
    	name = ${identity.fullName}
    	email = ${identity.email}
    	signingKey = ${identity.gpgKey}
    [safe]
    	directory = ${XDG_CACHE_HOME}/nix/tarball-cache-v2
    [include]
    	path = ${repo}/config/git/config
  '';

  browserDesktop = "chromium-browser.desktop";

  mimeappsList = pkgs.writeText "mimeapps.list" ''
    [Default Applications]
    x-scheme-handler/http=${browserDesktop}
    x-scheme-handler/https=${browserDesktop}
    text/html=${browserDesktop}
    text/plain=nvim.desktop
    application/pdf=org.pwmt.zathura.desktop
    x-scheme-handler/discord=vesktop.desktop
  '';

  fuzzelConf = pkgs.writeText "fuzzel-wrapper" ''
    include=${XDG_CONFIG_HOME}/fuzzel/themes/theme.ini
    include=${repo}/config/fuzzel/fuzzel.ini
  '';

  mkSymlink = target: link: ''
    ln -sfnT "${target}" "${link}"
    chown -h ${username}:users "${link}"
  '';

  mkMutableConfig = source: target: ''
    if [ -L "${target}" ]; then
      targetPath="$(readlink -f "${target}" || true)"
      sourcePath="$(readlink -f "${source}")"
      if [ "$targetPath" = "$sourcePath" ]; then
        rm -f "${target}"
        install -Dm600 -o ${username} -g users "${source}" "${target}"
      fi
    elif [ ! -e "${target}" ]; then
      install -Dm600 -o ${username} -g users "${source}" "${target}"
    fi
  '';

  mkDir = dir: ''
    install -d -o ${username} -g users "${dir}"
  '';
in
{
  systemd.tmpfiles.rules = [
    "L+ ${XDG_DATA_HOME}/fonts - - - - ${repo}/fonts"
    "d ${homeDirectory}/dev 0755 ${username} users -"
    "d ${homeDirectory}/Pictures/Screensavers 0755 ${username} users -"
    "d ${homeDirectory}/Pictures/Screenshots 0755 ${username} users -"
    "d ${homeDirectory}/Pictures/wp 0755 ${username} users -"
  ];

  system.activationScripts.userConfig.text = ''
    ${mkDir "${XDG_CONFIG_HOME}/fzf/themes"}

    ${mkDir "${XDG_CONFIG_HOME}/ghostty"}
    [ -d "${XDG_CONFIG_HOME}/ghostty/themes" ] && [ ! -L "${XDG_CONFIG_HOME}/ghostty/themes" ] && rm -rf "${XDG_CONFIG_HOME}/ghostty/themes"
    ${mkDir "${XDG_CONFIG_HOME}/git"}
    ${mkDir "${XDG_CONFIG_HOME}/gh"}
    ${mkDir "${XDG_CONFIG_HOME}/jj"}
    ${mkDir "${XDG_CONFIG_HOME}/rg"}
    ${mkDir "${XDG_CONFIG_HOME}/fd"}
    ${mkDir "${XDG_CONFIG_HOME}/npm"}
    ${mkDir "${XDG_CONFIG_HOME}/python"}
    ${mkDir "${XDG_CONFIG_HOME}/luarocks"}
    ${mkDir "${XDG_CONFIG_HOME}/github"}
    ${mkDir "${XDG_CONFIG_HOME}/direnv"}
    ${mkDir "${XDG_CONFIG_HOME}/devin"}
    ${mkDir "${XDG_CONFIG_HOME}/vim"}
    ${mkDir "${XDG_CONFIG_HOME}/zsh"}
    ${mkDir "${XDG_CONFIG_HOME}/tmux/themes"}
    ${mkDir "${XDG_STATE_HOME}/zsh"}
    ${mkDir "${XDG_DATA_HOME}/vim"}
    ${mkDir "${XDG_STATE_HOME}/vim"}
    ${mkDir "${XDG_CACHE_HOME}/vim"}
    ${mkDir "${homeDirectory}/.ssh"}

    ${lib.optionalString hostConfig.enableWayland ''
      ${mkDir "${XDG_CONFIG_HOME}/hypr/themes"}
      ${mkDir "${XDG_CONFIG_HOME}/waybar/themes"}
      ${mkDir "${XDG_CONFIG_HOME}/fuzzel/themes"}
      ${mkDir "${XDG_CONFIG_HOME}/dunst/themes"}
      ${mkDir "${XDG_CONFIG_HOME}/dunst/dunstrc.d"}

      ${mkSymlink "${themes}/hypr/themes/midnight.conf" "${XDG_CONFIG_HOME}/hypr/themes/midnight.conf"}
      ${mkSymlink "${themes}/hypr/themes/daylight.conf" "${XDG_CONFIG_HOME}/hypr/themes/daylight.conf"}
      ${mkSymlink "${themes}/waybar/themes/midnight.css" "${XDG_CONFIG_HOME}/waybar/themes/midnight.css"}
      ${mkSymlink "${themes}/waybar/themes/daylight.css" "${XDG_CONFIG_HOME}/waybar/themes/daylight.css"}
      ${mkSymlink "${themes}/fuzzel/themes/midnight.ini" "${XDG_CONFIG_HOME}/fuzzel/themes/midnight.ini"}
      ${mkSymlink "${themes}/fuzzel/themes/daylight.ini" "${XDG_CONFIG_HOME}/fuzzel/themes/daylight.ini"}
      ${mkSymlink "${themes}/dunst/themes/midnight.conf" "${XDG_CONFIG_HOME}/dunst/themes/midnight.conf"}
      ${mkSymlink "${themes}/dunst/themes/daylight.conf" "${XDG_CONFIG_HOME}/dunst/themes/daylight.conf"}

      ${mkSymlink "${hyprlandConf}" "${XDG_CONFIG_HOME}/hypr/hyprland.conf"}
      ${mkSymlink "${repo}/config/waybar/config.jsonc" "${XDG_CONFIG_HOME}/waybar/config"}
      ${mkSymlink "${repo}/config/waybar/style.css" "${XDG_CONFIG_HOME}/waybar/style.css"}
      ${mkSymlink "${repo}/config/dunst/dunstrc" "${XDG_CONFIG_HOME}/dunst/dunstrc"}
      ${mkSymlink "${fuzzelConf}" "${XDG_CONFIG_HOME}/fuzzel/fuzzel.ini"}
      ${mkSymlink "${hyprpaperConf}" "${XDG_CONFIG_HOME}/hypr/hyprpaper.conf"}
      ${mkSymlink "${repo}/config/hypr/hypridle.conf" "${XDG_CONFIG_HOME}/hypr/hypridle.conf"}
      ${mkSymlink "${hyprlockConf}" "${XDG_CONFIG_HOME}/hypr/hyprlock.conf"}
    ''}

    ${lib.optionalString hostConfig.enableDesktop ''
      ${mkDir "${XDG_CONFIG_HOME}/zathura/themes"}

      ${mkSymlink "${themes}/zathura/themes/midnight" "${XDG_CONFIG_HOME}/zathura/themes/midnight"}
      ${mkSymlink "${themes}/zathura/themes/daylight" "${XDG_CONFIG_HOME}/zathura/themes/daylight"}

      ${mkSymlink "${themes}/chromium/theme.css" "${repo}/config/chromium/extension/theme.css"}
      ${mkSymlink "${themes}/chromium/theme.js" "${repo}/config/chromium/extension/theme.js"}

      ${mkSymlink "${repo}/config/zathura/zathurarc" "${XDG_CONFIG_HOME}/zathura/zathurarc"}
      ${mkSymlink "${mimeappsList}" "${XDG_CONFIG_HOME}/mimeapps.list"}
      ${mkSymlink "${repo}/config/electron-flags.conf" "${XDG_CONFIG_HOME}/electron-flags.conf"}
    ''}

    ${lib.optionalString hostConfig.enableTexlive ''
      ${mkDir "${XDG_CONFIG_HOME}/latexmk"}
      ${mkSymlink "${repo}/config/latexmk/latexmkrc" "${XDG_CONFIG_HOME}/latexmk/latexmkrc"}
    ''}

    ${mkSymlink "${themes}/fzf/themes/midnight" "${XDG_CONFIG_HOME}/fzf/themes/midnight"}
    ${mkSymlink "${themes}/fzf/themes/daylight" "${XDG_CONFIG_HOME}/fzf/themes/daylight"}

    ${mkSymlink "${zshInit}" "${XDG_CONFIG_HOME}/zsh/.zshrc"}
    ${mkSymlink "${tmuxConf}" "${XDG_CONFIG_HOME}/tmux/tmux.conf"}

    ${mkSymlink "${repo}/config/nvim" "${XDG_CONFIG_HOME}/nvim"}
    ${mkSymlink "${repo}/config/ghostty/config" "${XDG_CONFIG_HOME}/ghostty/config"}
    ${mkSymlink "${repo}/config/ghostty/themes" "${XDG_CONFIG_HOME}/ghostty/themes"}
    ${mkSymlink "${gitConf}" "${XDG_CONFIG_HOME}/git/config"}
    ${mkSymlink "${repo}/config/git/ignore" "${XDG_CONFIG_HOME}/git/ignore"}
    ${mkSymlink "${repo}/config/git/hooks" "${XDG_CONFIG_HOME}/git/hooks"}
    ${mkSymlink "${repo}/config/ssh/config" "${homeDirectory}/.ssh/config"}
    cp -f "${repo}/config/gh/config.yaml" "${XDG_CONFIG_HOME}/gh/config.yml"
    chown ${username}:users "${XDG_CONFIG_HOME}/gh/config.yml"
    ${mkSymlink "${jjConf}" "${XDG_CONFIG_HOME}/jj/config.toml"}

    ${mkSymlink "${repo}/config/rg/config" "${XDG_CONFIG_HOME}/rg/config"}
    ${mkSymlink "${repo}/config/fd/ignore" "${XDG_CONFIG_HOME}/fd/ignore"}
    ${mkSymlink "${repo}/config/python/pythonrc" "${XDG_CONFIG_HOME}/python/pythonrc"}
    ${mkSymlink "${repo}/config/wgetrc" "${XDG_CONFIG_HOME}/wgetrc"}
    ${mkSymlink "${repo}/config/luarocks/config.lua" "${XDG_CONFIG_HOME}/luarocks/config.lua"}
    ${mkSymlink "${repo}/config/github/ruleset.json" "${XDG_CONFIG_HOME}/github/ruleset.json"}
    ${mkSymlink "${repo}/config/direnv/direnvrc" "${XDG_CONFIG_HOME}/direnv/direnvrc"}
    ${mkSymlink "${repo}/config/direnv/config.toml" "${XDG_CONFIG_HOME}/direnv/config.toml"}
    ${mkMutableConfig "${repo}/config/devin/config.json" "${XDG_CONFIG_HOME}/devin/config.json"}
    ${mkSymlink "${repo}/config/devin/agent.yaml" "${XDG_CONFIG_HOME}/devin/agent.yaml"}
    ${mkSymlink "${repo}/config/devin/skills" "${XDG_CONFIG_HOME}/devin/skills"}
    ${mkSymlink "${repo}/config/vim/vimrc" "${XDG_CONFIG_HOME}/vim/vimrc"}
    ${mkSymlink "${repo}/config/tmux/themes/midnight.conf" "${XDG_CONFIG_HOME}/tmux/themes/midnight.conf"}
    ${mkSymlink "${repo}/config/tmux/themes/daylight.conf" "${XDG_CONFIG_HOME}/tmux/themes/daylight.conf"}

    theme="$(cat "${XDG_STATE_HOME}/theme" 2>/dev/null)" || theme="midnight"
    [ -z "$theme" ] && theme="midnight"

    ${lib.optionalString hostConfig.enableWayland ''
      ln -sf "${XDG_CONFIG_HOME}/hypr/themes/$theme.conf" "${XDG_CONFIG_HOME}/hypr/themes/theme.conf"
      chown -h ${username}:users "${XDG_CONFIG_HOME}/hypr/themes/theme.conf"
      if [ ! -L "${XDG_CONFIG_HOME}/waybar/themes/theme.css" ] && [ ! -e "${XDG_CONFIG_HOME}/waybar/themes/theme.css" ]; then
        ln -sf "${XDG_CONFIG_HOME}/waybar/themes/$theme.css" "${XDG_CONFIG_HOME}/waybar/themes/theme.css"
        chown -h ${username}:users "${XDG_CONFIG_HOME}/waybar/themes/theme.css"
      fi
      ln -sf "${XDG_CONFIG_HOME}/fuzzel/themes/$theme.ini" "${XDG_CONFIG_HOME}/fuzzel/themes/theme.ini"
      chown -h ${username}:users "${XDG_CONFIG_HOME}/fuzzel/themes/theme.ini"
      ln -sf "${XDG_CONFIG_HOME}/dunst/themes/$theme.conf" "${XDG_CONFIG_HOME}/dunst/dunstrc.d/theme.conf"
      chown -h ${username}:users "${XDG_CONFIG_HOME}/dunst/dunstrc.d/theme.conf"

      wp_themed="${homeDirectory}/Pictures/Screensavers/wallpaper-$theme.jpg"
      wp_link="${homeDirectory}/Pictures/Screensavers/wallpaper.jpg"
      [ -f "$wp_themed" ] && {
        ln -sf "$wp_themed" "$wp_link"
        chown -h ${username}:users "$wp_link"
      }
    ''}

    ln -sf "${XDG_CONFIG_HOME}/fzf/themes/$theme" "${XDG_CONFIG_HOME}/fzf/themes/theme"
    chown -h ${username}:users "${XDG_CONFIG_HOME}/fzf/themes/theme"

    ${lib.optionalString hostConfig.enableDesktop ''
      ln -sf "${XDG_CONFIG_HOME}/zathura/themes/$theme" "${XDG_CONFIG_HOME}/zathura/theme"
      chown -h ${username}:users "${XDG_CONFIG_HOME}/zathura/theme"
    ''}

    src="${repo}/config/screen"
    dest="${homeDirectory}/Pictures/Screensavers"
    if [ -d "$src" ]; then
      for f in "$src"/*; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        [ -L "$dest/$name" ] || ln -sf "$f" "$dest/$name"
      done
      chown -h ${username}:users "$dest"/* 2>/dev/null || true
    fi

    if [ -d ${homeDirectory}/.ssh ]; then
      chmod 700 ${homeDirectory}/.ssh
      for f in ${homeDirectory}/.ssh/*; do
        [ -f "$f" ] || continue
        [ -L "$f" ] && continue
        case "$f" in
          *.pub|*/known_hosts|*/known_hosts.old) chmod 644 "$f" ;;
          *) chmod 600 "$f" ;;
        esac
      done
    fi
    if [ -d ${homeDirectory}/.gnupg ]; then
      find ${homeDirectory}/.gnupg -type d -exec chmod 700 {} +
      find ${homeDirectory}/.gnupg -type f -exec chmod 600 {} +
    fi

    dir="${XDG_CONFIG_HOME}/aws"
    mkdir -p "$dir"
    if [ ! -f "$dir/config" ]; then
      cat > "$dir/config" << 'AWSEOF'
    [default]
    [profile barrett]
    region = us-east-2
    output = json
    AWSEOF
      chown ${username}:users "$dir/config"
    fi
    chown ${username}:users "$dir"

    model_dir="${XDG_DATA_HOME}/whisper-models"
    model="ggml-large-v3-turbo-q5_0.bin"
    if [ ! -f "$model_dir/$model" ]; then
      mkdir -p "$model_dir"
      ${pkgs.curl}/bin/curl -L -o "$model_dir/$model" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$model"
      chown -R ${username}:users "$model_dir"
    fi


    for link in ${homeDirectory}/.nix-profile ${homeDirectory}/.nix-defexpr; do
      [ -L "$link" ] && [ ! -e "$link" ] && rm "$link"
    done

    [ -L ${homeDirectory}/.zshenv ] && rm ${homeDirectory}/.zshenv || true

    if [ ! -d ${repo}/fonts ] || [ -z "$(ls -A ${repo}/fonts 2>/dev/null)" ]; then
      echo "WARNING: ~/.config/nix/fonts is missing or empty"
    fi
  '';
}
