# rushi-config

Aggregator flake for a complete rushi deployment. It assembles the
kernel (`rushi-flake`), the TUI front-end (`rushi-tui`), external
tools, hooks, and UI extensions, plus a NixOS-style config module.
It mirrors the `pi-config` pattern: one flake assembles everything
and calls the kernel's `lib.mkRushi` to produce one runnable package.

## Usage

    nix build .#rushi    # build the fully configured package
    nix run   .#rushi    # run the configured rushi
    nix develop         # dev shell with the configured rushi on PATH

Layout of the `.#rushi` output (`$out`):

    bin/            rushi + all stage/tool binaries + tui
    tools/          tool manifests (kernel + external tools)
    ui_extensions/  external UI extension dirs (ext.toml + binaries)
    hooks/          external hook binaries
    config.toml     generated from the Nix module options
    tools.manifest  rushi.toml equivalent for `rushi setup --locked`

## Inputs and the bootstrap -> hosting transition

All local inputs use `path:` URLs for local development. When the
repos are hosted, flip each to a pinned `github:` ref. Then run
`nix flake update <input>` to pin it in the lock.

- `rushi-flake`: `path:/home/tony/programming/rust-unix-harness`
  -> `github:TonyWu20/rushi?ref=<rev>`
- `rushi-tui`: `path:/home/tony/programming/rushi-tui-ratatui-widget-based`
  -> `github:TonyWu20/rushi-tui?ref=<rev>`
- `rushi-goal-mode`: `path:/home/tony/programming/rushi-exts/goal-app`
  -> `github:TonyWu20/rushi-goal-mode?ref=<rev>`
- `no-find-grep`: `path:/home/tony/programming/rushi-exts/no-find-grep`
  -> `github:TonyWu20/no-find-grep-rushi?ref=<rev>`
- `rushi-simple-english`: `path:/home/tony/programming/rushi-simple-english`
  -> `github:TonyWu20/rushi-simple-english?ref=<rev>`

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

The `configModule` in `flake.nix` mirrors `config-real.toml` from the
kernel checkout. Hook `command` fields are bare binary names. The
hook binaries are bundled into `$out/hooks` by `lib.mkRushi`, and the
kernel resolves them from there at runtime.
