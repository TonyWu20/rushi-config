# configured.nix — how the rushi config is written.
#
# Read top-down. Each step is one import of a lower layer:
#
#   1. nativeToolNames   the native tool catalog
#                        (config/native-tools.nix, data).
#   2. extsForSystem     the ext table for this system
#                        (config/exts.nix, data).
#   3. tuiCompat         the bin/tui bridge derivation
#                        (tui-compat.nix).
#   4. toolPaths         the absolute store tool paths
#                        (tool-paths.nix).
#   5. rushiConfig       the config content
#                        (config/rushi-config.nix, data).
#
# Step 6 packages the config: lib.mkRushi (the kernel flake)
# with the config value as the sole NixOS-style module. The
# result carries .package (the configured kernel) and .config
# (the rendered config.toml text, shared with the TUI
# package).

{
  # The flake's full inputs attrset. It feeds the data layer
  # only: the ext table selects its ext flake inputs from it.
  inputs,
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
  # The consumer-side flag: the enabled build adds the
  # terminal-browser row to the exts table.
  enableTerminalBrowser ? false,
  # null keeps the built-in system-prompt.txt. A string is the
  # inline prompt text. A path or text-file derivation is read
  # as a file.
  systemPrompt ? null,
  # An attrset recursively merged on top of the config
  # section of the default rushi config value
  # (lib.recursiveUpdate: the override's keys win, the
  # rest is kept). It covers the [active], [model], [limits],
  # [paths], [hooks], [loop], [system_prompt], and [tui]
  # sections. null keeps the built-in defaults.
  configOverride ? null,
}:
let
  pkgs = import nixpkgs {
    inherit system;
    overlays = [ fenix.overlays.default ];
  };
  # 1. The native tool catalog (a plain list).
  nativeToolNames = [ "bash" ];
  # 2. The ext table for this system (the data file returns
  #    { extTools, extUi, extHooks }).
  extsForSystem = import ./config/exts.nix {
    inherit inputs;
    tbEnabled = enableTerminalBrowser;
  } system;
  # 3. The TUI binary for the configured package (the
  #    transition bridge). RETIRE with tui-compat.nix when
  #    kernel rushi#31 lands.
  tuiCompat = import ./tui-compat.nix {
    stdenv = pkgs.stdenv;
    rawTui = rushiTui.packages.${system}.default;
  };
  # 4. The absolute store tool paths ({ native, ext }).
  toolPaths = import ./tool-paths.nix {
    inherit nativeToolNames;
    rawKernel = rushiKernel.packages.${system}.rushi;
    extToolPackages = extsForSystem.extTools;
  };
  # 5. The config content: the defaults (top-down data,
  # config/rushi-config.nix), plus the consumer override.
  # The tuiPkg argument is the TUI bridge derivation.
  rushiDefaults = import ./config/rushi-config.nix {
    inherit extsForSystem nativeToolNames toolPaths systemPrompt;
    tuiPkg = tuiCompat;
  };
  # The merged config value: the defaults with configOverride
  # recursively merged on top of the config section
  # (lib.recursiveUpdate: the override's keys win, the rest
  # is kept).
  rushiConfig = rushiDefaults // {
    config = pkgs.lib.recursiveUpdate rushiDefaults.config
      (if configOverride == null then {} else configOverride);
  };
in
# 6. The kernel packages the config. The module is the
# NixOS-style function lib.mkRushi merges. It contributes the
# `rushi` fields; the kernel fills the rest (the manifest
# lists, the package layout).
rushiKernel.lib.mkRushi {
  inherit pkgs;
  modules = [
    (
      { ... }:
      {
        rushi = rushiConfig;
      }
    )
  ];
}
