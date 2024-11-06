## This module allows evaluating expressions safely against the following conditions:
## * nil dereferences
## * field accesses with incorrect discriminant in case objects
##
## `default(T)` is returned in those cases when evaluating an expression of type `T`.
## This simplifies code by reducing need for if-else branches.
##
## Note: experimental module, unstable API.

#[
TODO:
consider handling indexing operations, eg:
doAssert ?.default(seq[int])[3] == default(int)
]#

import std/macros

runnableExamples:
  type Foo = ref object
    x1: string
    x2: Foo
    x3: ref int

  var f: Foo
  assert ?.f.x2.x1 == "" # returns default value since `f` is nil

  var f2 = Foo(x1: "a")
  f2.x2 = f2
  assert ?.f2.x1 == "a" # same as f2.x1 (no nil LHS in this chain)
  assert ?.Foo(x1: "a").x1 == "a" # can use constructor inside

  # when you know a sub-expression doesn't involve a `nil` (e.g. `f2.x2.x2`),
  # you can scope it as follows:
  assert ?.(f2.x2.x2).x3[] == 0

  assert (?.f2.x2.x2).x3 == nil  # this terminates ?. early

runnableExamples:
  # ?. also allows case object
  type B = object
    b0: int
    case cond: bool
    of false: discard
    of true:
      b1: float

  var b = B(cond: false, b0: 3)
  doAssertRaises(FieldDefect): discard b.b1 # wrong discriminant
  doAssert ?.b.b1 == 0.0 # safe
  b = B(cond: true, b1: 4.5)
  doAssert ?.b.b1 == 4.5

  # lvalue semantics are preserved:
  if (let p = ?.b.b1.addr; p != nil): p[] = 4.7
  doAssert b.b1 == 4.7

proc finalize(n: NimNode, lhs: NimNode, level: int): NimNode =
  if level == 0:
    result = quote: `lhs` = `n`
  else:
    result = quote: (var `lhs` = `n`)

proc process(n: NimNode, lhs: NimNode, label: NimNode, level: int): NimNode =
  var n = n.copyNimTree
  var it = n
  let addr2 = bindSym"addr"
  var old: tuple[n: NimNode, index: int]
  while true:
    if it.len == 0:
      result = finalize(n, lhs, level)
      break
    elif it.kind == nnkCheckedFieldExpr:
      let dot = it[0]
      let obj = dot[0]
      let objRef = quote do: `addr2`(`obj`)
        # avoids a copy and preserves lvalue semantics, see tests
      let check = it[1]
      let okSet = check[1]
      let kind1 = check[2]
      let tmp = genSym(nskVar, "tmpCase")
      let body = process(objRef, tmp, label, level + 1)
      let tmp3 = nnkDerefExpr.newTree(tmp)
      it[0][0] = tmp3
      let dot2 = nnkDotExpr.newTree(@[tmp, dot[1]])
      if old.n != nil: old.n[old.index] = dot2
      else: n = dot2
      let assgn = finalize(n, lhs, level)
      result = quote do:
        `body`
        if `tmp3`.`kind1` notin `okSet`: break `label`
        `assgn`
      break
    elif it.kind in {nnkHiddenDeref, nnkDerefExpr}:
      let tmp = genSym(nskVar, "tmp")
      let body = process(it[0], tmp, label, level + 1)
      it[0] = tmp
      let assgn = finalize(n, lhs, level)
      result = quote do:
        `body`
        if `tmp` == nil: break `label`
        `assgn`
      break
    elif it.kind == nnkCall: # consider extending to `nnkCallKinds`
      # `copyNimTree` needed to avoid `typ = nil` issues
      old = (it, 1)
      it = it[1].copyNimTree
    else:
      old = (it, 0)
      it = it[0]

macro `?.`*(a: typed): auto =
  ## Transforms `a` into an expression that can be safely evaluated even in
  ## presence of intermediate nil pointers/references, in which case a default
  ## value is produced.
  let lhs = genSym(nskVar, "lhs")
  let label = genSym(nskLabel, "label")
  let body = process(a, lhs, label, 0)
  result = quote do:
    var `lhs`: type(`a`) = default(type(`a`))
    block `label`:
      `body`
    `lhs`

# the code below is not needed for `?.`
from std/options import Option, isSome, get, option, unsafeGet, UnpackDefect

macro `??.`*(a: typed): Option =
  ## Same as `?.` but returns an `Option`.
  runnableExamples:
    import std/options
    type Foo = ref object
      x1: ref int
      x2: int
    # `?.` can't distinguish between a valid vs invalid default value, but `??.` can:
    var f1 = Foo(x1: int.new, x2: 2)
    doAssert (??.f1.x1[]).get == 0 # not enough to tell when the chain was valid.
    doAssert (??.f1.x1[]).isSome # a nil didn't occur in the chain
    doAssert (??.f1.x2).get == 2

    var f2: Foo
    doAssert not (??.f2.x1[]).isSome # f2 was nil

    doAssertRaises(UnpackDefect): discard (??.f2.x1[]).get
    doAssert ?.f2.x1[] == 0 # in contrast, this returns default(int)

  let lhs = genSym(nskVar, "lhs")
  let lhs2 = genSym(nskVar, "lhs")
  let label = genSym(nskLabel, "label")
  let body = process(a, lhs2, label, 0)
  result = quote do:
    var `lhs`: Option[type(`a`)] = default(Option[type(`a`)])
    block `label`:
      var `lhs2`: type(`a`) = default(type(`a`))
      `body`
      `lhs` = option(`lhs2`)
    `lhs`

template fakeDot*(a: Option, b): untyped =
  ## See top-level example.
  let a1 = a # to avoid double evaluations
  type T = Option[typeof(unsafeGet(a1).b)]
  if isSome(a1):
    let a2 = unsafeGet(a1)
    when typeof(a2) is ref|ptr:
      if a2 == nil:
        default(T)
      else:
        option(a2.b)
    else:
      option(a2.b)
  else:
    # nil is "sticky"; this is needed, see tests
    default(T)

# xxx this should but doesn't work: func `[]`*[T, I](a: Option[T], i: I): Option {.inline.} =

func `[]`*[T, I](a: Option[T], i: I): auto {.inline.} =
  ## See top-level example.
  if isSome(a):
    # correctly will raise IndexDefect if a is valid but wraps an empty container
    result = option(a.unsafeGet[i])

func `[]`*[U](a: Option[U]): auto {.inline.} =
  ## See top-level example.
  if isSome(a):
    let a2 = a.unsafeGet
    if a2 != nil:
      result = option(a2[])

when false:
  # xxx: expose a way to do this directly in std/options, e.g.: `getAsIs`
  proc safeGet[T](a: Option[T]): T {.inline.} =
    get(a, default(T))
