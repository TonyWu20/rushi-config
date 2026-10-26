# tui-compat.nix — the transition bridge for the TUI binary.
#
# The configured kernel package copies `$TUI_SRC/bin/tui` into
# its bin/ (the locked kernel mk-rushi, 04ba2e8). The
# self-wired TUI (issue #22) ships only `bin/rushi-tui`, so
# this wrapper feeds the binary into that `bin/tui` slot.
# Cutover policy (2026-09-22, user decision): no
# `bin/rushi-tui` alias is carried alongside. When the kernel
# ships the #31 fix, the configured package carries only
# `bin/rushi-tui` and this file is deleted.
#
# RETIRE when kernel rushi#31 lands: pass the raw TUI package
# straight to rushi.tui and drop this file.

{
  # The stdenv for the wrapper derivation (the plain system
  # stdenv: the wrapper is a pure file copy).
  stdenv,
  # The raw TUI package from the TUI flake. Since the
  # self-wired entry (rushi-tui issue #22) the package ships a
  # single `rushi-tui` binary at bin/rushi-tui; the old
  # `bin/tui` name is gone.
  rawTui,
}:
stdenv.mkDerivation {
  pname = "rushi-tui-bin-compat";
  version = "0.1";
  nativeBuildInputs = [ rawTui ];
  unpackPhase = "true";
  installPhase = ''
    mkdir -p $out/bin
    cp ${rawTui}/bin/rushi-tui $out/bin/tui
  '';
}
