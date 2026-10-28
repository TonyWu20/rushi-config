# Issue draft: the `rushiExt` ext flake contract

_Draft issue for the `TonyWu20/rushi` kernel repo._

## Problem

A consumer who assembles a rushi package from ext flakes
must hand-route each ext package into a bucket:

    exts = {
      extTools = [ goalFlake.packages."x86_64-linux"."goal-blocked" ];
      extUi    = [ goalFlake.packages."x86_64-linux"."goal-ext" ];
      extHooks = [ … ];
    }

The bucket knowledge already exists on the producer side.
Each ext package carries `meta.rushi` (issue #13):
`entry` for tools, `ext` for UI exts, `bin` for hooks.
The flake does not aggregate it. The consumer selects
`packages.<system>.<name>` per package and routes the
results into the right lists. That hand-routing is the
puzzle: raw attribute selection plus bucket mapping,
repeated in every consumer flake.

nixvim does not have this puzzle, and the reason is
informative. Most neovim plugins have no distribution
flake, so nixvim fetches plugin sources internally
(pinned revs under nixvim's own nixpkgs pin). Rushi's
exts are flake distributions. The consumer declares
them as their own flake inputs. That is the Nix-idiomatic
form and a convenience the consumer keeps. What is
missing is the bridge: a typed placement API that puts
a declared ext flake into the right buckets.

## Proposal

One flake output attribute per ext flake (the `rushiExt`
contract):

    rushiExt = system: {
      tools = [ … ];   # packages with meta.rushi.entry set
      ui = [ … ];      # packages with meta.rushi.ext set
      hooks = [ … ];   # packages with meta.rushi.bin set
    };

The producer adds one line to the flake, using a kernel
lib helper:

    rushiExt = system: lib.rushiExtBuckets {
      packages = self.packages.${system};
    };

`lib.rushiExtBuckets { packages; }` scans `meta.rushi`
and buckets. No new producer data. The `meta.rushi`
declarations (issue #13) stay the single bucket source.
The kernel lib also exposes the consumer-side fold:
`lib.unionRushiExt { system; extFlakes = [ … ]; }`
returns `{ extTools; extUi; extHooks; }` by reading each
flake's `rushiExt.${system}` and concatenating.

The deployment-layer builder (rushi-config's
`lib.mkRushiFull`) accepts `exts` as a list of ext flake
inputs and calls the union. The raw bucket table stays
as the migration shape until the ext repos adopt the
contract.

## Acceptance criteria

- [ ] `lib.rushiExtBuckets` + `lib.unionRushiExt` in the
      kernel `lib` output, documented next to
      `docs/reference/nix/nix-flake-module.md`.
- [ ] The `meta.rushi` declarations stay the single
      bucket source (the contract derives, never
      re-declares).
- [ ] A consumer declaring two ext flakes in their own
      flake inputs writes `exts = [ a b ]` and never
      selects `packages.<system>.<name>`.
