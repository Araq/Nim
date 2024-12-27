discard """
  action: "compile"
  cmd: "cat $file | $nim check --stdinfile:$file -"
"""

import std/assertions

# Test the nimscript config is loaded
assert defined(nimscriptConfigLoaded)

{.warning: "Hello".}  #[tt.Warning
         ^ Hello]#
