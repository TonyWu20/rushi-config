# config-module.nix — the rushi config side of the flake, extracted
# from flake.nix so the main flake stays a concise build-graph view.
#
# This file holds the config declarations the main flake hands to the
# kernel's lib.mkRushi:
#
#   * nativeToolNames  the kernel native tool names (declare-once
#                      catalog; the manifest dir is tools/<name>).
#   * exts             the declare-once external table
#                      (config/exts.nix).
#   * configModule     the NixOS-style config module that mirrors
#                      config-real.toml. It is the module the flake
#                      passes to lib.mkRushi.
#
# configModule parameters:
#
#   system     the target system (resolves the per-system exts table).
#   tuiPkg     the TUI binary package (shipped as rushi.tui).
#   toolPaths  ? null. Absolute store tool paths ({ native, ext }).
#              null keeps the relative tools/... entries, which are
#              valid for a package that bundles tools/ next to its
#              config. Both the configured and the self-contained TUI
#              packages pass absolute store paths, so their generated
#              config.toml files are byte-identical.
#   toolNames  ? null. The native tool names to expose. null is the
#              full catalog. A subset (e.g. [ "bash" ]) ships a
#              version with fewer native tools.
#   systemPrompt ? null. The [system_prompt] text. null is the
#              built-in system-prompt.txt. A string is the inline
#              text. A path (or a text-file derivation) is read
#              as a file.
#
# flake.nix imports this file with the flake's `inputs` attrset
# (plus the optional `tbEnabled` flag) and re-binds the three
# names per build instantiation, so the flake's build section
# stays a concise view of the build graph.

{
  # The flake's full inputs attrset. The ext table selects each
  # ext flake directly, so no alias bindings are needed.
  inputs,
  # The optional terminal-browser tool (the tool-only
  # terminal-browser-agent repo). false (the default, off) keeps
  # the exts table without the tool row. true enables the row.
  tbEnabled ? false,
}:
let
  # The declare-once native tool catalog: one name per kernel tool.
  # The manifest dir is always tools/<name> (the kernel's tools/
  # layout). Drives rushi.tools and the relative native_tool_paths.
  nativeToolNames = [ "bash" ];

  # The declare-once ext table (config/exts.nix): the single source of
  # truth for which ext packages to bundle.
  exts = import ./config/exts.nix {
    inherit inputs tbEnabled;
  };

  # The [hooks] defs + pipeline table (config/hook-windows.nix),
  # written out explicitly, one steps list per window.
  hookWindows = import ./config/hook-windows.nix;
in
{
  inherit exts nativeToolNames;

  # The NixOS-style config module. It mirrors config-real.toml (the
  # local dev config). In the Nix version, ext binaries and the TUI
  # are bundled into the package by lib.mkRushi, so hook `command`
  # fields are the BARE binary names, not local dev paths. The kernel
  # resolves a bare name against the package bin/ dir (kernel hooks),
  # then the package hooks/ dir (ext hooks), then PATH.
  configModule =
    {
      system,
      tuiPkg,
      toolPaths ? null,
      toolNames ? null,
      systemPrompt ? null,
    }:
    {
      ...
    }:
    let
      # The declare-once ext table for this system. Every build list
      # and runtime value below derives from `e`.
      e = exts system;
      # The native tool names for this build: the passed subset, or
      # the full catalog when null.
      tools = if toolNames == null then nativeToolNames else toolNames;
      # A text-file source: a Nix path value, or a derivation
      # attrset that carries an outPath (for example the result
      # of `pkgs.writeText`).
      isFileSource =
        v:
        builtins.isPath v || (builtins.isAttrs v && v ? outPath);
      # The [system_prompt] text. The parameter is null, the
      # built-in system-prompt.txt. A string is used verbatim.
      # A path or text-file derivation is read as a file.
      systemPromptText =
        if systemPrompt == null then
          builtins.readFile ./system-prompt.txt
        else if isFileSource systemPrompt then
          builtins.readFile systemPrompt
        else
          systemPrompt;
      # The [paths] tool entries. Relative by default: the configured
      # package bundles tools/ next to its config, so the relative
      # entries resolve. The TUI variant passes absolute store paths
      # because its package ships no tools/ dir.
      toolPathAttrs =
        if toolPaths == null then
          { native_tool_paths = map (n: "tools/${n}") tools; }
        else
          {
            native_tool_paths = toolPaths.native;
            extension_tool_paths = toolPaths.ext;
          };
    in
    {
      rushi = {
        version = "0.1";

        # The [tools] enabled list of the generated tools.manifest:
        # one entry per native tool this build exposes.
        tools = tools;

        # The ext packages bundled into the package: tools/,
        # ui_extensions/, hooks/. Declared once in the exts table.
        external_tools = e.extTools;
        external_ui_extensions = e.extUi;
        external_hooks = e.extHooks;

        # The TUI binary package, shipped into the package bin/ dir.
        tui = tuiPkg;

        # The generated config.toml content. The sections mirror
        # config-real.toml.
        config = {
          # [active]
          active = {
            model = "Qwen3.8-27B-NVFP4-RTX5090-DFlash2";
          };

          # [model]
          model = {
            "Qwen3.8-27B-NVFP4-RTX5090-DFlash2" = {
              api_key_env = "LLAMA_API_KEY";
              base_url = "http://127.0.0.1:30000";
              context_tokens = 262144;
              model_id = "Qwen3.8-27B-NVFP4-RTX5090-v2";
              vision = true;
            };
            api = "responses";
            max_output_tokens = 65536;
            reasoning_effort = "xhigh";
          };

          # [limits]
          limits = {
            bash_timeout_max = 600;
            compact_enabled = true;
            compact_keep_tokens = 20000;
            compact_reserve_tokens = 16384;
            compact_strategy = "compact";
            context_budget_tokens = 262144;
          };

          # [paths]
          paths = toolPathAttrs // {
            sessions_root = "sessions";
          };

          # [hooks] (config/hook-windows.nix)
          hooks = hookWindows;

          # [loop]
          loop = {
            arg_style = "append_session";
            args = [ "run" ];
            command = "rushi";
          };

          # [system_prompt]
          system_prompt = {
            text = systemPromptText;
          };

          # [tui]
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
      };

      # ui_extension_names is left unset so the kernel (rushi#13)
      # fills the manifest [ui_extensions] list at eval time from
      # each producer's meta.rushi.ext. The kernel's drift guard
      # still verifies each name has a bundled entry dir.
    };
}
