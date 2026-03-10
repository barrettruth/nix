{
  lib,
  config,
  pkgs,
  hostConfig,
  ...
}:

let
  name = "Barrett Ruth";
  email = "br.barrettruth@gmail.com";
  gpgKey = "A6C96C9349D2FC81";
in
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
      "CLAUDE.md"
      ".claude/"
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
      ".direnv"
      ".envrc"
    ];

    signing = {
      key = gpgKey;
      signByDefault = true;
    };

    settings = {
      user = { inherit name email; };
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
        t = "tag";
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

  programs.jujutsu = {
    enable = true;
    settings = {
      user = { inherit name email; };
      signing = {
        behavior = "own";
        backend = "gpg";
        key = gpgKey;
      };
      ui = {
        editor = "nvim";
        pager = "less -FRX";
        diff-editor = ":builtin";
        merge-editor = "vimdiff";
      };
      git.sign-on-push = true;
      merge-tools.vimdiff.program = "nvim";
    };
  };

  xdg.configFile."github/ruleset.json".text = builtins.toJSON {
    name = "main";
    target = "branch";
    enforcement = "active";
    conditions.ref_name = {
      exclude = [ ];
      include = [ "~DEFAULT_BRANCH" ];
    };
    rules = [
      { type = "deletion"; }
      { type = "non_fast_forward"; }
      { type = "required_signatures"; }
      {
        type = "pull_request";
        parameters = {
          required_approving_review_count = 1;
          dismiss_stale_reviews_on_push = true;
          required_reviewers = [ ];
          require_code_owner_review = false;
          require_last_push_approval = true;
          required_review_thread_resolution = true;
          allowed_merge_methods = [
            "squash"
            "rebase"
          ];
        };
      }
    ];
    bypass_actors = [
      {
        actor_id = 5;
        actor_type = "RepositoryRole";
        bypass_mode = "always";
      }
    ];
  };

  home.packages = [ pkgs.tea ];

  programs.ssh.matchBlocks."codeberg.org" = {
    identityFile = "~/.ssh/id_ed25519";
  };

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "https";
      prompt = "enabled";
      aliases = {
        init = "!gh api --method PATCH /repos/\"$1\" -f delete_branch_on_merge=true -f allow_squash_merge=true -f allow_merge_commit=false -f allow_rebase_merge=true -f allow_auto_merge=true -f allow_update_branch=true -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=BLANK > /dev/null && gh api --method POST /repos/\"$1\"/rulesets --input ${config.xdg.configHome}/github/ruleset.json > /dev/null && echo \"done: $1\"";
      };
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
      "jetson-nano" = {
        hostname = "100.95.16.119";
        user = "charlie";
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

  services.gpg-agent = lib.mkIf hostConfig.isLinux {
    enable = true;
    defaultCacheTtl = 7200;
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
