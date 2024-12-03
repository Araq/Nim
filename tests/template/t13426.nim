discard """
  cmd: "nim check --hints:off $file"
  errormsg: ""
  nimout: '''
t13426.nim(81, 6) template/generic instantiation of `fun` from here
t13426.nim(80, 24) Error: type mismatch: got <int> but expected 'string'
t13426.nim(81, 6) template/generic instantiation of `fun` from here
t13426.nim(80, 17) Error: type mismatch: got <uint, string>
but expected one of:
proc `and`(x, y: uint): uint
  first type mismatch at position: 2
  required type for y: uint
  but expression 'high(@[1])' is of type: string
proc `and`(x, y: uint64): uint64
  first type mismatch at position: 2
  required type for y: uint64
  but expression 'high(@[1])' is of type: string
10 other mismatching symbols have been suppressed; compile with --showAllMismatches:on to see them

expression: 1'u and high(@[1])
t13426.nim(81, 6) template/generic instantiation of `fun` from here
t13426.nim(80, 17) Error: expression '' has no type (or is ambiguous)
t13426.nim(87, 6) template/generic instantiation of `fun` from here
t13426.nim(86, 22) Error: type mismatch: got <int> but expected 'string'
t13426.nim(87, 6) template/generic instantiation of `fun` from here
t13426.nim(86, 15) Error: type mismatch: got <int literal(1), string>
but expected one of:
proc `and`(x, y: int): int
  first type mismatch at position: 2
  required type for y: int
  but expression 'high(@[1])' is of type: string
proc `and`(x, y: int16): int16
  first type mismatch at position: 2
  required type for y: int16
  but expression 'high(@[1])' is of type: string
proc `and`(x, y: int32): int32
  first type mismatch at position: 2
  required type for y: int32
  but expression 'high(@[1])' is of type: string
proc `and`(x, y: int64): int64
  first type mismatch at position: 2
  required type for y: int64
  but expression 'high(@[1])' is of type: string
proc `and`(x, y: int8): int8
  first type mismatch at position: 2
  required type for y: int8
  but expression 'high(@[1])' is of type: string
proc `and`(x, y: uint): uint
  first type mismatch at position: 2
  required type for y: uint
  but expression 'high(@[1])' is of type: string
proc `and`(x, y: uint16): uint16
  first type mismatch at position: 2
  required type for y: uint16
  but expression 'high(@[1])' is of type: string
proc `and`(x, y: uint32): uint32
  first type mismatch at position: 2
  required type for y: uint32
  but expression 'high(@[1])' is of type: string
proc `and`(x, y: uint64): uint64
  first type mismatch at position: 2
  required type for y: uint64
  but expression 'high(@[1])' is of type: string
proc `and`(x, y: uint8): uint8
  first type mismatch at position: 2
  required type for y: uint8
  but expression 'high(@[1])' is of type: string
2 other mismatching symbols have been suppressed; compile with --showAllMismatches:on to see them

expression: 1 and high(@[1])
t13426.nim(87, 6) template/generic instantiation of `fun` from here
t13426.nim(86, 15) Error: expression '' has no type (or is ambiguous)
'''
"""

# bug # #13426
block:
  template bar(t): string = high(t)
  proc fun[A](key: A) =
    var h = 1'u and bar(@[1])
  fun(0)

block:
  template bar(t): string = high(t)
  proc fun[A](key: A) =
    var h = 1 and bar(@[1])
  fun(0)
