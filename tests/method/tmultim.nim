discard """
  matrix: "--multimethods:on"
  output: '''
collide: unit, thing
collide: unit, thing
collide: thing, unit
collide: thing, thing
collide: unit, thing |
collide: unit, thing |
collide: thing, unit |
do nothing
'''
  joinable: false
  disabled: true
"""


# tmultim2
type
  TThing {.inheritable.} = object
  TUnit = object of TThing
    x: int
  TParticle = object of TThing
    a, b: int

method collide(a, b: TThing) {.base, inline.} =
  echo "collide: thing, thing"

method collide(a: TThing, b: TUnit) {.inline.} =
  echo "collide: thing, unit"

method collide(a: TUnit, b: TThing) {.inline.} =
  echo "collide: unit, thing"

proc test(a, b: TThing) {.inline.} =
  collide(a, b)

proc staticCollide(a, b: TThing) {.inline.} =
  procCall collide(a, b)

var
  a: TThing
  b, c: TUnit
collide(b, c) # ambiguous (unit, thing) or (thing, unit)? -> prefer unit, thing!
test(b, c)
collide(a, b)
staticCollide(a, b)



# tmultim6
type
  Thing {.inheritable.} = object
  Unit[T] = object of Thing
    x: T
  Particle = object of Thing
    a, b: int

method collide(a, b: Thing) {.base, inline.} =
  quit "to override!"

method collide[T](a: Thing, b: Unit[T]) {.inline.} =
  echo "collide: thing, unit |"

method collide[T](a: Unit[T], b: Thing) {.inline.} =
  echo "collide: unit, thing |"

proc test(a, b: Thing) {.inline.} =
  collide(a, b)

var
  aaa: Thing
  bbb, ccc: Unit[string]
collide(bbb, Thing(ccc))
test(bbb, ccc)
collide(aaa, bbb)



# tmethods1
method somethin(obj: RootObj) {.base.} =
  echo "do nothing"

type
  TNode* {.inheritable.} = object
  PNode* = ref TNode

  PNodeFoo* = ref object of TNode

  TSomethingElse = object
  PSomethingElse = ref TSomethingElse

method foo(a: PNode, b: PSomethingElse) {.base.} = discard
method foo(a: PNodeFoo, b: PSomethingElse) = discard

var o: RootObj
o.somethin()
