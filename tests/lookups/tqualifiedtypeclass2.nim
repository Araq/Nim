# issue #18095

type
  A* = object
  B* = object
  C* = A | B
type B2 = tqualifiedtypeclass2.B
type C2 = tqualifiedtypeclass2.C
proc fn1(a: tqualifiedtypeclass2.B) = discard
proc fn2(a: C) = discard
proc f3(a: C2) = discard # Error: invalid type: 'C2' in this context: 'proc (a: C2)' for proc
proc fn4(a: tqualifiedtypeclass2.C) = discard # ditto
