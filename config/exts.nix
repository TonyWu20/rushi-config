# config/exts.nix — the declare-once exts table.
#
# The single source of truth for which ext packages this flake bundles.
# Every build list (rushi.external_*) and every runtime value in the
# generated config (ext tool paths, ui-ext entry names) derives from
# this table in pure Nix, at eval time. To add or drop an ext, edit
# one row.
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
  goalFlake,
  nfgFlake,
  seFlake,
  statuslineFlake,
  obscuraWebFlake,
  mermaidExtFlake,
}:
system:
{
  # External tool packages. One row per ext tool. The producer's
  # meta.rushi.entry (issue #13) supplies the tools/<entry> path the
  # generated config carries.
  extTools = [
    goalFlake.packages.${system}.goal
    goalFlake.packages.${system}."goal-blocked"
    goalFlake.packages.${system}."goal-complete"
    obscuraWebFlake.packages.${system}."web-fetch"
    obscuraWebFlake.packages.${system}."web-search"
  ];

  # External UI extension packages. The producer's meta.rushi.ext
  # (issue #13) supplies the [ui_extensions] entry name at eval time.
  extUi = [
    goalFlake.packages.${system}."goal-ext"
    seFlake.packages.${system}."simple-english-ext"
    statuslineFlake.packages.${system}.statusline
    mermaidExtFlake.packages.${system}."mermaid-ext"
  ];

  # External hook packages, bundled into the package's hooks/ dir.
  # Each producer's meta.rushi.bin (issue #13) names the bundled
  # binary.
  extHooks = [
    goalFlake.packages.${system}."hook-goal-idle"
    goalFlake.packages.${system}."hook-goal-compact"
    goalFlake.packages.${system}."hook-goal-tools"
    goalFlake.packages.${system}."hook-goal-arm"
    goalFlake.packages.${system}."hook-goal-tokens"
    nfgFlake.packages.${system}."hook-no-find-grep"
    seFlake.packages.${system}."hook-simple-english"
  ];
}
