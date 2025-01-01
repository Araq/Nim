discard """
  errormsg: "unhandled exception: t9768.nim(24, 3) `a < 4`  [AssertionDefect]"
  file: "std/assertions.nim"
  matrix: "-d:nimPreviewSlimSystem"
  nimout: '''
stack trace: (most recent call last)
t9768.nim(29, 33)        :static
t9768.nim(24, 11)        foo1
'''
"""
import std/assertions









## line 20

proc foo1(a: int): auto =
  doAssert a < 4
  result = a * 2

proc main()=
  static:
    if foo1(1) > 0: discard foo1(foo1(2))

main()
