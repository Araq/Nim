discard """
  output: '''
n
n
(one: 1, two: 2, three: 3)
1
2
3
(one: 4, two: 5, three: 6)
4
(one: 7, two: 8, three: 9)
7
8
9
(foo: 38, other: "string here")
43
100
90
'''
"""


block tindex:
  type
    TMyTuple = tuple[a, b: int]

  proc indexOf(t: typedesc, name: string): int =
    ## takes a tuple and looks for the field by name.
    ## returs index of that field.
    var
      d: t
      i = 0
    for n, x in fieldPairs(d):
      if n == name: return i
      i.inc
    raise newException(ValueError, "No field " & name & " in type " &
      astToStr(t))

  doAssert TMyTuple.indexOf("b") == 1



block ttemplate:
  # bug #1902
  # This works.
  for name, value in (n: "v").fieldPairs:
    echo name

  template wrapper(): void =
    for name, value in (n: "v").fieldPairs:
      echo name
  wrapper()



block tbreak:
  # bug #2134
  type
    TestType = object
      one: int
      two: int
      three: int

  var
    ab = TestType(one:1, two:2, three:3)
    ac = TestType(one:4, two:5, three:6)
    ad = TestType(one:7, two:8, three:9)
    tstSeq = [ab, ac, ad]

  for tstElement in mitems(tstSeq):
    echo tstElement
    for tstField in fields(tstElement):
      #for tstField in [1,2,4,6]:
      echo tstField
      if tstField == 4:
        break



block timplicit_with_partial:
  type
    Base = ref object of RootObj
    Foo {.partial.} = ref object of Base

  proc my(f: Foo) =
    #var f.next = f
    let f.foo = 38
    let f.other = "string here"
    echo f[]
    echo f.foo + 5

  var g: Foo
  new(g)
  my(g)

  type
    FooTask {.partial.} = ref object of RootObj

  proc foo(t: FooTask) {.liftLocals: t.} =
    var x = 90
    if true:
      var x = 10
      while x < 100:
        inc x
      echo x
    echo x

  foo(FooTask())

block: # issue #24338
  var innerCount = 0
  var outerCount = 0
  template c(w: int): int =
    let q = w
    inc innerCount
    0

  template t(r: (int, int); x: int) =
    for _ in r.fields:
      let w = x
      doAssert w == 0
      dec outerCount

  proc k() =
    t((0, 0), c(0))

  k()
  doAssert innerCount == 2
  doAssert outerCount == -2

block: # issue #24338 with object
  type Foo = object
    x, y: int
  var innerCount = 0
  var outerCount = 0
  template c(w: int): int =
    let q = w
    inc innerCount
    0

  template t(r: Foo; x: int) =
    for _ in r.fields:
      let w = x
      doAssert w == 0
      dec outerCount

  proc k() =
    t(Foo(x: 0, y: 0), c(0))

  k()
  doAssert innerCount == 2
  doAssert outerCount == -2
