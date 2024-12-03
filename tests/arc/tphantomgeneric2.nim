discard """
  output: '''
created Phantom[system.float] with value 1
created Phantom[system.string] with value 2
created Phantom[system.byte] with value 3
destroyed Phantom[system.byte] with value 3
destroyed Phantom[system.string] with value 2
destroyed Phantom[system.float] with value 1
'''
"""

# issue #24374

type Phantom[T] = object
  value: int
  # markerField: T

proc initPhantom[T](value: int): Phantom[T] =
  doAssert value >= 0
  echo "created " & $Phantom[T] & " with value " & $value
  result = Phantom[T](value: value)

proc `=wasMoved`[T](x: var Phantom[T]) =
  x.value = -1

proc `=destroy`[T](x: Phantom[T]) =
  if x.value >= 0:
    echo "destroyed " & $Phantom[T] & " with value " & $x.value

let
  x = initPhantom[float](1)
  y = initPhantom[string](2)
  z = initPhantom[byte](3)
