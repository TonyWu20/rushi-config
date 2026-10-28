# configured.nix — how the rushi config is written.
#
# Read top-down. Each step is one import of a lower layer:
#
#   1. nativeToolNames   the native tool catalog
#                        (config/native-tools.nix, data).
#   2. tuiCompat         the bin/tui bridge derivation
#                        (tui-compat.nix).
#   3. toolPaths         the absolute store tool paths
#                        (tool-paths.nix).
#
# The ext table for this system (extsForSystem) is a
# parameter: the repo default (config/exts.nix, data) or a
# consumer ext set.
#
# The config modules (the modules parameter) are the
# declarative data this build assembles: null is the repo's
# own deployment (the data module config/rushi-config.nix), a
# list is the consumer's declarative modules (the
# nixvim-config/default.nix shape). The builder modules (exts,
# tui) always come first, so the config modules can override
# them.
#
# Step 4 packages the config: lib.mkRushi (the kernel flake)
# with the module list. The kernel merges the result on top of
# its neutral defaults (lib/rushi-defaults.nix). The result
# carries .package (the configured kernel) and .config (the
# rendered config.toml text, shared with the TUI package).

{
  # The nixpkgs input (the shared system packages).
  nixpkgs,
  # The fenix input (the shared Rust toolchain overlay).
  fenix,
  # The kernel flake input (lib.mkRushi + the raw kernel package).
  rushiKernel,
  # The TUI flake input (the raw TUI package).
  rushiTui,
  # The target system.
  system,
  # The per-system ext table ({ extTools, extUi, extHooks }).
  # The repo default (config/exts.nix, data) or a consumer
  # ext set (lib.mkRushiFull `exts`).
  extsForSystem,
  # The declarative config modules for this build. null is the
  # repo's own deployment (the config/rushi-config.nix data
  # module). A list is the consumer's modules (the
  # nixvim-config/default.nix shape): NixOS-style module
  # functions that set the rushi.* options. They merge (NixOS
  # module semantics) on top of the kernel's neutral defaults.
  modules ? null,
}:
let
  pkgs = import nixpkgs {
    inherit system;
    overlays = [ fenix.overlays.default ];
  };
  # 1. The native tool catalog (a plain list).
  nativeToolNames = [ "bash" ];
  # 2. The TUI binary for the configured package (the
  #    transition bridge). RETIRE with tui-compat.nix when
  #    kernel rushi#31 lands.
  tuiCompat = import ./tui-compat.nix {
    stdenv = pkgs.stdenv;
    rawTui = rushiTui.packages.${system}.default;
  };
  # 3. The absolute store tool paths ({ native, ext }).
  toolPaths = import ./tool-paths.nix {
    inherit nativeToolNames;
    rawKernel = rushiKernel.packages.${system}.rushi;
    extToolPackages = extsForSystem.extTools;
  };
  # The repo's own config data (the nixvim-config/default.nix
  # shape): a module that sets the rushi.* options. It is used
  # only for the repo's own deployment (modules = null).
  repoModule = import ./config/rushi-config.nix {
    inherit nativeToolNames toolPaths;
  };
  # The ext packages: the exts table's lists, into the kernel
  # option schema.
  extsModule = { ... }: {
    rushi.external_tools = extsForSystem.extTools;
    rushi.external_ui_extensions = extsForSystem.extUi;
    rushi.external_hooks = extsForSystem.extHooks;
  };
  # The TUI binary: the self-wired bridge, shipped into the
  # package bin/ dir.
  tuiModule = { ... }: {
    rushi.tui = tuiCompat;
  };
  # The config modules: the repo deployment or the consumer's.
  configModules = if modules == null then [ repoModule ] else modules;
in
# 4. The kernel packages the config: the builder modules first,
# then the config modules (the NixOS merge: later modules
# win). The kernel merges the result on top of its neutral
# defaults.
rushiKernel.lib.mkRushi {
  inherit pkgs;
  modules = [ extsModule tuiModule ] ++ configModules;
}
