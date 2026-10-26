# config/native-tools.nix — the declare-once native tool catalog.
#
# One name per kernel native tool. The manifest dir for each tool
# is always tools/<name> (the kernel's tools/ layout). This list
# drives the [tools] enabled list of the generated tools.manifest
# and the relative/absolute native_tool_paths entries. To expose
# more native tools, add their names here.

[ "bash" ]
