# issue #20073

type Foo = object
proc foo(f: Foo) = discard

template works*() =
  var f: Foo
  foo(f)

template boom*() =
  var f: Foo
  f.foo() # Error: attempting to call undeclared routine: 'foo'
  f.foo # Error: undeclared field: 'foo' for type a.Foo

# issue #7085

proc bar(a: string): string =
  return a & "bar"

template baz*(a: string): string =
  var b = a.bar()
  b

# issue #7223

import mdotcall2

type
  Bytes* = seq[byte]
  
  BytesRange* = object
    bytes*: Bytes
    ibegin*, iend*: int

proc privateProc(r: BytesRange): int = r.ibegin

template rangeBeginAddr*(r: BytesRange): pointer =
  r.bytes.baseAddr.shift(r.privateProc)

# issue #11733

type ObjA* = object

proc foo2(o: var ObjA) = discard
proc bar2(o: var ObjA, arg: Natural) = discard

template publicTemplateObjSyntax*(o: var ObjA, arg: Natural, doStuff: untyped) =
  o.foo2()
  doStuff
  o.bar2(arg)

# issue #15246
import os

template sourceBaseName*(): string =
  bind splitFile
  instantiationInfo().filename.splitFile().name

# issue #12683

import unicode
template toRune(s: string): Rune = s.runeAt(0)
proc heh*[T](x: Slice[T], chars: string) = discard chars.toRune

# issue #7889

from streams import newStringStream, readData, writeData

template bindmeTemplate*(): untyped =
  var tst = "sometext"
  var ss = newStringStream("anothertext")
  ss.writeData(tst[0].addr, 2)
  discard ss.readData(tst[0].addr, 2) # <= comment this out to make compilation successful

from macros import quote, newIdentNode

macro bindmeQuote*(): untyped =
  quote do:
    var tst = "sometext"
    var ss = newStringStream("anothertext")
    ss.writeData(tst[0].addr, 2)
    discard ss.readData(tst[0].addr, 2) # <= comment this out to make compilation successful

# issue #14894

proc myProc(s: string) = discard

template myTemplate* =
  "".myProc
