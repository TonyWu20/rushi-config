# rushi-full.nix — the full rushi package.
#
# The configured kernel + the self-wired TUI + the headless
# goal seeder in one store object. One import (or this
# flake's devShell) puts the version-locked `rushi` +
# `rushi-tui` + `rushi-goal` set on PATH, so the TUI can no
# longer drive an ambient or stale kernel resolved from PATH.
# The two inputs' root config.toml files are byte-identical
# (one evaluation, the same absolute store tool paths) and
# their ui_extensions/ dirs bundle the same ext packages, so
# overlaying the TUI onto the kernel package merges without
# conflict.
#
# This file also owns the pieces it merges: the self-
# contained TUI package (tui-full.nix) and the raw goal
# seeder. It returns both, so the per-system attrset can
# alias the TUI piece as `rushi-tui` / `tui`.

{
  # The flake's full inputs attrset. It feeds the config side
  # only: the ext table selects its ext flake inputs from it.
  inputs,
  # The nixpkgs input (the shared system packages).
  nixpkgs,
  # The fenix input (the shared Rust toolchain overlay).
  fenix,
  # The kernel flake input (the raw kernel package).
  rushiKernel,
  # The TUI flake input (the raw TUI package).
  rushiTui,
  # The goal seeder flake input (the headless `rushi-goal` binary).
  rushiGoalMode,
  # The target system.
  system,
  # The consumer-side flag: the enabled build adds the
  # terminal-browser row to the exts table.
  enableTerminalBrowser ? false,
  # The configured kernel result (from configured.nix):
  # .package is the configured kernel, .config is the
  # generated config text the TUI package reuses.
  configured,
}:
let
  # The config side: the per-system exts table. The TUI
  # package's ext sources and tool packages come from it.
  configSide = import ./config-module.nix {
    inherit inputs;
    tbEnabled = enableTerminalBrowser;
  };
  extsForSystem = configSide.exts system;
  # The system packages, with the shared Rust toolchain.
  pkgs = import nixpkgs {
    inherit system;
    overlays = [ fenix.overlays.default ];
  };
  # The mold-linker stdenv (the TUI package's stdenv field).
  moldStdenv = pkgs.stdenvAdapters.useMoldLinker pkgs.clangStdenv;
  # The headless goal seeder (rushi-goal-mode issue #8): a
  # bare binary, not a loop tool and not an ext. A user setup
  # script calls it once to arm the session goal files before
  # a headless `rushi run` starts.
  rushiGoal = rushiGoalMode.packages.${system}."rushi-goal";
  # The self-contained TUI piece (its own file).
  tuiFull = import ./tui-full.nix {
    stdenv = pkgs.stdenv;
    inherit moldStdenv;
    rawTui = rushiTui.packages.${system}.default;
    rawKernel = rushiKernel.packages.${system}.rushi;
    extUiSources = extsForSystem.extUi;
    extToolPackages = extsForSystem.extTools;
    tuiConfigText = configured.config;
    writeText = pkgs.writeText;
  };
  # The full rushi package: a pure merge, no compilation.
  rushiFull = pkgs.stdenv.mkDerivation {
    pname = "rushi-full";
    version = "0.1";
    # A pure merge: no compilation. unpackPhase is a no-op, so
    # installPhase alone lays out $out.
    nativeBuildInputs = [
      configured.package
      tuiFull
      rushiGoal
    ];
    unpackPhase = "true";
    installPhase = ''
      mkdir -p $out
      # Configured kernel first: bin/rushi + the native tool
      # wrappers + tools/ + tools.manifest + hooks/ +
      # config.toml + ui_extensions/.
      cp -a ${configured.package}/. $out/
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
      cp ${rushiGoal}/bin/rushi-goal $out/bin/rushi-goal
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
  # The full rushi package (the flake's default).
  rushiFull = rushiFull;
  # The self-contained TUI piece the package bundles. The
  # per-system attrset aliases it as `rushi-tui` / `tui`.
  tuiFull = tuiFull;
}
