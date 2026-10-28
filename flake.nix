# rushi-config — the aggregator (the rushi analog of pi-config).
#
# One flake that packages the kernel + TUI front-end + config as a
# single usable `rushi` deployment. External exts are consumer data:
# the consumer declares them and the builder places them. The user
# runs it like pi-config:
#
#   nix build .#            # build the combined kernel + TUI package
#   nix build .#rushi       # the configured kernel package alone
#   nix run   .#rushi       # run rushi from the configured kernel
#
# The kernel flake (rushi-kernel) provides `lib.mkRushi`; this flake feeds
# it NixOS-style modules that declare the model, limits, and tools. This
# flake is the deployment layer: it holds no ext flake inputs. Ext
# sourcing is consumer data — a consumer flake declares the ext flake
# inputs in its own `inputs` and passes them to the builder's `exts`
# parameter (the rushiExt contract, kernel docs ext-flake-authoring.md
# section 4.6). The prebaked packages ship zero exts.
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
#   L0  config/hook-windows.nix the [hooks] pipeline (data).
#       config/native-tools.nix the native tool catalog (data).
#       config/rushi-config.nix the repo's data module (rushi.* values).
#
# external: the kernel flake's lib.mkRushi (below L0).
#

{
  description = "rushi-config — packages rushi (kernel + TUI + config) as one Nix deployment";

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
    # drift between the kernel and the TUI.

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

  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      fenix,
      # The hyphenated input names (rushi-kernel, rushi-tui)
      # destructure as bare identifiers. The body uses them
      # without the `inputs.` prefix (for example
      # `rushi-kernel.lib.mkRushi`).
      rushi-kernel,
      rushi-tui,
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
      # named flake inputs, the target system, and the
      # consumer values to build.nix. That file shows the two
      # build products: how the config is written
      # (configured.nix) and the full package
      # (rushi-full.nix). flake.nix keeps a concise view of the
      # flake inputs and the outputs wiring.
      #
      # The consumer-side value `modules` (default
      # null) is the declarative config this build assembles:
      # null is the repo's own deployment, a list is the
      # consumer's modules (merged on top of the kernel's
      # neutral defaults). The consumer-side value `exts`
      # (default null, no exts) is the consumer ext set.
      # Three forms: a list of ext flake inputs (the
      # rushiExt contract: each flake exposes
      # rushiExt.<system> = { tools; ui; hooks; }, derived
      # from its meta.rushi declarations), or the
      # raw { extTools, extUi, extHooks } package table.
      # Ext sourcing is consumer data: this flake holds no
      # ext flake inputs.
      buildForSystem =
        {
          system,
          exts ? null,
          modules ? null,
        }:
        import ./build.nix {
          inherit system exts modules;
          # The flake inputs the build section names, stated
          # explicitly at the boundary instead of looked up
          # inside the inputs bag.
          nixpkgs = inputs.nixpkgs;
          fenix = inputs.fenix;
          rushiKernel = inputs."rushi-kernel";
          rushiTui = inputs."rushi-tui";
        };
    in
    {
      # The prebaked packages. The default build ships zero
      # exts: ext sourcing is consumer data (the builder's
      # `exts` parameter, the consumer's own flake inputs).
      packages = pkgLib.genAttrs supportedSystems (
        system:
        buildForSystem { inherit system; }
      );

      # The consumer-side control point for the config and
      # the ext set. The caller passes its values; the
      # result is the combined rushi-full package.
      # `modules` (default [ ]) is the consumer's declarative
      # rushi config: NixOS-style modules that set the
      # rushi.* options (the nixvim-config/default.nix shape),
      # merged on top of the kernel's neutral defaults. [ ] is
      # the kernel defaults only. `exts` (default null, no
      # exts) is the consumer ext set: a list of ext flake
      # inputs (the rushiExt contract) or the raw
      # { extTools, extUi, extHooks } package table. The
      # consumer declares the ext flake inputs in its own
      # `inputs`; this flake holds none.
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
        # `exts` (default null, no exts) is the consumer ext
        # set. Three forms: a list of ext flake inputs (the
        # rushiExt contract: each flake exposes
        # rushiExt.<system> = { tools; ui; hooks; }, derived
        # from its meta.rushi declarations; kernel docs
        # ext-flake-authoring.md section 4.6), or the raw
        # { extTools, extUi, extHooks } package table
        # (migration shape). The consumer declares the exts in
        # their own flake inputs, so the ext set is
        # consumer-owned. This flake holds no ext flake
        # inputs.
        mkRushiFull =
          {
            system,
            exts ? null,
            modules ? [ ],
          }:
          let
            r = buildForSystem {
              inherit system exts modules;
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
              echo "Run:  rushi run <session>   |   rushi-tui"
            '';
          };
        }
      );
    };
}
