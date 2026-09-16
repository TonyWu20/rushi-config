# rushi-config — the aggregator (the rushi analog of pi-config).
#
# One flake that packages the kernel + TUI front-end + config + external
# tools/hooks/UI-extensions as a single usable `rushi` package. The user
# runs it like pi-config:
#
#   nix build .#rushi       # build the configured rushi package
#   nix run   .#rushi       # run rushi from the configured package
#
# The kernel flake (rushi-kernel) provides `lib.mkRushi`; this flake feeds
# it NixOS-style modules that declare the model, limits, tools, and the
# external ext/hook/UI-ext packages. Each ext repo ships its own flake
# (Mode B, ext-flake-authoring.md), so this flake just references their
# `packages` outputs and hands them to `lib.mkRushi`.
#
# Dependency shape (a clean DAG, no cycle):
#
#   rushi-kernel (kernel, base)  <── rushi-tui (needs rushi-common from it)
#        │                                  │
#        └────────────┬─────────────────────┘
#                     ▼
#            rushi-config (this flake: the single deployable entry point)
#
# The kernel ref is pinned ONCE, here. The TUI flake's own kernel inputs
# `follows` this flake's `rushi-kernel` input, so the `rushi-common`
# crate and the kernel binary always come from the same source.

{
  description = "rushi-config — packages rushi (kernel + TUI + config + exts) as one Nix deployment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ── Kernel (provides lib.mkRushi). Pinned github ref; the lock pins
    # the exact commit. Since rushi#10 (merge bf87e41) lib.mkRushi
    # auto-derives extension_tool_paths + ui-ext names at build time,
    # defaults rushi.tools to the full kernel set, and guards hook
    # commands. Bump: `nix flake update rushi-kernel`. ──
    rushi-kernel = { url = "github:TonyWu20/rushi"; };
    rushi-tui = {

      # ── TUI front-end (Tier-2, the canonical fork). Bootstrap local. ──
      # At hosting time, flip to a pinned github ref.
      url = "github:TonyWu20/rushi-tui";
      # The TUI flake declares its own kernel input (`rushi-kernel`,
      # the launcher package). It aliases THIS flake's kernel input,
      # so there is exactly one kernel pin to maintain. `follows`
      # shares the rev structurally (a partial `nix flake update` can
      # no longer drift it). The TUI's `rushi-common` crate comes in
      # as a cargo git dep (rev pinned in its Cargo.lock), so no raw
      # source-tree input is needed anymore.
      inputs.rushi-kernel.follows = "rushi-kernel";
    };

    # ── Extension / hook repos (each is its own git repo + flake). ──
    # At hosting time, flip each to a pinned github ref.
    rushi-goal-mode = { url = "github:TonyWu20/rushi-goal-mode"; };
    no-find-grep = { url = "github:TonyWu20/no-find-grep-rushi"; };
    rushi-simple-english = { url = "github:TonyWu20/rushi-simple-english"; };
    # Local pin until the host-cwd protocol (tick cwd field + RUSHI_CWD)
    # is released and stabilized upstream. Flip back to
    # github:TonyWu20/rushi-statusline at hosting time.
    rushi-statusline = {
      url = "github:TonyWu20/rushi-statusline";
    };
    rushi-obscura-web-access = { url = "github:TonyWu20/rushi-obscura-web-access"; };
  };

  outputs = inputs @ { self, nixpkgs, fenix, ... }:
    let
      # Explicit system list + genAttrs (the kernel flake's shape).
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      pkgLib = nixpkgs.lib;

      rushiKernel = inputs."rushi-kernel";
      tuiFlake = inputs."rushi-tui";
      goalFlake = inputs."rushi-goal-mode";
      nfgFlake = inputs."no-find-grep";
      seFlake = inputs."rushi-simple-english";
      statuslineFlake = inputs."rushi-statusline";
      obscuraWebFlake = inputs."rushi-obscura-web-access";

      # ── The config module: mirrors config-real.toml (the local dev
      # config). In the Nix version, ext binaries and the TUI are bundled
      # into the package by lib.mkRushi, so hook `command` fields are the
      # BARE binary names, not local dev paths. The kernel resolves a bare
      # name against the package bin/ dir, then the package hooks/ dir,
      # then PATH.
      configModule =
        { system, tuiPkg }:
        { config, lib, pkgs, ... }:
        let
          # Single source of truth for the native tool set. Paths win over
          # names: the runtime (`route`) scans these dirs, and a tool's name
          # is just the basename of its dir. This feeds only
          # `native_tool_paths`; since rushi#10 the kernel defaults
          # `rushi.tools` to its own full tool set, so no tool whitelist
          # is declared here anymore.
          nativeToolPaths = [
            "tools/bash"
            "tools/edit"
            "tools/read"
            "tools/write"
          ];
        in
        {
          rushi.version = "0.1";

          # [model] + per-model overrides (dotted model name is quoted).
          rushi.config.model = {
            api = "responses";
            max_output_tokens = 65536;
            reasoning_effort = "xhigh";
            "Qwen3.8-27B-NVFP4-RTX5090-DFlash2" = {
              model_id = "Qwen3.8-27B-NVFP4-RTX5090-DFlash2";
              base_url = "http://127.0.0.1:30000";
              api_key_env = "LLAMA_API_KEY";
              context_tokens = 262144;
              vision = true;
            };
          };
          rushi.config.active.model = "Qwen3.8-27B-NVFP4-RTX5090-DFlash2";

          # [paths] — native tool manifest dirs resolve inside the package
          # ($out); the runtime (`route`) scans them and registers every
          # tool found.
          #
          # extension_tool_paths is no longer declared here: since rushi#10
          # lib.mkRushi auto-derives it at build time from the
          # `rushi.external_tools` list below (ext tool dirs discovered in
          # the copied $out/tools/ layout), so the external list is the
          # single source of truth.
          rushi.config.paths = {
            sessions_root = "sessions";
            native_tool_paths = nativeToolPaths;
          };

          # [limits]
          rushi.config.limits = {
            bash_timeout_max = 600;
            compact_enabled = true;
            compact_reserve_tokens = 16384;
            compact_keep_tokens = 20000;
            compact_strategy = "compact";
            context_budget_tokens = 262144;
          };

          # [hooks] — bare binary names. The kernel resolves a bare name
          # against the package bin/ dir (kernel-shipped hooks), then
          # $out/hooks/ (ext hooks bundled by lib.mkRushi), then PATH.
          rushi.config.hooks = {
            timeout_ms = 30000;
            on = [
              { window = "exhausted.handle"; command = "harness-hook-compact"; args = [ ]; }
              { window = "overflow.resolve"; command = "harness-hook-compact"; args = [ ]; }
              # goal-app goal-continuation hooks
              { window = "run.idle"; command = "harness-hook-goal-idle"; args = [ ]; }
              { window = "compact.before"; command = "harness-hook-goal-compact"; args = [ ]; }
              { window = "tool.before"; command = "harness-hook-goal-tools"; args = [ ]; }
              { window = "model.before"; command = "harness-hook-goal-arm"; args = [ ]; }
              # no-find-grep tool guard
              { window = "tool.before"; command = "harness-hook-no-find-grep"; args = [ ]; }
              # simple-english writing-rule hook (tool + model + idle windows)
              { window = "tool.before"; command = "harness-hook-simple-english"; args = [ ]; }
              { window = "model.before"; command = "harness-hook-simple-english"; args = [ ]; }
              { window = "run.idle"; command = "harness-hook-simple-english"; args = [ ]; }
            ];
          };

          # [system_prompt] — dev prompt text from config-real.toml. The
          # text lives in system-prompt.txt (byte-identical to the local dev
          # config). Empty text would fall back to the kernel default.
          rushi.config.system_prompt = {
            text = builtins.readFile ./system-prompt.txt;
          };

          # [loop]
          rushi.config.loop = {
            command = "rushi";
            args = [ "run" ];
            arg_style = "append_session";
          };

          # [tui] — TUI-owned display settings (the harness ignores these;
          # the TUI binary reads them).
          rushi.config.tui = {
            clipboard = "unnamed";
            tool_display = {
              preset = "opencode";
              bash_collapsed_lines = 5;
              highlight_engine = "tree-sitter";
              expand_mode = "click";
              anim_ms = 400;
              diff_collapsed_lines = 12;
            };
          };

          # ── Kernel tools: since rushi#10 the kernel defaults
          # `rushi.tools` to its full tool set (eval-time derivation from
          # tools/*/tool.toml), which is exactly the native set shipped
          # here — so no explicit override is declared. ──

          # ── TUI binary (Tier-2 front-end from the TUI flake). Shipped
          # at $out/bin/tui next to the package's generated config.toml
          # and bundled ui_extensions/. Since rushi-tui dd69b84 (issue
          # #11), a bare `bin/tui` with no `--config` resolves its
          # config side-by-side (`<exe_dir>/../config.toml`), so the
          # bundled extension layer loads without any wrapper shim. The
          # kernel's TUI launcher passes an explicit `--config`, which
          # still wins over every fallback step.
          rushi.tui = tuiPkg;

          # ── External tools (goal-mode) — bundled into $out/tools. ──
          rushi.external_tools = [
            goalFlake.packages.${system}.goal
            goalFlake.packages.${system}."goal-blocked"
            goalFlake.packages.${system}."goal-complete"
            obscuraWebFlake.packages.${system}."web-fetch"
            obscuraWebFlake.packages.${system}."web-search"
          ];

          # ── External hooks — bundled into $out/hooks. ──
          rushi.external_hooks = [
            goalFlake.packages.${system}."hook-goal-idle"
            goalFlake.packages.${system}."hook-goal-compact"
            goalFlake.packages.${system}."hook-goal-tools"
            goalFlake.packages.${system}."hook-goal-arm"
            nfgFlake.packages.${system}."hook-no-find-grep"
            seFlake.packages.${system}."hook-simple-english"
          ];

          # ── External UI extensions — bundled into $out/ui_extensions. ──
          # Mirrors the [tui] ext_dirs list in config-real.toml: statusline,
          # goal, simple-english (notify-rs is commented out there, so it
          # is not bundled). [tui] ext_dirs stays empty in the generated
          # config; the TUI then falls back to <config_dir>/ui_extensions,
          # which is where mkRushi copies these.
          rushi.external_ui_extensions = [
            statuslineFlake.packages.${system}.statusline
            goalFlake.packages.${system}."goal-ext"
            seFlake.packages.${system}."simple-english-ext"
          ];

          # rushi.ui_extension_names is no longer declared: since rushi#10
          # lib.mkRushi auto-discovers the ext entry dir names at build
          # time from the bundled $out/ui_extensions/ layout (each holds
          # ext.toml) and records them in tools.manifest. It remains an
          # optional drift-guard override, so we omit it (declare-once).
        };

      # Nix attrset siblings do not share scope, so the configured package
      # (the mkRushi result) is bound in the `let` and referenced by key.
      forSystem = system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ fenix.overlays.default ];
          };
          # The raw TUI binary from the TUI flake.
          rawTui = tuiFlake.packages.${system}.default;
          #
          # ── TUI binary for the configured package: the raw TUI as-is.
          # rushi-tui since dd69b84 (issue #11) resolves its config
          # side-by-side with the binary (<exe_dir>/../config.toml,
          # after the --config flag and $CONFIG). Because mkRushi installs
          # it into the configured package's bin/ next to the generated
          # config.toml and bundled ui_extensions/, the bare binary loads
          # the bundled extension layer with no wrapper. An earlier
          # shell-shim version is obsolete now that the TUI resolves
          # side-by-side natively.
          tuiPkg = rawTui;
          # The fully configured rushi: kernel + TUI + config + exts.
          mk = rushiKernel.lib.mkRushi {
            inherit pkgs;
            modules = [ (configModule { inherit system tuiPkg; }) ];
          };
          #
          # ── The self-contained TUI package the flake delivers as `tui`.
          # rawTui + the generated config.toml (byte-identical to the
          # configured package's, from mk.config) + the bundled
          # ui_extensions/, all laid out side by side. Since rushi-tui
          # dd69b84 (issue #11) the bare binary resolves its config
          # next to itself (<exe_dir>/../config.toml, after the
          # --config flag and $CONFIG), so no wrapper is needed: the
          # binary shipped at bin/tui finds config.toml and the
          # bundled extension layer in the same directory tree.
          extUiPkgs = [
            statuslineFlake.packages.${system}.statusline
            goalFlake.packages.${system}."goal-ext"
            seFlake.packages.${system}."simple-english-ext"
          ];
          tuiConfigFile = pkgs.writeText "rushi-tui-config.toml" mk.config;
          # Copy each bundled ext package into $out/ui_extensions/ (the
          # same layout logic as lib.mkRushi's extUiScript). Since
          # rushi#10 entry-dir names are auto-discovered (each ext.toml
          # dir), so each source must ship one, else the build fails
          # with a clear error instead of silently dropping the ext.
          extUiCopyScript = builtins.concatStringsSep "\n" (
            builtins.map
              (s:
                let sp = if builtins.isString s then s else toString s; in
                ''
                  # External UI ext source: ${sp}
                  if [ ! -d "${sp}" ]; then
                    echo "rushi-tui: UI ext source ${sp} is missing or not a directory" >&2
                    exit 1
                  fi
                  ext_toml=""
                  for t in "${sp}"/ext.toml "${sp}"/*/ext.toml; do
                    if [ -f "$t" ]; then ext_toml="$t"; break; fi
                  done
                  if [ -z "$ext_toml" ]; then
                    echo "rushi-tui: UI ext source ${sp} ships no ext.toml (broken ext)" >&2
                    exit 1
                  fi
                  cp -rL "${sp}/." "$out/ui_extensions/"
                ''
              )
              extUiPkgs
          );
          tuiFull = pkgs.stdenv.mkDerivation {
            pname = "rushi-tui";
            version = "0.1";
            nativeBuildInputs = [ rawTui ] ++ extUiPkgs;
            unpackPhase = "true";
            installPhase = ''
              mkdir -p $out/bin $out/ui_extensions
              # The raw TUI binary, shipped beside its config.toml and
              # ui_extensions/ so the TUI's native side-by-side config
              # resolution (rushi-tui dd69b84, issue #11) finds them.
              # No wrapper: an explicit --config still wins over every
              # fallback step in the TUI.
              cp ${rawTui}/bin/tui $out/bin/tui
              chmod +x $out/bin/tui
              ${extUiCopyScript}
              # ${tuiConfigFile} interpolates the writeText store path
              # (added to the closure automatically as a build dep).
              cp ${tuiConfigFile} $out/config.toml
              test -x $out/bin/tui || { echo "ERROR: tui binary missing"; exit 1; }
            '';
            meta = with pkgs.lib; {
              description = "Self-contained rushi TUI (bundled config + UI extensions)";
              mainProgram = "tui";
            };
          };
        in
        {
          default = mk.package;
          rushi = mk.package;
          # Raw kernel binary (no user config), for `rushi setup` / dev.
          rushi-kernel = rushiKernel.packages.${system}.rushi;
          # The self-contained TUI front-end: raw tui + generated
          # config.toml + bundled ui_extensions/ + the side-by-side
          # config shim, so a delivered `tui` loads its extensions.
          tui = tuiFull;
        };
    in
    {
      packages = pkgLib.genAttrs supportedSystems forSystem;

      # Re-expose the kernel's NixOS / home-manager modules so a consumer
      # config can do `programs.rushi.enable = true; package = <pkg>;`.
      nixosModules = {
        rushi = rushiKernel.nixosModules.rushi;
      };
      homeManagerConfig = {
        rushi = rushiKernel.homeManagerConfig.rushi;
      };

      # Dev shell with the configured rushi on PATH.
      devShells = pkgLib.genAttrs supportedSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ fenix.overlays.default ];
          };
          configured = self.packages.${system}.default;
          # External hook binaries live in the package's hooks/ dir
          # (lib.mkRushi), not bin/. The devShell mechanism only exposes
          # a buildInput's bin/ dirs on PATH, so a bare hook command name
          # is not found on PATH. The current kernel resolves bare names
          # against <exe_dir>/../hooks/ when it runs from the package,
          # but a binary built before that kernel fix (an older store
          # build) still needs the PATH entry. This shim re-exposes the
          # package's hooks/ as a bin/ dir so the devShell mechanism
          # picks it up.
          hookPathShim = pkgs.stdenv.mkDerivation {
            pname = "rushi-hook-shim";
            version = "0.1";
            nativeBuildInputs = [ configured ];
            unpackPhase = "true";
            installPhase = ''
              mkdir -p $out/bin
              if [ -d ${configured}/hooks ]; then
                cp -rL ${configured}/hooks/. $out/bin/
              fi
            '';
          };
        in
        {
          default = pkgs.mkShell {
            buildInputs = [ configured hookPathShim ];
            shellHook = ''
              echo "Configured rushi (v${configured.version})."
              echo "  bin/           rushi + all stage/tool/hook binaries + tui"
              echo "  tools/         kernel + external tool manifests"
              echo "  ui_extensions/ external UI extension files"
              echo "  hooks/         external hook binaries"
              echo "  config.toml    generated from the Nix module options"
              echo "Run:  $PWD/bin/rushi"
            '';
          };
        });
    };
}
