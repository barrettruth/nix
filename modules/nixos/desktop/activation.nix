{
  pkgs,
  lib,
  hostConfig,
  identity,
  ...
}:
let
  helpers = import ./helpers.nix { inherit hostConfig; };
  inherit (helpers)
    username
    homeDirectory
    XDG_CONFIG_HOME
    XDG_DATA_HOME
    XDG_STATE_HOME
    XDG_CACHE_HOME
    repo
    mkSymlink
    mkMutableConfig
    mkDir
    ;

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
    run-shell ${pkgs.tmuxPlugins.mosaic}/share/tmux-plugins/mosaic/mosaic.tmux
    source ${repo}/config/tmux/tmux.conf
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
    ${mkDir "${XDG_CONFIG_HOME}/claude"}
    ${mkDir "${XDG_CONFIG_HOME}/codex"}
    if [ -e "${homeDirectory}/.codex" ] || [ -L "${homeDirectory}/.codex" ]; then
      rm -rf "${homeDirectory}/.codex"
    fi
    ${mkDir "${XDG_CONFIG_HOME}/vim"}
    ${mkDir "${XDG_CONFIG_HOME}/zsh"}
    ${mkDir "${XDG_CONFIG_HOME}/tmux/themes"}
    ${mkDir "${XDG_STATE_HOME}/zsh"}
    ${mkDir "${XDG_DATA_HOME}/vim"}
    ${mkDir "${XDG_STATE_HOME}/vim"}
    ${mkDir "${XDG_CACHE_HOME}/vim"}
    ${mkDir "${homeDirectory}/.ssh"}

    ${lib.optionalString hostConfig.enableDesktop ''
      ${mkSymlink "${mimeappsList}" "${XDG_CONFIG_HOME}/mimeapps.list"}
      ${mkSymlink "${repo}/config/electron-flags.conf" "${XDG_CONFIG_HOME}/electron-flags.conf"}
    ''}

    ${lib.optionalString hostConfig.enableTexlive ''
      ${mkDir "${XDG_CONFIG_HOME}/latexmk"}
      ${mkSymlink "${repo}/config/latexmk/latexmkrc" "${XDG_CONFIG_HOME}/latexmk/latexmkrc"}
    ''}

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
    ${mkSymlink "${repo}/config/claude/settings.json" "${XDG_CONFIG_HOME}/claude/settings.json"}
    ${mkSymlink "${repo}/config/claude/CLAUDE.md" "${XDG_CONFIG_HOME}/claude/CLAUDE.md"}
    ${mkSymlink "${repo}/config/claude/rules" "${XDG_CONFIG_HOME}/claude/rules"}
    ${mkSymlink "${repo}/config/claude/hooks" "${XDG_CONFIG_HOME}/claude/hooks"}
    ${mkSymlink "${repo}/config/devin/skills" "${XDG_CONFIG_HOME}/claude/skills"}
    ${mkSymlink "${repo}/config/codex/config.toml" "${XDG_CONFIG_HOME}/codex/config.toml"}
    ${mkSymlink "${repo}/config/codex/AGENTS.md" "${XDG_CONFIG_HOME}/codex/AGENTS.md"}
    ${mkSymlink "${repo}/config/vim/vimrc" "${XDG_CONFIG_HOME}/vim/vimrc"}
    ${mkSymlink "${repo}/config/tmux/themes/midnight.conf" "${XDG_CONFIG_HOME}/tmux/themes/midnight.conf"}
    ${mkSymlink "${repo}/config/tmux/themes/daylight.conf" "${XDG_CONFIG_HOME}/tmux/themes/daylight.conf"}

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
