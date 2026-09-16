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

      # ── Declare-once ext tables (the single source of truth). ──
      # Each ext is declared exactly once: the package to bundle plus
      # its in-package entry name (hooks carry their binary + windows).
      # Every build list (rushi.external_*) and every runtime value in
      # the generated config (tool paths, ui-ext names, [tools] set,
      # hook commands) derives from these tables in pure Nix, at eval
      # time. To add or drop an ext, edit one row. `entry`/`bin` are
      # not derivable from the package (its pname is e.g.
      # "goal_blocked-tool", not the entry dir "goal_blocked"), so
      # they are carried here. No shell discovery needed: the kernel's
      # #10 build-time discovery still runs but only backstops these
      # values (deduped merge); its hook drift guard still verifies
      # every command resolves to a bundled binary.
      exts = system: {
        # Native kernel tools: manifest dir (relative to the package
        # root) + tool name. Drives native_tool_paths and [tools].
        nativeTools = [
          { path = "tools/bash"; name = "bash"; }
          { path = "tools/edit"; name = "edit"; }
          { path = "tools/read"; name = "read"; }
          { path = "tools/write"; name = "write"; }
        ];
        # External tools: package to bundle + entry dir under tools/.
        extTools = [
          { pkg = goalFlake.packages.${system}.goal; entry = "goal"; }
          { pkg = goalFlake.packages.${system}."goal-blocked"; entry = "goal_blocked"; }
          { pkg = goalFlake.packages.${system}."goal-complete"; entry = "goal_complete"; }
          { pkg = obscuraWebFlake.packages.${system}."web-fetch"; entry = "web_fetch"; }
          { pkg = obscuraWebFlake.packages.${system}."web-search"; entry = "web_search"; }
        ];
        # External UI extensions: package to bundle + entry dir under
        # ui_extensions/.
        extUi = [
          { pkg = goalFlake.packages.${system}."goal-ext"; entry = "goal"; }
          { pkg = seFlake.packages.${system}."simple-english-ext"; entry = "simple-english"; }
          { pkg = statuslineFlake.packages.${system}.statusline; entry = "statusline"; }
        ];
        # External hooks: package to bundle, binary name inside hooks/,
        # and the [[hooks.on]] windows that fire it.
        extHooks = [
          { pkg = goalFlake.packages.${system}."hook-goal-idle"; bin = "harness-hook-goal-idle"; windows = [ "run.idle" ]; }
          { pkg = goalFlake.packages.${system}."hook-goal-compact"; bin = "harness-hook-goal-compact"; windows = [ "compact.before" ]; }
          { pkg = goalFlake.packages.${system}."hook-goal-tools"; bin = "harness-hook-goal-tools"; windows = [ "tool.before" ]; }
          { pkg = goalFlake.packages.${system}."hook-goal-arm"; bin = "harness-hook-goal-arm"; windows = [ "model.before" ]; }
          { pkg = nfgFlake.packages.${system}."hook-no-find-grep"; bin = "harness-hook-no-find-grep"; windows = [ "tool.before" ]; }
          { pkg = seFlake.packages.${system}."hook-simple-english"; bin = "harness-hook-simple-english"; windows = [ "tool.before" "model.before" "run.idle" ]; }
        ];
        # Kernel-shipped hooks (bundled by the kernel in bin/, not by
        # any external package). No external_hooks entry.
        kernelHooks = [
          { command = "harness-hook-compact"; windows = [ "exhausted.handle" "overflow.resolve" ]; }
        ];
      };
      # Flatten { command; windows } regs into [[hooks.on]] rows.
      hookOn = regs: builtins.concatLists (
        builtins.map (r: builtins.map (w: { window = w; command = r.command; args = [ ]; }) r.windows) regs
      );
      # Flatten { pkg; bin; windows } regs into [[hooks.on]] rows.
      extHookOn = regs: builtins.concatLists (
        builtins.map (r: builtins.map (w: { window = w; command = r.bin; args = [ ]; }) r.windows) regs
      );

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
          # The declare-once exts table (top of this flake), resolved for
          # this system. Every build list and runtime value below derives
          # from `e`.
          e = exts system;
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
          # tool found. extension_tool_paths is likewise an explicit,
          # real-path list: it derives from the exts table (one entry per
          # bundled ext tool) rather than being auto-derived at build time.
          rushi.config.paths = {
            sessions_root = "sessions";
            native_tool_paths = map (t: t.path) e.nativeTools;
            extension_tool_paths = map (t: "tools/${t.entry}") e.extTools;
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
          # $out/hooks/ (ext hooks bundled by lib.mkRushi), then PATH, and
          # guards that each command resolves (rushi#10). The `on` list is
          # derived from the single-source hook regs above: kernel-shipped
          # hooks first, then the external (Nix-bundled) ones.
          rushi.config.hooks = {
            timeout_ms = 30000;
            on = (hookOn e.kernelHooks) ++ (extHookOn e.extHooks);
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

          # ── Kernel tools ──
          # `rushi.tools` names the kernel tools to ship in the package's
          # tools/ dir; the manifest records it for `rushi setup --locked`.
          # Declared explicitly (same table as native_tool_paths, so the
          # native set has one source of truth) rather than relying on the
          # kernel's full-set default: adding a kernel tool upstream should
          # be an intentional one-row change to the exts table, not a
          # silent behavior change.
          rushi.tools = builtins.map (t: t.name) e.nativeTools;

          # ── TUI binary (Tier-2 front-end from the TUI flake). Shipped
          # at $out/bin/tui next to the package's generated config.toml
          # and bundled ui_extensions/. Since rushi-tui dd69b84 (issue
          # #11), a bare `bin/tui` with no `--config` resolves its
          # config side-by-side (`<exe_dir>/../config.toml`), so the
          # bundled extension layer loads without any wrapper shim. The
          # kernel's TUI launcher passes an explicit `--config`, which
          # still wins over every fallback step.
          rushi.tui = tuiPkg;

          # ── External tools — bundled into $out/tools. ──
          # From the exts table: one row per ext tool, both the package
          # (built + copied) and its `tools/<entry>` path (in the
          # generated config) derive from that single row.
          rushi.external_tools = builtins.map (t: t.pkg) e.extTools;

          # ── External hooks — bundled into $out/hooks. ──
          # From the exts table. The external portion of
          # rushi.config.hooks.on derives from the same rows (the kernel
          # drift-guards that each command resolves to a bundled binary).
          rushi.external_hooks = builtins.map (h: h.pkg) e.extHooks;

          # ── External UI extensions — bundled into $out/ui_extensions. ──
          # Mirrors the [tui] ext_dirs list in config-real.toml: statusline,
          # goal, simple-english (notify-rs is commented out there, so it
          # is not bundled). [tui] ext_dirs stays empty in the generated
          # config; the TUI then falls back to <config_dir>/ui_extensions,
          # which is where mkRushi copies these.
          rushi.external_ui_extensions = builtins.map (u: u.pkg) e.extUi;

          # Explicit ui-ext entry names, derived from the same exts table
          # that drives external_ui_extensions. Declaring it (rather than
          # relying on the kernel's build-time auto-discovery) makes the
          # manifest [ui_extensions] list a pure-eval artifact and keeps
          # it consistent with the bundle list; the kernel's drift guard
          # still verifies each name has a bundled entry dir.
          rushi.ui_extension_names = builtins.map (u: u.entry) e.extUi;
        };

      # Nix attrset siblings do not share scope, so the configured package
      # (the mkRushi result) is bound in the `let` and referenced by key.
      forSystem = system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ fenix.overlays.default ];
          };
          # The declare-once exts table for this system.
          e = exts system;
          # The raw TUI binary from the TUI flake.
          rawTui = tuiFlake.packages.${system}.default;
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
          extUiPkgs = builtins.map (u: u.pkg) e.extUi;
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
