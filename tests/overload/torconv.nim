block:
  proc foo(x: int16 | int32): string = $typeof(x)
  proc bar[T: int16 | int32](x: T): string = $typeof(x)

  doAssert foo(123) == "int16"
  doAssert bar(123) == "int16"

block: # issue #4858
  type
    SomeType = object
      field1: uint

  proc namedProc(an: var SomeType, b: SomeUnsignedInt) = discard

  proc `+=`(an: var SomeType, b: SomeUnsignedInt) =
    namedProc(an, b) # <---- error here

  var t = SomeType()
  namedProc(t, 0)
  t += 0

block: # issue #10027
  type Uint24 = range[0'u32 .. 0xFFFFFF'u32]

  proc a(v: SomeInteger|Uint24): string = $type(v)

  doAssert a(42) == "int"
  doAssert a(42.Uint24) == $Uint24

block: # issue #12552
  let x = 1'i8
  proc foo(n : int): string = $typeof(n)
  proc bar[T : int](n : T): string = $ typeof(n)
  doAssert foo(x) == "int"
  doAssert bar(x) == "int"

block: # issue #15721
  proc fn(a = 4, b: seq[string] or tuple[] = ()) =
    discard # eg: when b is tuple[]: ...
  fn(1)
  fn(1, @[""])
  var a: seq[string] = @[]
  fn(1, a)
  fn(1, seq[string](@[]))
  fn(1, @[]) # BUG: error: conflicting types for 'fn__d58I39cH9a6bcpi3QDPJ5dBA'

block: # issue #15721, set
  proc fn(a = 4, b: set[uint8] or tuple[] = ()) =
    discard # eg: when b is tuple[]: ...
  fn(1)
  fn(1, {1'u8})
  var a: set[uint8] = {}
  fn(1, a)
  fn(1, set[uint8]({}))
  fn(1, {}) # BUG: internal error: invalid kind for lastOrd(tyEmpty)

block: # issue #21331
  let a : int8 | uint8 = 3
  doAssert sizeof(a)==sizeof(int8) # this fails

block:
  let x: range[0..5] = 1
  proc foo[T: SomeInteger](x: T): string = $typeof(x)
  discard foo(x)
