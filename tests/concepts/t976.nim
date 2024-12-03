discard """
  output: '''
Printable
'''
joinable: false
"""

#[
  The converter is a proper example of a confounding variable
  Moved to an isolated file
]#

type
  Obj1[T] = object
      v: T
converter toObj1[T](t: T): Obj1[T] =
  return Obj1[T](v: t)
block t976:
  type
    int1 = distinct int
    int2 = distinct int
    int1g = concept x
      x is int1
    int2g = concept x
      x is int2

  proc take[T: int1g](value: int1) =
    when T is int2:
      static: error("killed in take(int1)")

  proc take[T: int2g](vale: int2) =
    when T is int1:
      static: error("killed in take(int2)")

  var i1: int1 = 1.int1
  var i2: int2 = 2.int2

  take[int1](i1)
  take[int2](i2)

  template reject(e) =
    static: assert(not compiles(e))

  reject take[string](i2)
  reject take[int1](i2)

  # bug #6249
  type
      Obj2 = ref object
      PrintAble = concept x
          $x is string

  proc `$`[T](nt: Obj1[T]): string =
      when T is PrintAble: result = "Printable"
      else: result = "Non Printable"

  echo Obj2()