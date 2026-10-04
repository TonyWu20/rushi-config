# rushi-config — the aggregator (the rushi analog of pi-config).
#
# One flake that packages the kernel + TUI front-end + config + external
# tools/hooks/UI-extensions as a single usable `rushi` package. The user
# runs it like pi-config:
#
#   nix build .#            # build the combined kernel + TUI package
#   nix build .#rushi       # the configured kernel package alone
#   nix run   .#rushi       # run rushi from the configured kernel
#   nix run   .#rushi-bash  # the configured kernel, bash tool only
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
      inputs.rushi-config.follows = "";
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

      # ── The config side (exts table + config module) was extracted to
      # config-module.nix (the exts and hooks tables live in config/).
      # It is imported with the six ext flake aliases and its exts,
      # nativeToolNames, and configModule are re-bound here, so the
      # forSystem build section below stays a concise view of the build
      # graph.
      cfg = import ./config-module.nix {
        inherit
          goalFlake
          nfgFlake
          seFlake
          statuslineFlake
          obscuraWebFlake
          mermaidExtFlake
          ;
      };
      exts = cfg.exts;
      nativeToolNames = cfg.nativeToolNames;
      configModule = cfg.configModule;

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
          # The raw kernel package (bin/ + tools/ + tools.manifest):
          # the absolute store home of the native tool manifests.
          kernelRaw = rushiKernel.packages.${system}.rushi;
          # The headless goal seeder (rushi-goal-mode issue #8): a bare
          # binary, not a loop tool and not an ext. A user setup
          # script calls it once to arm the session goal files before
          # a headless `rushi run` starts.
          rushiGoalPkg = goalFlake.packages.${system}."rushi-goal";
          # Absolute store tool paths, written into BOTH generated
          # configs. The raw kernel package's tools/ for the native
          # set, each ext tool package's outPath for the external set.
          # Both packages carry those store paths in their closures,
          # so the entries resolve from anywhere. Because both
          # configs carry the same absolute paths, the two root-level
          # config.toml files are byte-identical. A buildEnv-based
          # devshell merge dedupes identical files, so the two
          # packages can share a merged shell root.
          absToolPathsFor = names:
          {
            native = map (n: "${kernelRaw}/tools/${n}") names;
            ext = map (t: if builtins.isString t then t else "${t}") e.extTools;
          };
          absToolPaths = absToolPathsFor nativeToolNames;
          # The fully configured rushi: kernel + TUI + config + exts.
          # Its config carries the same absolute store tool paths as
          # the TUI variant. The package still bundles tools/ next to
          # its config.toml (the kernel's layout), but the config
          # itself points at the store locations.
          mk = rushiKernel.lib.mkRushi {
            inherit pkgs;
            modules = [
              (configModule {
                inherit system tuiPkg;
                toolPaths = absToolPaths;
              })
            ];
          };
          # The TUI variant of the generated config: identical content
          # to mk.config, since both use the absolute store tool paths.
          mkTui = rushiKernel.lib.mkRushi {
            inherit pkgs;
            modules = [
              (configModule {
                inherit system tuiPkg;
                toolPaths = absToolPaths;
              })
            ];
          };

          # The lean variant: the configured kernel with only the bash
          # native tool. The model, limits, ext tools, hooks, and UI
          # layer are the same as `rushi`. The [tools] manifest and
          # native_tool_paths carry only bash, so the agent sees one
          # native tool.
          mkLean = rushiKernel.lib.mkRushi {
            inherit pkgs;
            modules = [
              (configModule {
                inherit system tuiPkg;
                toolNames = [ "bash" ];
                toolPaths = absToolPathsFor [ "bash" ];
              })
            ];
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
          extUiPkgs = e.extUi;
          # Store derivations of the ext tool packages: referenced by
          # the TUI config's absolute extension_tool_paths.
          extToolPkgs = e.extTools;
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
            nativeBuildInputs = [ rawTui ] ++ extUiPkgs ++ [ kernelRaw ] ++ extToolPkgs;
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
          # ── The combined package: configured kernel + self-wired
          # TUI + headless goal seeder in one store object. One
          # import (or this flake's devShell) puts the version-locked
          # `rushi` + `rushi-tui` + `rushi-goal` set on PATH, so the
          # TUI can no longer drive an ambient or stale kernel
          # resolved from PATH. The two inputs' root config.toml
          # files are byte-identical (one evaluation, same absolute
          # store tool paths) and their ui_extensions/ dirs bundle
          # the same ext packages, so overlaying the TUI onto the
          # kernel package merges without conflict.
          rushiFull = pkgs.stdenv.mkDerivation {
            pname = "rushi-full";
            version = "0.1";
            # A pure merge: no compilation. unpackPhase is a no-op, so
            # installPhase alone lays out $out.
            nativeBuildInputs = [
              mk.package
              tuiFull
              rushiGoalPkg
            ];
            unpackPhase = "true";
            installPhase = ''
              mkdir -p $out
              # Configured kernel first: bin/rushi + the native tool
              # wrappers + tools/ + tools.manifest + hooks/ +
              # config.toml + ui_extensions/.
              cp -a ${mk.package}/. $out/
              # Store inputs are read-only, so the kernel files above
              # land in $out read-only. Make them writable so the TUI
              # overlay below can overwrite the shared files
              # (config.toml, ui_extensions/). Nix normalizes store
              # permissions again at fixup.
              chmod -R u+w $out
              # Self-wired TUI on top: bin/rushi-tui. Its config.toml
              # and ui_extensions/ are identical to the kernel
              # package's, so the overlay dedupes instead of
              # conflicting.
              cp -a ${tuiFull}/. $out/
              # `cp -a` re-applies each source dir's mode to the
              # existing dir, so bin/ is read-only again. Re-open it
              # for the goal-seeder copy below.
              chmod -R u+w $out
              # Headless goal seeder next to the loop binaries:
              # bin/rushi-goal. It resolves config by the kernel
              # ladder, so the side-by-side step (<exe_dir>/../
              # config.toml) lands on this package's root config.toml.
              # A new path: no overlay conflict.
              cp ${rushiGoalPkg}/bin/rushi-goal $out/bin/rushi-goal
              chmod +x $out/bin/rushi-goal
              test -x $out/bin/rushi || { echo "ERROR: rushi kernel binary missing"; exit 1; }
              test -x $out/bin/rushi-tui || { echo "ERROR: rushi-tui binary missing"; exit 1; }
              test -x $out/bin/rushi-goal || { echo "ERROR: rushi-goal binary missing"; exit 1; }
            '';
            meta = {
              description = "Combined rushi: configured kernel + self-wired TUI + headless goal seeder in one package";
              mainProgram = "rushi";
            };
          };
        in
        {
          # The combined kernel + TUI + goal-seeder package is the
          # default, so a single import
          # (packages.<system>.default) always delivers the
          # version-locked set (rushi + rushi-tui + rushi-goal).
          default = rushiFull;
          # Explicit alias for the combined package.
          "rushi-full" = rushiFull;
          # The configured kernel alone (bin/ + tools/ + hooks/ +
          # config.toml + ui_extensions/), for consumers that only
          # run the CLI loop.
          rushi = mk.package;
          # The configured kernel with only the bash native tool: a
          # lean version of `rushi`. Same model, limits, ext tools,
          # hooks, and UI layer; the [tools] manifest and
          # native_tool_paths carry only bash.
          "rushi-bash" = mkLean.package;
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

      # Dev shell with the combined rushi on PATH. One package (the
      # combined kernel + TUI, the flake's `default`) puts both the
      # `rushi` loop and the `rushi-tui` front-end on PATH from the
      # same store object, so the pair can no longer skew. The
      # external hook binaries live in the package's hooks/ dir, not
      # bin/; the kernel resolves bare hook names against
      # <exe_dir>/../hooks/, so a fresh build needs no PATH shim.
      devShells = pkgLib.genAttrs supportedSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ fenix.overlays.default ];
          };
          full = self.packages.${system}.default;
        in
        {
          default = pkgs.mkShell {
            packages = [ full ];
            shellHook = ''
              echo "Configured rushi (v${full.version}) — binaries on PATH:"
              echo "  rushi         configured kernel (bin/ + tools/ + hooks/"
              echo "                   config.toml + ui_extensions/ in the package)"
              echo "  rushi-tui     self-wired TUI entry, same store object"
              echo "  rushi-goal    headless goal seeder, same store object"
              echo "Run:  rushi run <session>   |   rushi-tui"
              echo "Headless: rushi-goal <session> <goal> && rushi run <session>"
            '';
          };
        }
      );
    };
}
