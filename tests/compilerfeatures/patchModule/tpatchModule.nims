# See `tpatchModule`

switch("hint", "all:off")
switch("warning", "all:off")
--warning:CannotOpen
--hint:Patch

# Tests:
#   - patching a foreign and `stdlib` module
#   - patch resolved relative to config
#   - that path substitution is performed
patchModule("std/httpclient", "mpatchModule")

# Tests:
#   - patching one of multiple modules with the same name and in the same package
#     ```
#     ├── a
#     │   └── same_module_name.nim
#     ├── b
#     │   └── same_module_name.nim
#     ```
#   - patching a module with an absolute target path given
patchModule("$projectpath/b/same_module_name.nim", "$projectpath/mpatchModule.nim")

# Patch a target module that is imported using an absolute path:
# (This also tests that `patchModule` overrides `patchFile`.)
patchFile("stdlib", "oids", "b/same_module_name")
patchModule("oids", "mpatchModule")

# Patch with a module that is in a foreign package:
--path:mpatchModulePkg
patchModule("mpatchModule_f", "mpatchModulePkg")

# Try to patch a patch (patch1->patch0->target):
# This won't patch `mpatchModule_a` with `mpatchModule_c`.
# This will patch `mpatchModule_b` with `mpatchModule_c`.
# Patching a patch is achieved by importing a patch into
# another patch and then patching the target with it,
# because later target patch assignments take precedence
# over earlier ones.
patchModule("mpatchModule_a", "mpatchModule_b")
patchModule("mpatchModule_b", "mpatchModule_c")

# Try to patch a missing target:
patchModule("missingTarget_uasdygf8a7fg8uq23vfquoevfqo8ef", "mpatchModule")

# Try to patch with a missing patch:
patchModule("times", "missingPatch_uasdygf8a7fg8uq23vfquoevfqo8ef")

# Try to patch a missing target and patch:
patchModule("missingTarget_uasdygf8a7fg8uq23vfquoevfqo8ef", "missingPatch_uasdygf8a7fg8uq23vfquoevfqo8ef")

# Try to patch an empty target:
patchModule("", "mpatchModule")

# Try to patch an empty patch:
patchModule("tpatchModule", "")

# Try to patch an empty target and patch:
patchModule("", "")

# Try to patch the project module:
patchModule("tpatchModule", "mpatchModule")

# Try to patch a target that patches the patch (cycle: patch->target->patch):
patchModule("mpatchModule_d", "mpatchModule_e")
patchModule("mpatchModule_e", "mpatchModule_d")

#======================================
# Test how non-module paths are handled
#======================================

# # Create some test dependencies:
# import std/[os, strformat, macros]
# macro buildLib(module) =
#   let id = module.strVal
#   quote do:
#     echo staticExec(getCurrentCompilerExe() & " c --nimMainPrefix:" & `id` &
#                     " --noMain --app:staticLib  -o:" & `id` & ".lib " & `id` & ".nim")
# buildLib mpatchModule_cmdline_linked_a
# buildLib mpatchModule_pragma_linked_a
# buildLib mpatchModule_cmdline_linked_b
# buildLib mpatchModule_pragma_linked_b

# # XXX: These paths are being prefixed with `thisDir()` because `--link` and
# #      `--compile` don't try resolving the path relative to this script.
# #      I think that is a bug.
# switch("link", thisDir()/"mpatchModule_cmdline_linked_a.lib")
# switch("compile", thisDir()/"tpatchModule_cmdline_compiled_a.c")

# # Patch module:
# patchModule("mpatchModule_cmdline_linked_a.lib", "mpatchModule_cmdline_linked_b.lib")

# # Try patching a non-module path relative to this script that is `system.staticRead`:
# patchModule("../dummy.txt", "../readme.md")

# # Try patching a non-module path relative to a search path that is `system.staticRead`:
# --path:".."/".."
# patchModule("tests/dummy.txt", "tests/readme.md")
