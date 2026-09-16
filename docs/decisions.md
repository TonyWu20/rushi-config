# Decisions

Session notes on design decisions for this config flake. Newest first.

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
| `config.hooks` vs `external_hooks` | `hooks.on` is intrinsic config. The window-to-command bindings cannot be derived from a package, so this list stays. The bare-name to binary link is kernel path resolution. |
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
