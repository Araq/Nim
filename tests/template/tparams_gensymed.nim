discard """
output: '''
0
1
2
3
0
1
2
3
wth
3
2
1
0
(total: 6)
S1
5
abc
'''
"""
# bug #1915

import macros

# Test that parameters are properly gensym'ed finally:

template genNodeKind(kind, name: untyped) =
  proc name*(children: varargs[NimNode]): NimNode {.compiletime.}=
    result = newNimNode(kind)
    for c in children:
      result.add(c)

genNodeKind(nnkNone, None)


# Test that generics in templates still work (regression to fix #1915)

# bug #2004

type Something = object

proc testA(x: Something) = discard

template def(name: untyped) =
  proc testB[T](reallyUniqueName: T) =
    `test name`(reallyUniqueName)
def A

var x: Something
testB(x)


# bug #2215
# Test that templates in generics still work (regression to fix the
# regression...)

template forStatic(index, slice, predicate: untyped) =
  const a = slice.a
  const b = slice.b
  when a <= b:
    template iteration(i: int) =
      block:
        const index = i
        predicate
    template iterateStartingFrom(i: int) =
      when i <= b:
        iteration i
        iterateStartingFrom i + 1
    iterateStartingFrom a

proc concreteProc(x: int) =
  forStatic i, 0..3:
    echo i

proc genericProc(x: auto) =
  forStatic i, 0..3:
    echo i

concreteProc(7) # This works
genericProc(7)  # This doesn't compile

import tables

# bug #9476
proc getTypeInfo*(T: typedesc): pointer =
  var dummy: T
  getTypeInfo(dummy)


macro implementUnary(op: untyped): untyped =
  result = newStmtList()

  template defineTable(tableSymbol) =
    var tableSymbol = initTable[pointer, pointer]()
  let tableSymbol = genSym(nskVar, "registeredProcs")
  result.add(getAst(defineTable(tableSymbol)))

  template defineRegisterInstantiation(tableSym, regTemplSym, instSym, op) =
    template regTemplSym*(T: typedesc) =
      let ti = getTypeInfo(T)

      proc instSym(xOrig: int): int {.gensym, cdecl.} =
        let x {.inject.} = xOrig
        op

      tableSym[ti] = cast[pointer](instSym)

  let regTemplSymbol = ident("registerInstantiation")
  let instSymbol = ident("instantiation")
  result.add(getAst(defineRegisterInstantiation(
    tableSymbol, regTemplSymbol, instSymbol, op
  )))

  echo result.repr


implementUnary(): x*x

registerInstantiation(int)
registerInstantiation(float)

# bug #10192
template nest(body) {.dirty.} =
  template p1(b1: untyped) {.dirty, used.} =
    template implp1: untyped {.dirty.} = b1
  template p2(b2: untyped) {.dirty, used.} =
    template implp2: untyped {.dirty.} = b2

  body
  implp1
  implp2

template test() =
  nest:
    p1:
      var foo = "bar"
    p2:
      doAssert(foo.len == 3)

test()

# regression found in PMunch's parser generator

proc namedcall(arg: string) =
  discard

macro m(): untyped =
  result = quote do:
    (proc (arg: string) =
      namedcall(arg = arg)
      echo arg)

let meh = m()
meh("wth")


macro foo(body: untyped): untyped =
  result = body

template baz(): untyped =
  foo:
    proc bar2(b: int): int =
      echo b
      if b > 0: b + bar2(b = b - 1)
      else: 0
  echo (total: bar2(3))

baz()

# bug #12121
macro state_machine_enum(states: varargs[untyped]) =
  result = nnkTypeSection.newTree(
    nnkTypeDef.newTree(
      nnkPragmaExpr.newTree(ident("State"), nnkPragma.newTree(ident("pure"))),
      newEmptyNode(),
      nnkEnumTy.newTree(newEmptyNode())
    )
  )

  for s in states:
    expectKind(s, nnkIdent)
    result[0][2].add s

template mystate_machine(body: untyped) =
  state_machine_enum(S1, S2, S3)
  var state_stack: seq[State]
  template state_current(): State {.inject, used.} =
    state_stack[^1]
  template state_push(state_name) {.inject, used.} =
    state_stack.add State.state_name
  template state_pop(n = 1) {.inject, used.} =
    state_stack.setLen(state_stack.len - n)
  body

mystate_machine:
  state_push(S1)
  echo state_current()
  state_pop()

# bug #15075
block: #Doesn't work
  template genGenTempl: untyped =
    proc loop(locals: int)
    proc loop(locals: int) = discard
  genGenTempl()
  let pool = loop

block: #Doesn't work
  macro genGenMacro: untyped =
    quote do:
      proc loop(locals: int)
      proc loop(locals: int) = discard
  genGenMacro()
  let pool = loop

block: #This works
  proc loop(locals: int)
  proc loop(locals: int) = discard
  let pool = loop

#Now somewhat recursive:
type Cont = ref object of RootObj
  fn*: proc(c: Cont): Cont {.nimcall.}

block: #Doesn't work
  template genGenTempl(): untyped =
    proc loop(locals: Cont): Cont
    proc loop(locals: Cont): Cont =
      return Cont(fn: loop)
    proc doServer(): Cont =
      return Cont(fn: loop)
  genGenTempl()
  discard doServer()

block: #Doesn't work
  macro genGenMacro(): untyped =
    quote:
      proc loop(locals: Cont): Cont
      proc loop(locals: Cont): Cont =
        return Cont(fn: loop)
      proc doServer(): Cont =
        return Cont(fn: loop)
  genGenMacro()
  discard doServer()

block: #This works
  proc loop(locals: Cont): Cont
  proc loop(locals: Cont): Cont =
    return Cont(fn: loop)
  proc doServer(): Cont =
    return Cont(fn: loop)
  discard doServer()

#And fully recursive:
block: #Doesn't work
  template genGenTempl: untyped =
    proc loop(locals: int)
    proc loop(locals: int) = loop(locals)
  genGenTempl()
  let pool = loop

block: #Doesn't work
  macro genGenMacro: untyped =
    quote do:
      proc loop(locals: int)
      proc loop(locals: int) = loop(locals)
  genGenMacro()
  let pool = loop

block: #This works
  proc loop(locals: int)
  proc loop(locals: int) = loop(locals)
  let pool = loop

block:
  template genAndCallLoop: untyped =
    proc loop() {.gensym.}
    proc loop() {.gensym.} =
      discard
    loop()
  genAndCallLoop

block: #Fully recursive and gensymmed:
  template genGenTempl: untyped =
    proc loop(locals: int) {.gensym.}
    proc loop(locals: int) {.gensym.} = loop(locals)
    let pool = loop
  genGenTempl()

block: #Make sure gensymmed symbol doesn't overwrite the forward decl
  proc loop()
  proc loop() = discard
  template genAndCallLoop: untyped =
    proc loop() {.gensym.} =
      discard
    loop()
  genAndCallLoop()

template genLoopDecl: untyped =
  proc loop()
template genLoopDef: untyped =
  proc loop() = discard
block:
  genLoopDecl
  genLoopDef
  loop()
block:
  proc loop()
  genLoopDef
  loop()
block:
  genLoopDecl
  proc loop() = discard
  loop()

block: #Gensymmed sym sharing forward decl
  macro genGenMacro: untyped =
    let sym = genSym(nskProc, "loop")
    nnkStmtList.newTree(
      newProc(sym, body = newEmptyNode()),
      newCall(sym),
      newProc(sym, body = newStmtList()),
    )
  genGenMacro

# inject pragma on params

template test(procname, body: untyped): untyped = 
  proc procname(data {.inject.}: var int = 0) =
    body

test(hello):
  echo data
  data = 3

var data = 5

hello(data)

# bug #5691

template bar(x: typed) = discard
macro barry(x: typed) = discard

var a = 0

bar:
  var a = 10

barry:
  var a = 20

bar:
  var b = 10

barry:
  var b = 20

var b = 30

# template bar(x: static int) = discard
#You may think that this should work:
# bar((var c = 1; echo "hey"; c))
# echo c
#But it must not! Since this would be incorrect:
# bar((var b = 3; const c = 1; echo "hey"; c))
# echo b # <- b wouldn't exist

discard not (let xx = 1; true)
discard xx

template barrel(a: typed): untyped = a

barrel:
  var aa* = 1
  var bb = 3
  export bb

# Test declaredInScope within params
template test1: untyped =
  when not declaredInScope(thing):
    var thing {.inject.}: int

proc chunkedReadLoop =
  test1
  test1

template test2: untyped =
  when not not not declaredInScope(thing):
    var thing {.inject.}: int

proc chunkedReadLoop2 =
  test2
  test2

test1(); test2()

block: # bug #22846
  template foo2(x: proc (y: string)) =
    let f = x
    f("abc")

  foo2(proc (y: string) = echo y)

