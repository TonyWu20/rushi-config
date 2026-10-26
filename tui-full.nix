# tui-full.nix — the self-contained rushi TUI package.
#
# The package the flake delivers as `rushi-tui` (the `tui` key
# is kept as a pre-issue-#22 alias). The raw TUI binary + the
# generated TUI config.toml (absolute tool paths) + the
# bundled ui_extensions/, all laid out side by side. Since
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
  # The external UI ext sources (the per-system exts table's
  # extUi list: store derivations or strings).
  extUiSources,
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
  # Copy each bundled ext source into $out/ui_extensions/ (the
  # same layout logic as lib.mkRushi's extUiScript). Since
  # rushi#10 entry-dir names are auto-discovered (each ext.toml
  # dir), so each source must ship one, else the build fails
  # with a clear error instead of silently dropping the ext.
  copyExtUiScript = builtins.concatStringsSep "\n" (
    map (
      source:
      let
        # The source as a string: a plain path string, or the
        # derivation's store path.
        sourceString = if builtins.isString source then source else toString source;
      in
      ''
        # External UI ext source: ${sourceString}
        if [ ! -d "${sourceString}" ]; then
          echo "rushi-tui: UI ext source ${sourceString} is missing or not a directory" >&2
          exit 1
        fi
        ext_toml=""
        for entry in "${sourceString}"/ext.toml "${sourceString}"/*/ext.toml; do
          if [ -f "$entry" ]; then ext_toml="$entry"; break; fi
        done
        if [ -z "$ext_toml" ]; then
          echo "rushi-tui: UI ext source ${sourceString} ships no ext.toml (broken ext)" >&2
          exit 1
        fi
        cp -rL "${sourceString}/." "$out/ui_extensions/"
      ''
    ) extUiSources
  );
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
  nativeBuildInputs = [ rawTui ] ++ extUiSources ++ [ rawKernel ] ++ extToolPackages;
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
    ${copyExtUiScript}
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
