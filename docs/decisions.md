# Decisions

Session notes on design decisions for this config flake. Newest first.

## Destructure the ext input names in the `outputs` pattern (2026-10-12)

**Decision.** The `outputs` signature now destructures all eleven
hyphenated flake input names alongside `self`, `nixpkgs`, and
`fenix`. The body uses them as bare names. No `inputs."…"`
prefix remains in the flake body.

**Rationale.** User instruction. Nix destructures hyphenated
attrpaths in lambda patterns. The binding is usable in the body
with attrselects (for example `rushi-kernel.lib.mkRushi`). The
`inputs.` prefix and the quoted select add no capability.

**Verified.** `nix flake check --no-build` passes all checks on
the host system (`x86_64-linux`).

## Drop the `goal` ext tool from the exts table (2026-10-12)

**Decision.** `config/exts.nix` no longer lists the `goal`
package (`rushi-goal-mode` `goal` output) in `extTools`. The
`goal-blocked` and `goal-complete` loop tools stay in `extTools`.
The `goal-ext` UI extension stays in `extUi`. The `rushi-goal`
headless seeder stays: it is a separate output, shipped into the
combined package `bin/`.

**Rationale.** User decision. The agent does not need to see the
`goal` tool.

**Verified.** `nix flake check --no-build` passes all checks on
the host system (`x86_64-linux`).

## Drop the flake-input alias bindings (2026-10-12)

**Decision.** `flake.nix` no longer binds alias identifiers for
the hyphenated flake inputs. All eleven alias lines are gone
(`rushiKernel`, `tuiFlake`, `goalFlake`, `nfgFlake`, `seFlake`,
`statuslineFlake`, `obscuraWebFlake`, `mineruFlake`, `imgFlake`,
`mermaidExtFlake`, `tbFlake`). The call sites select
`inputs."rushi-kernel"` and friends directly.

The extracted modules take the `inputs` attrset instead of the
alias chain. `config-module.nix` and `config/exts.nix` now take
`{ inputs, tbEnabled ? false }`. The exts table selects each ext
flake directly (for example
`inputs."rushi-goal-mode".packages.${system}."goal-blocked"`).
The `tbFlake ? null` value-or-null optionality became the
`tbEnabled` boolean, symmetric with the consumer-side
`enableTerminalBrowser` flag.

**Rationale.** User correction. Hyphenated input names only bar
a bare Nix identifier. `inputs."rushi-kernel"` is a valid quoted
attribute select anywhere in the `inputs@{…}` outputs body. The
alias bindings added indirection without capability.

**Verified.** `nix flake check --no-build` passes all checks on
the host system (`x86_64-linux`).

## Flip the `terminal-browser-agent` input to `github:` (2026-10-10)

**Decision.** The `terminal-browser-agent` input is now
`github:TonyWu20/terminal-browser-agent`. The lock pins rev
`544a372`. That rev is the default-branch HEAD. It is the
same rev as the local checkout. This replaces the absolute
`path:` pin from the earlier same-day entry. Bump with
`nix flake update terminal-browser-agent`.

**Rationale.** User decision. The repo is on github. The flake
pulls the hosted source. A `path:` pin couples the flake to
one machine's checkout. Other consumers cannot build from it.

**Verified.** `nix flake lock` re-pinned the node to the
github rev. `.#rushi-full` (off) is unchanged: store path
`1lxwi0jf…rushi-full-0.1`. `.#rushi-full-tb` now builds
`q7cgxf5b…rushi-full-0.1` from the hosted source. The
`tools/terminal-browser/` layout, the `bin/` trio, and the
config's `extension_tool_paths` entry all pass as before. The
lib builder resolves to the same two derivations.

**Note.** The TB tool package got a new store path
(`crv29ndz…terminal-browser-tool-0.1.0`). The derivation's
source input moved from the path flake to the git flake. The
file content is unchanged.

## Optional terminal-browser tool in `rushi-full` (2026-10-10)

**Decision.** The terminal-browser tool (the tool-only
terminal-browser-agent repo) is wired into the build as an
optional ext tool. The new flake input `terminal-browser-agent`
pins the local repo by absolute path
(`/home/tony/programming/terminal-browser-agent`, two levels up
from this flake). The exts table gains a `tbFlake ? null`
parameter: a non-null value appends the `terminal-browser` row to
`extTools`. The flake builds two config-side instantiations:
`cfg` (tool off, the default) and `cfgTb` (tool on).
`rushi-full` keeps the off default. The consumer enables the tool
through the prebaked `packages.<system>."rushi-full-tb"` attr or
through `lib.mkRushiFull
{ system = …; enableTerminalBrowser = true; }`.

**Rationale.** The tool is a personal web-browsing extension. The
user requires the option to live on the consumer side of
rushi-config, so the default package is unchanged and the enabled
variant is a separate, explicitly requested build. A relative
`path:../../terminal-browser-agent` input is not usable: in pure
eval mode a relative path input resolves against the git snapshot
root, not the checkout. The absolute path pin matches this
repo's documented bootstrap-stage convention.

**Verified.** `.#rushi-full` (off) is byte-identical to the
pre-change build: store path `1lxwi0jf…rushi-full-0.1` before
and after. `.#rushi-full-tb` builds
`9pziy8n0…rushi-full-0.1` and carries
`tools/terminal-browser/{tool.toml,bin/,docs/}`, the
`bin/` trio (`rushi` + `rushi-tui` + `rushi-goal`), and the
tool's store path in the generated config's
`extension_tool_paths`. The off package's config and `tools/`
carry no terminal-browser entry. `lib.mkRushiFull` with
`system` and `enableTerminalBrowser` resolves to the same
derivations as the two prebaked attrs.

**Note.** The kernel's `tools.manifest` is unchanged in shape:
ext tools are not enumerated there. They are addressed by the
`tools/<entry>` bundle dir and the config's
`extension_tool_paths`. A Nix parse quirk shaped the lib
builder: a tight `f { … }."attr"` selects on the argument
attrset, not on the call result, so the select goes through a
named `let` binding. The flake.nix + flake.lock pair is atomic
as usual: commit them together.

## Bash-only native tool catalog, lean variant retired (2026-10-06)

**Decision.** The `nativeToolNames` catalog in `config-module.nix`
is now `[ "bash" ]`. Every package exposes one native tool:
bash. That covers the configured `rushi`, the combined
`rushi-full`, and the self-wired `rushi-tui`. This change
removed the `rushi-bash` lean variant and its `mkLean` builder
from `flake.nix`. The variant would now build a byte-identical
duplicate of `rushi`, so it is gone. The `configModule`
`toolNames` parameter remains for per-build subsets.

**Rationale.** The user wants a bash-only agent tool set. File
work now happens through bash. The same change updated the
`system-prompt.txt` guidance. It dropped the read/edit/write
tool advice. The new lines tell the model to check file size
before reading. They suggest mermaid diagrams, tables, or HTML
for long replies.

**Verified.** The `.#rushi` build passes. Its `config.toml`
carries one `native_tool_paths` entry: the `tools/bash` store
dir. The `tools.manifest` `[tools] enabled` list holds
`[ "bash" ]`. The `rushi-full` default builds with the same
config. `.#rushi-bash` no longer resolves. The ext tools,
hooks, and the four UI extensions are unchanged.

**Note.** The raw kernel package still bundles `bin/edit`,
`bin/read`, and `bin/write`. Those binaries and the
`tools/{edit,read,write}` manifests are inert. The manifest
`enabled` list is the only tool exposure point. The `rushi-tui`
config stays byte-identical to the kernel config, so the
`rushi-full` overlay merge is unchanged.

## Ship the headless goal seeder in `rushi-full` (2026-10-04)

**Decision.** `rushi-full` now bundles the `rushi-goal` binary from the
`rushi-goal-mode` input. The goal-mode pin moved from `d6a10ab` to
`9901ddf` (issue #8). The binary lands at `bin/rushi-goal` next to
`bin/rushi` and `bin/rushi-tui`.

**Rationale.** A headless setup script calls `rushi-goal <session>
<goal>` before it execs `rushi run <session>`. The seeder resolves
the config by the kernel ladder and writes the session goal files,
so the seeder and the loop agree. The combined package keeps the
pair version-locked in one store object.

**Verified.** `nix build .#rushi-full` passes. The store object
holds `bin/rushi`, `bin/rushi-tui`, and `bin/rushi-goal`. The
packaged `rushi-goal` seeded a scratch session and wrote
`goal.json` plus `goal-<id>.json` under the CWD sessions root.
Store path: `rushi-full` `3qks9a2` at the `9901ddf` pin.

**Note.** `rushi-goal` is a bare user binary, not a loop tool and
not an ext, so the `exts` table does not list it. The merge
installPhase makes `bin/` writable again after the TUI overlay,
because `cp -a` reapplies the source dir's read-only mode. The
`flake.nix` and `flake.lock` pair is atomic: a new flake.nix on
the old lock fails eval with a missing `rushi-goal` attribute.
Commit the pair together.

## Retire the non-Nix `out/` layout (2026-10-04)

**Decision.** Delete the stale `out/` directory in the repo root.
Add `out/` to `.gitignore`. Retire the non-Nix install flow: this
is a private repo, and the nix flake is the only distribution path.

**Rationale.** `out/` held a copied configured-kernel package
layout from before the TUI merge and the goal seeder. It shadowed
the real `nix build` output, so inspecting `out/` looked like the
default package lost the TUI and the seeder. Nothing regenerates
it now that the non-Nix install is retired.

**Verified.** No derivation in the build graph takes the flake
source (with `out/`) as an input, so the deletion changes no store
path. `git status` is clean after the commit. `nix build .#`
still resolves the default to `rushi-full`.

**Note.** If a non-Nix install flow returns, re-add an `out/`
builder and drop the ignore line.

## Tool-set variants and the config table split (2026-09-30)

**Decision.** The `exts` table moved to `config/exts.nix`. The `[hooks]`
defs and pipeline tables moved to `config/hook-windows.nix`. The
`nativeToolNames` catalog moved to the top of `config-module.nix`.

`configModule` gained a `toolNames` parameter. It sets the native tool
set to expose. The default (null) keeps the full catalog.

A new flake output `rushi-bash` builds the configured kernel with
`toolNames = [ "bash" ]`. Its `tools.manifest` and `native_tool_paths`
carry only the bash tool.

**Rationale.** The old `config-module.nix` mixed the exts table, the
hooks tables, and the config body in one file. Each table now has one
file with one job.

The `toolNames` parameter makes the tool set a direct input to the
module. A lean variant is a one-line flake change.

**Verified.** All five pre-existing outputs keep their store paths.
The generated configs are unchanged. The `.#rushi-bash` build passes.

- Store paths: `rushi-full` 73lv8n2d, `rushi` k7sbc82n, `rushi-tui` lxivqk61, `rushi-kernel` cifhx685
- The `native_tool_paths` line holds one entry. The `[tools] enabled` list holds `[ "bash" ]`
- The referenced `tools/bash` store dir is in the package closure

**Note.** `config/exts.nix` and `config/hook-windows.nix` must stay
Git-tracked. Nix sees the flake source as the Git tree. Untracked files
are invisible to flake evaluation.

**Open.** The output name `rushi-bash` is a working name. The lean
package is the configured kernel, not the combined TUI package. No
lean TUI variant exists yet.

## Extract the config module into config-module.nix (2026-09-30)

**Decision.** The `exts` declare-once table and the `configModule` definition moved from `flake.nix` to `config-module.nix`. `flake.nix` imports that file with the six ext flake aliases and re-binds `exts` and `configModule`. The `forSystem` build section is unchanged.

**Rationale.** About 225 lines of config text (ext table, hooks table, model, limits, and TUI settings) hid the build graph inside `flake.nix`. The split keeps the main flake a short build-graph view. The config content itself is unchanged.

**Verified.** `nix eval .#packages.x86_64-linux.default` gives the same store path before and after the split (`/nix/store/85552xb49cy4rd5wrc51lwrfviljd8fy-rushi-full-0.1`), so the generated config is byte-for-byte identical. A mutation test (changed model id in `config-module.nix`) changed the store path. Restoring the file brought the original path back. `nix-instantiate --parse` passes on both files. All five package outputs evaluate to valid store paths.

**Note.** `config-module.nix` must stay Git-tracked. Nix sees the flake source as the Git tree, and an untracked file is invisible to flake evaluation.

## Ship the combined kernel+TUI package as the default (2026-11-08)

**Decision.** The flake ships a combined package `rushi-full`: the configured kernel and the self-wired TUI in one store object. `default` and the `rushi-full` alias point to it. The kernel-only package stays as `rushi`. The TUI-only package stays as `rushi-tui`.

**Rationale.** Two independent store objects let a consumer import the TUI alone. The bare `rushi` name then resolved from PATH to a stale configured build. The TUI ran that stale kernel. Session logs kept the stale `decision`/`payload` hook fields, not the migrated `blocked_calls`.

**Verified.** `nix build` of the `rushi-full` output passes. The store object holds `bin/rushi`, `bin/rushi-tui`, `config.toml`, `hooks/`, `tools/` with `tools.manifest`, and `ui_extensions/`. The kernel binary matches the configured package byte for byte, and the TUI binary matches the `rushi-tui` package. The bundled no-find-grep hook emits `blocked_calls`. In the devShell, both PATH binaries resolve into the same `rushi-full` store object.

**Consumer note.** A consumer that imports `rushi-config.packages.${system}.default` gets the combined package after a relock. A consumer that listed both `default` and `rushi-tui` can drop the `rushi-tui` line.

## Explicit `[hooks]` placements replace the derived fold (2026-09-24)

**Supersedes** the derived-pipeline portion of "Hook cutover: `[[hooks.on]]` to defs + pipeline, kernel pin 462043d". The `hookDefs` / `hookPipeline` builders over the exts table were removed in favor of literal attrsets.

**Decision.** `hooks.defs` and `hooks.pipeline` are now literal attrsets in the config module. One def per hook, one ordered steps list per window. `exts.extHooks` now lists only the packages to bundle, and no longer carries `windows`. Each hook binary name is typed once in `hooks.defs`, and the kernel build-time drift guard still cross-checks every bare command against each producer's `meta.rushi.bin`.

**Rationale.** The fold was too abstract to review quickly. Explicit step lists keep window placement visible and editable without helper logic.

**Verified.** Eval passes and both package builds succeed. The two generated config.toml files remain byte-identical under cmp, and the configured package keeps its store path. The generated config still carries 8 defs and 7 pipeline windows, with zero legacy on rows.

## Goal-tokens hook fires at `model.after` (2026-09-24)

**Decision.** `harness-hook-goal-tokens` fires at `model.after`, not `model.before`. The local dev config had it registered at `model.before`, which was a mistake. Both configs now agree on `model.after`.

**Rationale.** The user confirmed the token-usage hook belongs after the model turn. The consumer flake's legacy `[[hooks.on]]` shape already used `model.after`, so only the dev config needed the fix.

**Verified.** The dev config pipeline now reads `model.before` = [goal-arm, simple-english] and `model.after` = [goal-tokens]. Config load under the post-cutover kernel passes with no pipeline errors.

## Hook cutover: `[[hooks.on]]` to defs + pipeline, kernel pin 462043d (2026-09-24)

**Supersedes** the wire-shape portions of "Hook overlap closed: external hooks declared once" and "Declare-once: paths win over names". The declare-once principle itself is unchanged.

**Decision.** `rushi.config` now emits the kernel issue #38 pipeline hook model. One named def per hook lives in the defs table, keyed by the bare command name. One ordered steps list per window lives in the pipeline table. The per-window step order preserves the legacy list order. The old row flatteners were replaced by the `hookDefs` / `hookPipeline` builders over the same ext table.

**Rationale.** The cutover kernel hard-rejects the legacy `on` key at config load. A pin to the cutover commit alone is still broken, because its Nix defaults leaked the legacy key into every generated config. 462043d is the first usable post-cutover pin. The old kernel silently ignores unknown `hooks` keys, so migrating without the pin bump would stop all hooks. The migration and the pin bump are atomic, and they landed together.

**Pin.** `rushi-kernel` ca70129 to 462043d (`github:TonyWu20/rushi` main).

**Verified.** `nix flake update rushi-kernel` plus `nix build .#rushi` (rc 0). The generated config has 8 defs entries and 7 pipeline windows, no `on` key, and the step order matches the legacy list. `rushi step` under the built binary passes the full config load for this config. The same binary hard-rejects the legacy dev config with the migration hint. The TUI package carries a byte-identical config.

## Absolute store tool paths in both configs, wrapper retired (2026-09-24)

**Supersedes** the same-day `rushi-tui-bin` bin-only wrapper entry.
That wrapper is now retired.

**Decision.** The configured package config now writes the same
absolute store tool paths as the TUI package. The two root-level
config.toml files are byte-identical. `pkgs.buildEnv` dedupes
identical files when merging roots.

The numtide/devshell devshell can now list both full rushi packages
side by side. The devshells list the full `rushi-tui` package
again. The `rushi-tui-bin` output and its derivation are dropped.

**Rationale.** The earlier buildEnv conflicting-subpath failure
happened because the two config.toml files differed in their tool
paths. One used relative entries, the other absolute store paths.
Now they are identical, so nothing conflicts. The bundled tools/
dir stays in the configured package. That is part of the kernel's
package layout.

**Verified.** The two root config.toml files diff clean. All six
absolute tool paths sit in the configured package closure. The
aggregator devShell and the consumer devshell build with both full
packages present. `rushi-tui` on PATH resolves to the TUI store
package. Its `--help` runs against its own config.

**Retire `rushi-tui-bin`.** The bin-only wrapper is now redundant.
If the two root config.toml files ever diverge again, a merge-safe
view can be reintroduced.

## devshell merge conflict: new `rushi-tui-bin` bin-only output (2026-09-24)

**Problem.** A devshell that merges whole package roots cannot combine
the two rushi packages. Both ship a root-level `config.toml` from the
issue-#22 side-by-side layout. The binary finds its config next to the
canonicalized executable.

The two files differ. The configured package writes relative
`tools/...` paths. The TUI package writes absolute store paths.
`pkgs.buildEnv` dies on the first conflicting subpath:

```
pkgs.buildEnv error: two given paths contain a conflicting subpath:
  `.../rushi-tui-0.1/config.toml' and
  `.../rushi-configured-0.1/config.toml'
```

numtide/devshell builds its `devshell-dir` as a `pkgs.buildEnv` over
all of `devshell.packages`. The consumer shell lists both rushi
packages, so it fails at build time.

`pkgs.mkShell` with `buildInputs` never hit this. It only puts each
input `bin/` dir on PATH. It never merges package roots, which is
why it shadowed the conflict.

In nixpkgs 26.11, `mkShell` with `packages` adds no root merge
either. It collapses to `nativeBuildInputs`.

**Decision.** Fix the packaging, do not hide it. New flake output
`rushi-tui-bin` is a bin/-only view of the self-contained TUI
package. Its `$out/bin/rushi-tui` symlinks into the real `rushi-tui`
store package.

The shell gains one `bin/rushi-tui` entry in any root merge. No
root-level `config.toml` is present, so nothing collides. The
symlink survives buildEnv's symlink-tree merge. The TUI side-by-side
config resolution still finds the right file.

The aggregator devShell `packages` list now reads
`[ configured, rushi-tui-bin, hookPathShim ]`. The consumer flake
devshell swaps `rushi-tui` for
`rushi-config.packages.${system}."rushi-tui-bin"`. The standalone
`. #rushi-tui` package is unchanged for `nix run` and `nix build`.

**Retire on kernel #31 cutover.** When the configured package ships
`bin/rushi-tui` itself, the wrapper is redundant. Drop `rushi-tui-bin`
and list only the configured package in devshells.

**Verified.** `nix build` of the new output and of the aggregator
devShell pass. In the activated shell, `command -v rushi-tui`
resolves through the wrapper to the store binary. `rushi-tui
--help` runs against its own config. The consumer devshell builds
its `devshell-dir` merge, and `rushi-tui` on PATH resolves to the
TUI store package.

## Self-wired TUI entry wired in (2026-09-22)

**Decision.** rushi-tui issue #22 (commits `7e44df7`, `e07d39b`,
`a3be449`, merge `0996b52`) made the TUI a self-wired front-end.
The entry binary is now `rushi-tui`. Config discovery uses the
shared kernel resolver from rushi-common 0.1.3. The loop defaults
to the Tier-1 `rushi` CLI when no `[loop]` section is set.
This flake adapted to that change.

- The lock pin moved to `0996b52`. That is the issue #22 merge.
- `tuiFull` now copies `bin/rushi-tui` from the raw TUI package.
  The old `bin/tui` path no longer exists upstream.
  `mainProgram` is `rushi-tui`.
- The new `rushi-tui` flake output is the self-contained package.
  `tui` stays as a kept alias for existing run commands.
- The configured `rushi` package still needs a bridge. The locked
  kernel `mk-rushi.nix` (rev `04ba2e8`) hardcodes a copy of
  `$TUI_SRC/bin/tui` into the package. It warns and skips when the
  file is missing. So a small `rushi-tui-bin-compat` derivation
  re-exposes the binary under both names. The kernel's `cp`
  follows the symlink and lands a real `bin/tui`.
- The `[loop]` config section already matches the self-wired
  default (`rushi run`, append_session). No config change was
  needed.
- No `[tui].binary` key was added. The kernel launcher finds the
  side-by-side `bin/tui` in the configured package. That path is
  retired when the kernel retires the `rushi tui` arm (kernel
  `docs/itches.md`).

**Cutover decision (2026-09-22, user).** Clean cutover: no `bin/tui`
alias in the post-fix state, and no old-name fallback for pre-#22
TUI pins. The bridge carries the binary only into the kernel's
hardcoded `bin/tui` slot. No dual-name transition.

**Retire the bridge.** When kernel rushi#31 lands, drop the
`rushi-tui-bin-compat` derivation. Pass `rawTui` straight to
`rushi.tui`. Then `bin/rushi-tui` is the only TUI binary in the
configured package.

**Verified.** `nix build .#rushi` and `.#rushi-tui` pass. The
configured package keeps a real `bin/tui` plus `config.toml`. The
`. #rushi-tui` package ships `bin/rushi-tui` next to its
`config.toml` and `ui_extensions/`. Its `--help` reports the
self-wired entry and its `[loop]` section is `rushi run`.

## mermaid ext wired in (2026-09-20)

**Decision.** The standalone `rushi-tui-mermaid-ext` repo is wired
in with one row in the declare-once `extUi` table.
It is the `ui_extensions/mermaid` entry, split from the rushi-exts
monorepo and pushed public on 2026-09-20.

- New flake input `rushi-tui-mermaid-ext`, pointing at
  `github:TonyWu20/rushi-tui-mermaid-ext`. Its `nixpkgs` and `fenix`
  follow this flake, like every other ext input.
- The lock pins commit `44467d3`.
- The `extUi` row is
  `{ pkg = mermaidExtFlake.packages.${system}."mermaid-ext"; }`.
- That row is the single source of truth. It drives
  `rushi.external_ui_extensions`, the `tui` package bundle, and the
  `tools.manifest` `[ui_extensions] enabled` list.
- The manifest list is derived from the producer's `meta.rushi.ext`
  at eval time (rushi#13). No entry name is re-typed on the
  consumer side.

**binDir note.** The producer's `ext.toml` declares
`command = "target/debug/mermaid-ext"`. It mirrors the monorepo's
`ext-env.sh` debug-build flow. So its flake passes
`binDir = "target/debug"` to `wrapAsExt`. The release binary then
lands where the manifest resolves `command` against the entry dir.
The consumer stays unaware of the layout.

**Verified.** `nix build .#rushi` and `.#tui` pass.
`ui_extensions/mermaid/` ships `ext.toml` plus the binary under
`target/debug/`. The `tools.manifest` `[ui_extensions] enabled` list
gains `mermaid`. The bundled binary renders `fence:mermaid` requests
into ASCII art.

## Ext-side issues filed for host-provided session_dir (2026-09-17)

The interim `RUSHI_CWD` fix works, but the exts still re-derive the
session dir from `CONFIG` + `RUSHI_CWD`. The host now hands over a
pre-resolved `session_dir` on session-carrying ops (rushi-tui#14).
Two ext-side issues are open:

- `rushi-goal-mode#2`: goal-ext should consume the host-provided
  `session_dir` from the commands/invoke/event handlers.
- `rushi-simple-english#3`: simple-english-ext should consume the
  host-provided `session_dir` in the row handler.

The `row` op does not yet carry `session_dir` (only commands,
invoke, and event do). That gap is noted in rushi-simple-english#3
and is a TUI-side follow-up.

## Upstream issues filed for session-path ownership (2026-09-17)

The path-resolution chaos (each consumer re-derives the session dir)
is tracked by two upstream issues. The interim fix lives in the exts
(the `RUSHI_CWD` anchor). It now ships on both GitHub remotes.

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
first pinned both ext repos via `git+file://` at the fix commits.
That local build passed the simulations above.

**Flip-back (2026-09-17, after the push).** Both fix commits are
now pushed to the github remotes. The flake is back on the
`github:TonyWu20` refs. The goal-mode lock pins `d7d016d`. The
simple-english lock pins `ffdb565`. The build from these refs passes
the same simulations.

The host-sent absolute `session_dir` for the session-carrying ops is
tracked in `rushi-tui#14`. The kernel's absolute hook env is tracked
in `rushi#16`. Both are now closed and landed. The exts can drop
the `CONFIG`-based path derivation in a future pass.

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

## System prompt override option (2026-10-17)

**Principle.** The `[system_prompt].text` value is a free build-time
consumer value, not a flake-attr value. Free text cannot be
prebaked into `packages.<system>`, so the option lives on the
consumer-side builder function (`lib.mkRushiFull`), mirroring the
`enableTerminalBrowser` precedent.

- `configModule` gains `systemPrompt ? null`.
  - `null` (default) keeps the built-in `system-prompt.txt`.
    The prebaked `packages` attrs stay byte-identical.
  - A string is used verbatim as the inline prompt text.
  - A path or text-file derivation is read as a file
    via `builtins.readFile`.
- `buildForSystem` and `lib.mkRushiFull` thread the parameter to
  both `mkRushi` instantiations. The configured `rushi` package
  and the `rushi-tui` package share one generated config, so
  one parameter covers both.
- Consumer usage:
  `inputs."rushi-config".lib.mkRushiFull
    { system = system; systemPrompt = ./my-prompt.txt; }`

Verified by evaluation: the default build's `[system_prompt].text`
still reads `system-prompt.txt`. A string override and a path
override both land in the generated `config.toml`.

## `bin/log` dropped in buildEnv-merged devshells: filed rushi#57 (2026-10-25)

**Problem.** The devshell `bin/` (the `devshell-dir` merged by `buildEnv`)
silently drops the kernel `log` stage binary.
The other 16 rushi binaries survive the merge.
`log` is not on the devshell `PATH`.

**Root cause.** The nixpkgs buildEnv builder hard-codes a skip for any
file named `log`. The source is
`pkgs/build-support/buildenv/builder.pl` (upstream master, line 151):
`$baseName eq "log"`. The builder treats `log` as a stray build log.
The `rushi-full` store object still contains `bin/log`.
Only the merge drops it. This is not a stale store or a build bug.

**Filed.** `rushi#57` (kernel): adopt a tool-name policy that avoids
buildEnv reserved names, or document the devshell caveat.
A `bin/log` alias does not help. buildEnv drops the alias too.

**Impact.** In the devshell, direct `log` calls fail.
The `rushi` loop still resolves its own tools from the package layout.
Consumer-side workaround if the name stays: a `shellHook` symlink of
`rushi-full/bin/log` into the devshell `bin/`.

## Extract the build side into build.nix (2026-10-27)

**Decision.** The per-system store assembly moved from `flake.nix`
to `build.nix`. That is the `buildForSystem` `let` block: the
`tuiPkg` transition bridge, the `mkRushi` calls, the absolute store
tool paths, and the `tuiFull` and `rushiFull` derivations.
`flake.nix` now holds only the flake inputs and the outputs wiring.
It calls `build.nix` through a one-line `buildForSystem` import.
The moved code is verbatim, with its comments.

**Rationale.** The big `let ... in` inside `outputs` hid the build
graph. The config-side split (config-module.nix) left the build
section as the last big blob. This split keeps flake.nix a short
flake-outputs view.

**Verified.** All seven `.#packages.x86_64-linux` attrs give the
same store path before and after the split. The attrs are default,
rushi-full, rushi, rushi-kernel, rushi-tui, tui, and rushi-full-tb.
So the generated derivations are unchanged. `nix-instantiate
--parse` passes on both files. The consumer-side builder still
resolves: `lib.mkRushiFull { system = "x86_64-linux"; }` gives the
default `rushi-full` store path. The flag build
(`enableTerminalBrowser = true`) gives the prebaked `rushi-full-tb`
path. The devShell output evaluates too.

**Note.** `build.nix` must stay Git-tracked. Nix sees the flake
source as the Git tree. An untracked file is invisible to flake
evaluation. This note also holds for `config-module.nix`.

## Split the build side into role files (2026-10-27)

**Decision.** The build side split into role files, one
purpose each. `tool-paths.nix` holds the absolute store tool
paths. `tui-compat.nix` holds the bin/tui transition bridge.
`tui-full.nix` holds the self-contained TUI derivation and
the ext ui copy script. `rushi-full.nix` holds the combined
package. `build.nix` is now a thin orchestrator. The cryptic
bindings were renamed: `c` to `configSide`, `e` to
`extsForSystem`, `mk` to `configured`, `kernelRaw` to
`rawKernel`, `rushiGoalPkg` to `rushiGoal`. The `extUiPkgs`
and `extToolPkgs` aliases were dropped. The exts table is
read by key.

**Also dropped.** The duplicate `mkTui` `mkRushi` call. It
was byte-identical to `mk`. The TUI config file reuses
`configured.config`. The `cfg`/`cfgTb` double instantiation
collapsed to one import. The flag selects the `tbEnabled`
value. The shell loop variable `t` was renamed to `entry`.

**Rationale.** The first extraction moved the build section
without changing it. One file carried five purposes,
single-letter bindings, and `inherit inputs` hid what each
piece did. The role split makes each piece locatable and
names the bindings after their role.

**Verified.** The `rushi` and `rushi-kernel` attrs keep
their store paths (their arguments were unchanged). The
`rushi-full`, `rushi-tui`, and `rushi-full-tb` attrs got
new store paths: the shell variable rename changes the
installPhase text. The built packages compare identical:
`diff -r` of the old and new `rushi-tui` trees and of the
old and new `rushi-full` trees reports no difference. The
`lib.mkRushiFull` builder resolves both flag variants. The
devShell evaluates.

**Note.** The new role files must stay Git-tracked. Nix
sees the flake source as the Git tree. An untracked file is
invisible to flake evaluation. This note also holds for
`build.nix` and `config-module.nix`.
