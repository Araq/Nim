type
  D[T] = object
  E[T] = object

block: # PR #22261
  proc d(x: D):bool= false
  proc d(x: int | D[SomeInteger]):bool= true
  doAssert d(D[5]()) == false

block: # bug #8568
#[
  Since PR #22261 and amendment has been made. Since D is a subset of D | E but
  not the other way around `checkGeneric` should favor proc g(a: D) instead
  of asserting ambiguity
]#
  proc g(a: D|E): string = "foo D|E"
  proc g(a: D): string = "foo D"
  doAssert g(D[int]()) == "foo D"

type Obj1[T] = object
  v: T
converter toObj1[T](t: T): Obj1[T] = return Obj1[T](v: t)
block: # issue #10019
  proc fun1[T](elements: seq[T]): string = "fun1 seq"
  proc fun1(o: object|tuple): string = "fun1 object|tuple"
  proc fun2[T](elements: openArray[T]): string = "fun2 openarray"
  proc fun2(o: object): string = "fun2 object"
  proc fun_bug[T](elements: openArray[T]): string = "fun_bug openarray"
  proc fun_bug(o: object|tuple):string = "fun_bug object|tuple"
  proc main() =
    var x = @["hello", "world"]
    block:
      # no ambiguity error shown here even though this would compile if we remove either 1st or 2nd overload of fun1
      doAssert fun1(x) == "fun1 seq"
    block:
      # ditto
      doAssert fun2(x) == "fun2 openarray"
    block:
      # Error: ambiguous call; both t0065.fun_bug(elements: openarray[T])[declared in t0065.nim(17, 5)] and t0065.fun_bug(o: object or tuple)[declared in t0065.nim(20, 5)] match for: (array[0..1, string])
      doAssert fun_bug(x) == "fun_bug openarray"
  main()
