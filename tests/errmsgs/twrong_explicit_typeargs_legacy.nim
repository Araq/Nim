discard """
  action: reject
  nimout: '''
twrong_explicit_typeargs_legacy.nim(25, 29) Error: type mismatch: got <int literal(320), int literal(200)>
but expected one of:
proc newImage[T: int32 | int64](w, h: int): ref Image[T]
  first type mismatch at position: 1 in generic parameters
  required type for T: int32 or int64
  but expression 'string' is of type: string

expression: newImage[string](320, 200)
'''
"""

# bug #4084
type
  Image[T] = object
    data: seq[T]

proc newImage[T: int32|int64](w, h: int): ref Image[T] =
  new(result)
  result.data = newSeq[T](w * h)

var correct = newImage[int32](320, 200)
var wrong = newImage[string](320, 200)
