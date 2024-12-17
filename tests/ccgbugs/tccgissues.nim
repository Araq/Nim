discard """
  output: '''
@[1, 2, 3, 4]
'''
"""

# issue #10999

proc varargsToSeq(vals: varargs[int32]): seq[int32] =
  result = newSeqOfCap[int32](vals.len)
  for v in vals:
    result.add v

echo varargsToSeq(1, 2, 3, 4)

type # bug #16845
  MyObjectKind = enum
    SomeKind

block:
  type
    MyObject = ref object
      case kind: MyObjectKind:
        of SomeKind:
          c: string

  var obj = MyObject(kind:SomeKind)
  obj.c = "some string"

block:
  type
    MyObject = ref object
      kind: MyObjectKind
      c: string

  var obj = MyObject(kind:SomeKind)
  obj.c = "some string"

block:
  type
    MyBaseObj[T] = object of RootObj
      test: seq[T]
    MyObj = object
      attr: MyBaseObj[string]

  var myObj: MyObj

block:
  type
    MyBaseAttrObj[T] = object of RootObj
      test: seq[T]
    MyBaseObj[T] = object of RootObj
      myBaseObj: MyBaseAttrObj[T]
    MyObj = object
      attr: MyBaseObj[string]

  var myObj: MyObj
