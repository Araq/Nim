{.experimental: "strictdefs".}

type Test = object
  id: int

proc foo {.noreturn.} = discard

proc test1(): Test =
  if true: #[tt.Warning
  ^ Cannot prove that 'result' is initialized. This will become a compile time error in the future. [ProveInit]]#
    return Test()
  else:
    return

proc test0(): Test =
  if true: #[tt.Warning
  ^ Cannot prove that 'result' is initialized. This will become a compile time error in the future. [ProveInit]]#
    return
  else:
    foo()

proc test2(): Test =
  if true: #[tt.Warning
  ^ Cannot prove that 'result' is initialized. This will become a compile time error in the future. [ProveInit]]#
    return
  else:
    return

proc test3(): Test =
  if true: #[tt.Warning
  ^ Cannot prove that 'result' is initialized. This will become a compile time error in the future. [ProveInit]]#
    return
  else:
    return Test()

proc test4(): Test =
  if true: #[tt.Warning
  ^ Cannot prove that 'result' is initialized. This will become a compile time error in the future. [ProveInit]]#
    return
  else:
    result = Test()
    return

proc test5(x: bool): Test =
  case x: #[tt.Warning
  ^ Cannot prove that 'result' is initialized. This will become a compile time error in the future. [ProveInit]]#
  of true:
    return
  else:
    return Test()

proc test6(x: bool): Test =
  case x: #[tt.Warning
  ^ Cannot prove that 'result' is initialized. This will become a compile time error in the future. [ProveInit]]#
  of true:
    return
  else:
    return

proc test7(x: bool): Test =
  case x: #[tt.Warning
  ^ Cannot prove that 'result' is initialized. This will become a compile time error in the future. [ProveInit]]#
  of true:
    return
  else:
    discard

proc test8(x: bool): Test =
  case x: #[tt.Warning
  ^ Cannot prove that 'result' is initialized. This will become a compile time error in the future. [ProveInit]]#
  of true:
    discard
  else:
    raise

proc hasImportStmt(): bool =
  if false: #[tt.Warning
  ^ Cannot prove that 'result' is initialized. This will become a compile time error in the future. [ProveInit]]#
    return true
  else:
    discard

discard hasImportStmt()

block:
  proc hasImportStmt(): bool =
    if false: #[tt.Warning
    ^ Cannot prove that 'result' is initialized. This will become a compile time error in the future. [ProveInit]]#
      return true
    else:
      return

  discard hasImportStmt()

block:
  block:
    proc foo(x: var int) =
      discard

    proc main =
      var s: int
      foo(s)#[tt.Warning
          ^ use explicit initialization of 's' for clarity [Uninit]]#

    main()

