discard """
cmd: "nim check --hints:off $file"
"""

block: # bug #21887
  type
    EnumA = enum A = 300, B
    EnumB = enum A = 10
    EnumC = enum C

  doAssert typeof(EnumC(A)) is EnumC #[tt.Error
                        ^ ambiguous identifier: 'A' -- use one of the following:
  EnumA.A: EnumA
  EnumB.A: EnumB]#

block: # issue #22598
  type
    A = enum
      red
    B = enum
      red

  let a = red #[tt.Error
          ^ ambiguous identifier: 'red' -- use one of the following:
  A.red: A
  B.red: B]#
