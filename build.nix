# build.nix — the per-system build entry point for the rushi
# flake.
#
# This file is layer L3 (the layer map is in the flake.nix
# header). It imports only L2 files. It shows the two things a
# build produces:
#
#   1. How the config is written (configured.nix): the config
#      value into lib.mkRushi.
#   2. The full rushi package (rushi-full.nix): the configured
#      kernel + the TUI + the goal seeder in one store object.
#
# Everything else (the data files, the mechanism files) lives
# in layers L0-L1 and does not appear here.
#
# flake.nix calls this file once per build: the `packages`
# genAttrs (the default and the enabled builds) and the
# `lib.mkRushiFull` builder function.

{
  # The flake's full inputs attrset. It feeds the ext table
  # only: config/exts.nix selects its ext flake inputs from
  # it.
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
  # The target system.
  system,
  # The consumer-side flags (the lib.mkRushiFull parameters).
  # `enableTerminalBrowser` (default false) picks the config-side
  # instantiation. The default build keeps the optional
  # terminal-browser tool off. The enabled build adds the
  # terminal-browser row to the default exts table. The flag
  # gates the default table only; a consumer ext set (the
  # `exts` parameter) decides the ext set.
  enableTerminalBrowser ? false,
  # The consumer ext set: an attrset { extTools, extUi,
  # extHooks } of ext packages for the target system. It
  # replaces the repo default exts table (config/exts.nix,
  # from the flake's pinned ext inputs). null keeps the
  # default table.
  exts ? null,
  # The declarative config modules for this build. null is
  # the repo's own deployment (the config/rushi-config.nix
  # data module). A list is the consumer's modules (the
  # nixvim-config/default.nix shape): NixOS-style module
  # functions that set the rushi.* options. They merge (NixOS
  # module semantics) on top of the kernel's neutral defaults.
  modules ? null,
}:
let
  # The per-system ext table: the consumer ext set or the
  # repo default (config/exts.nix, data).
  extsForSystem =
    if exts == null then
    import ./config/exts.nix {
      inherit inputs;
      tbEnabled = enableTerminalBrowser;
    } system
    else
    exts;
  # How the config is written: the configured kernel.
  # The lib.mkRushi call with the module list: the builder
  # modules (exts, tui), then the config modules (the repo
  # data module or the consumer's). The TUI bridge and the
  # tool paths are pulled in by that file itself.
  configured = import ./configured.nix {
    inherit nixpkgs fenix rushiKernel rushiTui system
      extsForSystem modules;
  };
  # The full rushi package: the configured kernel + the
  # self-contained TUI + the headless goal seeder in one store
  # object. It also returns the TUI piece it bundles, so the
  # attrset below can alias it.
  full = import ./rushi-full.nix {
    inherit nixpkgs fenix rushiKernel rushiTui rushiGoalMode
      system extsForSystem configured;
  };
in
{
  # The combined kernel + TUI + goal-seeder package is the
  # default, so a single import
  # (packages.<system>.default) always delivers the
  # version-locked set (rushi + rushi-tui + rushi-goal).
  default = full.rushiFull;
  # Explicit alias for the full package.
  "rushi-full" = full.rushiFull;
  # The configured kernel alone (bin/ + tools/ + hooks/ +
  # config.toml + ui_extensions/), for consumers that only
  # run the CLI loop.
  rushi = configured.package;
  # Raw kernel binary (no user config), for `rushi setup` / dev.
  "rushi-kernel" = rushiKernel.packages.${system}.rushi;
  # The self-contained TUI front-end (self-wired entry,
  # issue #22): the rushi-tui binary + generated config.toml +
  # bundled ui_extensions/, laid out side by side so the
  # delivered binary loads its extension layer and supervises
  # the Tier-1 rushi CLI itself.
  "rushi-tui" = full.tuiFull;
  # Pre-issue-#22 name, kept as an alias.
  tui = full.tuiFull;
}
