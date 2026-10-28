# Issue draft: a typed extension registry for `rushi.external_*`

_Draft issue for the `TonyWu20/rushi` kernel repo. The
capability gap versus the nixvim model: nixvim's extension
selection is a typed plugin registry
(`lib/plugins/` + `pkg-lists.nix`, the consumer writes
`plugins.xyz.enable = true`). Rushi has no equivalent:
`rushi.external_tools` / `external_ui_extensions` /
`external_hooks` are raw lists, and ext packages come from
separate flake repos selected by raw attribute paths
(`extFlake.packages."x86_64-linux".web-fetch`). The
consumer pins every ext flake and hand-types the attribute
selection._

## Problem

The nixvim model, in one expression:

    nixvim.plugins.lz-n.enable = true;
    nixvim.plugins.lz-n.settings.excluded = [ "net.nvim" ];

The consumer declares an extension by name. The registry
owns the fetch and the typed settings. No flake input
pinning, no attribute selection, no raw lists.

The rushi equivalent today, from a consumer flake:

    inputs."rushi-obscura-web-access".url =
      "github:TonyWu20/rushi-obscura-web-access";
    ...
    rushi.external_tools =
      [ inputs."rushi-obscura-web-access".packages."x86_64-linux"."web-fetch"
      ];

Each ext repo is pinned as a flake input, and the package
attribute is hand-selected. The `meta.rushi` contract
(issue #13) already carries the entry/ext/bin names, so the
selection knowledge exists. It is not typed.

## Proposal

A typed extension registry, one of two shapes:

- Option A (registry in the kernel): `rushi.exts.<name>`
  typed options (enable + settings, the nixvim plugin
  shape), with the ext sources declared in a kernel-side
  registry file (the `pkg-lists.nix` role). The kernel
  fetches or resolves the ext sources the way nixvim
  fetches plugins.
- Option B (standardized ext flake output, the lighter
  change): every ext repo exposes one flake attribute,
  `rushiExt = { tools = [ … ]; ui = [ … ]; hooks = [ … ]; }`
  (the per-system package lists, system-generic). Builders
  and modules select by name against that one attribute.
  The `meta.rushi` names (issue #13) stay authoritative
  for the config paths.

Option B keeps the ext repos independent (no registry to
maintain in the kernel) and removes every raw attribute
selection. Option A is the full nixvim shape.

## Acceptance criteria

- [ ] A consumer enables an ext by name, not by attribute
      path (option A) or through one standardized flake
      attribute (option B).
- [ ] The `meta.rushi` name derivation (issue #13) stays the
      single source for the config paths.
- [ ] Docs: the registry or the output contract, next to
      `docs/reference/nix/nix-flake-module.md`.
