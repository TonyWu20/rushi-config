# rushi-full.nix — the combined rushi package.
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

{
  # The stdenv for the merge derivation (the plain system
  # stdenv: the merge is a pure file copy).
  stdenv,
  # The configured kernel package (bin/ + tools/ + hooks/ +
  # config.toml + ui_extensions/).
  configuredRushiPackage,
  # The self-contained TUI package.
  tuiFullPackage,
  # The headless goal seeder package (rushi-goal-mode issue
  # #8): a bare binary, not a loop tool and not an ext. A
  # user setup script calls it once to arm the session goal
  # files before a headless `rushi run` starts.
  rushiGoalPackage,
}:
stdenv.mkDerivation {
  pname = "rushi-full";
  version = "0.1";
  # A pure merge: no compilation. unpackPhase is a no-op, so
  # installPhase alone lays out $out.
  nativeBuildInputs = [
    configuredRushiPackage
    tuiFullPackage
    rushiGoalPackage
  ];
  unpackPhase = "true";
  installPhase = ''
    mkdir -p $out
    # Configured kernel first: bin/rushi + the native tool
    # wrappers + tools/ + tools.manifest + hooks/ +
    # config.toml + ui_extensions/.
    cp -a ${configuredRushiPackage}/. $out/
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
    cp -a ${tuiFullPackage}/. $out/
    # `cp -a` re-applies each source dir's mode to the
    # existing dir, so bin/ is read-only again. Re-open it
    # for the goal-seeder copy below.
    chmod -R u+w $out
    # Headless goal seeder next to the loop binaries:
    # bin/rushi-goal. It resolves config by the kernel
    # ladder, so the side-by-side step (<exe_dir>/../
    # config.toml) lands on this package's root config.toml.
    # A new path: no overlay conflict.
    cp ${rushiGoalPackage}/bin/rushi-goal $out/bin/rushi-goal
    chmod +x $out/bin/rushi-goal
    test -x $out/bin/rushi || { echo "ERROR: rushi kernel binary missing"; exit 1; }
    test -x $out/bin/rushi-tui || { echo "ERROR: rushi-tui binary missing"; exit 1; }
    test -x $out/bin/rushi-goal || { echo "ERROR: rushi-goal binary missing"; exit 1; }
  '';
  meta = {
    description = "Combined rushi: configured kernel + self-wired TUI + headless goal seeder in one package";
    mainProgram = "rushi";
  };
}
