{
  config,
  pkgs,
  lib,
  modulesPath,
  identity,
  mkVpsSecret,
  ...
}:
let
  forgejoSigningKeyId = "AEB0C5593951F51260C1388DF09FD58E4737029E";
  forgejoSigningTrustFingerprint = "F2CC7F7FD33F423B7A31B4E3A6C96C9349D2FC81";
  forgejoOauthSources = {
    github = {
      provider = "github";
      displayName = "GitHub";
    };
    google = {
      provider = "gplus";
      displayName = "Google";
    };
    gitlab = {
      provider = "gitlab";
      displayName = "GitLab";
    };
  };
  forgejoOauthSecretNames = lib.flatten (
    lib.mapAttrsToList (name: _: [
      "forgejo-oauth-${name}-id"
      "forgejo-oauth-${name}-secret"
    ]) forgejoOauthSources
  );
  forgejoGpgAgentConf = pkgs.writeText "gpg-agent.conf" ''
    allow-loopback-pinentry
  '';
  forgejoGpgProgram = pkgs.writeShellScript "forgejo-gpg" ''
    exec ${pkgs.gnupg}/bin/gpg \
      --batch \
      --pinentry-mode loopback \
      --passphrase-file "$CREDENTIALS_DIRECTORY/gpg-passphrase" \
      "$@"
  '';
  forgejoBrandingSvg = pkgs.writeText "forgejo-delta-symbol.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">
      <style>
        .delta { fill: #121212; }
        @media (prefers-color-scheme: dark) { .delta { fill: #e0e0e0; } }
      </style>
      <g transform="translate(171.5, 831) scale(1, -1)">
        <path class="delta" d="M629 0H28V28L317 662H355L629 28ZM310 539 108 80H495L314 539Z"/>
      </g>
    </svg>
  '';
  forgejoAvatarSvg = pkgs.writeText "forgejo-delta-avatar.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">
      <rect width="1000" height="1000" fill="#ffffff"/>
      <g transform="translate(171.5, 831) scale(1, -1)">
        <path fill="#121212" d="M629 0H28V28L317 662H355L629 28ZM310 539 108 80H495L314 539Z"/>
      </g>
    </svg>
  '';
  forgejoBrandingAssets =
    pkgs.runCommand "forgejo-branding-assets"
      {
        nativeBuildInputs = [ pkgs.librsvg ];
      }
      ''
        mkdir -p $out
        cp ${forgejoBrandingSvg} $out/logo.svg
        cp ${forgejoBrandingSvg} $out/favicon.svg
        rsvg-convert -w 512 -h 512 ${forgejoBrandingSvg} > $out/logo.png
        rsvg-convert -w 192 -h 192 ${forgejoBrandingSvg} > $out/favicon.png
        rsvg-convert -w 180 -h 180 ${forgejoBrandingSvg} > $out/apple-touch-icon.png
        rsvg-convert -w 1024 -h 1024 ${forgejoAvatarSvg} > $out/avatar.png
        cp $out/avatar.png $out/avatar_default.png
      '';

  forgejoStixTwoFontFile = pkgs.runCommand "stix-two-text.ttf" { } ''
    cp '${pkgs.stix-two}/share/fonts/truetype/STIXTwoText[wght].ttf' $out
  '';
  forgejoMidnightFontsCss = pkgs.writeText "theme-midnight-fonts.css" ''
    @font-face {
      font-family: "SF Pro";
      src: url("/assets/fonts/san-francisco-pro/SF-Pro.ttf") format("truetype-variations");
      font-weight: 100 900;
      font-style: normal;
      font-display: swap;
    }
    @font-face {
      font-family: "SF Pro";
      src: url("/assets/fonts/san-francisco-pro/SF-Pro-Italic.ttf") format("truetype-variations");
      font-weight: 100 900;
      font-style: italic;
      font-display: swap;
    }
    @font-face {
      font-family: "Berkeley Mono";
      src: url("/assets/fonts/berkeley-mono/BerkeleyMono-Regular.ttf") format("truetype");
      font-weight: 400;
      font-style: normal;
      font-display: swap;
    }
    @font-face {
      font-family: "Berkeley Mono";
      src: url("/assets/fonts/berkeley-mono/BerkeleyMono-Italic.ttf") format("truetype");
      font-weight: 400;
      font-style: italic;
      font-display: swap;
    }
    @font-face {
      font-family: "Berkeley Mono";
      src: url("/assets/fonts/berkeley-mono/BerkeleyMono-Bold.ttf") format("truetype");
      font-weight: 700;
      font-style: normal;
      font-display: swap;
    }
    @font-face {
      font-family: "Berkeley Mono";
      src: url("/assets/fonts/berkeley-mono/BerkeleyMono-BoldItalic.ttf") format("truetype");
      font-weight: 700;
      font-style: italic;
      font-display: swap;
    }
    @font-face {
      font-family: "STIX Two Text";
      src: url("/assets/fonts/stix-two/STIXTwoText.ttf") format("truetype-variations");
      font-weight: 100 900;
      font-style: normal;
      font-display: swap;
    }
    :root {
      --fonts-override: "SF Pro", "STIX Two Text";
      --fonts-monospace: "Berkeley Mono", ui-monospace, SFMono-Regular, "SF Mono", Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace, var(--fonts-emoji);
    }
  '';

  forgejoMidnightLightCss = pkgs.writeText "theme-midnight-light.css" ''
    @import "theme-forgejo-light.css";
    @import "theme-midnight-fonts.css";
    :root {
      --is-dark-theme: false;
      --midnight-syntax-keyword: #3b5bdb;
      --midnight-syntax-string: #2d7f3e;
      --midnight-syntax-constant: #2d7f3e;
      --midnight-syntax-comment: #6b6b6b;
      --midnight-syntax-error: #c7254e;
      --zinc-50: #ffffff;
      --zinc-100: #fafafa;
      --zinc-150: #f5f5f5;
      --zinc-200: #ebebeb;
      --zinc-250: #e8e8e8;
      --zinc-300: #d0d0d0;
      --zinc-350: #c0c0c0;
      --zinc-400: #a0a0a0;
      --zinc-450: #888888;
      --zinc-500: #777777;
      --zinc-550: #6b6b6b;
      --zinc-600: #555555;
      --zinc-650: #444444;
      --zinc-700: #333333;
      --zinc-750: #2a2a2a;
      --zinc-800: #222222;
      --zinc-850: #1a1a1a;
      --zinc-900: #0a0a0a;
      --color-secondary-alpha-10: #d0d0d019;
      --color-secondary-alpha-20: #d0d0d033;
      --color-secondary-alpha-30: #d0d0d04b;
      --color-secondary-alpha-40: #d0d0d066;
      --color-secondary-alpha-50: #d0d0d080;
      --color-secondary-alpha-60: #d0d0d099;
      --color-secondary-alpha-70: #d0d0d0b3;
      --color-secondary-alpha-80: #d0d0d0cc;
      --color-secondary-alpha-90: #d0d0d0e1;
      --color-body: #f5f5f5;
      --color-text: #1a1a1a;
      --color-text-dark: #000000;
      --color-text-light: #4b5563;
      --color-text-light-1: #666666;
      --color-text-light-2: #888888;
      --color-text-light-3: #999999;
      --color-primary: #3b5bdb;
      --color-primary-contrast: #ffffff;
      --color-primary-hover: #2d49b8;
      --color-primary-active: #1d3175;
      --color-primary-dark-1: #2d49b8;
      --color-primary-dark-2: #243b94;
      --color-primary-dark-3: #1d3175;
      --color-primary-dark-4: #16265b;
      --color-primary-dark-5: #101c44;
      --color-primary-dark-6: #0a1330;
      --color-primary-dark-7: #050a1f;
      --color-primary-light-1: #4c6ef5;
      --color-primary-light-2: #748ffc;
      --color-primary-light-3: #91a7ff;
      --color-primary-light-4: #bac8ff;
      --color-primary-light-5: #dbe3fe;
      --color-primary-light-6: #edf1fe;
      --color-primary-light-7: #f5f8ff;
      --color-primary-alpha-10: #3b5bdb19;
      --color-primary-alpha-20: #3b5bdb33;
      --color-primary-alpha-30: #3b5bdb4b;
      --color-primary-alpha-40: #3b5bdb66;
      --color-primary-alpha-50: #3b5bdb80;
      --color-primary-alpha-60: #3b5bdb99;
      --color-primary-alpha-70: #3b5bdbb3;
      --color-primary-alpha-80: #3b5bdbcc;
      --color-primary-alpha-90: #3b5bdbe1;
      --color-red: #c7254e;
      --color-orange: #d9730d;
      --color-yellow: #996800;
      --color-green: #2d7f3e;
      --color-blue: #3b5bdb;
      --color-violet: #ae3ec9;
      --color-purple: #ae3ec9;
      --color-cyan: #1098ad;
      --color-teal: #1098ad;
      --color-secondary: #d0d0d0;
      --color-secondary-bg: #e8e8e8;
      --color-secondary-nav-bg: #ebebeb;
      --color-card: #ebebeb;
      --color-menu: #ebebeb;
      --color-nav-bg: #ebebeb;
      --color-nav-hover-bg: #d0d0d0;
      --color-box-body: #ebebeb;
      --color-box-body-highlight: #e0e0e0;
      --color-box-header: #e8e8e8;
      --color-header-wrapper: #e8e8e8;
      --color-header-wrapper-transparent: #e8e8e8e6;
      --color-placeholder-text: #888888;
      --color-input-background: #ffffff;
      --color-input-text: #1a1a1a;
      --color-input-border: #d0d0d0;
      --color-input-border-hover: #999999;
      --color-button: #d0d0d0;
      --color-code-bg: #e8e8e8;
      --color-markup-code-block: #e8e8e8;
      --color-markup-code-inline: #ebebeb;
      --color-diff-added-row-bg: #a5c5ab;
      --color-diff-removed-row-bg: #e2a1b2;
      --color-diff-moved-row-bg: #a9b7e5;
      --color-diff-added-row-border: #2d7f3e;
      --color-diff-removed-row-border: #c7254e;
      --color-link: #3b5bdb;
      --color-link-hover: #2d49b8;
      color-scheme: light;
    }
    ${forgejoMidnightSyntaxRules}
  '';

  forgejoMidnightDarkCss = pkgs.writeText "theme-midnight-dark.css" ''
    @import "theme-forgejo-dark.css";
    @import "theme-midnight-fonts.css";
    :root {
      --is-dark-theme: true;
      --midnight-syntax-keyword: #7aa2f7;
      --midnight-syntax-string: #98c379;
      --midnight-syntax-constant: #98c379;
      --midnight-syntax-comment: #666666;
      --midnight-syntax-error: #ff6b6b;
      --steel-900: #0a0a0a;
      --steel-850: #121212;
      --steel-800: #181818;
      --steel-750: #1a1a1a;
      --steel-700: #222222;
      --steel-650: #262626;
      --steel-600: #2d2d2d;
      --steel-550: #363636;
      --steel-500: #3d3d3d;
      --steel-450: #4a4a4a;
      --steel-400: #555555;
      --steel-350: #666666;
      --steel-300: #808080;
      --steel-250: #999999;
      --steel-200: #aaaaaa;
      --steel-150: #cccccc;
      --steel-100: #e0e0e0;
      --color-secondary-alpha-10: #3d3d3d19;
      --color-secondary-alpha-20: #3d3d3d33;
      --color-secondary-alpha-30: #3d3d3d4b;
      --color-secondary-alpha-40: #3d3d3d66;
      --color-secondary-alpha-50: #3d3d3d80;
      --color-secondary-alpha-60: #3d3d3d99;
      --color-secondary-alpha-70: #3d3d3db3;
      --color-secondary-alpha-80: #3d3d3dcc;
      --color-secondary-alpha-90: #3d3d3de1;
      --color-body: #121212;
      --color-text: #e0e0e0;
      --color-text-dark: #ffffff;
      --color-text-light: #999999;
      --color-text-light-1: #888888;
      --color-text-light-2: #666666;
      --color-text-light-3: #5a5a5a;
      --color-primary: #7aa2f7;
      --color-primary-contrast: #121212;
      --color-primary-hover: #9db8f7;
      --color-primary-active: #b5c8f7;
      --color-primary-dark-1: #9db8f7;
      --color-primary-dark-2: #b5c8f7;
      --color-primary-dark-3: #c8d6f8;
      --color-primary-dark-4: #d6e1fc;
      --color-primary-dark-5: #e2eafd;
      --color-primary-dark-6: #ecf1fd;
      --color-primary-dark-7: #f5f8fe;
      --color-primary-light-1: #5b87e8;
      --color-primary-light-2: #466dc4;
      --color-primary-light-3: #34528f;
      --color-primary-light-4: #233b66;
      --color-primary-light-5: #1a2b48;
      --color-primary-light-6: #131f33;
      --color-primary-light-7: #0d1622;
      --color-primary-alpha-10: #7aa2f719;
      --color-primary-alpha-20: #7aa2f733;
      --color-primary-alpha-30: #7aa2f74b;
      --color-primary-alpha-40: #7aa2f766;
      --color-primary-alpha-50: #7aa2f780;
      --color-primary-alpha-60: #7aa2f799;
      --color-primary-alpha-70: #7aa2f7b3;
      --color-primary-alpha-80: #7aa2f7cc;
      --color-primary-alpha-90: #7aa2f7e1;
      --color-red: #ff6b6b;
      --color-orange: #e5a56b;
      --color-yellow: #e5c07b;
      --color-green: #98c379;
      --color-blue: #7aa2f7;
      --color-violet: #c678dd;
      --color-purple: #c678dd;
      --color-cyan: #56b6c2;
      --color-teal: #56b6c2;
      --color-secondary: #3d3d3d;
      --color-secondary-bg: #2d2d2d;
      --color-secondary-nav-bg: #1a1a1a;
      --color-card: #222222;
      --color-menu: #222222;
      --color-nav-bg: #1a1a1a;
      --color-nav-hover-bg: #2d2d2d;
      --color-box-body: #222222;
      --color-box-body-highlight: #2d2d2d;
      --color-box-header: #2d2d2d;
      --color-header-wrapper: #1a1a1a;
      --color-header-wrapper-transparent: #1a1a1ae6;
      --color-placeholder-text: #888888;
      --color-input-background: #1a1a1a;
      --color-input-text: #e0e0e0;
      --color-input-border: #3d3d3d;
      --color-input-border-hover: #5a5a5a;
      --color-button: #3d3d3d;
      --color-code-bg: #1a1a1a;
      --color-markup-code-block: #2d2d2d;
      --color-markup-code-inline: #2d2d2d;
      --color-diff-added-row-bg: #0c2f1e;
      --color-diff-removed-row-bg: #291f27;
      --color-diff-moved-row-bg: #3a4a6d;
      --color-diff-added-row-border: #98c379;
      --color-diff-removed-row-border: #ff6b6b;
      --color-link: #7aa2f7;
      --color-link-hover: #9db8f7;
      color-scheme: dark;
    }
    ${forgejoMidnightSyntaxRules}
  '';

  forgejoMidnightSyntaxRules = ''
    /* ===== Chroma (file viewer, README, markdown code fences) ===== */
    .chroma .k, .chroma .kd, .chroma .kn, .chroma .kp, .chroma .kr, .chroma .kt,
    .chroma .cp, .chroma .cpf {
      color: var(--midnight-syntax-keyword);
    }
    .chroma .s, .chroma .s1, .chroma .s2, .chroma .sa, .chroma .sb, .chroma .sc,
    .chroma .sd, .chroma .sh, .chroma .si, .chroma .sr, .chroma .ss, .chroma .sx,
    .chroma .se, .chroma .dl {
      color: var(--midnight-syntax-string);
    }
    .chroma .m, .chroma .mb, .chroma .mf, .chroma .mh, .chroma .mi, .chroma .mo, .chroma .il,
    .chroma .kc, .chroma .no {
      color: var(--midnight-syntax-constant);
    }
    .chroma .c, .chroma .c1, .chroma .ch, .chroma .cm, .chroma .cs {
      color: var(--midnight-syntax-comment);
      font-style: italic;
    }
    .chroma .err, .chroma .gr, .chroma .gt {
      color: var(--midnight-syntax-error);
    }
    .chroma .gp, .chroma .go {
      color: var(--midnight-syntax-comment);
    }
    .chroma .ge { font-style: italic; }
    .chroma .gs { font-weight: bold; }
    .chroma .gd { color: var(--midnight-syntax-error); background-color: var(--color-diff-removed-row-bg); }
    .chroma .gi { color: var(--midnight-syntax-string); background-color: var(--color-diff-added-row-bg); }
    .chroma .nf, .chroma .nc, .chroma .nd, .chroma .ne, .chroma .nb, .chroma .nv,
    .chroma .nl, .chroma .nn, .chroma .nt, .chroma .nx, .chroma .ni, .chroma .na,
    .chroma .o, .chroma .ow, .chroma .p, .chroma .pi, .chroma .bp,
    .chroma .l, .chroma .ld, .chroma .w, .chroma .fm, .chroma .vc, .chroma .vg, .chroma .vi,
    .chroma .gh, .chroma .gu, .chroma .gl, .chroma .g {
      color: inherit;
    }
    /* ===== CodeMirror (web file editor) ===== */
    .CodeMirror.cm-s-default .cm-keyword,
    .CodeMirror.cm-s-paper .cm-keyword,
    .CodeMirror.cm-s-default .cm-meta,
    .CodeMirror.cm-s-paper .cm-meta {
      color: var(--midnight-syntax-keyword);
    }
    .CodeMirror.cm-s-default .cm-string,
    .CodeMirror.cm-s-paper .cm-string,
    .CodeMirror.cm-s-default .cm-string-2,
    .CodeMirror.cm-s-paper .cm-string-2,
    .CodeMirror.cm-s-default .cm-quote,
    .CodeMirror.cm-s-paper .cm-quote {
      color: var(--midnight-syntax-string);
    }
    .CodeMirror.cm-s-default .cm-atom,
    .CodeMirror.cm-s-paper .cm-atom,
    .CodeMirror.cm-s-default .cm-builtin,
    .CodeMirror.cm-s-paper .cm-builtin,
    .CodeMirror.cm-s-default .cm-number,
    .CodeMirror.cm-s-paper .cm-number {
      color: var(--midnight-syntax-constant);
    }
    .CodeMirror.cm-s-default .cm-comment,
    .CodeMirror.cm-s-paper .cm-comment {
      color: var(--midnight-syntax-comment);
      font-style: italic;
    }
    .CodeMirror.cm-s-default .cm-error,
    .CodeMirror.cm-s-paper .cm-error {
      color: var(--midnight-syntax-error);
    }
    .CodeMirror.cm-s-default .cm-header,
    .CodeMirror.cm-s-paper .cm-header,
    .CodeMirror.cm-s-default .cm-link,
    .CodeMirror.cm-s-paper .cm-link,
    .CodeMirror.cm-s-default .cm-url,
    .CodeMirror.cm-s-paper .cm-url {
      color: var(--midnight-syntax-keyword);
    }
    .CodeMirror.cm-s-default .cm-hr,
    .CodeMirror.cm-s-paper .cm-hr {
      color: var(--midnight-syntax-comment);
    }
    .CodeMirror.cm-s-default .cm-property,
    .CodeMirror.cm-s-paper .cm-property,
    .CodeMirror.cm-s-default .cm-variable,
    .CodeMirror.cm-s-paper .cm-variable,
    .CodeMirror.cm-s-default .cm-variable-2,
    .CodeMirror.cm-s-paper .cm-variable-2,
    .CodeMirror.cm-s-default .cm-variable-3,
    .CodeMirror.cm-s-paper .cm-variable-3,
    .CodeMirror.cm-s-default .cm-def,
    .CodeMirror.cm-s-paper .cm-def,
    .CodeMirror.cm-s-default .cm-tag,
    .CodeMirror.cm-s-paper .cm-tag,
    .CodeMirror.cm-s-default .cm-attribute,
    .CodeMirror.cm-s-paper .cm-attribute,
    .CodeMirror.cm-s-default .cm-bracket,
    .CodeMirror.cm-s-paper .cm-bracket,
    .CodeMirror.cm-s-default .cm-qualifier,
    .CodeMirror.cm-s-paper .cm-qualifier {
      color: inherit;
    }
    /* ===== Markup (rendered markdown content) ===== */
    .markup .absent { color: var(--midnight-syntax-error); }
    /* ===== CodeMirror 6 (file editor at /repos/.../_edit/...) =====
       CM6 ships its own theme via EditorView.theme()/HighlightStyle.define()
       in web_src/js/features/codemirror.ts with hardcoded VSCode-ish hex
       colors. Those styles get injected into <style> tags AT EDITOR MOUNT
       TIME and use obfuscated auto-generated class names, so per-token
       recoloring is done via custom/public/assets/js/midnight-cm6.js
       (a MutationObserver that rewrites the hex colors to midnight
       palette equivalents). Here we just set the wrapper text + bg via
       !important so the base text uses the midnight palette before the
       JS runs (and for tokens the JS doesn't recolor). */
    .cm-editor {
      color: var(--color-text) !important;
      background-color: var(--color-code-bg) !important;
    }
    .cm-editor .cm-content,
    .cm-editor .cm-line,
    .cm-editor .cm-gutters {
      color: var(--color-text) !important;
    }
    .cm-editor .cm-gutters {
      background-color: var(--color-code-bg) !important;
    }
  '';

  forgejoMidnightAutoCss = pkgs.writeText "theme-midnight-auto.css" ''
    @import "theme-midnight-light.css";
    @import "theme-midnight-dark.css" (prefers-color-scheme: dark);
  '';

  # CM6 language coverage extension lives in pkgs/forgejo-cm6-langs/ (custom
  # forgejo build that adds @codemirror/legacy-modes for INI/TOML/Shell/Lua/
  # Ruby/Dockerfile/Perl/Nginx/Diff). This JS only handles RECOLORING what
  # CM6 highlights with whichever VSCode palette it picked at editor mount
  # -- it does not add new languages.
  forgejoMidnightCm6Js = pkgs.writeText "midnight-cm6.js" ''
    (() => {
      // CodeMirror 6 (used in /repos/.../_edit/...) hardcodes VSCode-ish hex
      // colors in HighlightStyle.define() and picks dark vs light at editor
      // mount time via isDarkTheme() (web_src/js/utils.js). Both branches'
      // hex values get mapped to the SAME midnight CSS variable here, so
      // the resolved color always matches the current Forgejo theme
      // regardless of which VSCode palette CM6 picked. The variables are
      // declared on :root in theme-midnight-{light,dark}.css and resolve
      // through the cascade at use time.
      const COLOR_MAP = {
        "#569cd6": "var(--midnight-syntax-keyword)",
        "#0064ff": "var(--midnight-syntax-keyword)",
        "#c586c0": "var(--midnight-syntax-keyword)",
        "#af00db": "var(--midnight-syntax-keyword)",
        "#006ab1": "var(--midnight-syntax-keyword)",
        "#9cdcfe": "var(--color-text)",
        "#383a42": "var(--color-text)",
        "#4ec9b0": "var(--color-text)",
        "#267f99": "var(--color-text)",
        "#dcdcaa": "var(--color-text)",
        "#795e26": "var(--color-text)",
        "#d4d4d4": "var(--color-text)",
        "#ce9178": "var(--midnight-syntax-string)",
        "#a31515": "var(--midnight-syntax-string)",
        "#b5cea8": "var(--midnight-syntax-constant)",
        "#098658": "var(--midnight-syntax-constant)",
        "#6a9955": "var(--midnight-syntax-comment)",
        "#6b6b6b": "var(--midnight-syntax-comment)",
        "#ff0000": "var(--midnight-syntax-error)",
        "#e51400": "var(--midnight-syntax-error)",
        "#d16969": "var(--midnight-syntax-error)"
      };
      const rewrite = (el) => {
        if (!el || el.tagName !== "STYLE") return;
        let txt = el.textContent;
        if (!txt) return;
        let modified = false;
        for (const [from, to] of Object.entries(COLOR_MAP)) {
          if (txt.toLowerCase().includes(from)) {
            txt = txt.split(from).join(to);
            txt = txt.split(from.toUpperCase()).join(to);
            modified = true;
          }
        }
        if (modified) el.textContent = txt;
      };
      document.querySelectorAll("style").forEach(rewrite);
      new MutationObserver((muts) => {
        for (const m of muts) {
          for (const node of m.addedNodes) {
            if (node.nodeType === 1 && node.tagName === "STYLE") rewrite(node);
          }
        }
      }).observe(document.documentElement, { childList: true, subtree: true });
    })();
  '';

  forgejoMidnightHeaderTmpl = pkgs.writeText "header.tmpl" ''
    <script src="/assets/js/midnight-cm6.js" defer></script>
  '';
  forgejoOauthContainerTmpl = pkgs.writeText "oauth_container.tmpl" ''
    {{if or .OAuth2Providers .EnableOpenIDSignIn}}
    {{if or (and .PageIsSignUp (not .DisableRegistration)) (and .PageIsSignIn .EnableInternalSignIn)}}
      <div class="divider divider-text">
        {{ctx.Locale.Tr "sign_in_or"}}
      </div>
    {{end}}
    {{$oauthLabels := dict "github" "GitHub" "gitlab" "GitLab" "google" "Google"}}
    <div id="oauth2-login-navigator" class="tw-py-1">
      <div class="tw-flex tw-flex-col tw-justify-center">
        <div id="oauth2-login-navigator-inner" class="tw-flex tw-flex-col tw-flex-wrap tw-items-center tw-gap-2">
          {{range $provider := .OAuth2Providers}}
            {{$label := or (index $oauthLabels $provider.DisplayName) $provider.DisplayName}}
            <a class="{{$provider.Name}} ui button tw-flex tw-items-center tw-justify-center tw-py-2 tw-w-full oauth-login-link" href="{{AppSubUrl}}/user/oauth2/{{$provider.DisplayName}}">
              {{$provider.IconHTML 28}}
              {{ctx.Locale.Tr "sign_in_with_provider" $label}}
            </a>
          {{end}}
          {{if .EnableOpenIDSignIn}}
            <a class="openid ui button tw-flex tw-items-center tw-justify-center tw-py-2 tw-w-full" href="{{AppSubUrl}}/user/login/openid">
            {{svg "fontawesome-openid" 28 "tw-mr-2"}}
            {{ctx.Locale.Tr "auth.sign_in_openid"}}
            </a>
          {{end}}
        </div>
      </div>
    </div>
    {{end}}
  '';
in
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    (modulesPath + "/profiles/minimal.nix")
    (modulesPath + "/profiles/headless.nix")
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    devices = lib.mkForce [ "nodev" ];
    configurationLimit = 3;
  };

  documentation.enable = false;
  hardware.enableRedistributableFirmware = false;
  fonts.fontconfig.enable = false;

  networking = {
    hostName = "vps";
    useDHCP = false;
    interfaces.eth0 = {
      ipv4.addresses = [
        {
          address = "152.53.168.144";
          prefixLength = 22;
        }
      ];
      ipv6.addresses = [
        {
          address = "2a0a:4cc0:2000:af7d:c8e4:dff:fe7f:c233";
          prefixLength = 64;
        }
      ];
    };
    defaultGateway = {
      address = "152.53.168.1";
      interface = "eth0";
    };
    defaultGateway6 = {
      address = "fe80::1";
      interface = "eth0";
    };
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
    firewall.allowedTCPPorts = [
      22
      80
      443
    ];
  };

  services.openssh = {
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILA1pOJawzHtJqIn56AZT4IhPUh9vUEhLPLwndk5s3iM ${identity.email}"
  ];

  security.acme = {
    acceptTerms = true;
    defaults.email = identity.email;
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    clientMaxBodySize = "512m";
    virtualHosts."vault.${identity.domain}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:8222";
    };
    virtualHosts."git.${identity.domain}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:3000";
    };
    virtualHosts."delta.${identity.domain}" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:3001";
    };
  };

  services.vaultwarden = {
    enable = true;
    backupDir = "/var/backup/vaultwarden";
    environmentFile = "/var/lib/vaultwarden/vaultwarden.env";
    config = {
      DOMAIN = "https://vault.${identity.domain}";
      SIGNUPS_ALLOWED = false;
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
    };
  };

  sops.secrets =
    let
      mkForgejoSecret =
        restartUnits: name:
        mkVpsSecret name {
          owner = "git";
          group = "git";
          mode = "0400";
          inherit restartUnits;
        };
    in
    lib.genAttrs [
      "forgejo-resend-api-key"
      "forgejo-hcaptcha-sitekey"
      "forgejo-hcaptcha-secret"
    ] (mkForgejoSecret [ "forgejo.service" ])
    // lib.genAttrs forgejoOauthSecretNames (mkForgejoSecret [ "forgejo-oauth-sync.service" ])
    //
      lib.genAttrs
        [
          "forgejo-gpg-passphrase"
          "forgejo-gpg-secret.asc"
        ]
        (mkForgejoSecret [
          "forgejo.service"
          "forgejo-gpg-import.service"
        ]);

  services.forgejo = {
    enable = true;
    package = pkgs.callPackage ../../pkgs/forgejo-cm6-langs { };
    user = "git";
    group = "git";
    dump = {
      enable = true;
      backupDir = "/var/backup/forgejo";
    };
    secrets = {
      mailer.PASSWD = config.sops.secrets."forgejo-resend-api-key".path;
      service.HCAPTCHA_SITEKEY = config.sops.secrets."forgejo-hcaptcha-sitekey".path;
      service.HCAPTCHA_SECRET = config.sops.secrets."forgejo-hcaptcha-secret".path;
    };
    settings = {
      server = {
        DOMAIN = "git.${identity.domain}";
        ROOT_URL = "https://git.${identity.domain}/";
        HTTP_PORT = 3000;
        SSH_DOMAIN = "git.${identity.domain}";
      };
      service = {
        DISABLE_REGISTRATION = false;
        REGISTER_EMAIL_CONFIRM = true;
        ENABLE_NOTIFY_MAIL = true;
        ENABLE_CAPTCHA = true;
        REQUIRE_CAPTCHA_FOR_LOGIN = false;
        CAPTCHA_TYPE = "hcaptcha";
      };
      oauth2_client = {
        ENABLE_AUTO_REGISTRATION = true;
        ACCOUNT_LINKING = "auto";
        UPDATE_AVATAR = true;
        USERNAME = "nickname";
      };
      session.COOKIE_SECURE = true;
      mailer = {
        ENABLED = true;
        PROTOCOL = "smtps";
        SMTP_ADDR = "smtp.resend.com";
        SMTP_PORT = 2465;
        USER = "resend";
        FROM = "Forgejo <noreply@${identity.domain}>";
      };
      mirror = {
        DEFAULT_INTERVAL = "1h";
        MIN_INTERVAL = "10m";
      };
      "git.config" = {
        "gpg.program" = "${forgejoGpgProgram}";
      };
      "repository.signing" = {
        SIGNING_KEY = forgejoSigningKeyId;
        INITIAL_COMMIT = "always";
        CRUD_ACTIONS = "always";
        MERGES = "always";
        WIKI = "never";
      };
      ui = {
        DEFAULT_THEME = "midnight-auto";
        THEMES = "midnight-auto,midnight-light,midnight-dark";
      };
    };
  };

  systemd.services.forgejo = {
    environment.GNUPGHOME = "/var/lib/forgejo/.gnupg";
    serviceConfig.LoadCredential = lib.mkAfter [
      "gpg-passphrase:${config.sops.secrets."forgejo-gpg-passphrase".path}"
    ];
  };

  systemd.services.forgejo-gpg-import = {
    description = "Import Forgejo GPG signing key into git keyring (idempotent)";
    before = [ "forgejo.service" ];
    wantedBy = [ "forgejo.service" ];
    path = [ pkgs.gnupg ];
    serviceConfig = {
      Type = "oneshot";
      User = "git";
      Group = "git";
      LoadCredential = [
        "passphrase:${config.sops.secrets."forgejo-gpg-passphrase".path}"
        "secret:${config.sops.secrets."forgejo-gpg-secret.asc".path}"
      ];
      Environment = [ "GNUPGHOME=/var/lib/forgejo/.gnupg" ];
    };
    script = ''
      set -eu
      if gpg --list-secret-keys ${forgejoSigningKeyId} >/dev/null 2>&1; then
        exit 0
      fi
      gpg --batch --pinentry-mode loopback \
        --passphrase-file "$CREDENTIALS_DIRECTORY/passphrase" \
        --import "$CREDENTIALS_DIRECTORY/secret"
      printf '%s:6:\n' ${forgejoSigningTrustFingerprint} | gpg --import-ownertrust
    '';
  };

  systemd.services.forgejo-oauth-sync = {
    description = "Sync Forgejo OAuth2 authentication sources from on-disk credentials";
    after = [ "forgejo.service" ];
    requires = [ "forgejo.service" ];
    wantedBy = [ "forgejo.service" ];
    path = [ pkgs.gawk ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "git";
      Group = "git";
      WorkingDirectory = "/var/lib/forgejo";
      LoadCredential = lib.flatten (
        lib.mapAttrsToList (name: _: [
          "${name}-id:${config.sops.secrets."forgejo-oauth-${name}-id".path}"
          "${name}-secret:${config.sops.secrets."forgejo-oauth-${name}-secret".path}"
        ]) forgejoOauthSources
      );
    };
    script =
      let
        forgejo = "${config.services.forgejo.package}/bin/forgejo --config /var/lib/forgejo/custom/conf/app.ini --work-path /var/lib/forgejo";
        syncOne = name: cfg: ''
          id=$(${forgejo} admin auth list | awk -F'\t' -v d="${cfg.displayName}" -v n="${name}" 'NR>1 && ($2==d || $2==n) {print $1; exit}')
          key=$(cat "$CREDENTIALS_DIRECTORY/${name}-id")
          secret=$(cat "$CREDENTIALS_DIRECTORY/${name}-secret")
          if [ -z "$id" ]; then
            ${forgejo} admin auth add-oauth \
              --name "${name}" \
              --provider "${cfg.provider}" \
              --key "$key" \
              --secret "$secret"
          else
            ${forgejo} admin auth update-oauth \
              --id "$id" \
              --name "${name}" \
              --key "$key" \
              --secret "$secret"
          fi
        '';
      in
      ''
        set -eu
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList syncOne forgejoOauthSources)}
      '';
  };

  users.users.git = {
    isSystemUser = true;
    home = "/var/lib/forgejo";
    group = "git";
    shell = "${pkgs.bash}/bin/bash";
  };

  users.groups.git = { };

  systemd.tmpfiles.rules = [
    "d /var/lib/forgejo/.gnupg 0700 git git -"
    "L+ /var/lib/forgejo/.gnupg/gpg-agent.conf - - - - ${forgejoGpgAgentConf}"
    "d /var/lib/forgejo/custom/public 0750 git git -"
    "d /var/lib/forgejo/custom/public/assets 0750 git git -"
    "d /var/lib/forgejo/custom/public/assets/img 0750 git git -"
    "L+ /var/lib/forgejo/custom/public/assets/img/logo.svg - - - - ${forgejoBrandingAssets}/logo.svg"
    "L+ /var/lib/forgejo/custom/public/assets/img/logo.png - - - - ${forgejoBrandingAssets}/logo.png"
    "L+ /var/lib/forgejo/custom/public/assets/img/favicon.svg - - - - ${forgejoBrandingAssets}/favicon.svg"
    "L+ /var/lib/forgejo/custom/public/assets/img/favicon.png - - - - ${forgejoBrandingAssets}/favicon.png"
    "L+ /var/lib/forgejo/custom/public/assets/img/apple-touch-icon.png - - - - ${forgejoBrandingAssets}/apple-touch-icon.png"
    "L+ /var/lib/forgejo/custom/public/assets/img/avatar_default.png - - - - ${forgejoBrandingAssets}/avatar_default.png"
    "d /var/lib/forgejo/custom/public/assets/css 0750 git git -"
    "L+ /var/lib/forgejo/custom/public/assets/css/theme-midnight-auto.css - - - - ${forgejoMidnightAutoCss}"
    "L+ /var/lib/forgejo/custom/public/assets/css/theme-midnight-light.css - - - - ${forgejoMidnightLightCss}"
    "L+ /var/lib/forgejo/custom/public/assets/css/theme-midnight-dark.css - - - - ${forgejoMidnightDarkCss}"
    "L+ /var/lib/forgejo/custom/public/assets/css/theme-midnight-fonts.css - - - - ${forgejoMidnightFontsCss}"
    "d /var/lib/forgejo/custom/public/assets/js 0750 git git -"
    "L+ /var/lib/forgejo/custom/public/assets/js/midnight-cm6.js - - - - ${forgejoMidnightCm6Js}"
    "d /var/lib/forgejo/custom/templates 0750 git git -"
    "d /var/lib/forgejo/custom/templates/custom 0750 git git -"
    "L+ /var/lib/forgejo/custom/templates/custom/header.tmpl - - - - ${forgejoMidnightHeaderTmpl}"
    "d /var/lib/forgejo/custom/templates/user 0750 git git -"
    "d /var/lib/forgejo/custom/templates/user/auth 0750 git git -"
    "L+ /var/lib/forgejo/custom/templates/user/auth/oauth_container.tmpl - - - - ${forgejoOauthContainerTmpl}"
    "d /var/lib/forgejo/custom/public/assets/fonts 0750 git git -"
    "d /var/lib/forgejo/custom/public/assets/fonts/san-francisco-pro 0750 git git -"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/san-francisco-pro/SF-Pro.ttf - - - - ${../../fonts/san-francisco-pro}/SF-Pro.ttf"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/san-francisco-pro/SF-Pro-Italic.ttf - - - - ${../../fonts/san-francisco-pro}/SF-Pro-Italic.ttf"
    "d /var/lib/forgejo/custom/public/assets/fonts/berkeley-mono 0750 git git -"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/berkeley-mono/BerkeleyMono-Regular.ttf - - - - ${../../fonts/berkeley-mono}/BerkeleyMono-Regular.ttf"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/berkeley-mono/BerkeleyMono-Italic.ttf - - - - ${../../fonts/berkeley-mono}/BerkeleyMono-Italic.ttf"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/berkeley-mono/BerkeleyMono-Bold.ttf - - - - ${../../fonts/berkeley-mono}/BerkeleyMono-Bold.ttf"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/berkeley-mono/BerkeleyMono-BoldItalic.ttf - - - - ${../../fonts/berkeley-mono}/BerkeleyMono-BoldItalic.ttf"
    "d /var/lib/forgejo/custom/public/assets/fonts/stix-two 0750 git git -"
    "L+ /var/lib/forgejo/custom/public/assets/fonts/stix-two/STIXTwoText.ttf - - - - ${forgejoStixTwoFontFile}"
  ];

  environment.systemPackages = with pkgs; [
    vim
    git
    nodejs_22
    pnpm
  ];

  systemd.services.vaultwarden-r2-backup = {
    description = "Backup Vaultwarden to Cloudflare R2";
    after = [ "backup-vaultwarden.service" ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "/etc/vaultwarden-r2-backup.env";
    };
    path = [
      pkgs.awscli2
      pkgs.gawk
    ];
    script = ''
      export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
      export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
      ENDPOINT="$R2_ENDPOINT"
      DATE=$(date +%Y-%m-%d)

      aws s3 cp /var/backup/vaultwarden/db.sqlite3 \
        "s3://vaultwarden/$DATE/db.sqlite3" \
        --endpoint-url "$ENDPOINT"

      CUTOFF=$(date -d '30 days ago' +%Y-%m-%d)
      aws s3 ls s3://vaultwarden/ --endpoint-url "$ENDPOINT" \
        | awk '{print $2}' | tr -d '/' \
        | while read dir; do
            if [ "$dir" \< "$CUTOFF" ]; then
              aws s3 rm "s3://vaultwarden/$dir" --recursive --endpoint-url "$ENDPOINT"
            fi
          done
    '';
  };

  systemd.timers.vaultwarden-r2-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  users.users.delta = {
    isSystemUser = true;
    home = "/opt/delta";
    group = "delta";
  };

  users.groups.delta = { };

  systemd.services.delta = {
    description = "delta - personal todo/productivity platform";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = "/opt/delta";
      ExecStart = "${pkgs.nodejs_22}/bin/node .next/standalone/server.js";
      Restart = "on-failure";
      RestartSec = 5;
      User = "delta";
      Group = "delta";
      StateDirectory = "delta";
      EnvironmentFile = "/var/lib/delta/env";
    };
    environment = {
      NODE_ENV = "production";
      PORT = "3001";
      HOSTNAME = "127.0.0.1";
      DATABASE_URL = "/var/lib/delta/data.db";
    };
  };

  systemd.services.delta-r2-backup = {
    description = "Backup delta SQLite to Cloudflare R2";
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "/etc/delta-r2-backup.env";
    };
    path = [
      pkgs.awscli2
      pkgs.gawk
    ];
    script = ''
      export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
      export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
      ENDPOINT="$R2_ENDPOINT"
      DATE=$(date +%Y-%m-%d)

      aws s3 cp /var/lib/delta/data.db \
        "s3://delta/$DATE/data.db" \
        --endpoint-url "$ENDPOINT"

      CUTOFF=$(date -d '30 days ago' +%Y-%m-%d)
      aws s3 ls s3://delta/ --endpoint-url "$ENDPOINT" \
        | awk '{print $2}' | tr -d '/' \
        | while read dir; do
            if [ "$dir" \< "$CUTOFF" ]; then
              aws s3 rm "s3://delta/$dir" --recursive --endpoint-url "$ENDPOINT"
            fi
          done
    '';
  };

  systemd.timers.delta-r2-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 3d";
  };

  nix.extraOptions = ''
    min-free = ${toString (100 * 1024 * 1024)}
    max-free = ${toString (1024 * 1024 * 1024)}
  '';

  system.stateVersion = "24.11";
}
