# Issue draft: declarative `programs.rushi` options on the NixOS / home-manager modules

_Draft issue for the `TonyWu20/rushi` kernel repo. Filed from the
rushi-config side. The declarative config model (`lib.mkRushi` +
the `rushi.*` option schema) exists on the builder side. The
NixOS / home-manager module side still only accepts a prebuilt
`package` derivation._

## Problem

The kernel flake already provides the full declarative machinery:

- `lib.mkRushi { pkgs; modules = [ ... ]; }` evaluates a NixOS
  module system (`lib.evalModules`) over the typed `rushi.*`
  option schema (`lib/rushi-options.nix`): `rushi.config`
  (deep-merged attrset), `rushi.tools`, `rushi.ui_extensions`,
  `rushi.external_tools`, `rushi.external_ui_extensions`,
  `rushi.ui_extension_names`, `rushi.external_hooks`,
  `rushi.tui`, `rushi.environment`.
- The `examples/rushi-config` consumer flake shows the intended
  UX: the consumer writes declarative module functions and the
  kernel builder assembles the package.

But the NixOS / home-manager modules (`lib/nixos-module.nix`,
`lib/home-manager-module.nix`) expose only:

    programs.rushi = {
      enable = true;
      package = rushiConfigured.package;   # built outside the module
    };

A NixOS consumer who wants a different model, limits, ext set,
or hook set cannot express that inside their own NixOS module.
They must build the package in a separate flake (or a
rushi-config builder call) and pass the result. This is the
opposite of the nixvim model: `programs.nixvim` takes
declarative plugin and option data as module options.

## Proposal

Expose the declarative `rushi.*` options on the modules. A
NixOS config then reads:

    imports = [ (rushi-flake).nixosModules.rushi ];

    programs.rushi = {
      enable = true;
      # declarative, nixvim-style:
      config.limits.bash_timeout_max = 300;
      config.model."qwen".base_url = "http://127.0.0.1:30000";
      externalTools = [ someExtFlake.packages."x86_64-linux".web-fetch ];
      externalHooks = [ someHookFlake.packages."x86_64-linux".hook-x ];
    };

Shape (the NixOS module; the home-manager module mirrors it):

- `programs.rushi.modules` (list of module functions): the same
  form as `lib.mkRushi`'s `modules` argument. The module
  system merges them left to right.
- A typed convenience set mapped to the `rushi.*` options:
  `config`, `tools`, `uiExtensions`, `externalTools`,
  `externalUiExtensions`, `uiExtensionNames`, `externalHooks`,
  `tui`, `environment`. Optional if `modules` covers it. The
  typed set gives `lib.mkOption` type checking and docs.
- `package` stays for externally built packages. An assertion
  rejects `package` together with declarative options.
- An enabled module with declarative options assembles the
  package in-module via `lib.mkRushi`. The assembled package
  lands in `environment.systemPackages` (NixOS) or
  `home.packages` (home-manager).

## Implementation notes

- The flake's exposed `lib.mkRushi` already closes over the
  kernel source (`lib/default.nix` passes `src = ../.` and
  `kernelCargoLock = { lockFile = ../Cargo.lock; }`). The
  consumer passes only `{ pkgs; modules; }`, the
  `evalNixvim`-equivalent surface. The flake today exposes
  the bare module function
  (`nixosModules.rushi = import ./lib/nixos-module.nix`).
  The flake should wrap the exposed module so the in-module
  call can reach `flake.lib.mkRushi` and the consumer's
  `pkgs`. `rustToolchain` stays null (auto-resolved).
- `rushi.environment` keeps its three value forms (literal,
  `value`, `file`). sops-nix secrets keep working through the
  module path.
- Precedents: pi-flake's `nixosModules.coding-agent` (which the
  current module mirrors) and nixvim's `programs.nixvim`
  (declarative plugin and option options).

## Acceptance criteria

- [ ] `programs.rushi.modules` and the typed option set are
      declared on both the NixOS and the home-manager modules.
- [ ] An enabled module with declarative options builds the
      configured package without an external `lib.mkRushi`
      call.
- [ ] `package` and declarative options are mutually exclusive
      (assertion with a clear message).
- [ ] The `rushi.environment` `file` form works through the
      module path (sops-nix).
- [ ] Docs: a NixOS / home-manager usage section next to the
      `examples/rushi-config` flake example.
