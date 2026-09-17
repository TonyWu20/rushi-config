# Decisions

Session notes on design decisions for this config flake. Newest first.

## Upstream issues filed for session-path ownership (2026-09-17)

The path-resolution chaos (each consumer re-derives the session dir)
is tracked by two upstream issues. The interim fix stays in the exts
(the `RUSHI_CWD` anchor under the local pins above).

- `rushi#16`: the kernel hook env should carry absolute `SESSION`
  and `SESSIONS_ROOT` instead of relying on the inherited cwd.
- `rushi-tui#14`: session-carrying ext ops (`commands`, `invoke`,
  `event`) should carry an absolute `session_dir` so exts stop
  re-deriving paths from `CONFIG` + `RUSHI_CWD`.

Both issues cross-reference each other.

## goal-ext + simple-english-ext: resolve sessions_root against RUSHI_CWD (2026-09-17)

**Problem.** In the `configured` Nix package, `goal-ext` silently failed to write `goal.json`.
The ext resolved the relative `sessions_root` against the config file's parent directory.
Under Nix, that parent is the read-only store. The write failed silently.
No goal file appeared, and the goal hook fired with no goal state.

**Fix.** In `rushi-exts/goal-app/goal-ext/src/main.rs` (commit `d7d016d`) and
`rushi-simple-english/simple-english-ext/src/main.rs` (commit `5004957`),
`sessions_root()` now uses `RUSHI_CWD` as the base for relative paths.
The TUI host exports that env var at ext spawn time.
When `RUSHI_CWD` is unset (bare dev run), the config directory is used.
This matches the kernel, which resolves `sessions_root` against the loop cwd.

**Verified.** 25 goal-ext unit tests pass. 5 simple-english-ext tests pass.
Old-vs-new simulation with the Nix-store config plus `RUSHI_CWD`:
the old build wrote `goal.json` nowhere (the reported symptom).
The new build writes `goal.json` and `goal-<id>.json` into
`$RUSHI_CWD/sessions/<sess>/` and emits the `ext_status` append.

**Ownership of the session dir path.** The session dir is
`<launch cwd>/sessions/<name>`. The launch cwd is the single authority.
The kernel owns it, and the kernel exists in both TUI and headless modes.

- Kernel hooks get `SESSION` + `SESSIONS_ROOT` from the kernel.
  They resolve against the loop cwd. That side was already correct.
- goal-ext is TUI-only. The host spawns it and relays the launch cwd
  via `RUSHI_CWD` at spawn plus `cwd` fields on tick/row ops.
  The host is a relay, not an owner.
- Headless mode: no host, no goal-ext. `goal.json` is created by the
  user or a script. The goal-arm hook reads it with the kernel-provided
  `SESSION`/`SESSIONS_ROOT`. No goal path couples to the TUI host.

**No new env var.** The fix reuses `RUSHI_CWD`, which the host
already exports. No second channel is added. The user constraint is
to avoid stacking env vars to make paths work.

**Rollout (option 1: local pin, chosen 2026-09-17).** `flake.nix`
pins `rushi-goal-mode` to `git+file:///home/tony/programming/rushi-exts/goal-app`.
`rushi-simple-english` pins to `git+file:///home/tony/programming/rushi-simple-english`.
Both locks sit on the fix commits. The `configured` build from these
pins passes the simulation above.

The host-sent absolute `session_dir` for the session-carrying ops is
tracked in `rushi-tui#14`, and the kernel's absolute hook env in
`rushi#16`. When both land, flip the inputs back to the
`github:TonyWu20` refs and run `nix flake update rushi-goal-mode
rushi-simple-english`.

## rushi#13 landed: consumer side complete, all ext values meta-derived (2026-09)

The kernel merged #13 on main (merge `5be2920`). `lib.mkRushi` now
reads each producer's `meta.rushi` at eval time. This flake moved to
the cleanest declare-once form:

- The `exts` table rows carry only the package. Hook rows keep their
  `windows`. The `entry` and `bin` fields are gone.
- `rushi.config.paths.extension_tool_paths` is no longer declared.
  The kernel fills it from `meta.rushi.entry` at eval time.
- `rushi.ui_extension_names` is no longer declared. The kernel fills
  the manifest `[ui_extensions]` list from `meta.rushi.ext`.
- Hook `command` values in `[[hooks.on]]` derive from
  `pkg.meta.rushi.bin` in `extHookOn`, so the binary name is typed
  once, on the producer side.
- Pins bumped: `rushi-kernel` to `5be2920` (the #13 merge). All five
  producer inputs to their `meta.rushi` commits (goal-mode `a693684`,
  no-find-grep `041434d`, statusline `dbc9db2`, simple-english
  `8e67178`, web-access `6948d46`).
- Verified by building `.#packages.x86_64-linux.default`. The
  generated `config.toml` carries the 5 `extension_tool_paths` and
  all hook commands. `tools.manifest` `[ui_extensions]` lists goal,
  simple-english, and statusline. No build-time discovery fallback
  warnings fired (every producer carries `meta.rushi`).

## Wait for rushi#13: producer `meta.rushi` is the final declare-once (2026-09)

Decision: no consumer-side workarounds for the remaining
"typed twice" friction. The cleanest version is rushi#13.
It derives `extension_tool_paths` and ui-ext names at eval
time from a producer `meta.rushi` attribute. The consumer then
lists each ext once in `external_*` and types no paths or
names. The shipped config equals the returned `config`.

- Issue: https://github.com/TonyWu20/rushi/issues/13
  (follow-up to #10, `enhancement` label).
- Producer half of the contract: one `meta.rushi` line per
  ext package. Tools set `entry`, UI exts set `ext`, hooks
  set `bin`. The #13 body carries the full package list.
- The attribute is additive and inert until the kernel reads
  it. #10's discovery keeps working until then, so repos
  migrate incrementally.
- The `exts` table now on disk in this flake is provisional.
  After #13 lands, its `entry`/`bin` fields and the explicit
  `extension_tool_paths` / `ui_extension_names` declarations
  are dropped in favor of the meta-derived values.
- pname-based derivation was rejected: pname is packaging
  identity (`goal-tool`), not the runtime entry name (`goal`).
- Producer half done in the local checkouts (2026-09): all five
  ext repos now advertise `meta.rushi`. Tools set `entry`, UI-exts
  set `ext`, hooks set `bin`. Verified via `nix eval` (rushi value
  plus the nixpkgs auto-meta skeleton in `metaKeys` for every
  package) and by building the no-find-grep, simple-english, and
  statusline packages after the merge. The consumer half (kernel
  #13 reader) is still pending. The attribute stays inert until it
  lands.

## Hook overlap closed: external hooks declared once (2026-09)

`rushi.config.hooks` still overlapped `rushi.external_hooks`: every external
hook was typed in two places and two types. Once as a bundled package in
`external_hooks`, and again as a bare `command` name in `config.hooks.on`.

Closed by a single source of truth in the config module, `extHookRegs`.
Each entry carries the package, its runtime binary, and the windows that fire
it. Both lists now derive from it:

- `rushi.external_hooks` is `map (r: r.pkg) extHookRegs`.
- The external portion of `rushi.config.hooks.on` is `extHookOn extHookRegs`.
- Kernel-shipped hooks (no external package) live in a separate
  `kernelHookRegs` and prepend the `on` list.

So adding or removing an external hook is a one-line change to
`extHookRegs`. The kernel's #10 drift guard still verifies each `command`
resolves to a bundled binary.

## rushi#10 landed: redundant fields dropped, pin bumped (2026-09)

Kernel merge `bf87e41` (PR #11) shipped the auto-derivation.
`extension_tool_paths` is now derived from `external_tools` at build time.
`ui_extension_names` is auto-discovered from the bundled ext layout.
`rushi.tools` defaults to the full kernel tool set.
A build-time drift guard checks every bare hook command.
It fails the build when a command has no file in `$out/bin/` or `$out/hooks/`.

Per the follow-up note, this flake now drops the redundant fields.
Each ext is declared exactly once in its `external_*` list.

- `rushi.config.paths.extension_tool_paths` is dropped.
  The generated config carries the 5 ext tool paths.
  They are auto-derived from `rushi.external_tools`.
- `rushi.ui_extension_names` is dropped.
  The manifest `[ui_extensions] enabled` list is auto-discovered.
- `rushi.tools` is dropped.
  The manifest `[tools] enabled` uses the kernel default.
  That default is the same 4-tool native set this flake used to derive.
  `nativeToolPaths` stays. It still feeds the intrinsic `native_tool_paths`.
- The `tui` package's hardcoded entry-dir check is replaced.
  `extUiCopyScript` now runs a per-source `ext.toml` guard.
  It mirrors the kernel's `extUiScript`.
  This closes the last "type twice" coupling in this flake.

Kernel pin: lock rev `3e2a787` moved to `bf87e41`.
The github ref is kept.
That is the "back to the pinned ref at hosting time" state.
No `path:` flip was needed since #10 is closed.

Verified: `nix build .#rushi .#tui` passes all the new guards.
The generated `config.toml` and `tools.manifest` carry the auto-derived lists.

## Declare-once: paths win over names (2026-09)

**Principle.** A tool, hook, or ext is declared once, as a Nix value in the
`rushi.external_*` lists. The runtime paths the kernel needs are derived from
that declaration rather than re-typed as bare strings. Pointing at the
binary or manifest path already tells `rushi` the thing exists. Name
resolution is path resolution under the hood.

Per-pair resolution:

| Pair | Resolution |
|---|---|
| `config.paths.extension_tool_paths` vs `external_tools` | **Resolved by #10** (kernel `bf87e41`): auto-derived from `external_tools` at build time. This flake no longer declares the field. Before that it stayed an explicit per-entry list (real manifest dirs, not bare names) as the stopgap for the root-scan blindspot below. |
| `config.hooks` vs `external_hooks` | Closed locally. The external hooks are declared once in the `extHookRegs` single source, and both `rushi.external_hooks` and the external portion of `rushi.config.hooks.on` derive from it. Only kernel-shipped hooks (no package) remain as a small `kernelHookRegs` list. |
| `config.paths.native_tool_paths` vs `rushi.tools` | Collapsed here. `nativeToolPaths` is the single source for `native_tool_paths`. Since `bf87e41` the kernel defaults `rushi.tools` to its full tool set, so this flake no longer derives or declares it. |
| `external_ui_extensions` vs `ui_extension_names` | **Resolved by #10** (kernel `bf87e41`): entry names auto-discovered at build time from the bundled `$out/ui_extensions/` layout. This flake no longer declares `ui_extension_names`. |

### Why per-entry `extension_tool_paths` instead of a single `["tools"]` root

A root scan silently assumes every ext tool is Nix-bundled into the shared
`$out/tools`. That breaks the moment an ext has no flake, since a plain-path
source is not under that root. This is a blindspot. It is resolved by #10:
the kernel now auto-derives ext tool paths from the `external_tools` sources
at build time, so this flake no longer lists them.

### Follow-ups (all closed with #10)

- ~~**rushi#10** (kernel): auto-derive `extension_tool_paths` and
  `ui_extension_names` from the `external_*` lists at build time. Default
  `rushi.tools` to the full kernel set. Add a hook-command drift guard.~~
  **Done** — landed in kernel `bf87e41` (PR #11). The redundant fields were
  dropped from this flake on 2026-09 (see the entry above).
- ~~**Kernel pin:** `flake.nix` still pins `rushi-kernel` to the github ref
  (lock rev `3e2a787`)...~~ **Done** — lock now pins `bf87e41` on the
  github ref (hosting-time state). No `path:` flip was ever needed in this
  flake because #10 shipped to the remote.
