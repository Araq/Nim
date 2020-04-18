discard """
  errormsg: "type mismatch: got <proc (x: int): string{.noSideEffect, gcsafe, locks: 0.}> but expected 'MyProcType = proc (x: int): string{.closure.}'"
  file: "teffects1.nim"
  line: 38
  cmd: "nim check $file"
  nimout: '''teffects1.nim(22, 28) template/generic instantiation from here
teffects1.nim(23, 13) Error: can raise an unlisted exception: ref IOError
teffects1.nim(22, 29) Hint: 'IO2Error' is declared but not used [XDeclaredButNotUsed]
teffects1.nim(38, 21) Error: type mismatch: got <proc (x: int): string{.noSideEffect, gcsafe, locks: 0.}> but expected 'MyProcType = proc (x: int): string{.closure.}'
.raise effects differ'''
"""

type
  TObj {.pure, inheritable.} = object
  TObjB = object of TObj
    a, b, c: string

  IO2Error = ref object of IOError

proc forw: int {. .}

proc lier(): int {.raises: [IO2Error].} =
  writeLine stdout, "arg"

proc forw: int =
  raise newException(IOError, "arg")

{.push raises: [Defect].}

type
  MyProcType* = proc(x: int): string #{.raises: [ValueError, Defect].}

proc foo(x: int): string {.raises: [ValueError].} =
  if x > 9:
    raise newException(ValueError, "Use single digit")
  $x

var p: MyProcType = foo
{.pop.}
