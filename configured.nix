# configured.nix — how the rushi config is written.
#
# The configured kernel: lib.mkRushi (from the kernel flake) +
# the config module (config-module.nix). The call at the end of
# this file is the whole config-writing story:
#
#   1. The config side instantiates for this build: the exts
#      table, the native tool catalog, and the NixOS-style
#      config module.
#   2. The tool paths are absolute store paths
#      (tool-paths.nix). The generated config.toml resolves
#      tools from the store, not a relative tools/ dir.
#   3. The TUI binary is the transition bridge (tui-compat.nix),
#      since the locked kernel still copies bin/tui.
#   4. The result carries .package (the configured kernel) and
#      .config (the generated config text, shared with the TUI
#      package).

{
  # The flake's full inputs attrset. It feeds the config side
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
}:
let
  # The config side (config-module.nix). One import covers both
  # flag values: tbEnabled selects whether the exts table
  # carries the terminal-browser row.
  configSide = import ./config-module.nix {
    inherit inputs;
    tbEnabled = enableTerminalBrowser;
  };
  # The per-system exts table for this build.
  extsForSystem = configSide.exts system;
  # The system packages, with the shared Rust toolchain.
  pkgs = import nixpkgs {
    inherit system;
    overlays = [ fenix.overlays.default ];
  };
  # The TUI binary for the configured package (the transition
  # bridge). RETIRE with tui-compat.nix when kernel rushi#31
  # lands.
  tuiCompat = import ./tui-compat.nix {
    stdenv = pkgs.stdenv;
    rawTui = rushiTui.packages.${system}.default;
  };
  # The absolute store tool paths for the generated config.
  toolPaths = import ./tool-paths.nix {
    rawKernel = rushiKernel.packages.${system}.rushi;
    nativeToolNames = configSide.nativeToolNames;
    extToolPackages = extsForSystem.extTools;
  };
  # How the config is written: lib.mkRushi + the config module.
  # The package still bundles tools/ next to its config.toml
  # (the kernel's layout), but the config itself points at the
  # store locations.
  configured = rushiKernel.lib.mkRushi {
    inherit pkgs;
    modules = [
      (configSide.configModule {
        system = system;
        tuiPkg = tuiCompat;
        systemPrompt = systemPrompt;
        toolPaths = toolPaths;
      })
    ];
  };
in
configured
