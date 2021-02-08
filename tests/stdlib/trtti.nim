discard """
  matrix: "-d:nimExperimentalTypeInfoCore -d:nimTypeNames; -d:nimExperimentalTypeInfoCore -d:nimTypeNames --gc:arc"
"""

import std/[rtti,unittest,strutils]

proc main =
  block: # getDynamicTypeInfo
    type
      Base = object of RootObj
      PBase = ref Base
      Sub1 = ref object of Base
        s0: array[10, int]
    var a: PBase = Sub1()
    block:
      let t = a.getDynamicTypeInfo
      check t.size == int.sizeof + 10*int.sizeof
      when defined(nimV2):
        # "|compiler.trtti.Sub1:ObjectType|compiler.trtti.Base:ObjectType|RootObj|"
        check "Sub1:ObjectType" in $t.name
      else: check t.name == "Sub1:ObjectType"
      let t2 = a[].getDynamicTypeInfo
      check t2 == t
    block:
      a = PBase()
      let t = a.getDynamicTypeInfo
      check t.size == int.sizeof
      when defined(nimV2):
        check "Base" in $t.name
      else: check t.name == "Base"
main()
