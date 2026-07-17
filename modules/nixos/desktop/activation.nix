{
  pkgs,
  lib,
  hostConfig,
  identity,
  ...
}:
let
  helpers = import ./helpers.nix { inherit hostConfig pkgs; };
  inherit (helpers)
    username
    homeDirectory
    XDG_CONFIG_HOME
    XDG_DATA_HOME
    XDG_STATE_HOME
    XDG_CACHE_HOME
    repo
    runUser
    mkSymlink
    mkDir
    mkPrivateDir
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
    default-command = "log"
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
    # x-scheme-handler/discord=vesktop.desktop
  '';

  awsConf = pkgs.writeText "aws-config" ''
    [default]
    [profile barrett]
    region = us-east-2
    output = json
  '';
in
{
  systemd.tmpfiles.rules = [
    "d ${homeDirectory}/dev 0755 ${username} users -"
    "d ${homeDirectory}/Pictures/Screensavers 0755 ${username} users -"
    "d ${homeDirectory}/Pictures/Screenshots 0755 ${username} users -"
    "d ${homeDirectory}/Pictures/wp 0755 ${username} users -"
  ];

  system.activationScripts.userConfig.text = ''
    ${mkDir "${XDG_CONFIG_HOME}/ghostty"}
    if [ -d "${XDG_CONFIG_HOME}/ghostty/themes" ] && [ ! -L "${XDG_CONFIG_HOME}/ghostty/themes" ]; then
      rmdir "${XDG_CONFIG_HOME}/ghostty/themes" 2>/dev/null || true
    fi
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
    ${mkDir "${XDG_CONFIG_HOME}/codex"}
    ${mkDir "${XDG_CONFIG_HOME}/clangd"}
    if [ -L "${homeDirectory}/.codex" ]; then
      ${runUser} ${pkgs.coreutils}/bin/rm -f "${homeDirectory}/.codex"
    fi
    ${mkDir "${XDG_CONFIG_HOME}/zsh"}
    ${mkDir "${XDG_STATE_HOME}/zsh"}
    ${mkPrivateDir "${homeDirectory}/.ssh"}
    ${mkPrivateDir "${homeDirectory}/.gnupg"}

    ${lib.optionalString hostConfig.enableDesktop ''
      ${mkSymlink "${mimeappsList}" "${XDG_CONFIG_HOME}/mimeapps.list"}
      ${mkSymlink "${repo}/config/electron-flags.conf" "${XDG_CONFIG_HOME}/electron-flags.conf"}
    ''}

    ${lib.optionalString hostConfig.enableTexlive ''
      ${mkDir "${XDG_CONFIG_HOME}/latexmk"}
      ${mkSymlink "${repo}/config/latexmk/latexmkrc" "${XDG_CONFIG_HOME}/latexmk/latexmkrc"}
    ''}

    ${mkSymlink "${zshInit}" "${XDG_CONFIG_HOME}/zsh/.zshrc"}

    ${mkSymlink "${repo}/config/nvim" "${XDG_CONFIG_HOME}/nvim"}
    ${mkSymlink "${repo}/config/ghostty/config" "${XDG_CONFIG_HOME}/ghostty/config"}
    ${mkSymlink "${repo}/config/ghostty/themes" "${XDG_CONFIG_HOME}/ghostty/themes"}
    ${mkSymlink "${gitConf}" "${XDG_CONFIG_HOME}/git/config"}
    ${mkSymlink "${repo}/config/git/ignore" "${XDG_CONFIG_HOME}/git/ignore"}
    ${mkSymlink "${repo}/config/git/hooks" "${XDG_CONFIG_HOME}/git/hooks"}
    ${mkSymlink "${repo}/config/ssh/config" "${homeDirectory}/.ssh/config"}
    ${mkSymlink "${repo}/config/gh/config.yaml" "${XDG_CONFIG_HOME}/gh/config.yml"}
    ${mkSymlink "${jjConf}" "${XDG_CONFIG_HOME}/jj/config.toml"}

    ${mkSymlink "${repo}/config/rg/config" "${XDG_CONFIG_HOME}/rg/config"}
    ${mkSymlink "${repo}/config/fd/ignore" "${XDG_CONFIG_HOME}/fd/ignore"}
    ${mkSymlink "${repo}/config/python/pythonrc" "${XDG_CONFIG_HOME}/python/pythonrc"}
    ${mkSymlink "${repo}/config/wgetrc" "${XDG_CONFIG_HOME}/wgetrc"}
    ${mkSymlink "${repo}/config/luarocks/config.lua" "${XDG_CONFIG_HOME}/luarocks/config.lua"}
    ${mkSymlink "${repo}/config/github/ruleset.json" "${XDG_CONFIG_HOME}/github/ruleset.json"}
    ${mkSymlink "${repo}/config/direnv/direnvrc" "${XDG_CONFIG_HOME}/direnv/direnvrc"}
    ${mkSymlink "${repo}/config/direnv/config.toml" "${XDG_CONFIG_HOME}/direnv/config.toml"}
    ${mkSymlink "${repo}/config/devin/config.json" "${XDG_CONFIG_HOME}/devin/config.json"}
    ${mkSymlink "${repo}/config/devin/AGENTS.md" "${XDG_CONFIG_HOME}/devin/AGENTS.md"}
    ${mkSymlink "${repo}/config/codex/config.toml" "${XDG_CONFIG_HOME}/codex/config.toml"}
    ${mkSymlink "${repo}/config/codex/AGENTS.md" "${XDG_CONFIG_HOME}/codex/AGENTS.md"}
    ${mkSymlink "${repo}/config/clangd/config.yaml" "${XDG_CONFIG_HOME}/clangd/config.yaml"}

    ${mkDir "${XDG_CONFIG_HOME}/codex/skills"}
    if [ -L "${XDG_CONFIG_HOME}/devin/skills" ]; then
      rm -f "${XDG_CONFIG_HOME}/devin/skills"
    fi
    ${mkDir "${XDG_CONFIG_HOME}/devin/skills"}
    for skill in ${repo}/config/skills/*/; do
      [ -f "$skill/SKILL.md" ] || continue
      name="$(basename "$skill")"
      for agentdir in "${XDG_CONFIG_HOME}/codex/skills" "${XDG_CONFIG_HOME}/devin/skills"; do
        ${runUser} ${pkgs.coreutils}/bin/ln -sfnT "$skill" "$agentdir/$name"
      done
    done

    ${mkDir "${XDG_CONFIG_HOME}/aws"}
    ${mkSymlink "${awsConf}" "${XDG_CONFIG_HOME}/aws/config"}
    ${mkDir "${XDG_DATA_HOME}/whisper-models"}

    for link in ${homeDirectory}/.nix-profile ${homeDirectory}/.nix-defexpr; do
      [ -L "$link" ] && [ ! -e "$link" ] && ${runUser} ${pkgs.coreutils}/bin/rm "$link"
    done

    [ -L ${homeDirectory}/.zshenv ] && ${runUser} ${pkgs.coreutils}/bin/rm ${homeDirectory}/.zshenv || true

    if [ "$(readlink "${XDG_DATA_HOME}/fonts" 2>/dev/null || true)" = "${repo}/fonts" ]; then
      ${runUser} ${pkgs.coreutils}/bin/rm "${XDG_DATA_HOME}/fonts"
    fi
  '';
}
