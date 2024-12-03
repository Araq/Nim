discard """
  output: '''
we
direct
generic
generic
'''
joinable: false
"""

import algorithm, sugar, sequtils, typetraits, asyncdispatch

block tconfusing_arrow:
  type Deck = object
    value: int

  proc sort(h: var seq[Deck]) =
    # works:
    h.sort(proc (x, y: Deck): auto =
      cmp(x.value, y.value))
    # fails:
    h.sort((x, y: Deck) => cmp(ord(x.value), ord(y.value)))

  var player: seq[Deck] = @[]
  player.sort()



block tdictdestruct:
  type
    TDict[TK, TV] = object
      k: TK
      v: TV
    PDict[TK, TV] = ref TDict[TK, TV]

  proc fakeNew[T](x: var ref T, destroy: proc (a: ref T) {.nimcall.}) =
    discard

  proc destroyDict[TK, TV](a: PDict[TK, TV]) =
      return
  proc newDict[TK, TV](a: TK, b: TV): PDict[TK, TV] =
      fakeNew(result, destroyDict[TK, TV])

  # Problem: destroyDict is not instantiated when newDict is instantiated!
  discard newDict("a", "b")



block tgenericdefaults:
  type
    TFoo[T, U, R = int] = object
      x: T
      y: U
      z: R

    TBar[T] = TFoo[T, array[4, T], T]

  var x1: TFoo[int, float]

  static:
    doAssert type(x1.x) is int
    doAssert type(x1.y) is float
    doAssert type(x1.z) is int

  var x2: TFoo[string, R = float, U = seq[int]]

  static:
    doAssert type(x2.x) is string
    doAssert type(x2.y) is seq[int]
    doAssert type(x2.z) is float

  var x3: TBar[float]

  static:
    doAssert type(x3.x) is float
    doAssert type(x3.y) is array[4, float]
    doAssert type(x3.z) is float



block tprop:
  type
    TProperty[T] = object of RootObj
      getProc: proc(property: TProperty[T]): T {.nimcall.}
      setProc: proc(property: TProperty[T], value: T) {.nimcall.}
      value: T

  proc newProperty[T](value: RootObj): TProperty[T] =
    result.getProc = proc (property: TProperty[T]) =
      return property.value



block trefs:
  type
    PA[T] = ref TA[T]
    TA[T] = object
      field: T
  var a: PA[string]
  new(a)
  a.field = "some string"

  proc someOther[T](len: string): seq[T] = discard
  proc someOther[T](len: int): seq[T] = echo "we"

  proc foo[T](x: T) =
    var s = someOther[T](34)
    #newSeq[T](34)

  foo 23

  when false:
    # Compiles unless you use var a: PA[string]
    type
      PA = ref TA
      TA[T] = object

    # Cannot instantiate:
    type
      TA[T] = object
        a: PA[T]
      PA[T] = ref TA[T]

    type
      PA[T] = ref TA[T]
      TA[T] = object



block tmap_auto:
  let x = map(@[1, 2, 3], x => x+10)
  doAssert x == @[11, 12, 13]

  let y = map(@[(1,"a"), (2,"b"), (3,"c")], x => $x[0] & x[1])
  doAssert y == @["1a", "2b", "3c"]

  proc eatsTwoArgProc[T,S,U](a: T, b: S, f: proc(t: T, s: S): U): U =
    f(a,b)

  let z = eatsTwoArgProc(1, "a", (t,s) => $t & s)
  doAssert z == "1a"



block tproctypecache_falsepositive:
  type
    Callback = proc() {.closure, gcsafe.}
    GameState = ref object
      playerChangeHandlers: seq[Callback]

  proc newGameState(): GameState =
    result = GameState(
      playerChangeHandlers: newSeq[Callback]() # this fails
    )



block tptrinheritance:
  type NSPasteboardItem = ptr object
  type NSPasteboard = ptr object
  type NSArrayAbstract {.inheritable.} = ptr object
  type NSMutableArrayAbstract = ptr object of NSArrayAbstract
  type NSArray[T] = ptr object of NSArrayAbstract
  type NSMutableArray[T] = ptr object of NSArray[T]

  proc newMutableArrayAbstract(): NSMutableArrayAbstract = discard

  template newMutableArray(T: typedesc): NSMutableArray[T] =
    cast[NSMutableArray[T]](newMutableArrayAbstract())

  proc writeObjects(p: NSPasteboard, o: NSArray[NSPasteboardItem]) = discard

  let a = newMutableArray NSPasteboardItem
  var x: NSMutableArray[NSPasteboardItem]
  var y: NSArray[NSPasteboardItem] = x

  writeObjects(nil, a)



block tsigtypeop:
  type Vec3[T] = array[3, T]

  proc foo(x: Vec3, y: Vec3.T, z: x.T): x.type.T =
    return 10

  var y: Vec3[int] = [1, 2, 3]
  var z: int = foo(y, 3, 4)



block tvarargs_vs_generics:
  proc withDirectType(args: string) =
    echo "direct"
  proc withDirectType[T](arg: T) =
    echo "generic"
  proc withOpenArray(args: openArray[string]) =
    echo "openArray"
  proc withOpenArray[T](arg: T) =
    echo "generic"
  proc withVarargs(args: varargs[string]) =
    echo "varargs"
  proc withVarargs[T](arg: T) =
    echo "generic"

  withDirectType "string"
  withOpenArray "string"
  withVarargs "string"

block:
  type
    Que[T] {.gcsafe.} = object
      x: T

  proc `=`[T](q: var Que[T]; x: Que[T]) =
    discard

  var x: Que[int]
  doAssert(x.x == 0)


# bug #4466
proc identity[T](t: T): T = t

proc doSomething[A, B](t: tuple[a: A, b: B]) = discard

discard identity((c: 1, d: 2))
doSomething(identity((1, 2)))

# bug #6231
proc myProc[T, U](x: T or U) = discard

myProc[int, string](x = 2)

block: # issue #8390
  proc x[T:SomeFloat](q: openarray[T], y: T = 1): string =
    doAssert $q.type == $openarray[y.type]
    $y.type

  doAssert x(@[1.0]) == $1.0.type


block: # issue #9381
  var evalCount {.compileTime.} = 0

  macro test(t: typed): untyped =
    inc evalCount
    t

  type GenericObj[T] = object
    f: test(T)

  var x: GenericObj[int]
  static: doAssert evalCount == 1
