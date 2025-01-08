discard """
  cmd: "nim check $file"
  action: reject
  nimout: '''
twrongdefaultvalue.nim(20, 12) template/generic instantiation of `doit` from here
twrongdefaultvalue.nim(17, 37) Error: type mismatch: got <proc (p: int): Item[initItem.T]> but expected 'Item[system.string]'
twrongdefaultvalue.nim(25, 3) template/generic instantiation of `foo` from here
twrongdefaultvalue.nim(23, 33) Error: type mismatch: got <string> but expected 'int'
'''
"""

block: # issue #21258
  type Item[T] = object
    pos: int
  proc initItem[T](p:int=10000) : Item[T] = 
    result = Item[T](p)
  proc doit[T](x:Item[T], s:Item[T]=initItem) : string = 
    return $x.pos
  let x = Item[string](pos:100)
  echo doit(x)

block: # issue #21258, reduced case
  proc foo[T](x: seq[T], y: T = "foo") =
    discard
  foo @[1, 2, 3]
