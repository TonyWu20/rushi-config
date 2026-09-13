# rushi-config — the aggregator (the rushi analog of pi-config).
#
# One flake that packages the kernel + TUI front-end + config + external
# tools/hooks/UI-extensions as a single usable `rushi` package. The user
# runs it like pi-config:
#
#   nix build .#rushi       # build the configured rushi package
#   nix run   .#rushi       # run rushi from the configured package
#
# The kernel flake (rushi-flake) provides `lib.mkRushi`; this flake feeds
# it NixOS-style modules that declare the model, limits, tools, and the
# external ext/hook/UI-ext packages. Each ext repo ships its own flake
# (Mode B, ext-flake-authoring.md), so this flake just references their
# `packages` outputs and hands them to `lib.mkRushi`.
#
# Dependency shape (a clean DAG, no cycle):
#
#   rushi-flake (kernel, base)  <── rushi-tui (needs rushi-common from it)
#        │                                  │
#        └────────────┬─────────────────────┘
#                     ▼
#            rushi-config (this flake: the single deployable entry point)
#
# The kernel ref is pinned ONCE, here. The TUI flake's own kernel inputs
# are overridden to point at the same kernel, so the `rushi-common`
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
    rushi-flake = { url = "path:/home/tony/programming/rust-unix-harness"; };

    # ── TUI front-end (Tier-2, the canonical fork). Bootstrap local. ──
    # At hosting time, flip to a pinned github ref.
    rushi-tui = { url = "path:/home/tony/programming/rushi-tui-ratatui-widget-based"; };
    # Keep the TUI's kernel inputs in lockstep with THIS consumer's kernel
    # pin. Without this, the TUI flake's own bootstrap inputs could drift
    # to a different kernel ref than the one the consumer builds.
    rushi-tui.inputs.rushi-kernel.url = "path:/home/tony/programming/rust-unix-harness";
    rushi-tui.inputs.rushi-kernel-src.url = "path:/home/tony/programming/rust-unix-harness";

    # ── Extension / hook repos (each is its own git repo + flake). ──
    # At hosting time, flip each to a pinned github ref.
    rushi-goal-mode = { url = "path:/home/tony/programming/rushi-exts/goal-app"; };
    no-find-grep = { url = "path:/home/tony/programming/rushi-exts/no-find-grep"; };
    rushi-simple-english = { url = "path:/home/tony/programming/rushi-simple-english"; };
  };

  outputs = inputs @ { self, nixpkgs, fenix, ... }:
    let
      # Explicit system list + genAttrs (the kernel flake's shape).
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      pkgLib = nixpkgs.lib;

      rushiFlake = inputs."rushi-flake";
      tuiFlake = inputs."rushi-tui";
      goalFlake = inputs."rushi-goal-mode";
      nfgFlake = inputs."no-find-grep";
      seFlake = inputs."rushi-simple-english";

      # ── The config module: mirrors config-real.toml (the local dev
      # config). In the Nix version, ext binaries and the TUI are bundled
      # into the package by lib.mkRushi, so hook `command` fields are the
      # BARE binary names (resolved from $out/hooks/), not local dev paths.
      configModule =
        { system }:
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
          # ($out/tools). External tool paths are NOT set: the ext tools
          # are bundled into $out/tools by rushi.external_tools below.
          rushi.config.paths = {
            sessions_root = "sessions";
            native_tool_paths = [ "tools/bash" "tools/edit" "tools/read" "tools/write" ];
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

          # [hooks] — bare binary names; the external hook packages are
          # copied into $out/hooks by lib.mkRushi and the kernel resolves
          # the command from there.
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
          rushi.tui = tuiFlake.packages.${system}.default;

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
          rushi.external_ui_extensions = [
            goalFlake.packages.${system}."goal-ext"
            seFlake.packages.${system}."simple-english-ext"
          ];
        };

      # Nix attrset siblings do not share scope, so the configured package
      # (the mkRushi result) is bound in the `let` and referenced by key.
      forSystem = system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ fenix.overlays.default ];
          };
          # The fully configured rushi: kernel + TUI + config + exts.
          mk = rushiFlake.lib.mkRushi {
            inherit pkgs;
            modules = [ (configModule { inherit system; }) ];
          };
        in
        {
          default = mk.package;
          rushi = mk.package;
          # Raw kernel binary (no user config), for `rushi setup` / dev.
          rushi-kernel = rushiFlake.packages.${system}.rushi;
          # The TUI binary on its own.
          tui = tuiFlake.packages.${system}.default;
        };
    in
    {
      packages = pkgLib.genAttrs supportedSystems forSystem;

      # Re-expose the kernel's NixOS / home-manager modules so a consumer
      # config can do `programs.rushi.enable = true; package = <pkg>;`.
      nixosModules = {
        rushi = rushiFlake.nixosModules.rushi;
      };
      homeManagerConfig = {
        rushi = rushiFlake.homeManagerConfig.rushi;
      };

      # Dev shell with the configured rushi on PATH.
      devShells = pkgLib.genAttrs supportedSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ fenix.overlays.default ];
          };
          configured = self.packages.${system}.default;
        in
        {
          default = pkgs.mkShell {
            buildInputs = [ configured ];
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
