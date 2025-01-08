discard """
  matrix: "--mm:arc"
"""

type AnObject = object of RootObj
  value*: int

proc mutate(shit: sink AnObject) =
  shit.value = 1

proc foo = # bug #23359
  var bar = AnObject(value: 42)
  mutate(bar)
  doAssert bar.value == 42

foo()

block: # bug #23902
  proc foo(a: sink string): auto = (a, a)

  proc bar(a: sink int): auto = return a

  proc foo(a: sink string) =
    var x = (a, a)

block: # bug #24175
  block:
    func mutate(o: sink string): string =
      o[1] = '1'
      result = o

    static:
      let s = "999"
      let m = mutate(s)
      doAssert s == "999"
      doAssert m == "919"

    func foo() =
      let s = "999"
      let m = mutate(s)
      doAssert s == "999"
      doAssert m == "919"

    static:
      foo()
    foo()

  block:
    type O = object
      a: int

    func mutate(o: sink O): O =
      o.a += 1
      o

    static:
      let x = O(a: 1)
      let y = mutate(x)
      doAssert x.a == 1
      doAssert y.a == 2

    proc foo() =
      let x = O(a: 1)
      let y = mutate(x)
      doAssert x.a == 1
      doAssert y.a == 2

    static:
      foo()
    foo()
