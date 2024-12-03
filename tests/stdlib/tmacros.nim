discard """
  matrix: "--mm:refc; --mm:orc"
"""

#[
xxx macros tests need to be reorganized to makes sure each API is tested once
See also:
  tests/macros/tdumpast.nim for treeRepr + friends
]#

import std/macros
import std/assertions

block: # hasArgOfName
  macro m(u: untyped): untyped =
    for name in ["s","i","j","k","b","xs","ys"]:
      doAssert hasArgOfName(params u,name)
    doAssert not hasArgOfName(params u,"nonexistent")

  proc p(s: string; i,j,k: int; b: bool; xs,ys: seq[int] = @[]) {.m.} = discard

block: # bug #17454
  proc f(v: NimNode): string {.raises: [].} = $v

block: # unpackVarargs
  block:
    proc bar1(a: varargs[int]): string =
      result = ""
      for ai in a: result.add " " & $ai
    proc bar2(a: varargs[int]) =
      let s1 = bar1(a)
      let s2 = unpackVarargs(bar1, a) # `unpackVarargs` makes no difference here
      doAssert s1 == s2
    bar2(1, 2, 3)
    bar2(1)
    bar2()

  block:
    template call1(fun: typed; args: varargs[untyped]): untyped =
      unpackVarargs(fun, args)
    template call2(fun: typed; args: varargs[untyped]): untyped =
      # fun(args) # works except for last case with empty `args`, pending bug #9996
      when varargsLen(args) > 0: fun(args)
      else: fun()

    proc fn1(a = 0, b = 1) = discard (a, b)

    call1(fn1)
    call1(fn1, 10)
    call1(fn1, 10, 11)

    call2(fn1)
    call2(fn1, 10)
    call2(fn1, 10, 11)

  block:
    template call1(fun: typed; args: varargs[typed]): untyped =
      unpackVarargs(fun, args)
    template call2(fun: typed; args: varargs[typed]): untyped =
      # xxx this would give a confusing error message:
      # required type for a: varargs[typed] [varargs] but expression '[10]' is of type: varargs[typed] [varargs]
      when varargsLen(args) > 0: fun(args)
      else: fun()
    macro toString(a: varargs[typed, `$`]): string =
      var msg = genSym(nskVar, "msg")
      result = newStmtList()
      result.add quote do:
        var `msg` = ""
      for ai in a:
        result.add quote do: `msg`.add $`ai`
      result.add quote do: `msg`
    doAssert call1(toString) == ""
    doAssert call1(toString, 10) == "10"
    doAssert call1(toString, 10, 11) == "1011"

block: # SameType
  type
    A = int
    B = distinct int
    C = object
    Generic[T, Y] = object
  macro isSameType(a, b: typed): untyped =
    newLit(sameType(a, b))

  static:
    assert Generic[int, int].isSameType(Generic[int, int])
    assert Generic[A, string].isSameType(Generic[int, string])
    assert not Generic[A, string].isSameType(Generic[B, string])
    assert not Generic[int, string].isSameType(Generic[int, int])
    assert isSameType(int, A)
    assert isSameType(10, 20)
    assert isSameType("Hello", "world")
    assert not isSameType("Hello", cstring"world")
    assert not isSameType(int, B)
    assert not isSameType(int, Generic[int, int])
    assert not isSameType(C, string)
    assert not isSameType(C, int)


  #[
    # compiler sameType fails for the following, read more in `types.nim`'s `sameTypeAux`.
    type
      D[T] = C
      G[T] = T
    static:
      assert isSameType(D[int], C)
      assert isSameType(D[int], D[float])
      assert isSameType(G[float](1.0), float(1.0))
      assert isSameType(float(1.0), G[float](1.0))
  ]#

  type Tensor[T] = object
    data: T

  macro testTensorInt(x: typed): untyped =
    let
      tensorIntType = getTypeInst(Tensor[int])[1]
      xTyp = x.getTypeInst
    
    newLit(xTyp.sameType(tensorIntType))

  var
    x: Tensor[int]
    x1 = Tensor[float]()
    x2 = Tensor[A]()
    x3 = Tensor[B]()

  static: 
    assert testTensorInt(x)
    assert not testTensorInt(x1)
    assert testTensorInt(x2)
    assert not testTensorInt(x3)

block: # extractDocCommentsAndRunnables
  macro checkRunnables(prc: untyped) =
    let runnables = prc.body.extractDocCommentsAndRunnables()
    doAssert runnables[0][0].eqIdent("runnableExamples")

  macro checkComments(comment: static[string], prc: untyped) =
    let comments = prc.body.extractDocCommentsAndRunnables()
    doAssert comments[0].strVal == comment
    
  proc a() {.checkRunnables.} =
    runnableExamples: discard
    discard

  proc b() {.checkRunnables.} =
    runnableExamples "-d:ssl": discard
    discard
    
  proc c() {.checkComments("Hello world").} =
    ## Hello world

block: # bug #19020
  type
    foo = object

  template typ(T:typedesc) {.pragma.}

  proc bar() {.typ: foo.} = discard

  static:
    doAssert $bar.getCustomPragmaVal(typ) == "foo"
  doAssert $bar.getCustomPragmaVal(typ) == "foo"

block hasCustomPragmaGeneric:
  template examplePragma() {.pragma.}
  type
    Foo[T] {.examplePragma.} = object
      x {.examplePragma.}: T
  var f: Foo[string]
  doAssert f.hasCustomPragma(examplePragma)
  doAssert f.x.hasCustomPragma(examplePragma)

block getCustomPragmaValGeneric:
  template examplePragma(x: int) {.pragma.}
  type
    Foo[T] {.examplePragma(42).} = object
      x {.examplePragma(25).}: T
  var f: Foo[string]
  doAssert f.getCustomPragmaVal(examplePragma) == 42
  doAssert f.x.getCustomPragmaVal(examplePragma) == 25

block: # bug #21326
  macro foo(body: untyped): untyped =
    let a = body.lineInfoObj()
    let aLit = a.newLit
    result = quote do:
      doAssert $`a` == $`aLit`

  foo:
    let c = 1

  template name(a: LineInfo): untyped =
    discard a # `aLit` works though

  macro foo3(body: untyped): untyped =
    let a = body.lineInfoObj()
    # let ax = newLit(a)
    result = getAst(name(a))

  foo3:
    let c = 1

block: # bug #7375
  macro fails(b: static[bool]): untyped =
    doAssert b == false
    result = newStmtList()

  macro foo(): untyped =

    var b = false

    ## Fails
    result = quote do:
      fails(`b`)

  foo()

  macro someMacro(): untyped =
    template tmpl(boolean: bool) =
      when boolean:
        discard "it's true!"
      else:
        doAssert false
    result = getAst(tmpl(true))

  someMacro()

block:
  macro foo(): untyped =
    result = quote do: `littleEndian`

  doAssert littleEndian == foo()

block:
  macro eqSym(x, y: untyped): untyped =
    let eq = $x == $y # Unfortunately eqIdent compares to string.
    result = quote do: `eq`

  var r, a, b: int

  template fma(result: var int, a, b: int, op: untyped) =
    # fused multiple-add
    when eqSym(op, `+=`):
      discard "+="
    else:
      discard "+"

  fma(r, a, b, `+=`)

block:
  template test(boolArg: bool) =
    static:
      doAssert typeof(boolArg) is bool
    let x: bool = boolArg # compile error here, because boolArg became an int

  macro testWrapped1(boolArg: bool): untyped =
    # forwarding boolArg directly works
    result = getAst(test(boolArg))

  macro testWrapped2(boolArg: bool): untyped =
    # forwarding boolArg via a local variable also works
    let b = boolArg
    result = getAst(test(b))

  macro testWrapped3(boolArg: bool): untyped =
    # but using a literal `true` as a local variable will be converted to int
    let b = true
    result = getAst(test(b))

  test(true) # ok
  testWrapped1(true) # ok
  testWrapped2(true) # ok
  testWrapped3(true) 

block:
  macro foo(): untyped =
    var s = { 'a', 'b' }
    quote do:              
      let t = `s`         
      doAssert $typeof(t) == "set[char]"

  foo()

block: # bug #9607
  proc fun1(info:LineInfo): string = "bar"
  proc fun2(info:int): string = "bar"

  macro echoL(args: varargs[untyped]): untyped =
    let info = args.lineInfoObj
    let fun1 = bindSym"fun1"
    let fun2 = bindSym"fun2"

    # this would work instead
    # result = newCall(bindSym"fun2", info.line.newLit)

    result = quote do:

      # BUG1: ???(0, 0) Error: internal error: genLiteral: ty is nil
      `fun1`(`info`)

  macro echoM(args: varargs[untyped]): untyped =
    let info = args.lineInfoObj
    let fun1 = bindSym"fun1"
    let fun2 = bindSym"fun2"

    # this would work instead
    # result = newCall(bindSym"fun2", info.line.newLit)

    result = quote do:

      # BUG1: ???(0, 0) Error: internal error: genLiteral: ty is nil
      `fun2`(`info`.line)


  doAssert echoL() == "bar"
  doAssert echoM() == "bar"

block:
  macro hello[T](x: T): untyped =
    result = quote do:
      let m: `T` = `x`
      discard m

  hello(12)

block:
  proc hello(x: int, y: typedesc) =
    discard

  macro main =
    let x = 12
    result = quote do:
      `hello`(12, type(x))

  main()

block: # bug #22947
  macro bar[N: static int](a: var array[N, int]) =
    result = quote do:
      for i in 0 ..< `N`:
        `a`[i] = i

  func foo[N: static int](a: var array[N, int]) =
    bar(a)


  var a: array[4, int]
  foo(a)
