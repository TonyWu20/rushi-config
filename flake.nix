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

    # Every sub-flake input below follows this flake's `nixpkgs` and
    # `fenix`, so the whole build graph shares one nixpkgs revision and
    # one Rust toolchain. Without this each sub-flake pulls its own
    # nixpkgs + fenix, which duplicates toolchains and risks version
    # drift between the kernel, the TUI, and the ext packages.

    # ── Kernel (provides lib.mkRushi). Pinned github ref; the lock pins
    # the exact commit. Since rushi#13 lib.mkRushi reads each producer's
    # meta.rushi at eval time (tool paths, ui-ext names, hook command
    # guard) and defaults rushi.tools to the full kernel set.
    # Bump: `nix flake update rushi-kernel`. ──
    rushi-kernel = {
      url = "github:TonyWu20/rushi";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fenix.follows = "fenix";
    };
    rushi-tui = {
      # ── TUI front-end (Tier-2, the canonical fork). Bootstrap local. ──
      # At hosting time, flip to a pinned github ref.
      url = "github:TonyWu20/rushi-tui";
      # The TUI flake declares its own kernel input (`rushi-kernel`,
      # the launcher package). It aliases THIS flake's kernel input,
      # so there is exactly one kernel pin to maintain. `follows`
      # shares the rev structurally (a partial `nix flake update` can
      # no longer drift it). The TUI's `rushi-common` crate is pinned
      # to the crates.io release 0.1.5 (rushi-tui issue #22), so no
      # raw source-tree input is needed.
      inputs.rushi-kernel.follows = "rushi-kernel";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fenix.follows = "fenix";
    };

    # ── Extension / hook repos (each is its own git repo + flake). ──
    # At hosting time, flip each to a pinned github ref.
    rushi-goal-mode = {
      url = "github:TonyWu20/rushi-goal-mode";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fenix.follows = "fenix";
    };
    no-find-grep = {
      url = "github:TonyWu20/no-find-grep-rushi";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fenix.follows = "fenix";
    };
    rushi-simple-english = {
      url = "github:TonyWu20/rushi-simple-english";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fenix.follows = "fenix";
    };
    # Local pin until the host-cwd protocol (tick cwd field + RUSHI_CWD)
    # is released and stabilized upstream. Flip back to
    # github:TonyWu20/rushi-statusline at hosting time.
    rushi-statusline = {
      url = "github:TonyWu20/rushi-statusline";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fenix.follows = "fenix";
    };
    rushi-obscura-web-access = {
      url = "github:TonyWu20/rushi-obscura-web-access";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fenix.follows = "fenix";
    };
    # ── mermaid TUI transform ext (UI-ext repo, Mode B). ──
    rushi-tui-mermaid-ext = {
      url = "github:TonyWu20/rushi-tui-mermaid-ext";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fenix.follows = "fenix";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      fenix,
      ...
    }:
    let
      # Explicit system list + genAttrs (the kernel flake's shape).
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      pkgLib = nixpkgs.lib;

      rushiKernel = inputs."rushi-kernel";
      tuiFlake = inputs."rushi-tui";
      goalFlake = inputs."rushi-goal-mode";
      nfgFlake = inputs."no-find-grep";
      seFlake = inputs."rushi-simple-english";
      statuslineFlake = inputs."rushi-statusline";
      obscuraWebFlake = inputs."rushi-obscura-web-access";
      mermaidExtFlake = inputs."rushi-tui-mermaid-ext";

      # ── Declare-once ext tables (the single source of truth). ──
      # Each ext is declared exactly once: the package to bundle plus
      # (for hooks) the [[hooks.on]] windows that fire it. Every build
      # list (rushi.external_*) and every runtime value in the generated
      # config (tool paths, ui-ext names, hook commands) derives from
      # these tables in pure Nix, at eval time. To add or drop an ext,
      # edit one row.
      #
      # Since rushi#13 the kernel reads each producer's meta.rushi at
      # eval time: tools set meta.rushi.entry, UI-exts set
      # meta.rushi.ext, hooks set meta.rushi.bin. extension_tool_paths
      # and the manifest ui-ext list are derived from those declarations,
      # and a hook command matching a declared bin is drift-guard-exempt.
      # So this table no longer re-types the entry dir or the binary name.
      exts = system: {
        # Native kernel tools: manifest dir (relative to the package
        # root) + tool name. Drives native_tool_paths and [tools].
        nativeTools = [
          {
            path = "tools/bash";
            name = "bash";
          }
          {
            path = "tools/edit";
            name = "edit";
          }
          {
            path = "tools/read";
            name = "read";
          }
          {
            path = "tools/write";
            name = "write";
          }
        ];
        # External tools. meta.rushi.entry (issue #13) supplies the
        # tools/<entry> path in the generated config at eval time.
        extTools = [
          { pkg = goalFlake.packages.${system}.goal; }
          { pkg = goalFlake.packages.${system}."goal-blocked"; }
          { pkg = goalFlake.packages.${system}."goal-complete"; }
          { pkg = obscuraWebFlake.packages.${system}."web-fetch"; }
          { pkg = obscuraWebFlake.packages.${system}."web-search"; }
        ];
        # External UI extensions. meta.rushi.ext (issue #13) supplies the
        # manifest [ui_extensions] entry name at eval time.
        extUi = [
          { pkg = goalFlake.packages.${system}."goal-ext"; }
          { pkg = seFlake.packages.${system}."simple-english-ext"; }
          { pkg = statuslineFlake.packages.${system}.statusline; }
          { pkg = mermaidExtFlake.packages.${system}."mermaid-ext"; }
        ];
        # External hooks: package to bundle + the [[hooks.on]] windows
        # that fire it. The bare command name comes from the producer's
        # meta.rushi.bin (issue #13), so it is not re-typed here.
        extHooks = [
          {
            pkg = goalFlake.packages.${system}."hook-goal-idle";
            windows = [ "run.idle" ];
          }
          {
            pkg = goalFlake.packages.${system}."hook-goal-compact";
            windows = [ "compact.before" ];
          }
          {
            pkg = goalFlake.packages.${system}."hook-goal-tools";
            windows = [ "tool.before" ];
          }
          {
            pkg = goalFlake.packages.${system}."hook-goal-arm";
            windows = [ "model.before" ];
          }
          {
            pkg = goalFlake.packages.${system}."hook-goal-tokens";
            windows = [ "model.after" ];
          }
          {
            pkg = nfgFlake.packages.${system}."hook-no-find-grep";
            windows = [ "tool.before" ];
          }
          {
            pkg = seFlake.packages.${system}."hook-simple-english";
            windows = [
              "tool.before"
              "model.before"
              "run.idle"
            ];
          }
        ];
        # Kernel-shipped hooks (bundled by the kernel in bin/, not by
        # any external package). No external_hooks entry.
        kernelHooks = [
          {
            command = "harness-hook-compact";
            windows = [
              "exhausted.handle"
              "overflow.resolve"
            ];
          }
        ];
      };
      # Flatten { command; windows } regs into [[hooks.on]] rows.
      hookOn =
        regs:
        builtins.concatLists (
          map (
            r:
            map (w: {
              window = w;
              command = r.command;
              args = [ ];
            }) r.windows
          ) regs
        );
      # Flatten { pkg; windows } regs into [[hooks.on]] rows. The bare
      # command is the producer's meta.rushi.bin (issue #13), so the binary
      # name is read once on the producer side, not re-typed here.
      extHookOn =
        regs:
        builtins.concatLists (
          map (
            r:
            map (w: {
              window = w;
              command = r.pkg.meta.rushi.bin;
              args = [ ];
            }) r.windows
          ) regs
        );

      # ── The config module: mirrors config-real.toml (the local dev
      # config). In the Nix version, ext binaries and the TUI are bundled
      # into the package by lib.mkRushi, so hook `command` fields are the
      # BARE binary names, not local dev paths. The kernel resolves a bare
      # name against the package bin/ dir, then the package hooks/ dir,
      # then PATH.
      # `toolPaths` (optional): absolute tool-manifest paths for this
      # config. null (the default) keeps the relative `tools/...`
      # layout entries, which are valid for a package that bundles
      # tools/ next to its config. The self-contained TUI package
      # ships no tools/ dir, so it passes absolute store paths instead
      # (the Nix derivations' outPaths).
      configModule =
        { system, tuiPkg, toolPaths ? null }:
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          # The declare-once exts table (top of this flake), resolved for
          # this system. Every build list and runtime value below derives
          # from `e`.
          e = exts system;
          # The [paths] tool entries. Relative by default (the configured
          # package bundles tools/ next to its config, so the relative
          # entries resolve). The TUI variant passes absolute store
          # paths because its package ships no tools/ dir.
          toolPathAttrs =
            if toolPaths == null then
              { native_tool_paths = map (t: t.path) e.nativeTools; }
            else
              {
                native_tool_paths = toolPaths.native;
                extension_tool_paths = toolPaths.ext;
              };
        in
        {
          rushi = {
            config = {
              active = {
                model = "Qwen3.8-27B-NVFP4-RTX5090-DFlash2";
              };
              hooks = {
                on = (hookOn e.kernelHooks) ++ (extHookOn e.extHooks);
                timeout_ms = 30000;
              };
              limits = {
                bash_timeout_max = 600;
                compact_enabled = true;
                compact_keep_tokens = 20000;
                compact_reserve_tokens = 16384;
                compact_strategy = "compact";
                context_budget_tokens = 262144;
              };
              loop = {
                arg_style = "append_session";
                args = [ "run" ];
                command = "rushi";
              };
              model = {
                "Qwen3.8-27B-NVFP4-RTX5090-DFlash2" = {
                  api_key_env = "LLAMA_API_KEY";
                  base_url = "http://127.0.0.1:30000";
                  context_tokens = 262144;
                  model_id = "Qwen3.8-27B-NVFP4-RTX5090-DFlash2";
                  vision = true;
                };
                api = "responses";
                max_output_tokens = 65536;
                reasoning_effort = "xhigh";
              };
              paths = toolPathAttrs // {
                sessions_root = "sessions";
              };
              system_prompt = {
                text = builtins.readFile ./system-prompt.txt;
              };
              tui = {
                clipboard = "unnamed";
                tool_display = {
                  anim_ms = 400;
                  bash_collapsed_lines = 5;
                  diff_collapsed_lines = 12;
                  expand_mode = "click";
                  highlight_engine = "tree-sitter";
                  preset = "opencode";
                };
              };
            };
            external_hooks = map (h: h.pkg) e.extHooks;
            external_tools = map (t: t.pkg) e.extTools;
            external_ui_extensions = map (u: u.pkg) e.extUi;
            tools = map (t: t.name) e.nativeTools;
            tui = tuiPkg;
            version = "0.1";
          };

          # ui_extension_names is left unset so the kernel (rushi#13)
          # fills the manifest [ui_extensions] list at eval time from
          # each producer's meta.rushi.ext. The kernel's drift guard
          # still verifies each name has a bundled entry dir.
        };

      # Nix attrset siblings do not share scope, so the configured package
      # (the mkRushi result) is bound in the `let` and referenced by key.
      forSystem =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ fenix.overlays.default ];
          };
          moldStdenv = pkgs.stdenvAdapters.useMoldLinker pkgs.clangStdenv;
          # The declare-once exts table for this system.
          e = exts system;
          # The raw TUI package from the TUI flake. Since the
          # self-wired entry (rushi-tui issue #22,
          # docs/tui-self-wired-entry.md) the package ships a single
          # `rushi-tui` binary at bin/rushi-tui; the old `bin/tui`
          # name is gone.
          rawTui = tuiFlake.packages.${system}.default;
          # ── TUI binary for the configured package.
          # Since rushi-tui dd69b84 (issue #11) the TUI resolves its
          # config side-by-side with the binary
          # (<exe_dir>/../config.toml), so the bare binary installed
          # into the configured package's bin/ next to the generated
          # config.toml and bundled ui_extensions/ loads the bundled
          # extension layer with no wrapper. An earlier shell-shim
          # version is obsolete now that the TUI resolves side-by-side
          # natively.
          #
          # Transition bridge (RETIRE when kernel rushi#31 lands:
          # then pass rawTui straight to rushi.tui and drop this).
          # The locked kernel mk-rushi (04ba2e8) still copies
          # `$TUI_SRC/bin/tui` into the configured package's bin/.
          # The self-wired TUI (issue #22) ships only `bin/rushi-tui`,
          # so this wrapper feeds the binary into that `bin/tui`
          # slot. Cutover policy (2026-09-22, user decision): no
          # `bin/rushi-tui` alias is carried alongside. When the
          # kernel ships the #31 fix, the configured package carries
          # only `bin/rushi-tui` and this wrapper is deleted.
          tuiPkg = pkgs.stdenv.mkDerivation {
            pname = "rushi-tui-bin-compat";
            version = "0.1";
            nativeBuildInputs = [ rawTui ];
            unpackPhase = "true";
            installPhase = ''
              mkdir -p $out/bin
              cp ${rawTui}/bin/rushi-tui $out/bin/tui
            '';
          };
          # The fully configured rushi: kernel + TUI + config + exts.
          # Its config keeps the bundled relative tool paths: the
          # package ships tools/ next to its config.toml, so the
          # relative entries resolve inside the package's own closure.
          mk = rushiKernel.lib.mkRushi {
            inherit pkgs;
            modules = [ (configModule { inherit system tuiPkg; }) ];
          };
          # The raw kernel package (bin/ + tools/ + tools.manifest):
          # the absolute store home of the native tool manifests.
          kernelRaw = rushiKernel.packages.${system}.rushi;
          # Absolute tool paths for the self-contained TUI package's
          # config. The TUI package ships no tools/ dir (the kernel/TUI
          # separation is intentional), so its config must point at the
          # tool manifests' store locations: the raw kernel package's
          # tools/ for the native set, each ext tool package's outPath
          # for the external set. Relative entries would dangle against
          # the TUI package root and the model would start every
          # session with zero tool schemas.
          absToolPaths = {
            native = map (t: "${kernelRaw}/tools/${t.name}") e.nativeTools;
            ext = map (t: if builtins.isString t.pkg then t.pkg else "${t.pkg}") e.extTools;
          };
          # The TUI variant of the generated config: same content as
          # mk.config, with absolute tool paths instead of the bundled
          # relative ones.
          mkTui = rushiKernel.lib.mkRushi {
            inherit pkgs;
            modules = [ (configModule { inherit system tuiPkg; toolPaths = absToolPaths; }) ];
          };
          #
          # ── The self-contained TUI package the flake delivers as
          # `rushi-tui` (the `tui` key is kept as a pre-issue-#22
          # alias). rawTui + the generated TUI config.toml (absolute
          # tool paths, from mkTui.config) + the bundled
          # ui_extensions/, all laid out side by side. Since rushi-tui
          # dd69b84 (issue #11) the bare binary resolves its config
          # next to itself (<exe_dir>/../config.toml; the shared
          # resolver added in issue #22 / kernel PR #30 checks $CONFIG
          # first, then the --config flag, then side-by-side with the
          # exe canonicalized, then CWD), so no wrapper is needed:
          # the binary shipped at bin/rushi-tui finds config.toml and
          # the bundled extension layer in the same directory tree.
          # Self-wired loop (issue #22): when the config has a [loop]
          # section the TUI supervises exactly that command (here:
          # `rushi run <session>`); otherwise it falls back to the
          # Tier-1 `rushi` CLI from PATH. No kernel launcher
          # subcommand is involved.
          extUiPkgs = map (u: u.pkg) e.extUi;
          # Store derivations of the ext tool packages: referenced by
          # the TUI config's absolute extension_tool_paths.
          extToolPkgs = map (t: t.pkg) e.extTools;
          tuiConfigFile = pkgs.writeText "rushi-tui-config.toml" mkTui.config;
          # Copy each bundled ext package into $out/ui_extensions/ (the
          # same layout logic as lib.mkRushi's extUiScript). Since
          # rushi#10 entry-dir names are auto-discovered (each ext.toml
          # dir), so each source must ship one, else the build fails
          # with a clear error instead of silently dropping the ext.
          extUiCopyScript = builtins.concatStringsSep "\n" (
            map (
              s:
              let
                sp = if builtins.isString s then s else toString s;
              in
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
            ) extUiPkgs
          );
          tuiFull = pkgs.stdenv.mkDerivation {
            stdenv = moldStdenv;
            pname = "rushi-tui";
            version = "0.1";
            # The TUI config's absolute tool paths point into these
            # store dirs, so they must stay in the package closure or
            # a GC would leave the config dangling.
            nativeBuildInputs = [ rawTui ] ++ extUiPkgs ++ [ kernelRaw ]
            ++ extToolPkgs;
            unpackPhase = "true";
            installPhase = ''
              mkdir -p $out/bin $out/ui_extensions
              # The raw TUI binary (rushi-tui, issue #22), shipped
              # beside its config.toml and ui_extensions/ so the TUI's
              # native side-by-side config resolution finds them. An
              # explicit --config (what the kernel passes) still wins
              # over the side-by-side and CWD steps; only the $CONFIG
              # env var outranks it (kernel precedence).
              cp ${rawTui}/bin/rushi-tui $out/bin/rushi-tui
              chmod +x $out/bin/rushi-tui
              ${extUiCopyScript}
              # ${tuiConfigFile} interpolates the writeText store path
              # (added to the closure automatically as a build dep).
              cp ${tuiConfigFile} $out/config.toml
              test -x $out/bin/rushi-tui || { echo "ERROR: rushi-tui binary missing"; exit 1; }
            '';
            meta = {
              description = "Self-contained rushi TUI (bundled config + UI extensions)";
              mainProgram = "rushi-tui";
            };
          };
          # ── bin/-only view of the self-contained TUI package, for
          # devshells that merge package roots.
          # Both `rushi-configured` (the default package) and
          # `rushi-tui` ship a root-level `config.toml` — that is the
          # issue-#22 side-by-side layout (bin/<entry> + config.toml +
          # ui_extensions/; the TUI resolves its config next to the
          # canonicalized binary). A devshell that merges whole package
          # roots (the consumer flake's numtide/devshell `packages` env,
          # whose devshell-dir is a pkgs.buildEnv over all packages)
          # cannot combine the two: buildEnv fails with "two given paths
          # contain a conflicting subpath" (the two config.toml files
          # differ: relative vs absolute tool paths). This wrapper
          # contributes only a bin/ dir to the merge: a symlink into the
          # real store package, so the TUI's side-by-side config
          # resolution still lands on its own absolute-path config.
          rushiTuiBin = pkgs.stdenv.mkDerivation {
            pname = "rushi-tui-bin";
            version = "0.1";
            nativeBuildInputs = [ tuiFull ];
            unpackPhase = "true";
            installPhase = ''
              mkdir -p $out/bin
              ln -s ${tuiFull}/bin/rushi-tui $out/bin/rushi-tui
            '';
            meta = {
              description = "bin/ only view of the self-wired TUI entry (devshell merge-safe)";
              mainProgram = "rushi-tui";
            };
          };
        in
        {
          default = mk.package;
          rushi = mk.package;
          # Raw kernel binary (no user config), for `rushi setup` / dev.
          rushi-kernel = rushiKernel.packages.${system}.rushi;
          # The self-contained TUI front-end (self-wired entry,
          # issue #22): the rushi-tui binary + generated config.toml +
          # bundled ui_extensions/, laid out side by side so the
          # delivered binary loads its extension layer and supervises
          # the Tier-1 rushi CLI itself.
          "rushi-tui" = tuiFull;
          # Pre-issue-#22 name, kept as an alias.
          tui = tuiFull;
          # bin/ only view of the TUI entry for merge-based devshells
          # (avoids the root config.toml collision; see the derivation).
          "rushi-tui-bin" = rushiTuiBin;
        };
    in
    {
      packages = pkgLib.genAttrs supportedSystems forSystem;

      # Re-expose the kernel's NixOS / home-manager modules so a consumer
      # config can do `programs.rushi.enable = true; package = <pkg>;`.
      nixosModules = {
        rushi = rushiKernel.nixosModules.rushi;
      };
      homeManagerModules = {
        rushi = rushiKernel.homeManagerModules.rushi;
      };

      # Dev shell with the configured rushi on PATH.
      devShells = pkgLib.genAttrs supportedSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ fenix.overlays.default ];
          };
          configured = self.packages.${system}.default;
          # The bin/-only view of the self-contained TUI package. The
          # full `rushi-tui` package cannot be listed next to the
          # configured one in any devshell that merges whole package
          # roots (the consumer flake's numtide/devshell env does:
          # its devshell-dir is a pkgs.buildEnv over all packages, and
          # both rushi packages ship a root-level config.toml that
          # buildEnv refuses to combine). This wrapper contributes only
          # a bin/ dir to any merge, with the binary symlinking into
          # the store package so its side-by-side config resolution
          # still lands on its own absolute-tool-path config.
          rushi-tui-bin = self.packages.${system}."rushi-tui-bin";
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
            packages = [
              configured
              rushi-tui-bin
              hookPathShim
            ];
            shellHook = ''
              echo "Configured rushi (v${configured.version}) — binaries on PATH:"
              echo "  rushi         configured kernel (bin/ + tools/ + ui_extensions/"
              echo "                   hooks/ + config.toml bundled in the package)"
              echo "  rushi-tui     self-wired TUI entry (bin/-only view; its"
              echo "                   config + ui_extensions/ resolve side-by-side"
              echo "                   from the .#rushi-tui store package)"
              echo "  hooks/        external hook binaries on PATH (shim)"
              echo "Run:  rushi run <session>   |   rushi-tui"
            '';
          };
        }
      );
    };
}
