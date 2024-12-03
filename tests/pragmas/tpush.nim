discard """
  targets: "c js"
"""

# test the new pragmas

{.push warnings: off, hints: off.}
proc noWarning() =
  var
    x: int
  echo(x)

{.pop.}

proc WarnMe() =
  var
    x: int
  echo(x)

# bug #11852
proc foo(x: string, y: int, res: int) =
  {.push checks: off}
  var a: ptr char = unsafeAddr(x[y])
  {.pop.}
  if x.len > y:
    doAssert ord(a[]) == 51
  else:
    doAssert x.len + 48 == res

foo("", 0, 48)
foo("abc", 40, 51)

# bug #22362
{.push staticBoundChecks: on.}
proc main(): void =
  {.pop.}
  discard
  {.push staticBoundChecks: on.}

main()


proc timnFoo[T](obj: T) {.noSideEffect.} = discard # BUG

{.push exportc.}
proc foo1() =
  var s1 = "bar"
  timnFoo(s1)
  var s2 = @[1]
  timnFoo(s2)
{.pop.}


block: # bug #22913
  block:
    type r = object

    template std[T](x: T) =
      let ttt {.used.} = x
      result = $ttt

    proc bar[T](x: T): string =
      std(x)

    {.push exportc: "$1".}
    proc foo(): r =
      let s = bar(123)
    {.pop.}

    discard foo()

  block:
    type r = object
    {.push exportc: "$1".}
    proc foo2(): r =
      let s = $result
    {.pop.}

    discard foo2()

block: # bug #23019
  proc f(x: bool)

  proc a(x: int) =
    if false: f(true)

  proc f(x: bool) =
    if false: a(0)

  proc k(r: int|int) {.inline.} =  # seems to require being generic and inline
    if false: a(0)


  # {.push tags: [].}
  {.push raises: [].}

  {.push warning[ObservableStores]:off.}  # can be any warning, off or on
  let w = 0
  k(w)
  {.pop.}
  {.pop.}

{.push exportC.}

block:
  proc foo11() =
    const factor = [1, 2, 3, 4]
    doAssert factor[0] == 1
  proc foo21() =
    const factor = [1, 2, 3, 4]
    doAssert factor[0] == 1

  foo11()
  foo21()

template foo31() =
  let factor = [1, 2, 3, 4]
  doAssert factor[0] == 1
template foo41() =
  let factor = [1, 2, 3, 4]
  doAssert factor[0] == 1

foo31()
foo41()

{.pop.}

import macros

block:
  {.push deprecated.}
  template test() = discard
  test()
  {.pop.}
  macro foo(): bool =
    let ast = getImpl(bindSym"test")
    var found = false
    if ast[4].kind == nnkPragma:
      for x in ast[4]:
        if x.eqIdent"deprecated":
          found = true
          break
    result = newLit(found)
  doAssert foo()
