discard """
  output: '''
int
float
'''
"""

# issue #22479

type Obj[T] = object

proc `=destroy`[T](self: var Obj[T]) =
  echo T

block:
  let intObj = Obj[int]()

block:
  let floatObj = Obj[float]()
