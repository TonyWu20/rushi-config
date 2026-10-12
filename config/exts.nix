# config/exts.nix — the declare-once exts table.
#
# The single source of truth for which ext packages this flake bundles.
# Every build list (rushi.external_*) and every runtime value in the
# generated config (ext tool paths, ui-ext entry names) derives from
# this table in pure Nix, at eval time. To add or drop an ext, edit
# one row. The terminal-browser row is optional: it is present only
# when `tbEnabled` is true.
#
# Since rushi#13 the kernel reads each producer's meta.rushi at eval
# time. Tool packages set meta.rushi.entry, UI-ext packages set
# meta.rushi.ext, and hook packages set meta.rushi.bin. The manifest
# [ui_extensions] list and extension_tool_paths derive from those
# declarations. For hooks the bin name doubles as the bundle name:
# mkRushi copies each meta.rushi.bin into $out/hooks/, and a bare
# hook command matching a declared bin is drift-guard-exempt. A bare
# command the meta does not cover is file-checked against $out/bin/
# and $out/hooks/ at build time, so a typo in the [hooks.defs] table
# still fails the build.
#
# WHERE a hook fires (the pipeline windows) is not in this table.
# Window placement lives in config/hook-windows.nix.

{
  # The flake's full inputs attrset. The ext table selects each
  # ext flake directly, so no alias bindings are needed.
  inputs,
  # The optional terminal-browser tool (the tool-only
  # terminal-browser-agent repo). false (the default) keeps the
  # tool row out of the default build.
  tbEnabled ? false,
}:
system:
{
  # External tool packages. One row per ext tool. The producer's
  # meta.rushi.entry (issue #13) supplies the tools/<entry> path the
  # generated config carries.
  extTools = [
    inputs."rushi-goal-mode".packages.${system}."goal-blocked"
    inputs."rushi-goal-mode".packages.${system}."goal-complete"
    inputs."rushi-obscura-web-access".packages.${system}."web-fetch"
    inputs."rushi-obscura-web-access".packages.${system}."web-search"
    inputs."rushi-mineru-pdf".packages.${system}.mineru
    inputs."rushi-image-read".packages.${system}.img
  ]
  # The optional terminal-browser tool. Present only when
  # `tbEnabled` is true; the default build keeps the row out.
  ++ (
    if tbEnabled then
    [ inputs."terminal-browser-agent".packages.${system}."terminal-browser" ]
    else
    [ ]
  );

  # External UI extension packages. The producer's meta.rushi.ext
  # (issue #13) supplies the [ui_extensions] entry name at eval time.
  extUi = [
    inputs."rushi-goal-mode".packages.${system}."goal-ext"
    inputs."rushi-simple-english".packages.${system}."simple-english-ext"
    inputs."rushi-statusline".packages.${system}.statusline
    inputs."rushi-tui-mermaid-ext".packages.${system}."mermaid-ext"
  ];

  # External hook packages, bundled into the package's hooks/ dir.
  # Each producer's meta.rushi.bin (issue #13) names the bundled
  # binary.
  extHooks = [
    inputs."rushi-goal-mode".packages.${system}."hook-goal-idle"
    inputs."rushi-goal-mode".packages.${system}."hook-goal-compact"
    inputs."rushi-goal-mode".packages.${system}."hook-goal-tools"
    inputs."rushi-goal-mode".packages.${system}."hook-goal-arm"
    inputs."rushi-goal-mode".packages.${system}."hook-goal-tokens"
    inputs."no-find-grep".packages.${system}."hook-no-find-grep"
    inputs."rushi-simple-english".packages.${system}."hook-simple-english"
  ];
}
