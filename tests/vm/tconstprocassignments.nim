discard """
  output: '''
100
100
'''
"""

proc f():int {.compileTime.} = 100

const F = f
echo F()

const G = proc ():int =
  let x = f
  let y = x
  y()

echo G()


block: # bug #24359
  block:
    proc h(_: bool) = discard
    const m = h
    static: m(true)  # works
    m(true)          # does not work

block:
  block:
    proc h(_: bool): int = result = 1
    const m = h
    static: doAssert m(true) == 1 # works
    doAssert m(true) == 1          # does not work
