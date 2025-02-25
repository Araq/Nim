proc mutate(a: var openarray[int]) =
  var i = 0
  for x in a.mitems:
    x = i
    inc i

proc mutate(a: var openarray[char]) =
  var i = 1
  for ch in a.mitems:
    ch = 'a'


static:
  var a = [10, 20, 30]
  assert a.toOpenArray(1, 2).len == 2

  mutate(a)
  assert a.toOpenArray(0, 2) == [0, 1, 2]
  assert a.toOpenArray(0, 0) == [0]
  assert a.toOpenArray(1, 2) == [1, 2]
  assert "Hello".toOpenArray(1, 4) == "ello"
  var str = "Hello"
  str.toOpenArray(2, 4).mutate()
  assert str.toOpenArray(0, 4).len == 5
  assert str.toOpenArray(0, 0).len == 1
  assert str.toOpenArray(0, 0).high == 0
  assert str == "Heaaa"
  assert str.toOpenArray(0, 4) == "Heaaa"

  var arr: array[3..4, int] = [1, 2]
  assert arr.toOpenArray(3, 4) == [1, 2]
  assert arr.toOpenArray(3, 4).len == 2
  assert arr.toOpenArray(3, 3).high == 0

  assert arr.toOpenArray(3, 4).toOpenArray(0, 0) == [1]


proc doThing(s: static openArray[int]) = discard

doThing([10, 20, 30].toOpenArray(0, 0))

# bug #19969
proc f(): array[1, byte] =
  var a: array[1, byte]
  result[0..0] = a.toOpenArray(0, 0)

doAssert static(f()) == [byte(0)]


# bug #15952
proc main1[T](a: openArray[T]) = discard
proc main2[T](a: var openArray[T]) = discard

proc main =
  var a = [1,2,3,4,5]
  main1(a.toOpenArray(1,3))
  main2(a.toOpenArray(1,3))
static: main()
main()

# bug #16306
{.experimental: "views".}
proc test(x: openArray[int]): tuple[id: int] =
  let y: openArray[int] = toOpenArray(x, 0, 2)
  result = (y[0],)
template fn=
  doAssert test([0,1,2,3,4,5]).id == 0
fn() # ok
static: fn()


block: # bug #22095
  type
    StUint = object
      limbs: array[4, uint64]

  func shlAddMod(a: var openArray[uint64]) =  
    a[0] = 10

  func divRem(r: var openArray[uint64]) =
    shlAddMod(r.toOpenArray(0, 3))

  func fn(): StUint =
    divRem(result.limbs)

  const
    z = fn()

  doAssert z.limbs[0] == 10

block: # bug #24630
  func f(a: static openArray[int]): int =
    12

  func g(a: static openArray[int]) =
    const b = f(a)

  g(@[1,2,3])
