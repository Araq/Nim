discard """
  cmd: "nim check $options $file"
  matrix: "--hints:off"
  action: "reject"
  nimout: '''
tmetafield.nim(27, 5) Error: 'proc' is not a concrete type; for a callback without parameters use 'proc()'
tmetafield.nim(28, 5) Error: 'Foo' is not a concrete type for 'seq[Foo]'
tmetafield.nim(30, 5) Error: invalid type: 'proc' in this context: 'TBaseMed' for var
'''
"""

# bug #188








# line 20
type
  Foo[T] = object
    x: T

  TBaseMed =  object
    doSmth: proc
    data: seq[Foo]

var a: TBaseMed

