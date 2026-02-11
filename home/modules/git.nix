{
  lib,
  config,
  pkgs,
  ...
}:

{
  programs.git = {
    enable = true;
    lfs.enable = true;

    ignores = [
      "*.swp"
      "*.swo"
      "*~"
      ".vscode/"
      ".idea/"
      ".DS_Store"
      "Thumbs.db"
      "*.o"
      "*.a"
      "*.so"
      "*.pyc"
      "__pycache__/"
      "node_modules/"
      "target/"
      "dist/"
      "build/"
      "out/"
      "*.class"
      "*.log"
      ".env"
      ".env.local"
      ".envrc"
      "venv/"
      ".mypy_cache/"
      "result"
      "result-*"
      ".claude/settings.local.json"
    ];

    signing = {
      key = "A6C96C9349D2FC81";
      signByDefault = true;
    };

    settings = {
      user = {
        name = "Barrett Ruth";
        email = "br.barrettruth@gmail.com";
      };
      alias = {
        a = "add";
        b = "branch";
        c = "commit";
        acp = "!acp() { git add . && git commit -m \"$*\" && git push; }; acp";
        cane = "commit --amend --no-edit";
        cf = "config";
        ch = "checkout";
        cl = "clone";
        cp = "cherry-pick";
        d = "diff";
        dt = "difftool";
        f = "fetch";
        i = "init";
        lg = "log --oneline --graph --decorate";
        m = "merge";
        p = "pull";
        pu = "push";
        r = "remote";
        rb = "rebase";
        rs = "restore";
        rt = "reset";
        s = "status";
        sm = "submodule";
        st = "stash";
        sw = "switch";
        wt = "worktree";
      };
      init.defaultBranch = "main";
      core = {
        editor = "nvim";
        whitespace = "fix,-indent-with-non-tab,trailing-space,cr-at-eol";
      };
      color.ui = "auto";
      diff.tool = "codediff";
      difftool.prompt = false;
      difftool.codediff.cmd = "nvim -c 'CodeDiff' $LOCAL $REMOTE";
      merge.tool = "codediff";
      mergetool.prompt = false;
      mergetool.codediff.cmd = "nvim -c 'CodeDiff' $LOCAL $REMOTE $MERGED";
      push.autoSetupRemote = true;
      credential.helper = "cache";
    };
  };

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "https";
      prompt = "enabled";
    };
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "*" = {
        addKeysToAgent = "yes";
      };
      "github.com" = {
        identityFile = "~/.ssh/id_ed25519";
      };
      "lightsail" = {
        hostname = "52.87.124.139";
        user = "ec2-user";
        identityFile = "~/.ssh/lightsail-keypair.pem";
        extraOptions = {
          SetEnv = "TERM=xterm-256color";
        };
      };
      "uva-portal" = {
        hostname = "portal.cs.virginia.edu";
        user = "jxa9ev";
        identityFile = "~/.ssh/uva_key";
      };
      "uva-nvidia" = {
        hostname = "grasshopper02.cs.virginia.edu";
        user = "jxa9ev";
        proxyJump = "uva-portal";
        identityFile = "~/.ssh/uva_key";
      };
    };
  };

  programs.gpg.enable = true;

  services.gpg-agent = {
    enable = true;
    defaultCacheTtl = 3600;
    maxCacheTtl = 7200;
    pinentry.package = pkgs.pinentry-curses;
  };

  home.activation.secretPermissions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -d "${config.home.homeDirectory}/.ssh" ]; then
      $DRY_RUN_CMD chmod 700 "${config.home.homeDirectory}/.ssh"
      for f in "${config.home.homeDirectory}/.ssh/"*; do
        [ -f "$f" ] || continue
        [ -L "$f" ] && continue
        case "$f" in
          *.pub|*/known_hosts|*/known_hosts.old)
            $DRY_RUN_CMD chmod 644 "$f" ;;
          *)
            $DRY_RUN_CMD chmod 600 "$f" ;;
        esac
      done
    fi
    if [ -d "${config.home.homeDirectory}/.gnupg" ]; then
      $DRY_RUN_CMD find "${config.home.homeDirectory}/.gnupg" -type d -exec chmod 700 {} +
      $DRY_RUN_CMD find "${config.home.homeDirectory}/.gnupg" -type f -exec chmod 600 {} +
    fi
  '';
}
