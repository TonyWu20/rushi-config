# tui-full.nix — the self-contained rushi TUI package.
#
# The package the flake delivers as `rushi-tui` (the `tui` key
# is kept as a pre-issue-#22 alias). The raw TUI binary + the
# generated TUI config.toml (absolute tool paths) + the
# bundled ui_extensions/ (the configured kernel piece's
# assembled ext dir, the single source for the TUI ext layer),
# all laid out side by side. Since
# rushi-tui dd69b84 (issue #11) the bare binary resolves its
# config next to itself (<exe_dir>/../config.toml; the shared
# resolver added in issue #22 / kernel PR #30 checks $CONFIG
# first, then the --config flag, then side-by-side with the
# exe canonicalized, then CWD), so no wrapper is needed: the
# binary shipped at bin/rushi-tui finds config.toml and the
# bundled extension layer in the same directory tree.
#
# Self-wired loop (issue #22): when the config has a [loop]
# section the TUI supervises exactly that command (here:
# `rushi run <session>`); otherwise it falls back to the
# Tier-1 `rushi` CLI from PATH. No kernel launcher subcommand
# is involved.

{
  # The stdenv for the mkDerivation call (the plain system
  # stdenv, as in the original build section).
  stdenv,
  # The mold stdenv, the derivation's stdenv field.
  moldStdenv,
  # The raw TUI package from the TUI flake (bin/rushi-tui).
  rawTui,
  # The raw kernel package (bin/ + tools/ + tools.manifest).
  # Its absolute store tool manifests are referenced by the
  # generated config's native entries.
  rawKernel,
  # The configured kernel package (lib.mkRushi's .package).
  # Its ui_extensions/ dir is the assembled single source for
  # the TUI extension layer: the module-merged
  # external_ui_extensions (the consumer's TUI ext set) plus
  # any kernel-bundled ui extension names. The TUI piece
  # bundles that dir verbatim, so it can never drift from the
  # kernel piece it overlays onto.
  uiExtDir,
  # The external tool packages (the exts table's extTools
  # list). The generated config's external entries reference
  # them.
  extToolPackages,
  # The generated TUI config content (a string, the same
  # content as the configured kernel's config).
  tuiConfigText,
  # The nixpkgs writeText function (writes the config file
  # into the store).
  writeText,
}:
let
  # Copy the configured kernel piece's assembled ui_extensions/
  # dir (the single source: the module-merged
  # external_ui_extensions, already validated there — each
  # entry ships an ext.toml or the kernel piece's build failed
  # with a clear error). An empty dir (the no-exts deployment)
  # is a no-op.
  uiExtCopy = ''
    if [ -d "${uiExtDir}/ui_extensions" ] && [ -n "$(ls -A "${uiExtDir}/ui_extensions" 2>/dev/null)" ]; then
      cp -rL "${uiExtDir}/ui_extensions/." "$out/ui_extensions/"
    fi
  '';
  # The TUI config file (a writeText store derivation, added to
  # the package closure automatically as a build dep).
  tuiConfigFile = writeText "rushi-tui-config.toml" tuiConfigText;
in
stdenv.mkDerivation {
  stdenv = moldStdenv;
  pname = "rushi-tui";
  version = "0.1";
  # The TUI config's absolute tool paths point into these
  # store dirs, so they must stay in the package closure or
  # a GC would leave the config dangling.
  nativeBuildInputs = [ rawTui rawKernel uiExtDir ] ++ extToolPackages;
  unpackPhase = "true";
  installPhase = ''
    mkdir -p $out/bin $out/ui_extensions
    # The raw TUI binary (rushi-tui, issue #22), shipped
    # beside its config.toml and ui_extensions/ so the TUI's
    # native side-by-side config resolution finds them. An
    # explicit --config (what the kernel passes) still wins
    # over the side-by-side and CWD steps; only the $CONFIG
    # env var outranks it (kernel precedence).
    cp ${rawTui}/bin/rushi-tui $out/bin/rushi-tui
    chmod +x $out/bin/rushi-tui
    ${uiExtCopy}
    # ${tuiConfigFile} interpolates the writeText store path
    # (added to the closure automatically as a build dep).
    cp ${tuiConfigFile} $out/config.toml
    test -x $out/bin/rushi-tui || { echo "ERROR: rushi-tui binary missing"; exit 1; }
  '';
  meta = {
    description = "Self-contained rushi TUI (bundled config + UI extensions)";
    mainProgram = "rushi-tui";
  };
}
