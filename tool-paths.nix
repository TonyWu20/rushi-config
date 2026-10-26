# tool-paths.nix — the absolute store tool paths for the
# generated rushi configs.
#
# The generated config.toml files point at absolute store
# paths, not relative tools/ entries. Both the configured
# kernel package and the self-contained TUI package carry those
# store paths in their closures, so the entries resolve from
# anywhere. Because both packages carry the same absolute
# paths, the two root-level config.toml files are
# byte-identical.
#
# The native entries point into the raw kernel package's
# tools/ dir (the absolute store home of the native tool
# manifests). The external entries are each ext tool
# package's store path.

{
  # The raw kernel package (bin/ + tools/ + tools.manifest).
  rawKernel,
  # The native tool names this build exposes (the config-side
  # catalog, or a per-build subset).
  nativeToolNames,
  # The external tool packages (the per-system exts table's
  # extTools list: store derivations or strings).
  extToolPackages,
}:
{
  # The native entries: one per native tool name.
  native = map (name: "${rawKernel}/tools/${name}") nativeToolNames;
  # The external entries: each ext tool package's outPath.
  ext = map (pkg: if builtins.isString pkg then pkg else "${pkg}") extToolPackages;
}
