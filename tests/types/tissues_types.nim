discard """
  output: '''true
true
true
true
(member: "hello world")
(member: 123.456)
(member: "hello world", x: ...)
(member: 123.456, x: ...)
0
false
'''
"""

block t1252:
  echo float32 isnot float64
  echo float32 isnot float
  echo int32 isnot int64
  echo int32 isnot int

block t5640:
  type
    vecBase[I: static[int]] = distinct array[I, float32]
    vec2 = vecBase[2]

  var v = vec2([0.0'f32, 0.0'f32])

block t7581:
  discard int -1

block t7905:
  template foobar(arg: typed): untyped =
    type
      MyType = object
        member: type(arg)

    var myVar: MyType
    myVar.member = arg
    echo myVar

  foobar("hello world")
  foobar(123.456'f64)

  template foobarRec(arg: typed): untyped =
    type
      MyType = object
        member: type(arg)
        x: ref MyType

    var myVar: MyType
    myVar.member = arg
    echo myVar

  foobarRec("hello world")
  foobarRec(123.456'f64)

# bug #5170

when true:
  type Foo = object
    bar: bool

  type Bar = object
    sameBody: string

  var b0: Bar
  b0.sameBody = "abc"

block:
  type Foo = object
    baz: int

  type Bar = object
    sameBody: string

  var b1: Bar
  b1.sameBody = "def"

  var f2: Foo
  echo f2.baz

var f1: Foo
echo f1.bar

import macros

block: # issue #12582
  macro foo(T: type): type =
    nnkBracketExpr.newTree(bindSym "array", newLit 1, T)
  var
    _: foo(int) # fine
  type
    Foo = object
      x: foo(int) # fine
    Bar = ref object
      x: foo(int) # error
  let b = Bar()
  let b2 = Bar(x: [123])

block:
  when true: # bug #14710
    type Foo[T] = object
      x1: int
      when T.sizeof == 4: discard # SIGSEGV
      when sizeof(T) == 4: discard # ok
    let t = Foo[float](x1: 1)
    doAssert t.x1 == 1

block:
  template s(d: varargs[typed])=discard

  proc something(x:float)=discard
  proc something(x:int)=discard
  proc otherthing()=discard

  s(something)
  s(otherthing, something)
  s(something, otherthing)
