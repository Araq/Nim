block: # bug #15526
  block:
    type Foo = ref object
      x1: int
    let f1 = Foo(x1: 1)
  block:
    type Foo = ref object
      x2: int
    let f2 = Foo(x2: 2)

block: # ditto
  template fn() =
    block:
      type Foo = ref object
        x1: int
      let f1 = Foo(x1: 1)
      doAssert f1.x1 == 1
    block:
      type Foo = ref object
        x2: int
      let f2 = Foo(x2: 2)
      doAssert f2.x2 == 2
  static: fn()
  fn()

block: # bug #17162
  template fn =
    var ret: string
    block:
      type A = enum a0, a1, a2
      for ai in A:
        ret.add $ai
    block:
      type A = enum b0, b1, b2, b3
      for ai in A:
        ret.add $ai
    doAssert ret == "a0a1a2b0b1b2b3"

  static: fn() # ok
  fn() # was bug

block: # ditto
  proc fn =
    var ret: string
    block:
      type A = enum a0, a1, a2
      for ai in A:
        ret.add $ai
    block:
      type A = enum b0, b1, b2, b3
      for ai in A:
        ret.add $ai
    doAssert ret == "a0a1a2b0b1b2b3"

  static: fn() # ok
  fn() # was bug

block: # bug #5170
  block:
    type Foo = object
      x1: int
    let f1 = Foo(x1: 1)
  block:
    type Foo = object
      x2: int
    let f2 = Foo(x2: 2)

block: # ditto
  block:
    type Foo = object
      bar: bool
    var f1: Foo

  block:
    type Foo = object
      baz: int
    var f2: Foo
    doAssert f2.baz == 0

  block:
    template fn() =
      block:
        type Foo = object
          x1: int
        let f1 = Foo(x1: 1)
        doAssert f1.x1 == 1
      block:
        type Foo = object
          x2: int
        let f2 = Foo(x2: 2)
        doAssert f2.x2 == 2
    static: fn()
    fn()

when true: # ditto, refs https://github.com/nim-lang/Nim/issues/5170#issuecomment-582712132
  type Foo1 = object # at top level
    bar: bool
  var f1: Foo1

  block:
    type Foo1 = object
      baz: int
    var f2: Foo1
    doAssert f2.baz == 0

block: # make sure `hashType` doesn't recurse infinitely
  type
    PFoo = ref object
      a, b: PFoo
      c: int
  var a: PFoo

block: # issue #22571
  macro foo(x: typed) =
    result = x

  block: # or `proc main =`
    foo:
      type Foo = object
    doAssert $Foo() == "()"

block: # bug #7784
  block:
    type
        Color = enum clrBlack, clrRed, clrGreen, clrBlue

    var color = clrRed
    doAssert(ord(color) == 1)
    doAssert($color == "clrRed")

  block:
    type
        Color = enum
          clrBlack = "Black",
          clrRed = "Red",
          clrGreen = "Green",
          clrBlue = "Blue"

    var color = clrRed
    doAssert(ord(color) == 1)
    doAssert($color == "Red")
