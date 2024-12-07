discard """
  cmd: "nim c --expandMacro:foo $file"
  nimout: '''texpandmacro.nim(17, 1) Hint: expanded macro:
echo ["injected echo"]
var x = 4 [ExpandMacro]
type
  Hello = object
    private: string
'''
  output: '''injected echo'''
"""

import macros

macro foo(x: untyped): untyped =
  result = quote do:
    echo "injected echo"
    `x`

foo:
  var x = 4
  type
    Hello = object
      private: string
