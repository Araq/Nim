discard """
  targets: "c js"
"""

block:
  type
    hasFieldX = concept z
      z.x is int

    obj_x = object
      x: int

    ref_obj_x = ref object
      x: int

    ref_to_obj_x = ref obj_x

    p_o_x = ptr obj_x
    v_o_x = var obj_x

  template check(x) =
    static: assert(x)

  check obj_x is hasFieldX
  check ref_obj_x is hasFieldX
  check ref_to_obj_x is hasFieldX
  check p_o_x is hasFieldX
  check v_o_x is hasFieldX

block:
  type
    Foo = concept x
      x.isFoo
    Bar = distinct float
  template isFoo(x: Bar): untyped = true
  proc foo(x: var Foo) =
    float(x) = 1.0
  proc foo2(x: var Bar) =
    float(x) = 1.0
  proc foo3(x: var (Bar|SomeNumber)) =
    float(x) = 1.0
  proc foo4(x: var any) =
    float(x) = 1.0
  var x: Bar
  foo(x)
  foo2(x)
  foo3(x)
  foo4(x)

block: # bug #9550
  block:
    type Foo = concept c
      for v in c: (v is char)

    func foo(c: Foo) = (for v in c: discard)
    foo @['a', 'b' ,'c']

  block:
    type Foo = concept c
      for v in c: (v is char)

    func foo(c: Foo) = (for v in c: discard)
    foo ['a', 'b' ,'c']
