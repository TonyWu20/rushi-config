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
  # The flake's full inputs attrset. It forwards to the data
  # layer only: the ext table selects its ext flake inputs from
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
  # terminal-browser row to the exts table.
  enableTerminalBrowser ? false,
  # null keeps the built-in system-prompt.txt. A string is the
  # inline prompt text. A path or text-file derivation is read
  # as a file.
  systemPrompt ? null,
  # An attrset recursively merged on top of the config
  # section of the default rushi config value
  # (lib.recursiveUpdate: the override's keys win, the
  # rest is kept). null keeps the built-in defaults.
  configOverride ? null,
}:
let
  # How the config is written: the configured kernel.
  # The lib.mkRushi call, with the config value
  # (config/rushi-config.nix), the system-prompt override, and
  # the absolute store tool paths. The TUI bridge and the tool
  # paths are pulled in by that file itself.
  configured = import ./configured.nix {
    inherit inputs nixpkgs fenix rushiKernel rushiTui system
      enableTerminalBrowser systemPrompt configOverride;
  };
  # The full rushi package: the configured kernel + the
  # self-contained TUI + the headless goal seeder in one store
  # object. It also returns the TUI piece it bundles, so the
  # attrset below can alias it.
  full = import ./rushi-full.nix {
    inherit inputs nixpkgs fenix rushiKernel rushiTui rushiGoalMode
      system enableTerminalBrowser configured;
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
