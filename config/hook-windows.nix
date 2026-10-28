# config/hook-windows.nix — the [hooks] section of the generated
# config.
#
# Written out explicitly (the explicit-placements decision,
# 2026-09-24): one def per hook, one ordered steps list per
# window, so a reader sees the full pipeline without tracing a
# fold. `defs` names each hook and `pipeline` places each hook
# in its window(s).
#
# This file covers the kernel-shipped hooks only. Ext hooks
# (goal-continuation, linters) ship with the ext packages, and
# their window placement is consumer data: a consumer module
# sets rushi.config.hooks for their own ext set.
#
# The command is the bare binary name. The kernel resolves it
# against the package bin/ dir (kernel-shipped hooks), then the
# package hooks/ dir (ext hooks), then PATH. The kernel's
# build-time drift guard fails the build when a def name
# matches no bundled bin, so a typo or rename is loud, not
# silent.

{
  timeout_ms = 30000;

  # One [hooks.defs.<name>] entry per hook (2, kernel-shipped).
  defs = {
    "harness-hook-compact".command = "harness-hook-compact";
    "harness-hook-no-long-sleep".command =
      "harness-hook-no-long-sleep";
  };

  # One [hooks.pipeline."<window>"] entry per window. Steps fire
  # in list order. The kernel runs the steps in that order, and
  # a later step may veto an earlier one.
  pipeline = {
    "exhausted.handle".steps = [ "harness-hook-compact" ];
    "overflow.resolve".steps = [ "harness-hook-compact" ];
    "tool.before".steps = [ "harness-hook-no-long-sleep" ];
  };
}
