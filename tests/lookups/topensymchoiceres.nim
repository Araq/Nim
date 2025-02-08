discard """
  output: '''
int: 100
'''
"""

# issue #20240

type Action[T] = proc (x: T): void {.nimcall.}

proc doThing(x : float) = echo "float: ", x

proc getDoThing[T]: Action[T] =
  mixin doThing
  assert compiles(doThing(default(T))) # still works
  result = doThing # but this doesn't -- type mismatch: got 'None' for 'doThing' but expected 'Action[system.int]'
  
proc doThing(x : int) = echo "int: ", x
let intDoThing = getDoThing[int]()
intDoThing(100)
