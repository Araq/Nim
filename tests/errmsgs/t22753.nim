discard """
cmd: "nim check --hints:off $file"
errormsg: "type mismatch"
nimoutFull: true
nimout: '''
t22753.nim(51, 13) Error: array expects two type parameters
t22753.nim(52, 1) Error: expression 'x' has no type (or is ambiguous)
t22753.nim(52, 1) Error: expression 'x' has no type (or is ambiguous)
t22753.nim(52, 2) Error: type mismatch: got <>
but expected one of:
proc `[]=`(s: var string; i: BackwardsIndex; x: char)
  first type mismatch at position: 2
  required type for i: BackwardsIndex
  but expression '0' is of type: int literal(0)
proc `[]=`[I: Ordinal; T, S](a: T; i: I; x: sink S)
  first type mismatch at position: 0
proc `[]=`[Idx, T; U, V: Ordinal](a: var array[Idx, T]; x: HSlice[U, V];
                                  b: openArray[T])
  first type mismatch at position: 2
  required type for x: HSlice[[]=.U, []=.V]
  but expression '0' is of type: int literal(0)
proc `[]=`[Idx, T](a: var array[Idx, T]; i: BackwardsIndex; x: T)
  first type mismatch at position: 2
  required type for i: BackwardsIndex
  but expression '0' is of type: int literal(0)
proc `[]=`[T, U: Ordinal](s: var string; x: HSlice[T, U]; b: string)
  first type mismatch at position: 2
  required type for x: HSlice[[]=.T, []=.U]
  but expression '0' is of type: int literal(0)
proc `[]=`[T; U, V: Ordinal](s: var seq[T]; x: HSlice[U, V]; b: openArray[T])
  first type mismatch at position: 2
  required type for x: HSlice[[]=.U, []=.V]
  but expression '0' is of type: int literal(0)
proc `[]=`[T](s: var openArray[T]; i: BackwardsIndex; x: T)
  first type mismatch at position: 2
  required type for i: BackwardsIndex
  but expression '0' is of type: int literal(0)
template `[]=`(a: WideCStringObj; idx: int; val: Utf16Char)
  first type mismatch at position: 3
  required type for val: Utf16Char
  but expression '9' is of type: int literal(9)
template `[]=`(s: string; i: int; val: char)
  first type mismatch at position: 3
  required type for val: char
  but expression '9' is of type: int literal(9)

expression: x[0] = 9
'''
"""

var x: array[3] # bug #22753
x[0] = 9
