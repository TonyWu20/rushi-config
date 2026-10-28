# rushi-full.nix — the full rushi package.
#
# The configured kernel + the self-wired TUI in one store
# object. One import (or this flake's devShell) puts the
# version-locked `rushi` + `rushi-tui` pair on PATH, so the
# TUI can no longer drive an ambient or stale kernel
# resolved from PATH.
# The two inputs' root config.toml files are byte-identical
# (one evaluation, the same absolute store tool paths) and
# the TUI piece bundles the kernel piece's own assembled
# ui_extensions/ dir (the single source), so overlaying the
# TUI onto the kernel package merges without conflict.
#
# This file also owns the pieces it merges: the self-
# contained TUI package (tui-full.nix) and the raw goal
# seeder. It returns both, so the per-system attrset can
# alias the TUI piece as `rushi-tui` / `tui`.

{
  # The nixpkgs input (the shared system packages).
  nixpkgs,
  # The fenix input (the shared Rust toolchain overlay).
  fenix,
  # The kernel flake input (the raw kernel package).
  rushiKernel,
  # The TUI flake input (the raw TUI package).
  rushiTui,
  # The target system.
  system,
  # The per-system ext table ({ extTools, extUi, extHooks }).
  # The consumer ext set: null is no exts, a list is the
  # rushiExt contract fold, a raw attrset is the migration
  # shape (lib.mkRushiFull `exts`).
  extsForSystem,
  # The configured kernel result (from configured.nix):
  # .package is the configured kernel, .config is the
  # generated config text the TUI package reuses.
  configured,
}:
let
  # The system packages, with the shared Rust toolchain.
  pkgs = import nixpkgs {
    inherit system;
    overlays = [ fenix.overlays.default ];
  };
  # The mold-linker stdenv (the TUI package's stdenv field).
  moldStdenv = pkgs.stdenvAdapters.useMoldLinker pkgs.clangStdenv;
  # The self-contained TUI piece (its own file).
  tuiFull = import ./tui-full.nix {
    stdenv = pkgs.stdenv;
    inherit moldStdenv;
    rawTui = rushiTui.packages.${system}.default;
    rawKernel = rushiKernel.packages.${system}.rushi;
    # The TUI piece bundles the kernel piece's assembled
    # ui_extensions/ dir itself (the single source: the
    # module-merged external_ui_extensions), so it can never
    # drift from the piece it overlays onto.
    uiExtDir = configured.package;
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
      test -x $out/bin/rushi || { echo "ERROR: rushi kernel binary missing"; exit 1; }
      test -x $out/bin/rushi-tui || { echo "ERROR: rushi-tui binary missing"; exit 1; }
    '';
    meta = {
      description = "Combined rushi: configured kernel + self-wired TUI in one package";
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
