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

    # ── Kernel (provides lib.mkRushi). Bootstrap local checkout. ──
    # At hosting time, flip to a pinned github ref:
    #   url = "github:TonyWu20/rust-unix-harness?ref=v0.1.0";
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

      # ── The config module: mirrors config-real.toml (the local dev
      # config). In the Nix version, ext binaries and the TUI are bundled
      # into the package by lib.mkRushi, so hook `command` fields are the
      # BARE binary names, not local dev paths. The kernel resolves a bare
      # name against the package bin/ dir, then the package hooks/ dir,
      # then PATH.
      configModule =
        { system, tuiPkg }:
        { config, lib, pkgs, ... }:
        {
          rushi.version = "0.1";

          # [model] + per-model overrides (dotted model name is quoted).
          rushi.config.model = {
            api = "responses";
            max_output_tokens = 32768;
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

          # [paths] — kernel-native tool paths resolve inside the package
          # ($out/tools). The ext tool manifests are bundled into $out/tools
          # by rushi.external_tools below; extension_tool_paths lists them so
          # the kernel registers the goal tools at runtime (mirrors the
          # goal-tools group dir in config-real.toml). The dir names must
          # match the external_tools bundle.
          rushi.config.paths = {
            sessions_root = "sessions";
            native_tool_paths = [ "tools/bash" "tools/edit" "tools/read" "tools/write" ];
            extension_tool_paths = [ "tools/goal" "tools/goal_blocked" "tools/goal_complete" ];
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

          # ── Kernel tools (whitelist from the kernel's bundled set). ──
          rushi.tools = [ "read" "write" "edit" "bash" ];

          # ── TUI binary (Tier-2 front-end from the TUI flake). Shipped
          # at $out/bin/tui so the kernel's side-by-side resolver finds it.
          # The derivation is shimmed (tuiPkg, see forSystem): a bare
          # `bin/tui` picks up the package's sibling config.toml, which
          # is what makes the bundled ui_extensions/ layer reachable.
          # The kernel's TUI launcher always passes --config, so the shim
          # is a no-op on that path.
          rushi.tui = tuiPkg;

          # ── External tools (goal-mode) — bundled into $out/tools. ──
          rushi.external_tools = [
            goalFlake.packages.${system}.goal
            goalFlake.packages.${system}."goal-blocked"
            goalFlake.packages.${system}."goal-complete"
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

          # The entry directory names of the packages above, as shipped in
          # $out/ui_extensions/ and as the TUI's extension discovery names
          # them. Declared here so the generated tools.manifest lists the
          # bundled UI extensions (rushi.ui_extension_names), keeping the
          # manifest truthful for `rushi setup --locked`. The order mirrors
          # external_ui_extensions.
          rushi.ui_extension_names = [ "statusline" "goal" "simple-english" ];
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
          # ── The self-contained TUI front-end the flake delivers. ──
          # The raw tui binary resolves `--config` against the process CWD
          # (default `config.toml`). The Nix package puts its generated
          # `config.toml` and the bundled `ui_extensions/` layer at the
          # package root, but a raw binary run on its own cannot know that,
          # so the TUI's `<config_dir>/ui_extensions` extension fallback
          # (empty `[tui] ext_dirs`) resolves against the CWD and finds no
          # bundled extensions. The `rushi` kernel resolves its config
          # side-by-side (`<exe_dir>/../config.toml`) and passes an explicit
          # `--config`, so `bin/rushi` already works; to make the delivered
          # `bin/tui` self-contained too, ship a thin shim as the tui: when
          # the caller did not pass `--config` / `--config=…`, inject the
          # side-by-side `config.toml`. An explicit `--config` (what the
          # kernel passes) is honored as-is. This mirrors the kernel's own
          # side-by-side resolution.
          #
          # mkRushi installs this derivation's `bin/tui` into the configured
          # package and adds it to that package's build inputs, so the raw
          # tui store path the shim `exec`s is guaranteed present in the
          # final closure.
          tuiPkg = pkgs.stdenv.mkDerivation {
            pname = "rushi-tui";
            version = "0.1";
            nativeBuildInputs = [ rawTui ];
            unpackPhase = "true";
            installPhase = ''
              mkdir -p $out/bin
              cat > $out/bin/tui <<'SHIM'
              #!/bin/sh
              # rushi-tui side-by-side config shim (see the flake comment
              # for why). Honor an explicit --config; otherwise default to
              # the config.toml that sits next to this binary in the
              # package layout, so the TUI's <config_dir>/ui_extensions
              # fallback finds the bundled UI extensions.
              dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
              have=""
              for a in "$@"; do
                case "$a" in
                  --config|--config=*) have=1 ;;
                esac
              done
              if [ -n "$have" ]; then
                exec ${rawTui}/bin/tui "$@"
              else
                exec ${rawTui}/bin/tui "$@" --config "$dir/config.toml"
              fi
              SHIM
              chmod +x $out/bin/tui
            '';
          };
          # The fully configured rushi: kernel + TUI + config + exts.
          mk = rushiKernel.lib.mkRushi {
            inherit pkgs;
            modules = [ (configModule { inherit system tuiPkg; }) ];
          };
        in
        {
          default = mk.package;
          rushi = mk.package;
          # Raw kernel binary (no user config), for `rushi setup` / dev.
          rushi-kernel = rushiKernel.packages.${system}.rushi;
          # The TUI binary on its own (raw; the self-contained tui lives in
          # the configured package's bin/).
          tui = rawTui;
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
