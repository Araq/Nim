discard """
  targets: "c cpp"
  matrix: "--mm:refc; --mm:arc"
"""

# bug #7308
proc foo(x: seq[int32]) =
  var y = newSeq[cint](1)

proc bar =
  var t = newSeq[int32](1)
  foo(t)

bar()


# bug #16246

proc testWeirdTypeAliases() =
  var values = newSeq[cuint](8)
  # var values: seq[cuint] does not produce codegen error
  var drawCb = proc(): seq[uint32] =
    result = newSeq[uint32](10)

testWeirdTypeAliases()

block: # bug #11797
  block:
    type cdouble2 = cdouble
    type Foo1 = seq[cdouble]
    type Foo2 = seq[cdouble2]
    static: doAssert Foo1 is Foo2
    var a1: Foo1
    var a2: Foo2
    doAssert a1 == @[]
    doAssert a2 == @[]

  block:
    proc foo[T: int|cint](fun: proc(): T) = discard
    proc foo1(): cint = 1
    proc foo3(): int32 = 2
    foo(proc(): cint = foo1())
    foo(proc(): int32 = foo3())


block: # bug #24604
  type MyType {.importc, incompleteStruct.} = object
  var v {.exportc.}: ptr MyType
