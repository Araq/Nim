discard """
  targets: "c cpp"
"""

# bug #19094
type
  X = object
    filler: array[2048, int]
    innerAddress: uint

proc initX(): X =
  result.innerAddress = cast[uint](result.addr)

proc initXInPlace(x: var X) =
  x.innerAddress = cast[uint](x.addr)

block: # NRVO1
  var x = initX()
  let innerAddress = x.innerAddress
  let outerAddress = cast[uint](x.addr)
  doAssert(innerAddress == outerAddress) # [OK]

block: # NRVO2
  var x: X
  initXInPlace(x)
  let innerAddress = x.innerAddress
  let outerAddress = cast[uint](x.addr)
  doAssert(innerAddress == outerAddress) # [OK]

block: # bug #22354
  type Object = object
    foo: int

  proc takeFoo(self: var Object): int =
    result = self.foo
    self.foo = 999

  proc doSomething(self: var Object; foo: int = self.takeFoo()) =
    discard

  proc main() =
    var obj = Object(foo: 2)
    obj.doSomething()
    doAssert obj.foo == 999


  main()

proc main = # bug #24677
  let NULL = 1
  doAssert NULL == 1

  var COMMA = 1
  doAssert COMMA == 1

  for NDEBUG in 0..2:
    doAssert NDEBUG == NDEBUG
main()
