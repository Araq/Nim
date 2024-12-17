discard """
  valgrind: true
  cmd: "nim c --gc:arc -d:useMalloc $file"
  output: '''myobj destroyed
myobj destroyed
myobj destroyed
A
B
begin
end
prevented
(ok: true, value: "ok")
myobj destroyed
'''
"""

# bug #13102

type
  D = ref object
  R = object
    case o: bool
    of false:
      discard
    of true:
      field: D

iterator things(): R =
  when true:
    var
      unit = D()
    while true:
      yield R(o: true, field: unit)
  else:
    while true:
      var
        unit = D()
      yield R(o: true, field: unit)

proc main =
  var i = 0
  for item in things():
    discard item.field
    inc i
    if i == 2: break

main()

# bug #13149

type
  TMyObj = object
    p: pointer
    len: int

proc `=destroy`(o: var TMyObj) =
  if o.p != nil:
    dealloc o.p
    o.p = nil
    echo "myobj destroyed"

proc `=copy`(dst: var TMyObj, src: TMyObj) =
  `=destroy`(dst)
  dst.p = alloc(src.len)
  dst.len = src.len

proc `=sink`(dst: var TMyObj, src: TMyObj) =
  `=destroy`(dst)
  dst.p = src.p
  dst.len = src.len

type
  TObjKind = enum Z, A, B
  TCaseObj = object
    case kind: TObjKind
    of Z: discard
    of A:
      x1: int # this int plays important role
      x2: TMyObj
    of B:
      y: TMyObj

proc testSinks: TCaseObj =
  result = TCaseObj(kind: A, x1: 5000, x2: TMyObj(len: 5, p: alloc(5)))
  result = TCaseObj(kind: B, y: TMyObj(len: 3, p: alloc(3)))

proc use(x: TCaseObj) = discard

proc testCopies(i: int) =
  var a: array[2, TCaseObj]
  a[i] = TCaseObj(kind: A, x1: 5000, x2: TMyObj(len: 5, p: alloc(5)))
  a[i+1] = a[i] # copy, cannot move
  use(a[i])

let x1 = testSinks()
testCopies(0)

# bug #12957

type
  PegKind* = enum
    pkCharChoice,
    pkSequence
  Peg* = object ## type that represents a PEG
    case kind: PegKind
    of pkCharChoice: charChoice: ref set[char]
    else: discard
    sons: seq[Peg]

proc charSet*(s: set[char]): Peg =
  ## constructs a PEG from a character set `s`
  result = Peg(kind: pkCharChoice)
  new(result.charChoice)
  result.charChoice[] = s

proc len(a: Peg): int {.inline.} = return a.sons.len
proc myadd(d: var Peg, s: Peg) {.inline.} = add(d.sons, s)

proc sequence*(a: openArray[Peg]): Peg =
  result = Peg(kind: pkSequence, sons: @[])
  when false:
    #works too:
    result.myadd(a[0])
    result.myadd(a[1])
  for x in items(a):
    # works:
    #result.sons.add(x)
    # fails:
    result.myadd x
  if result.len == 1:
    result = result.sons[0] # this must not move!

when true:
  # bug #12957

  proc p =
    echo "A"
    let x = sequence([charSet({'a'..'z', 'A'..'Z', '_'}),
              charSet({'a'..'z', 'A'..'Z', '0'..'9', '_'})])
    echo "B"
  p()

  proc testSubObjAssignment =
    echo "begin"
    # There must be extactly one element in the array constructor!
    let x = sequence([charSet({'a'..'z', 'A'..'Z', '_'})])
    echo "end"
  testSubObjAssignment()


#------------------------------------------------

type
  MyObject = object
    x1: string
    case kind1: bool
      of false: y1: string
      of true:
          y2: seq[string]
          case kind2: bool
              of true: z1: string
              of false:
                z2: seq[string]
                flag: bool
    x2: string

proc test_myobject =
  var x: MyObject = MyObject()
  x.x1 = "x1"
  x.x2 = "x2"
  x.y1 = "ljhkjhkjh"
  {.cast(uncheckedAssign).}:
    x.kind1 = true
  x.y2 = @["1", "2"]
  {.cast(uncheckedAssign).}:
    x.kind2 = true
  x.z1 = "yes"
  {.cast(uncheckedAssign).}:
    x.kind2 = false
  x.z2 = @["1", "2"]
  {.cast(uncheckedAssign).}:
    x.kind2 = true
  x.z1 = "yes"
  x.kind2 = true # should be no effect
  doAssert(x.z1 == "yes")
  {.cast(uncheckedAssign).}:
    x.kind2 = false
    x.kind1 = x.kind2 # support self assignment with effect

  try:
    x.kind1 = x.flag # flag is not accesible
  except FieldDefect:
    echo "prevented"

  doAssert(x.x1 == "x1")
  doAssert(x.x2 == "x2")


test_myobject()


#------------------------------------------------
# bug #14244

type
  RocksDBResult*[T] = object
    case ok*: bool
    of true:
      value*: T
    else:
      error*: string

proc init(): RocksDBResult[string] =
  result = default(RocksDBResult[string])
  {.cast(uncheckedAssign).}:
    result.ok = true
  result.value = "ok"

echo init()


#------------------------------------------------
# bug #14312

type MyObj = object
  case kind: bool
    of false: x0: int # would work with a type like seq[int]; value would be reset
    of true: x1: string

var a = MyObj(kind: false, x0: 1234)
{.cast(uncheckedAssign).}:
  a.kind = true
doAssert(a.x1 == "")

block:
  # bug #15532
  type Kind = enum
    k0, k1

  type Foo = object
    y: int
    case kind: Kind
    of k0: x0: int
    of k1: x1: int

  const j0 = Foo(y: 1, kind: k0, x0: 2)
  const j1 = Foo(y: 1, kind: k1, x1: 2)

  doAssert j0.y == 1
  doAssert j0.kind == k0
  doAssert j1.kind == k1

  doAssert j1.x1 == 2
  doAssert j0.x0 == 2
