discard """
  cmd: "nim c --gc:arc $file"
  output: '''
hello
hello
@["a", "b"]
---------------------
plain:
destroying: ('first', 42)
destroying: ('second', 20)
destroying: ('third', 12)

Option[T]:
destroying: ('first', 42)
destroying: ('second', 20)
destroying: ('third', 12)

seq[T]:
destroying: ('first', 42)
destroying: ('second', 20)
destroying: ('third', 12)

1 1
'''
"""

import dmodule

var val = parseMinValue()
if val.kind == minDictionary:
  echo val

#------------------------------------------------------------------------------
# Issue #15238
#------------------------------------------------------------------------------

proc sinkArg(x: sink seq[string]) =
  discard

proc varArg(lst: var seq[string]) = 
  sinkArg(lst)

var x = @["a", "b"]
varArg(x)
echo x


#------------------------------------------------------------------------------
# Issue #15286
#------------------------------------------------------------------------------

import std/os
discard getFileInfo(".")


#------------------------------------------------------------------------------
# Issue #15707
#------------------------------------------------------------------------------

type
  JVMObject = ref object
proc freeJVMObject(o: JVMObject) =
  discard
proc fromJObject(T: typedesc[JVMObject]): T =
  result.new(cast[proc(r: T) {.nimcall.}](freeJVMObject))

discard JVMObject.fromJObject()


#------------------------------------------------------------------------------
# Issue #15910
#------------------------------------------------------------------------------

import options

type
  Thing = object
    name: string
    age: int

proc `=destroy`(thing: var Thing) =
  if thing.name != "":
    echo "destroying: ('", thing.name, "', ", thing.age, ")"
  `=destroy`(thing.name)
  `=destroy`(thing.age)

proc plain() =
  var t = Thing(name: "first", age: 42)
  t = Thing(name: "second", age: 20)
  t = Thing()
  let u = Thing(name: "third", age: 12)

proc optionT() =
  var t = Thing(name: "first", age: 42).some
  t = Thing(name: "second", age: 20).some
  t = none(Thing)
  let u = Thing(name: "third", age: 12).some

proc seqT() =
  var t = @[Thing(name: "first", age: 42)]
  t = @[Thing(name: "second", age: 20)]
  t = @[]
  let u = @[Thing(name: "third", age: 12)]

echo "---------------------"
echo "plain:"
plain()
echo()

echo "Option[T]:"
optionT()
echo()

echo "seq[T]:"
seqT()
echo()


#------------------------------------------------------------------------------
# Issue #16120, const seq into sink
#------------------------------------------------------------------------------

proc main =
  let avals = @[@[1.0'f32, 4.0, 7.0, 10.0]]
  let rankdef = avals
  echo avals.len, " ", rankdef.len

main()


#------------------------------------------------------------------------------
# Issue #16722, ref on distinct type, wrong destructors called
#------------------------------------------------------------------------------

type
  Obj = object of RootObj
  ObjFinal = object
  ObjRef = ref Obj
  ObjFinalRef = ref ObjFinal
  D = distinct Obj
  DFinal = distinct ObjFinal
  DRef = ref D
  DFinalRef = ref DFinal

proc `=destroy`(o: var Obj) =
  doAssert false, "no Obj is constructed in this sample"

proc `=destroy`(o: var ObjFinal) =
  doAssert false, "no ObjFinal is constructed in this sample"

var dDestroyed: int
proc `=destroy`(d: var D) =
  dDestroyed.inc

proc `=destroy`(d: var DFinal) =
  dDestroyed.inc

func newD(): DRef =
  DRef ObjRef()

func newDFinal(): DFinalRef =
  DFinalRef ObjFinalRef()

proc testRefs() =
  discard newD()
  discard newDFinal()

testRefs()

doAssert(dDestroyed == 2)


#------------------------------------------------------------------------------
# Issue #16185, complex self-assingment elimination
#------------------------------------------------------------------------------

type
  CpuStorage*[T] = ref CpuStorageObj[T]
  CpuStorageObj[T] = object
    size*: int
    raw_buffer*: ptr UncheckedArray[T]
  Tensor[T] = object
    buf*: CpuStorage[T]
  TestObject = object
    x: Tensor[float]

proc `=destroy`[T](s: var CpuStorageObj[T]) =
  if s.raw_buffer != nil:
    s.raw_buffer.deallocShared()
    s.size = 0
    s.raw_buffer = nil

proc `=`[T](a: var CpuStorageObj[T]; b: CpuStorageObj[T]) {.error.}

proc allocCpuStorage[T](s: var CpuStorage[T], size: int) =
  new(s)
  s.raw_buffer = cast[ptr UncheckedArray[T]](allocShared0(sizeof(T) * size))
  s.size = size

proc newTensor[T](size: int): Tensor[T] =
  result = default(Tensor[T])
  allocCpuStorage(result.buf, size)

proc `[]`[T](t: Tensor[T], idx: int): T = t.buf.raw_buffer[idx]
proc `[]=`[T](t: Tensor[T], idx: int, val: T) = t.buf.raw_buffer[idx] = val

proc toTensor[T](s: seq[T]): Tensor[T] =
  result = newTensor[T](s.len)
  for i, x in s:
    result[i] = x

proc main2() =
  var t: TestObject = TestObject()
  t.x = toTensor(@[1.0, 2, 3, 4])
  t.x = t.x  
  doAssert(t.x.buf != nil) # self-assignment above should be eliminated

main2()
