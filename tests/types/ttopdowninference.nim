block:
  var s: seq[string] = (discard; @[])

  var x: set[char] =
    if true:
      try:
        case 1
        of 1:
          if false:
            {'4'}
          else:
            block:
              s.add "a"
              {}
        else: {'3'}
      except: {'2'}
    else: {'1'}
  doAssert x is set[char]
  doAssert x == {}
  doAssert s == @["a"]

  x = {'a', 'b'}
  doAssert x == {'a', 'b'}

  x = (s.add "b"; {})
  doAssert x == {}
  doAssert s == @["a", "b"]

  let x2: set[byte] = {1}
  doAssert x2 == {1u8}

block:
  let x3: array[0..2, byte] = [1, 2, 3]
  #let x4: openarray[byte] = [1, 2, 3]
  #let x5: openarray[byte] = @[1, 2, 3]
  let x6: seq[byte] = @[1, 2, 3]
  let x7: seq[seq[float32]] = @[@[1, 2, 3], @[4.3, 5, 6]]
  type ABC = enum a, b, c
  let x8: array[ABC, byte] = [1, 2, 3]
  doAssert x8[a] == 1
  doAssert x8[a] + x8[b] == x8[c]

  const x9: array[-2..2, float] = [0, 1, 2, 3, 4]
  let x10: array[ABC, byte] = block:
    {.gcsafe.}:
      [a: 1, b: 2, c: 3]
  proc `@`(x: float): float = x + 1
  doAssert @1 == 2
  let x11: seq[byte] = system.`@`([1, 2, 3])

block:
  type Foo = object
    x: BiggestInt
  var foo: Foo
  foo.x = case true
  of true: ord(1)
  else: 0
  foo.x = if true: ord(1) else: 0

block:
  type Foo = object
    x: (float, seq[(byte, seq[byte])])
    
  let foo = Foo(x: (1, @{2: @[], 3: @[4, 5]}))
  doAssert foo.x == (1.0, @{2u8: @[], 3u8: @[4u8, 5]})

block:
  type Foo = object
    x: tuple[a: float, b: seq[(byte, seq[byte])]]
    
  let foo = Foo(x: (a: 1, b: @{2: @[3, 4], 5: @[]}))
  doAssert foo.x == (1.0, @{2u8: @[3u8, 4], 5u8: @[]})

block:
  proc foo(): seq[float] = @[1]

  let fooLamb = proc(): seq[float] = @[1]

  doAssert foo() == fooLamb()

block:
  type Foo[T] = float32

  let x: seq[Foo[int32]] = @[1]

block:
  type Foo = ref object
  type Bar[T] = ptr object

  let x1: seq[Foo] = @[nil]
  let x2: seq[Bar[int]] = @[nil]
  let x3: seq[cstring] = @[nil]

block:
  let x: seq[cstring] = @["abc", nil, "def"]
  doAssert x.len == 3
  doAssert x[0] == cstring"abc"
  doAssert x[1].isNil
  doAssert x[2] == "def".cstring

block:
  type Foo = object
    x: tuple[a: float, b: seq[(byte, seq[cstring])]]
    
  let foo = Foo(x: (a: 1, b: @{2: @[nil, "abc"]}))
  doAssert foo.x == (1.0, @{2u8: @[cstring nil, cstring "abc"]})

block:
  type Foo = object
    x: tuple[a: float, b: seq[(byte, seq[ptr int])]]
    
  let foo = Foo(x: (a: 1, b: @{2: @[nil, nil]}))
  doAssert foo.x == (1.0, @{2u8: @[(ptr int)(nil), nil]})

when false: # unsupported
  block: # type conversion
    let x = seq[(cstring, float32)](@{"abc": 1.0, "def": 2.0})
    doAssert x[0] == (cstring"abc", 1.0'f32)
    doAssert x[1] == (cstring"def", 2.0'f32)

block: # enum
  type Foo {.pure.} = enum a
  type Bar {.pure.} = enum a, b, c

  var s: seq[Bar] = @[a, b, c]

block: # overload selection
  proc foo(x, y: int): int = x + y + 1
  proc foo(x: int): int = x - 1
  var s: seq[proc (x, y: int): int] = @[nil, foo, foo]
  var s2: seq[int]
  for a in s:
    if not a.isNil: s2.add(a(1, 2))
  doAssert s2 == @[4, 4]

block: # with generics?
  proc foo(x, y: int): int = x + y + 1
  proc foo(x: int): int = x - 1
  proc bar[T](x, y: T): T = x - y
  var s: seq[proc (x, y: int): int] = @[nil, foo, foo, bar]
  var s2: seq[int]
  for a in s:
    if not a.isNil: s2.add(a(1, 2))
  doAssert s2 == @[4, 4, -1]
  proc foo(x, y: float): float = x + y + 1.0
  var s3: seq[proc (x, y: float): float] = @[nil, foo, foo, bar]
  var s4: seq[float]
  for a in s3:
    if not a.isNil: s4.add(a(1, 2))
  doAssert s4 == @[4.0, 4, -1]

block: # range types
  block:
    let x: set[range[1u8..5u8]] = {1, 3}
    doAssert x == {range[1u8..5u8](1), 3}
    doAssert $x == "{1, 3}"
  block:
    let x: seq[set[range[1u8..5u8]]] = @[{1, 3}]
    doAssert x == @[{range[1u8..5u8](1), 3}]
    doAssert $x[0] == "{1, 3}"
  block:
    let x: seq[range[1u8..5u8]] = @[1, 3]
    doAssert x == @[range[1u8..5u8](1), 3]
    doAssert $x == "@[1, 3]"
  block: # already worked before, make sure it still works
    let x: set[range['a'..'e']] = {'a', 'c'}
    doAssert x == {range['a'..'e']('a'), 'c'}
    doAssert $x == "{'a', 'c'}"
  block: # extended
    let x: seq[set[range['a'..'e']]] = @[{'a', 'c'}]
    doAssert x[0] == {range['a'..'e']('a'), 'c'}
    doAssert $x == "@[{'a', 'c'}]"
  block:
    type Foo = object
      x: (range[1u8..5u8], seq[(range[1f32..5f32], seq[range['a'..'e']])])
      
    let foo = Foo(x: (1, @{2: @[], 3: @['c', 'd']}))
    doAssert foo.x == (range[1u8..5u8](1u8), @{range[1f32..5f32](2f32): @[], 3f32: @[range['a'..'e']('c'), 'd']})
  block:
    type Foo = object
      x: (range[1u8..5u8], seq[(range[1f32..5f32], seq[set[range['a'..'e']]])])
      
    let foo = Foo(x: (1, @{2: @[], 3: @[{'c', 'd'}]}))
    doAssert foo.x == (range[1u8..5u8](1u8), @{range[1f32..5f32](2f32): @[], 3f32: @[{range['a'..'e']('c'), 'd'}]})

block: # templates
  template foo: untyped = (1, 2, "abc")
  let x: (float, byte, cstring) = foo()
  doAssert x[0] == float(1)
  doAssert x[1] == byte(2)
  doAssert x[2] == cstring("abc")
  let (a, b, c) = x
  doAssert a == float(1)
  doAssert b == byte(2)
  doAssert c == cstring("abc")


proc foo(): set[char] = # bug #11259
  discard "a"
  {}

discard foo()

block: # bug #11085
  const ok1: set[char] = {}
  var ok1b: set[char] = {}

  const ok2: set[char] = block:
    {}

  const ok3: set[char] = block:
    var x: set[char] = {}
    x
  var ok3b: set[char] = block:
    var x: set[char] = {}
    x

  var bad: set[char] = block:
    {}

# bug #6213
block:
  block:
    type MyEnum = enum a, b
    type MyTuple = tuple[x: set[MyEnum]]

    var myVar: seq[MyTuple] = @[ (x: {}) ]
    doAssert myVar.len == 1

  block:
    type
      Foo = tuple
        f: seq[string]
        s: string

    proc e(): seq[Foo] =
      return @[
        (@[], "asd")
      ]

    doAssert e()[0].f == @[]

block: # bug #11777
  type S = set[0..5]
  var s: S = {1, 2}
  doAssert 1 in s

block: # bug #20807
  var s: seq[string]
  template fail =
    s = @[]
  template test(body: untyped) =
    body
  proc test(a: string) = discard
  test: fail()
  doAssert not (compiles do:
    let x: seq[int] = `@`[string]([]))

block: # bug #21377
  proc b[T](v: T): seq[int] =
    let x = 0
    @[]

  doAssert b(0) == @[]

block: # bug #21377
  proc b[T](v: T): seq[T] =
    let x = 0
    @[]

  doAssert b(0) == @[]

block: # bug #21377
  proc b[T](v: T): set[bool] =
    let x = 0
    {}

  doAssert b(0) == {}

block: # bug #21377
  proc b[T](v: T): array[0, int] =
    let x = 0
    []

  doAssert b(0) == []

block: # bug #21377
  proc b[T](v: T): array[0, (string, string)] =
    let x = 0
    {:}

  doAssert b(0) == {:}

block: # bug #22180
  type A = object
  proc j() = discard

  let x =
    if false:
      (ref A)(nil)
    else:
      if false:
        quit 1
      else:
        if true:
          j()
          nil  # compiles with (ref A)(nil) here
        else:
          (ref A)(nil)
  doAssert x.isNil
  
  let y =
    case true
    of false:
      (ref A)(nil)
    else:
      case true
      of false:
        quit 1
      else:
        case true
        of true:
          j()
          nil  # compiles with (ref A)(nil) here
        else:
          (ref A)(nil)
  doAssert y.isNil

block: # issue #24164, related regression
  proc foo(x: proc ()) = discard
  template bar(x: untyped = nil) =
    foo(x)
  bar()

block: # bug #24296
  # Either changing the template to `proc`/`func` or using `$""`, not a string
  # literal alone, allows any version of Nim 2.x to compile this.
  template g(): string = ""

  # Alternatively: don't retrieve the string through g(), but directly, also
  # allows compilation across Nim 2.x versions.
  const d: cstring = ""
  const f: cstring = $""
  const b = cstring g()
  const m = cstring ""
  const p = cstring $""

  # But this does not compile across Nim 2.x/devel.
  const c: cstring = g()
  let e: cstring = g()

block: # bug #24295
  template g(_: int): string = ""
  const c: cstring = 0.g()

