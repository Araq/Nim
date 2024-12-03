discard """
  matrix: "-d:nimInternalNonVtablesTesting"
  output: '''(peel: 0, color: 15)
(color: 15)
17
(width: 0.0, taste: "", color: 13)
(width: 0.0, taste: "", color: 15)
cool
test'''
"""

# bug #5241
type
  BaseFruit[T] = object of RootObj
    color: T

  MidLevel[T] = object of BaseFruit[T]

  Mango = object of MidLevel[int]
    peel: int

  Peach[X, T, Y] = object of T
    width: X
    taste: Y

proc setColor[T](self: var BaseFruit[T]) =
  self.color = 15

proc setColor[T](self: var BaseFruit[T], c: int) =
  self.color = c

var c: Mango
setColor(c)
echo c

var d: MidLevel[int]
setColor(d)
echo d

type
  FooBase[T] = ref object of RootRef
    v: T
  BarClient = ref object of FooBase[int]

proc getColor[T](f: FooBase[T]): T = 17
var b: BarClient
echo getColor(b)

var z: Peach[float64, BaseFruit[int], string]
z.setColor(13)
echo z

z.setColor()
echo z

# bug #5411
type
  Foo[T] = ref object of RootRef
    v: T
  Bar = ref object of Foo[int]

method m(o: RootRef) {.base.} = assert(false, "Abstract method called")
method m[T](o: Foo[T]) = echo "cool"

var v: Bar
v.new()
v.m() # Abstract method not called anymore


# bug #88

type
  TGen[T] = object of RootObj
    field: T

  TDerived[T] = object of TGen[T]
    nextField: T

proc doSomething[T](x: ref TGen[T]) =
  type
    Ty = ref TDerived[T]
  echo Ty(x).nextField

var
  x: ref TDerived[string]
new(x)
x.nextField = "test"

doSomething(x)
