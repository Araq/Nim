discard """
  action: "compile"
  cmd: "cat $file | $nim check --stdinfile:$file -"
  # Don't believe cat and pipes works on windows
  disabled: "win"
"""

import std/[assertions, paths]

# Test the nimscript config is loaded
assert defined(nimscriptConfigLoaded)

assert currentSourcePath() == $(getCurrentDir()/Path"tloadstdin.nim")

{.warning: "Hello".}  #[tt.Warning
         ^ Hello]#
