# config-module.nix — the rushi config side of the flake, extracted from
# flake.nix so the main flake stays a concise build-graph view.
#
# This file holds the two config declarations the main flake hands to the
# kernel's lib.mkRushi:
#
#   * exts          the declare-once ext table (the single source of truth
#                   for which ext packages to bundle and which tool,
#                   ui-ext, and hook names to emit).
#   * configModule  the NixOS-style config module that mirrors
#                   config-real.toml (model, limits, hooks, paths, tui).
#                   It is the module the flake passes to lib.mkRushi.
#
# flake.nix imports this file with the six ext flake aliases and re-binds
# the two names, so the flake's forSystem build section is unchanged.

{
  # The six ext flake aliases (each ext repo's flake output, bound in the
  # main flake's let from its flake inputs).
  goalFlake,
  nfgFlake,
  seFlake,
  statuslineFlake,
  obscuraWebFlake,
  mermaidExtFlake,
}:
let
  # ── Declare-once ext tables (the single source of truth). ──
  # Each ext is declared exactly once: the package to bundle.
  # Every build list (rushi.external_*) and every runtime value in
  # the generated config (tool paths, ui-ext names) derives from
  # these tables in pure Nix, at eval time. To add or drop an ext,
  # edit one row. Hook window placements live explicitly in the
  # config module's [hooks] table instead (see that table).
  #
  # Since rushi#13 the kernel reads each producer's meta.rushi at
  # eval time: tools set meta.rushi.entry, UI-exts set
  # meta.rushi.ext, hooks set meta.rushi.bin. extension_tool_paths
  # and the manifest ui-ext list are derived from those declarations.
  # For hooks, the bin name doubles as the bundle name: mkRushi
  # copies each meta.rushi.bin into $out/hooks/, and a bare hook
  # command matching a declared bin is drift-guard-exempt. Any
  # bare command the meta does not cover is file-checked against
  # $out/bin/ and $out/hooks/ at build time, so typos in the
  # [hooks.defs] table still fail the build.
  exts = system: {
    # Native kernel tools: manifest dir (relative to the package
    # root) + tool name. Drives native_tool_paths and [tools].
    nativeTools = [
      {
        path = "tools/bash";
        name = "bash";
      }
      {
        path = "tools/edit";
        name = "edit";
      }
      {
        path = "tools/read";
        name = "read";
      }
      {
        path = "tools/write";
        name = "write";
      }
    ];
    # External tools. meta.rushi.entry (issue #13) supplies the
    # tools/<entry> path in the generated config at eval time.
    extTools = [
      { pkg = goalFlake.packages.${system}.goal; }
      { pkg = goalFlake.packages.${system}."goal-blocked"; }
      { pkg = goalFlake.packages.${system}."goal-complete"; }
      { pkg = obscuraWebFlake.packages.${system}."web-fetch"; }
      { pkg = obscuraWebFlake.packages.${system}."web-search"; }
    ];
    # External UI extensions. meta.rushi.ext (issue #13) supplies the
    # manifest [ui_extensions] entry name at eval time.
    extUi = [
      { pkg = goalFlake.packages.${system}."goal-ext"; }
      { pkg = seFlake.packages.${system}."simple-english-ext"; }
      { pkg = statuslineFlake.packages.${system}.statusline; }
      { pkg = mermaidExtFlake.packages.${system}."mermaid-ext"; }
    ];
    # External hooks: the packages to bundle into the package's
    # hooks/ dir (lib.mkRushi). Each ext repo's flake sets
    # meta.rushi.bin (issue #13), which the kernel's drift guard
    # reads at eval time. WHERE each hook fires (the pipeline
    # windows) is placed explicitly in the config module's
    # [hooks] table, not in this table.
    extHooks = [
      goalFlake.packages.${system}."hook-goal-idle"
      goalFlake.packages.${system}."hook-goal-compact"
      goalFlake.packages.${system}."hook-goal-tools"
      goalFlake.packages.${system}."hook-goal-arm"
      goalFlake.packages.${system}."hook-goal-tokens"
      nfgFlake.packages.${system}."hook-no-find-grep"
      seFlake.packages.${system}."hook-simple-english"
    ];
  };
  # Hook window placements are NOT derived here. They are written
  # out explicitly in the config module's [hooks] table (the
  # defs + pipeline attrsets), one step list per window, so a
  # reader can see the full pipeline without tracing a fold.
  # The exts table above only decides which hook packages get
  # bundled. It carries no window information.

  # ── The config module: mirrors config-real.toml (the local dev
  # config). In the Nix version, ext binaries and the TUI are bundled
  # into the package by lib.mkRushi, so hook `command` fields are the
  # BARE binary names, not local dev paths. The kernel resolves a bare
  # name against the package bin/ dir, then the package hooks/ dir,
  # then PATH.
  # `toolPaths` (optional): absolute tool-manifest paths for this
  # config. null (the default) keeps the relative `tools/...`
  # layout entries, which are valid for a package that bundles
  # tools/ next to its config. Both the configured and the
  # self-contained TUI package pass absolute store paths (the Nix
  # derivations' outPaths), so their generated config.toml files
  # are byte-identical and mergeable in buildEnv-based devshells.
  configModule =
    { system, tuiPkg, toolPaths ? null }:
    {
      ...
    }:
    let
      # The declare-once exts table (this file), resolved for
      # this system. Every build list and runtime value below derives
      # from `e`.
      e = exts system;
      # The [paths] tool entries. Relative by default (the configured
      # package bundles tools/ next to its config, so the relative
      # entries resolve). The TUI variant passes absolute store
      # paths because its package ships no tools/ dir.
      toolPathAttrs =
        if toolPaths == null then
          { native_tool_paths = map (t: t.path) e.nativeTools; }
        else
          {
            native_tool_paths = toolPaths.native;
            extension_tool_paths = toolPaths.ext;
          };
    in
    {
      rushi = {
        config = {
          active = {
            model = "Qwen3.8-27B-NVFP4-RTX5090-DFlash2";
          };
          # ── Lifecycle hooks (kernel issue #38 pipeline model). ──
          # Written out explicitly so a reader sees, window by
          # window, exactly which hooks fire and in what order.
          # `defs` names each hook; `pipeline` says which windows
          # fire it. The command is the bare binary name; the
          # kernel resolves it against the package bin/ (kernel)
          # and hooks/ (ext) dirs, then PATH. The kernel's drift
          # guard fails the build if a def name matches no bundled
          # bin, so a typo or a rename is loud, not silent.
          hooks = {
            timeout_ms = 30000;
            # One [hooks.defs.<name>] per hook (8 total).
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
            # One [hooks.pipeline."<window>"] per window, explicit
            # step lists in fire order. The kernel runs the steps
            # in this order; a later step may veto an earlier one.
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
          };
          limits = {
            bash_timeout_max = 600;
            compact_enabled = true;
            compact_keep_tokens = 20000;
            compact_reserve_tokens = 16384;
            compact_strategy = "compact";
            context_budget_tokens = 262144;
          };
          loop = {
            arg_style = "append_session";
            args = [ "run" ];
            command = "rushi";
          };
          model = {
            "Qwen3.8-27B-NVFP4-RTX5090-DFlash2" = {
              api_key_env = "LLAMA_API_KEY";
              base_url = "http://127.0.0.1:30000";
              context_tokens = 262144;
              model_id = "Qwen3.8-27B-NVFP4-RTX5090-DFlash2";
              vision = true;
            };
            api = "responses";
            max_output_tokens = 65536;
            reasoning_effort = "xhigh";
          };
          paths = toolPathAttrs // {
            sessions_root = "sessions";
          };
          system_prompt = {
            text = builtins.readFile ./system-prompt.txt;
          };
          tui = {
            clipboard = "unnamed";
            tool_display = {
              anim_ms = 400;
              bash_collapsed_lines = 5;
              diff_collapsed_lines = 12;
              expand_mode = "click";
              highlight_engine = "tree-sitter";
              preset = "opencode";
            };
          };
        };
        external_hooks = e.extHooks;
        external_tools = map (t: t.pkg) e.extTools;
        external_ui_extensions = map (u: u.pkg) e.extUi;
        tools = map (t: t.name) e.nativeTools;
        tui = tuiPkg;
        version = "0.1";
      };

      # ui_extension_names is left unset so the kernel (rushi#13)
      # fills the manifest [ui_extensions] list at eval time from
      # each producer's meta.rushi.ext. The kernel's drift guard
      # still verifies each name has a bundled entry dir.
    };
in
{
  inherit exts configModule;
}
