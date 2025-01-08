discard """
output: "8\n8\n4"
"""

import
  macros, typetraits

template selectType(x: int): type =
  when x < 10:
    int
  else:
    string

template simpleTypeTempl: type =
  string

macro typeFromMacro: type = bindSym"string"

# The tests below check that the result variable of the
# selected type matches the literal types in the code:

proc t1*(x: int): simpleTypeTempl() =
  result = "test"

proc t2*(x: int): selectType(100) =
  result = "test"

proc t3*(x: int): selectType(1) =
  result = 10

proc t4*(x: int): typeFromMacro() =
  result = "test"

var x*: selectType(50) = "test"

proc t5*(x: selectType(5)) =
  var y = x + 10
  echo y

var y*: type(t2(100)) = "test"

proc t6*(x: type(t3(0))): type(t1(0)) =
  result = $x

proc t7*(x: int): type($x) =
  result = "test"

# This is a more complicated example involving a type
# selection through a macro:
# https://github.com/nim-lang/Nim/issues/7230

macro getBase*(bits: static[int]): untyped =
  if bits >= 128:
    result = newTree(nnkBracketExpr, ident("MpUintBase"), ident("uint64"))
  else:
    result = newTree(nnkBracketExpr, ident("MpUintBase"), ident("uint32"))

type
  BaseUint* = SomeUnsignedInt or MpUintBase

  MpUintBase*[T] = object
      lo*, hi*: T

  ## This gets type mismatch
  MpUint*[bits: static[int]] = getBase(bits)

var m1: MpUint[128]
var m2: MpUint[64]
var m3: getBase(32)

static:
  # assert m1.type.name == "MpUintBase[uint64]"
  assert m1.lo.type.name == "uint64"
  assert m2.lo.type.name == "uint32"
  assert m3.type.name == "MpUintBase[system.uint32]"

# https://github.com/nim-lang/Nim/issues/7379

import macros, typetraits

macro works(): untyped =
  result = getType(int64)

macro fails(bits: static[int]): untyped =
  if bits > 64:
    result = getType(int64)
  else:
    result = getType(int32)

type
  Foo*[bits: static[int]] = works()
  Bar*[bits: static[int]] = fails(bits)

var a: Foo[16]
var b: Bar[256]
var c: Bar[32]

echo sizeof(a)
echo sizeof(b)
echo sizeof(c)
