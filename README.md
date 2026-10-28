# rushi-config

Aggregator flake for a complete rushi deployment. It assembles the
kernel (`rushi-flake`), the TUI front-end (`rushi-tui`), external
tools, hooks, and UI extensions, plus a NixOS-style config module.
It mirrors the `pi-config` pattern: one flake assembles everything
and calls the kernel's `lib.mkRushi` to produce one runnable package.

## Usage

    nix build .#rushi    # build the fully configured package
    nix run   .#rushi    # run the configured rushi
    nix run   .#rushi-tui   # run the self-contained TUI (config + exts)
    nix run   .#tui         # alias of .#rushi-tui
    nix build .#rushi-full-tb   # rushi-full with the optional
                                 # terminal-browser tool enabled
    nix develop          # dev shell with the configured rushi on PATH

Layout of the `.#rushi` output (`$out`):

    bin/            rushi + all stage/tool binaries + tui
                    (bin/tui is the kernel transition slot. Cutover:
                     it disappears when kernel rushi#31 lands. the
                     self-wired entry bin/rushi-tui ships in the
                     .#rushi-tui package)
    tools/          tool manifests (kernel + external tools)
    ui_extensions/  external UI extension dirs (ext.toml + binaries)
    hooks/          external hook binaries
    config.toml     generated from the Nix module options
    tools.manifest  rushi.toml equivalent for `rushi setup --locked`

Layout of the `.#rushi-tui` output (self-contained TUI package):

    bin/rushi-tui   the TUI binary (self-wired entry, rushi-tui issue
                    #22). Resolves config side-by-side. Supervises the
                    loop via the [loop] section or the `rushi` CLI
                    from PATH.
    config.toml     generated from the Nix module options
    ui_extensions/  the bundled UI extensions

## Inputs and the bootstrap -> hosting transition

All local inputs use `path:` URLs for local development. When the
repos are hosted, flip each to a pinned `github:` ref. Then run
`nix flake update <input>` to pin it in the lock.

- `rushi-kernel`: `path:/home/tony/programming/rust-unix-harness`
  -> `github:TonyWu20/rushi?ref=<rev>`
- `rushi-tui`: `github:TonyWu20/rushi-tui`, lock rev `0996b52`.
  That rev carries the issue #22 self-wired entry.
  The binary is `rushi-tui`.
- `rushi-goal-mode`: `path:/home/tony/programming/rushi-exts/goal-app`
  -> `github:TonyWu20/rushi-goal-mode?ref=<rev>`
- `no-find-grep`: `path:/home/tony/programming/rushi-exts/no-find-grep`
  -> `github:TonyWu20/no-find-grep-rushi?ref=<rev>`
- `rushi-simple-english`: `path:/home/tony/programming/rushi-simple-english`
  -> `github:TonyWu20/rushi-simple-english?ref=<rev>`
- `rushi-mineru-pdf`: `github:TonyWu20/rushi-mineru-pdf`, the lock
  pins the rev. Bump with `nix flake update rushi-mineru-pdf`.
- `rushi-image-read`: `github:TonyWu20/rushi-image-read`, the `img`
  image-read ext tool. The lock pins the rev.
  Bump with `nix flake update rushi-image-read`.
- `terminal-browser-agent`: `github:TonyWu20/terminal-browser-agent`,
  hosted ext repo. The lock pins the rev (current: `544a372`).
  Bump with `nix flake update terminal-browser-agent`.

Notes:

- The TUI flake's own kernel inputs (`rushi-kernel` and
  `rushi-kernel-src`) are overridden in this flake. This keeps the
  kernel source and the kernel binary on the same pin.
- The kernel's `lib.mkRushi` accepts `kernelCargoLock` (a Nix path to
  the kernel `Cargo.lock`). A plain `src/Cargo.lock` reference
  mis-resolves when the kernel flake is a flake `path:` input. So the
  lock file is handed over as an explicit path ref.
- Each ext repo ships its own Mode-B flake. This aggregator only
  consumes their `packages.<system>.<name>` outputs.

## Config

The repo's own config is data. `config/rushi-config.nix` is
the repo's data module: the `rushi.*` option values the
prebaked `packages` attrs build, read top to bottom (the
[active], [model], [limits], [paths], [hooks], [loop],
[system_prompt], and [tui] sections). It mirrors
`config-real.toml` from the kernel checkout. The declare-once
`exts` table lives in `config/exts.nix`. The `[hooks]` defs
and pipeline tables live in `config/hook-windows.nix`. The
native tool catalog lives in `config/native-tools.nix`. Hook
`command` fields are bare binary names. The hook binaries are
bundled into `$out/hooks` by `lib.mkRushi`, and the kernel
resolves them from there at runtime. The consumer does not
take this config. The consumer writes their own declarative
module (the nixvim model). The builder merges it on top of
the kernel's neutral defaults (the Config (consumer side)
section).

The nix files form a layer hierarchy (the map is in the
flake.nix header). A file imports lower layers only.
`build.nix` (L3) shows two things: how the config is written
(`configured.nix`, L2) and the full package (`rushi-full.nix`,
L2). The mechanism files (L1): `tool-paths.nix`,
`tui-compat.nix`, `tui-full.nix`. The data files (L0):
`config/*.nix`. `flake.nix` calls `build.nix` through the
`buildForSystem` wrapper. The flake inputs cross the boundary
by name.

## Tool-set variants

The `nativeToolNames` list in `config/native-tools.nix` is
the native tool catalog. It is `[ "bash" ]`. Every package ships
a `tools.manifest` with `enabled = [ "bash" ]` and one
`native_tool_paths` entry. Edit that list to expose more native
tools. The `rushi-config.nix` `toolNames` parameter accepts a
per-build subset for future variants. The ext tools, hooks, and
UI extensions are unchanged by the native tool set.

## Optional terminal-browser tool

`rushi-full` can bundle the terminal-browser tool from the
`terminal-browser-agent` repo. The tool is opt-in: the default
builds (`.#rushi-full`, `.#rushi`, `.#rushi-tui`, the devShell)
ship without it.

Enable it on the consumer side:

- Prebaked attr, one-shot from this repo:
  `nix build .#rushi-full-tb`
- Builder function, from a consuming flake or NixOS module:
  `inputs."rushi-config".lib.mkRushiFull
    { system = system; enableTerminalBrowser = true; }`

The enabled build appends the tool row to the exts table
(`extTools` in `config/exts.nix`), so the configured package and
the TUI package both carry it: `tools/terminal-browser/` is
bundled in the package, and the generated config's
`extension_tool_paths` names the tool's store path. The disabled
build is byte-identical to the pre-option package.

## Config (consumer side)

The config is built from the consumer side. In the nixvim
model, the consumer repo owns the config data, and the flake
only assembles. `lib.mkRushiFull` takes `modules`: the
consumer's declarative rushi config (a list of NixOS-style
modules, the `nixvim-config/default.nix` shape). The modules
merge (NixOS module semantics) on top of the kernel's
neutral defaults. No rushi-config repo config is involved.

- Builder function, from a consuming flake:
  `inputs."rushi-config".lib.mkRushiFull
    { system = system;
      modules = [ ./my-rushi-config.nix ]; }`

The module is data, read top-down. It sets the `rushi.*`
options (the kernel option schema):

```
{ config, lib, pkgs, ... }:
{
  rushi.config.model = { api = "responses"; max_output_tokens = 32768; };
  rushi.config.limits = { bash_timeout_max = 300; };
  rushi.config.system_prompt.text = "…";
  rushi.config.hooks = { … };
}
```

`modules = [ ]` (the default) is the kernel's neutral
defaults plus the default ext catalog. The repo's own config
(model table, prompt, hook windows, limits tuning) ships in
the prebaked `packages` attrs only. A consumer who wants to
start from it copies the data files
(config/rushi-config.nix, config/hook-windows.nix) into
their own repo.

The `[system_prompt].text` value is one of the config
sections. A consumer sets it in their module (a string, or a
file read in the module body). The prebaked `packages` attrs
carry the built-in `system-prompt.txt` at the repo root.

## Ext selection

The ext set is data. The default set is the declare-once
table in `config/exts.nix`, built from this flake's pinned
ext inputs. A consumer picks their own ext set through the
builder:

- Builder function, from a consuming flake (the ext packages
  come from the consumer's own pinned ext flake inputs):
  `inputs."rushi-config".lib.mkRushiFull
    { system = system;
      exts = {
        extTools = [ myExtInputs."rushi-obscura-web-access".packages."x86_64-linux"."web-fetch" … ];
        extUi = [ myExtInputs."rushi-statusline".packages."x86_64-linux".statusline … ];
        extHooks = [ … ];
      }; }`

`exts` (default null) is an attrset `{ extTools, extUi,
extHooks }` of ext packages for the target system. It
replaces the default table. null keeps the default table.
The consumer pins its own ext flake inputs and passes the
packages, so the ext set is consumer-owned.

The `enableTerminalBrowser` flag gates the default table
only. A consumer ext set decides the ext set.

## Troubleshooting: external hooks not firing

Symptom: session events show
`hook.<window>.error` / `spawn harness-hook-…: No such file or
directory`. The kernel found the hook registration but not the
binary.

Cause (as of 2026-09-15): the running `rushi` binary predates the
kernel's hook-resolution commit (`d43337f` in rust-unix-harness,
"resolve external hook commands against the package layout"). Older
binaries spawn bare hook names straight from `PATH`; the devShell
only exposes the package `bin/` dir on `PATH`, and external hooks
live in `hooks/` — so every external hook fails with ENOENT while
the kernel-shipped `harness-hook-compact` (in `bin/`) works.

Fixes, in order of preference:

- Run a build from the current flake.lock. The kernel at or after
  `d43337f` resolves a bare name against `<exe_dir>/<name>` then
  `<exe_dir>/../hooks/<name>`, so a freshly built package is
  self-contained and does not need `PATH` at all.
- `nix develop` here now adds a `rushi-hook-shim` derivation that
  re-exposes the package `hooks/` dir as a `bin/` dir, so the
  devShell `PATH` carries the hook names even for older binaries.
- If a run still fails: re-enter the devShell after a
  `nix flake update` (an already-open shell keeps the old store
  paths) and start a new session — a running loop keeps its binary
  for the whole session.

Verify with: `nix develop --command sh -c 'command -v
harness-hook-goal-arm'` — it must print a store path, not "not
found".

## Troubleshooting: TUI extensions not loaded

Symptom: the TUI starts with none of the bundled UI extensions. The
statusline, goal row, and simple-english are all missing, even though
`$out/ui_extensions/` holds them. It happens when the TUI is run on
its own (`bin/rushi-tui`, or the devShell `tui` alias), not via
`rushi`.

Cause: the raw `rushi-tui` binary finds its config through the
shared kernel resolver (`rushi_common::paths`, rushi-common 0.1.3,
kernel PR #30). rushi-tui issue #22 moved the resolver there.
The order is: the `$CONFIG` env var, the `--config` flag, the
side-by-side `<exe_dir>/../config.toml` with the exe canonicalized,
then the CWD `config.toml`. The Nix package keeps `config.toml` and
`ui_extensions/` at the package root. A CWD config dir has no
bundled extensions, so none load. The `rushi` kernel does not hit
this, because it resolves its config side-by-side and passes an
explicit `--config` to the TUI.

Fix (shipped upstream, wired up here): the root cause was fixed in
rushi-tui commit `dd69b84` (issue #11, merged as `0a2cf53`).
Issue #22 (commit `7e44df7`) then moved the resolver to the shared
kernel module and shipped the binary as `rushi-tui`. The flake ships
the TUI binary next to `config.toml` and `ui_extensions/` in both
packages. In the configured `rushi` package it lands as `bin/tui`
via the kernel bridge. In the `.#rushi-tui` package it is
`bin/rushi-tui`. So the side-by-side step finds the bundled config
and extension layer. No wrapper shim is needed any more.

`--config` still wins over the side-by-side and CWD steps. Only
the `$CONFIG` env var outranks it.

The `.#rushi-tui` flake output is that self-contained package.
`.#tui` is a kept alias. `nix run .#rushi-tui` from any CWD loads
the bundled extensions the same way.

Verify: run the packaged `bin/rushi-tui` from a CWD with no
`config.toml`.
Set `TUI_EXT_LOG` to a file first. Every bundled extension must
appear as a `spawn … gen=0` line in that file.

    TUI_EXT_LOG=/tmp/ext.log $OUT/bin/rushi-tui

## Decisions

- 2026-09-22: rushi-tui issue #22 made the TUI a self-wired entry.
  The binary is now `rushi-tui`. This flake's `.#rushi-tui` output
  ships `bin/rushi-tui`. `.#tui` stays a kept alias.
- 2026-09-22: the configured `rushi` package still bundles the TUI
  through the `bin/tui` kernel bridge. The locked kernel's mk-rushi
  hardcodes the old name. Cutover policy: no alias is kept. When
  kernel rushi#31 lands the bridge drops and the package ships only
  `bin/rushi-tui`.
- 2026-09-22: the config `[loop]` section already matches the
  self-wired default. No config change was needed. See
  docs/decisions.md for the full record.
- 2026-09-16: `.#tui` changed from the raw TUI binary to a
  self-contained package (raw tui + config.toml + ui_extensions/).
  `nix run .#tui` loads the bundled extensions from any CWD.
- 2026-09-16: the side-by-side `--config` fix landed upstream
  (TonyWu20/rushi-tui#11, commit `dd69b84`, merged as `0a2cf53`).
  The flake dropped its `bin/tui` config shim. `rushi.tui` is now
  the raw TUI package. The lock must keep `rushi-tui` pinned at or
  after `dd69b84`.
