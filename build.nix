# build.nix — the per-system build orchestrator for the rushi
# flake.
#
# This file wires the build pieces. It picks the config-side
# instantiation, resolves the upstream flake packages, and
# hands the computed values to the role files:
#
#   * tool-paths.nix  the absolute store tool paths.
#   * tui-compat.nix  the transition-bridge TUI bin wrapper
#                     (RETIRE when kernel rushi#31 lands).
#   * tui-full.nix    the self-contained TUI package.
#   * rushi-full.nix  the combined package (the flake's
#                     default).
#
# flake.nix calls this file once per build: the `packages`
# genAttrs (the default and the enabled builds) and the
# `lib.mkRushiFull` builder function.

{
  # The flake's full inputs attrset. It feeds the config side
  # only: the ext table selects its ext flake inputs from it.
  # This is the only reference the build section makes to the
  # inputs bag; every other value is a named argument.
  inputs,
  # The nixpkgs input (the shared system packages).
  nixpkgs,
  # The fenix input (the shared Rust toolchain overlay).
  fenix,
  # The kernel flake input (lib.mkRushi + the raw kernel package).
  rushiKernel,
  # The TUI flake input (the raw TUI package).
  rushiTui,
  # The goal seeder flake input (the headless `rushi-goal` binary).
  rushiGoalMode,
  # The target system (the flake's own system value, or a
  # consuming flake's).
  system,
  # The consumer-side flags (the lib.mkRushiFull parameters).
  # `enableTerminalBrowser` (default false) picks the config-side
  # instantiation. The default build keeps the optional
  # terminal-browser tool off. The enabled build adds the
  # terminal-browser row to the exts table.
  enableTerminalBrowser ? false,
  # null keeps the built-in system-prompt.txt. A string is the
  # inline prompt text. A path or text-file derivation is read
  # as a file.
  systemPrompt ? null,
}:
let
  # The config side (config-module.nix): the exts table, the
  # native tool catalog, and the NixOS-style config module.
  # One import covers both flag values: tbEnabled selects
  # whether the exts table carries the terminal-browser row.
  configSide = import ./config-module.nix {
    inherit inputs;
    tbEnabled = enableTerminalBrowser;
  };
  # The per-system exts table for this build. The
  # terminal-browser row is present only when the flag is set.
  extsForSystem = configSide.exts system;
  # The system packages, with the shared Rust toolchain.
  pkgs = import nixpkgs {
    inherit system;
    overlays = [ fenix.overlays.default ];
  };
  # The mold-linker stdenv (the TUI package's stdenv field).
  moldStdenv = pkgs.stdenvAdapters.useMoldLinker pkgs.clangStdenv;

  # The upstream packages.
  rawTui = rushiTui.packages.${system}.default;
  rawKernel = rushiKernel.packages.${system}.rushi;
  # The headless goal seeder (rushi-goal-mode issue #8).
  rushiGoal = rushiGoalMode.packages.${system}."rushi-goal";

  # The TUI binary for the configured package (the transition
  # bridge). RETIRE with tui-compat.nix when kernel rushi#31
  # lands.
  tuiCompat = import ./tui-compat.nix {
    stdenv = pkgs.stdenv;
    inherit rawTui;
  };

  # The absolute store tool paths for the generated configs.
  toolPaths = import ./tool-paths.nix {
    inherit rawKernel;
    nativeToolNames = configSide.nativeToolNames;
    extToolPackages = extsForSystem.extTools;
  };

  # The configured kernel (kernel + TUI + config + exts). Its
  # config carries the absolute store tool paths. The package
  # still bundles tools/ next to its config.toml (the kernel's
  # layout), but the config itself points at the store
  # locations. One mkRushi call serves both the configured
  # kernel and the self-contained TUI package: the TUI's
  # generated config is byte-identical (the same toolPaths), so
  # the TUI package's config file reuses configured.config.
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

  # The self-contained TUI package (bin/rushi-tui + config.toml
  # + ui_extensions/, side by side).
  tuiFull = import ./tui-full.nix {
    stdenv = pkgs.stdenv;
    inherit moldStdenv rawTui rawKernel;
    extUiSources = extsForSystem.extUi;
    extToolPackages = extsForSystem.extTools;
    tuiConfigText = configured.config;
    writeText = pkgs.writeText;
  };

  # The combined package: the flake's default.
  rushiFull = import ./rushi-full.nix {
    stdenv = pkgs.stdenv;
    configuredRushiPackage = configured.package;
    tuiFullPackage = tuiFull;
    rushiGoalPackage = rushiGoal;
  };
in
{
  # The packages above are let-bound and referenced by key
  # here: Nix attrset siblings do not share scope.
  #
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
  rushi = configured.package;
  # Raw kernel binary (no user config), for `rushi setup` / dev.
  "rushi-kernel" = rawKernel;
  # The self-contained TUI front-end (self-wired entry,
  # issue #22): the rushi-tui binary + generated config.toml +
  # bundled ui_extensions/, laid out side by side so the
  # delivered binary loads its extension layer and supervises
  # the Tier-1 rushi CLI itself.
  "rushi-tui" = tuiFull;
  # Pre-issue-#22 name, kept as an alias.
  tui = tuiFull;
}
