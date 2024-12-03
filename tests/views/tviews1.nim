discard """
  output: '''11
22
33
3
2
3
3
15
(oa: [1, 3, 4])'''
  targets: "c cpp"
"""

{.experimental: "views".}

proc take(a: openArray[int]) =
  echo a.len

proc main(s: seq[int]) =
  var x: openArray[int] = s
  for i in 0 .. high(x):
    echo x[i]
  take(x)

  take(x.toOpenArray(0, 1))
  let y = x
  take y
  take x

main(@[11, 22, 33])

var x: int

proc foo(x: var int): var int =
  once: x = 42
  return x

var y: var int = foo(x)
y = 15
echo foo(x)
# bug #16132

# bug #18690

type
  F = object
    oa: openArray[int]

let s1 = @[1,3,4,5,6]
var test = F(oa: toOpenArray(s1, 0, 2))
echo test

type
  Foo = object
    x: string
    y: seq[int]
    data: array[10000, byte]

  View[T] = object
    x: lent T

proc mainB =
  let f = Foo(y: @[1, 2, 3])
  let foo = View[Foo](x: f)
  assert foo.x.x == ""
  assert foo.x.y == @[1, 2, 3]

mainB()


# bug #15897
type Outer = ref object 
  value: int
type Inner = object
  owner: var Outer
  
var o = Outer(value: 1234)
var v = Inner(owner: o).owner.value
doAssert v == 1234

block: # bug #21674
  type
    Lent = object
      data: lent int

  proc foo(s: Lent) =
    var m = 12
    discard cast[lent int](m)

  proc main =
    var m1 = 123
    var x = Lent(data: m1)
    foo(x)

  main()

block: # bug #22117
  proc main: int =
    var a = 10
    defer: discard a # extend a's lifetime

    var aref: var int = a
      #└──── 'aref' borrows from location 'a' which does not live long enough

    result = aref

  doAssert main() == 10

type
  Slice*[T] = object
    first, last: int
    p: ptr UncheckedArray[T]

var i = 0

converter autoToOpenArray*[T](s: Slice[T]): openArray[T] =
  inc i
  result = toOpenArray(s.p, s.first, s.last)

proc acceptOpenArray(s: openArray[byte]) = discard

proc bug22597 = # bug #22597
  acceptOpenArray(Slice[byte]())
  doAssert i == 1

bug22597()

block: # bug #20048
  type
    Test = object
      tokens: openArray[string]

  func init(Self: typedesc[Test], tokens: openArray[string]): Self = Self(tokens: tokens)

  let data = Test.init(["123"])
  doAssert @(data.tokens) == @["123"] 
