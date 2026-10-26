# config/rushi-config.nix — the rushi config content, as data.
#
# This file is the generated `rushi` config value, top to bottom:
# the version, the [tools] enabled list, the bundled ext
# packages, the TUI binary, and the config.toml sections
# ([active], [model], [limits], [paths], [hooks], [loop],
# [system_prompt], [tui]). The sections mirror config-real.toml
# from the kernel checkout.
#
# It is data, not a NixOS module: one function of named
# arguments, and its body reads top-down. configured.nix (the
# assembly layer) wraps this value in the module function the
# kernel's lib.mkRushi expects.

{
  # The per-system ext table (from config/exts.nix): extTools,
  # extUi, extHooks.
  extsForSystem,
  # The native tool catalog (config/native-tools.nix).
  nativeToolNames,
  # The TUI binary package, bundled into the package bin/ dir.
  tuiPkg,
  # The [paths] tool entries: null keeps the relative tools/...
  # entries (valid for a package that bundles tools/ next to
  # its config). A { native, ext } attrset of absolute store
  # paths is used by the TUI variant (its package ships no
  # tools/ dir).
  toolPaths ? null,
  # The native tool names to expose. null is the full catalog.
  # A subset (e.g. [ "bash" ]) ships a variant with fewer
  # native tools.
  toolNames ? null,
  # The [system_prompt] text. null is the built-in
  # system-prompt.txt. A string is the inline text. A path (or a
  # text-file derivation) is read as a file.
  systemPrompt ? null,
}:
let
  # The [tools] enabled list of the generated tools.manifest:
  # one entry per native tool this build exposes.
  tools = if toolNames == null then nativeToolNames else toolNames;
  # A text-file source: a Nix path value, or a derivation
  # attrset that carries an outPath (for example the result
  # of `pkgs.writeText`).
  isFileSource =
    v:
    builtins.isPath v || (builtins.isAttrs v && v ? outPath);
  # The [system_prompt] text (the parameter resolution above).
  systemPromptText =
    if systemPrompt == null then
      builtins.readFile ../system-prompt.txt
    else if isFileSource systemPrompt then
      builtins.readFile systemPrompt
    else
      systemPrompt;
  # The [paths] tool entries (the toolPaths argument above).
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
  version = "0.1";

  # The [tools] enabled list of the generated tools.manifest.
  tools = tools;

  # The ext packages bundled into the package: tools/,
  # ui_extensions/, hooks/. Declared once in the exts table
  # (config/exts.nix).
  external_tools = extsForSystem.extTools;
  external_ui_extensions = extsForSystem.extUi;
  # ui_extension_names is left unset on purpose: the kernel
  # (rushi#13) fills the manifest [ui_extensions] list at eval
  # time from each producer's meta.rushi.ext. The kernel's
  # drift guard still verifies each name has a bundled entry
  # dir.
  external_hooks = extsForSystem.extHooks;

  # The TUI binary package, shipped into the package bin/ dir.
  tui = tuiPkg;

  # The generated config.toml content. The sections mirror
  # config-real.toml from the kernel checkout.
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
    hooks = import ./hook-windows.nix;

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
}
