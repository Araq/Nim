discard """
  cmd: "nim c --hints:off -d:testsConciseTypeMismatch $file"
  action: reject
  nimout: '''
twrong_explicit_typeargs.nim(26, 29) Error: type mismatch
Expression: newImage[string](320, 200)
  [1] 320: int literal(320)
  [2] 200: int literal(200)

Expected one of (first mismatch at [position]):
[1] proc newImage[T: int32 | int64](w, h: int): ref Image[T]
  generic parameter mismatch, expected int32 or int64 but got 'string' of type: string
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
