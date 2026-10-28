# config/rushi-config.nix — the repo's declarative rushi
# config, as data.
#
# The repo owner's deployment: the `rushi.*` option values the
# prebaked packages.* attrs build. This file is data, not a
# value: a NixOS-style module function (the
# nixvim-config/default.nix shape), read top-down. It sets the
# version, the native tool list, and the config.toml sections
# ([active], [model], [limits], [paths], [hooks], [loop],
# [system_prompt], [tui]). The sections mirror config-real.toml
# from the kernel checkout.
#
# The builder-owned fields are not here: the ext packages
# (rushi.external_*) come from the builder's exts module
# (the consumer ext set: null, a flake-input list, or the raw
# table), and the TUI binary (rushi.tui) is wired by the
# builder's tui module.
#
# A consumer does not take this file. The consumer builder
# (lib.mkRushiFull) merges the consumer's own modules on top of
# the kernel's neutral defaults. A consumer who wants this
# exact setup copies the data into their own repo.

{
  # The native tool catalog (config/native-tools.nix).
  nativeToolNames,
  # The [paths] tool entries: a { native, ext } attrset of
  # absolute store paths. The TUI package ships no tools/ dir,
  # so the entries point into the store.
  toolPaths,
}:
{
  # The kernel version the build targets (recorded in the
  # generated tools.manifest).
  rushi.version = "0.1";

  # The [tools] enabled list of the generated tools.manifest:
  # one entry per native tool this build exposes.
  rushi.tools = nativeToolNames;

  # The generated config.toml content. The sections mirror
  # config-real.toml from the kernel checkout.
  rushi.config = {
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
    paths = {
      native_tool_paths = toolPaths.native;
      extension_tool_paths = toolPaths.ext;
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

    # [system_prompt] (the repo's built-in prompt file)
    system_prompt = {
      text = builtins.readFile ../system-prompt.txt;
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
