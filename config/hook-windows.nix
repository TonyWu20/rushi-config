# config/hook-windows.nix — the [hooks] section of the generated config.
#
# Written out explicitly (the explicit-placements decision, 2026-09-24):
# one def per hook, one ordered steps list per window, so a reader sees
# the full pipeline without tracing a fold. `defs` names each hook and
# `pipeline` places each hook in its window(s).
#
# The command is the bare binary name. The kernel resolves it against
# the package bin/ dir (kernel-shipped hooks), then the package hooks/
# dir (ext hooks), then PATH. The kernel's build-time drift guard fails
# the build when a def name matches no bundled bin, so a typo or rename
# is loud, not silent.

{
  timeout_ms = 30000;

  # One [hooks.defs.<name>] entry per hook (8 total).
  defs = {
    # Kernel-shipped (bundled by the kernel in bin/).
    "harness-hook-compact".command = "harness-hook-compact";
    # Goal-continuation hooks (rushi-goal-mode).
    "harness-hook-goal-idle".command = "harness-hook-goal-idle";
    "harness-hook-goal-compact".command = "harness-hook-goal-compact";
    "harness-hook-goal-tools".command = "harness-hook-goal-tools";
    "harness-hook-goal-arm".command = "harness-hook-goal-arm";
    "harness-hook-goal-tokens".command = "harness-hook-goal-tokens";
    # Linters (no-find-grep, simple-english).
    "harness-hook-no-find-grep".command = "harness-hook-no-find-grep";
    "harness-hook-simple-english".command = "harness-hook-simple-english";
  };

  # One [hooks.pipeline."<window>"] entry per window. Steps fire in
  # list order. The kernel runs the steps in that order, and a later
  # step may veto an earlier one.
  pipeline = {
    "exhausted.handle".steps = [ "harness-hook-compact" ];
    "overflow.resolve".steps = [ "harness-hook-compact" ];
    "run.idle".steps = [
      "harness-hook-goal-idle"
      "harness-hook-simple-english"
    ];
    "compact.before".steps = [ "harness-hook-goal-compact" ];
    "tool.before".steps = [
      "harness-hook-goal-tools"
      "harness-hook-no-find-grep"
      "harness-hook-simple-english"
    ];
    "model.before".steps = [
      "harness-hook-goal-arm"
      "harness-hook-simple-english"
    ];
    "model.after".steps = [ "harness-hook-goal-tokens" ];
  };
}
