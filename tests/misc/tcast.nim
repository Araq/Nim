discard """
  output: '''
Hello World
Hello World
Hello World'''
  joinable: false
"""
type MyProc = proc() {.cdecl.}
type MyProc2 = proc() {.nimcall.}
type MyProc3 = proc() #{.closure.} is implicit

proc testProc() {.exportc:"foo".} = echo "Hello World"

template reject(x) = doAssert(not compiles(x))

proc callPointer(p: pointer) =
  # can cast to proc(){.cdecl.}
  let ffunc0 = cast[MyProc](p)
  # can cast to proc(){.nimcall.}
  let ffunc1 = cast[MyProc2](p)
  # cannot cast to proc(){.closure.}
  reject: cast[MyProc3](p)

  ffunc0()
  ffunc1()

    # bug #5901
  proc foo() {.importc.}
  (cast[proc(a: int) {.cdecl.}](foo))(5)

callPointer(cast[pointer](testProc))

reject: discard cast[enum](0)
proc a = echo "hi"

reject: discard cast[ptr](a)

# bug #15623
block:
  if false:
    let x = cast[ptr int](nil)
    echo x[]

block:
  if false:
    var x: ref int = nil
    echo cast[ptr int](x)[]

block:
  doAssert cast[int](cast[ptr int](nil)) == 0

block:
  var x: ref int = nil
  doAssert cast[int](cast[ptr int](x)) == 0

block: # cast of nil
  block:
    static:
      let a = cast[pointer](nil)
      doAssert a.repr == "nil"

  block:
    static:
      doAssert cast[ptr int](nil).repr == "nil"

  block:
    const str = cast[ptr int](nil)
    static:
      doAssert str.repr == "nil"

  block:
    static:
      doAssert cast[ptr int](nil).repr == "nil"

  block:
    static:
      doAssert cast[RootRef](nil).repr == "nil"

  when false: # xxx bug #15730, not fixed yet
    block:
      static:
        doAssert cast[cstring](nil).repr == "nil"

template main() =
  # xxx move all under here to get tested in VM
  block: # cast of enum
    type Koo = enum k1, k2
    type Goo = enum g1, g2
    type Boo = enum b1 = -1, b2, b3, b4
    type Coo = enum c1 = -1i8, c2, c3, c4
    when nimvm:
      # xxx: Error: VM does not support 'cast' from tyEnum to tyEnum
      discard
    else:
      doAssert cast[Koo](k2) == k2
      doAssert cast[Goo](k2) == g2
      doAssert cast[Goo](k2.ord) == g2

      doAssert b3.ord == 1
      doAssert cast[Koo](b3) == k2
      doAssert cast[Boo](k2) == b3

      doAssert c3.ord == 1
      doAssert cast[Koo](c3) == k2
      doAssert cast[Coo](k2) == c3

static: main()
main()
