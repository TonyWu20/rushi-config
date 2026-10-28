# rushi-config — the aggregator (the rushi analog of pi-config).
#
# One flake that packages the kernel + TUI front-end + config + external
# tools/hooks/UI-extensions as a single usable `rushi` package. The user
# runs it like pi-config:
#
#   nix build .#            # build the combined kernel + TUI package
#   nix build .#rushi       # the configured kernel package alone
#   nix run   .#rushi       # run rushi from the configured kernel
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
# File layout (a hierarchy: a file imports lower layers only,
# never a sibling):
#
#   L4  flake.nix               the flake inputs + outputs
#                               wiring.
#   L3  build.nix               the per-system entry: the config
#                               write + the full package.
#   L2  configured.nix          the config write (lib.mkRushi).
#       rushi-full.nix          the full package (the merge).
#   L1  tool-paths.nix          the absolute store tool paths.
#       tui-compat.nix         the bin/tui transition bridge.
#       tui-full.nix           the self-contained TUI package.
#   L0  config/exts.nix         the ext table (data).
#       config/hook-windows.nix the [hooks] pipeline (data).
#       config/native-tools.nix the native tool catalog (data).
#       config/rushi-config.nix the repo's data module (rushi.* values).
#
# external: the kernel flake's lib.mkRushi (below L0).
#

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

    # ── Extension / hook repos (each is its own git repo + flake).
    # rushi-image-read ships the `img` image-read ext tool; local
    # pin until hosting (see its input below). ──
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
    # Hosted ext repo. The lock pins the exact rev.
    # Bump: `nix flake update rushi-mineru-pdf`.
    rushi-mineru-pdf = {
      url = "github:TonyWu20/rushi-mineru-pdf";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fenix.follows = "fenix";
    };
    # Hosted ext repo. The lock pins the exact rev.
    # Bump: `nix flake update rushi-image-read`.
    rushi-image-read = {
      url = "github:TonyWu20/rushi-image-read";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fenix.follows = "fenix";
    };
    # ── mermaid TUI transform ext (UI-ext repo, Mode B). ──
    rushi-tui-mermaid-ext = {
      url = "github:TonyWu20/rushi-tui-mermaid-ext";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.fenix.follows = "fenix";
    };

    # ── terminal-browser tool ext (tool-only repo, Mode B). ──
    # Hosted ext repo. The lock pins the exact rev.
    # Bump: `nix flake update terminal-browser-agent`. The tool
    # is optional in the build: see cfgTb below.
    terminal-browser-agent = {
      url = "github:TonyWu20/terminal-browser-agent";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      fenix,
      # The hyphenated ext input names destructure as bare
      # identifiers. The body uses them without the `inputs.`
      # prefix (for example `rushi-kernel.lib.mkRushi`).
      rushi-kernel,
      rushi-tui,
      rushi-goal-mode,
      no-find-grep,
      rushi-simple-english,
      rushi-statusline,
      rushi-obscura-web-access,
      rushi-mineru-pdf,
      rushi-image-read,
      rushi-tui-mermaid-ext,
      terminal-browser-agent,
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

      # The per-system build. buildForSystem hands the flake's
      # named flake inputs, the target system, and the two
      # consumer flags to build.nix. That file shows the two
      # build products: how the config is written
      # (configured.nix) and the full package
      # (rushi-full.nix). flake.nix keeps a concise view of the
      # flake inputs and the outputs wiring.
      #
      # The consumer-side flag `enableTerminalBrowser` (default
      # false) picks the config-side instantiation. The default
      # build keeps the optional terminal-browser tool off. The
      # enabled build adds the terminal-browser row to the exts
      # table. The consumer-side value `modules` (default
      # null) is the declarative config this build assembles:
      # null is the repo's own deployment, a list is the
      # consumer's modules (merged on top of the kernel's
      # neutral defaults). The consumer-side value `exts`
      # (default null) replaces the repo default exts table
      # with a consumer ext set. Three forms: a list of ext
      # flake inputs (the rushiExt contract: each flake
      # exposes rushiExt.<system> = { tools; ui; hooks; },
      # derived from its meta.rushi declarations), or the
      # raw { extTools, extUi, extHooks } package table.
      buildForSystem =
        {
          system,
          enableTerminalBrowser ? false,
          exts ? null,
          modules ? null,
        }:
        import ./build.nix {
          inherit inputs system enableTerminalBrowser exts modules;
          # The flake inputs the build section names, stated
          # explicitly at the boundary instead of looked up
          # inside the inputs bag.
          nixpkgs = inputs.nixpkgs;
          fenix = inputs.fenix;
          rushiKernel = inputs."rushi-kernel";
          rushiTui = inputs."rushi-tui";
          rushiGoalMode = inputs."rushi-goal-mode";
        };
    in
    {
      # The per-system default build (the optional terminal-browser
      # tool is off, the long-standing attr set) plus a prebaked
      # enabled-variant attr.
      packages = pkgLib.genAttrs supportedSystems (
        system:
        let
          base = buildForSystem { inherit system; };
          withTb = buildForSystem {
            inherit system;
            enableTerminalBrowser = true;
          };
        in
        base // {
          # Prebaked convenience for the enabled variant. A consuming
          # flake gets the same package through lib.mkRushiFull with
          # the flag set.
          "rushi-full-tb" = withTb."rushi-full";
        }
      );

      # The consumer-side control point for the optional tool,
      # the config, and the ext set. The caller passes its
      # values; the result is the combined rushi-full package.
      # `modules` (default [ ]) is the consumer's declarative
      # rushi config: NixOS-style modules that set the
      # rushi.* options (the nixvim-config/default.nix shape),
      # merged on top of the kernel's neutral defaults. [ ] is
      # the kernel defaults only. `exts` (default null)
      # replaces the repo default exts table with a consumer
      # ext set: a list of ext flake inputs (the rushiExt
      # contract) or the raw { extTools, extUi, extHooks }
      # package table. `enableTerminalBrowser` (default
      # false) adds the terminal-browser row to the default
      # exts table.
      #
      # From a consuming flake:
      #   inputs."rushi-config".lib.mkRushiFull
      #     {
      #       system = system;
      #       modules = [ ./my-rushi-config.nix ];
      #       exts = [ myGoalFlake myWebFlake ];
      #       # exts = { extTools = [ … ]; extUi = [ … ]; extHooks = [ … ]; };
      #     }
      #
      # The consumer module is declarative data (it sets the
      # rushi.* options):
      #   { config, lib, pkgs, ... }:
      #   {
      #     rushi.config.model = { api = "responses"; max_output_tokens = 32768; };
      #     rushi.config.limits = { bash_timeout_max = 300; };
      #     rushi.config.system_prompt.text = "…";
      #   }
      # One-shot from this repo: `nix build .#rushi-full-tb`.
      # Note: the `r` binding below is required. A tight
      # `buildForSystem { … }."rushi-full"` parses as a select on
      # the argument attrset, not on the call result (a Nix parse
      # quirk), so the select must go through a named binding.
      lib = {
        # The caller passes its target `system` (the flake or NixOS
        # module's own system value). `modules` (default [ ]) is
        # the consumer's declarative rushi config: NixOS-style
        # modules that set the rushi.* options (the
        # nixvim-config/default.nix shape). They merge on top of
        # the kernel's neutral defaults. [ ] is the kernel
        # defaults only. No rushi-config repo config is involved
        # in the consumer path.
        # `exts` (default null) replaces the repo default exts
        # table (config/exts.nix, from the flake's pinned ext
        # inputs) with a consumer ext set. Three forms: a
        # list of ext flake inputs (the rushiExt contract:
        # each flake exposes rushiExt.<system> = { tools; ui;
        # hooks; }, derived from its meta.rushi declarations;
        # kernel docs ext-flake-authoring.md section 4.6), or
        # the raw { extTools, extUi, extHooks } package table
        # (migration shape). The consumer declares the exts in
        # their own flake inputs, so the ext set is
        # consumer-owned.
        # `enableTerminalBrowser` (default false) adds the
        # terminal-browser row to the default exts table.
        mkRushiFull =
          {
            system,
            enableTerminalBrowser ? false,
            exts ? null,
            modules ? [ ],
          }:
          let
            r = buildForSystem {
              inherit system enableTerminalBrowser exts modules;
            };
          in
          r."rushi-full";
      };

      # Re-expose the kernel's NixOS / home-manager modules so a consumer
      # config can do `programs.rushi.enable = true; package = <pkg>;`.
      nixosModules = {
        rushi = rushi-kernel.nixosModules.rushi;
      };
      homeManagerModules = {
        rushi = rushi-kernel.homeManagerModules.rushi;
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
