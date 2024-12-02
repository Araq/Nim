discard """
output: '''
@[]
5
0
a
hi
Hello, World!
(e: 42)
hey
foo
foo
foo
false
true
0
'''
"""


import macros, json


block t2057:
  proc mpf_get_d(x: int): float = float(x)
  proc mpf_cmp_d(a: int; b: float): int = 0

  template toFloatHelper(result, tooSmall, tooLarge: untyped) =
    result = mpf_get_d(a)
    if result == 0.0 and mpf_cmp_d(a,0.0) != 0:
      tooSmall
    if result == Inf:
      tooLarge

  proc toFloat(a: int): float =
    toFloatHelper(result) do:
      raise newException(ValueError, "number too small")
    do:
      raise newException(ValueError, "number too large")

  doAssert toFloat(8) == 8.0



import sequtils, os
block t2629:
  template glob_rst(basedir: string = ""): untyped =
    if baseDir.len == 0:
      to_seq(walk_files("*.rst"))
    else:
      to_seq(walk_files(basedir/"*.rst"))

  let rst_files = concat(glob_rst(), glob_rst("docs"))

  when true: echo rst_files


block t5417:
  macro genBody: untyped =
    let sbx = genSym(nskLabel, "test")
    when true:
      result = quote do:
        block `sbx`:
          break `sbx`
    else:
      template foo(s1, s2) =
        block s1:
          break s2
      result = getAst foo(sbx, sbx)

  proc test() =
    genBody()



block t909:
  template baz() =
    proc bar() =
      var x = 5
      iterator foo(): int {.closure.} =
        echo x
      var y = foo
      discard y()

  macro test(): untyped =
    result = getAst(baz())

  test()
  bar()



block t993:
  type PNode = ref object of RootObj

  template litNode(name, ty)  =
    type name = ref object of PNode
      val: ty
  litNode PIntNode, int

  template withKey(j: JsonNode; key: string; varname,
                    body: untyped): typed =
    if j.hasKey(key):
      let varname{.inject.}= j[key]
      block:
        body

  var j = parsejson("{\"zzz\":1}")
  withkey(j, "foo", x):
    echo(x)




block t1337:
  template someIt(a, pred): untyped =
    var it {.inject.} = 0
    pred

  proc aProc(n: auto) =
    n.someIt(echo(it))

  aProc(89)



import mlt
block t4564:
  type Bar = ref object of RootObj
  proc foo(a: Bar): int = 0
  var a: Bar
  let b = a.foo() > 0



block t8052:
  type
    UintImpl[N: static[int], T: SomeUnsignedInt] = object
      raw_data: array[N, T]

  template genLoHi(TypeImpl: untyped): untyped =
    template loImpl[N: static[int], T: SomeUnsignedInt](dst: TypeImpl[N div 2, T], src: TypeImpl[N, T]) =
      let halfSize = N div 2
      for i in 0 ..< halfSize:
        dst.raw_data[i] = src.raw_data[i]

    proc lo[N: static[int], T: SomeUnsignedInt](x: TypeImpl[N,T]): TypeImpl[N div 2, T] {.inline.}=
      loImpl(result, x)

  genLoHi(UintImpl)

  var a: UintImpl[4, uint32]

  a.raw_data = [1'u32, 2'u32, 3'u32, 4'u32]
  doAssert a.lo.raw_data.len == 2
  doAssert a.lo.raw_data[0] == 1
  doAssert a.lo.raw_data[1] == 2



block t2585:
  type
    RenderPass = object
       state: ref int
    RenderData = object
        fb: int
        walls: seq[RenderPass]
    Mat2 = int
    Vector2[T] = T
    Pixels=int

  template use(fb: int, st: untyped): untyped =
      echo "a ", $fb
      st
      echo "a ", $fb

  proc render(rdat: var RenderData; passes: var openArray[RenderPass]; proj: Mat2;
              indexType = 1) =
      for i in 0 ..< len(passes):
          echo "blah ", repr(passes[i])

  proc render2(rdat: var RenderData; screenSz: Vector2[Pixels]; proj: Mat2) =
      use rdat.fb:
          render(rdat, rdat.walls, proj, 1)



block t4292:
  template foo(s: string): string = s
  proc variadicProc(v: varargs[string, foo]) = echo v[0]
  variadicProc("a")



block t2670:
  template testTemplate(b: bool): typed =
    when b:
        var a = "hi"
    else:
        var a = 5
    echo a
  testTemplate(true)



block t4097:
  var i {.compileTime.} = 2

  template defineId(t: typedesc) =
    const id {.genSym.} = i
    static: inc(i)
    proc idFor(T: typedesc[t]): int {.inline, raises: [].} = id

  defineId(int8)
  defineId(int16)

  doAssert idFor(int8) == 2
  doAssert idFor(int16) == 3



block t5235:
  template outer(body: untyped) =
    template test(val: string) =
      const SomeConst: string = val
      echo SomeConst
    body

  outer:
    test("Hello, World!")


# bug #11941
type X = object
  e: int

proc works(T: type X, v: auto): T = T(e: v)
template fails(T: type X, v: auto): T = T(e: v)

var
  w = X.works(42)
  x = X.fails(42)

echo x

import mtempl5


proc foo(): auto =
  trap "foo":
    echo "hey"

discard foo()


# bug #4722
type
  IteratorF*[In] = iterator() : In {.closure.}

template foof(In: untyped) : untyped =
  proc ggg*(arg: IteratorF[In]) =
    for i in arg():
      echo "foo"


iterator hello() : int {.closure.} =
  for i in 1 .. 3:
    yield i

foof(int)
ggg(hello)


# bug #2586
var z = 10'u8
echo z < 9 # Works
echo z > 9 # Error: type mismatch


# bug #5993
template foo(p: proc) =
  var bla = 5
  p(bla)

foo() do(t: var int):
  discard
  t = 5

proc bar(t: var int) =
  t = 5

foo(bar)

block: # bug #12595
  template test() =
    let i = 42
    discard {i: ""}

  test()

block: # bug #21920
  template t[T](): T =
    discard

  t[void]() # Error: expression has no type: discard

template m(a: uint, p: int) = discard

block: # bug #23680
  template m(x: untyped, i: int) = echo x
  proc j(n: int | int) = m([0][0], 0)
  j(0)
