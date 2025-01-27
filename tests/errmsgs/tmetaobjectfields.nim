discard """
  cmd: "nim check --hints:off $file"
  action: "reject"
  nimout: '''
tmetaobjectfields.nim(26, 5) Error: 'array' is not a concrete type
tmetaobjectfields.nim(30, 5) Error: 'seq' is not a concrete type
tmetaobjectfields.nim(34, 5) Error: 'set' is not a concrete type
tmetaobjectfields.nim(37, 3) Error: 'sink' is not a concrete type
tmetaobjectfields.nim(39, 3) Error: 'lent' is not a concrete type
tmetaobjectfields.nim(56, 16) Error: 'seq' is not a concrete type
tmetaobjectfields.nim(60, 5) Error: 'ptr' is not a concrete type
tmetaobjectfields.nim(61, 5) Error: 'ref' is not a concrete type
tmetaobjectfields.nim(62, 5) Error: 'auto' is not a concrete type
tmetaobjectfields.nim(63, 5) Error: 'UncheckedArray' is not a concrete type
tmetaobjectfields.nim(68, 5) Error: 'object' is not a concrete type
tmetaobjectfields.nim(72, 5) Error: 'Type3011:ObjectType' is not a concrete type
'''
"""


# bug #6982
# bug #19546
# bug #23531
type
  ExampleObj1 = object
    arr: array

type
  ExampleObj2 = object
    arr: seq

type
  ExampleObj3 = object
    arr: set

type A = object
  b: sink
  # a: openarray
  c: lent

type PropertyKind = enum
  tInt,
  tFloat,
  tBool,
  tString,
  tArray

type
  Property = ref PropertyObj
  PropertyObj = object
    case kind: PropertyKind
    of tInt: intValue: int
    of tFloat: floatValue: float
    of tBool: boolValue: bool
    of tString: stringValue: string
    of tArray: arrayValue: seq

type
  RegressionTest = object
    a: ptr
    b: ref
    c: auto
    d: UncheckedArray

# bug #3011
type
  Type3011 = ref object 
    context: ref object

type
  Value3011 = ref object
    typ: Type3011

proc x3011(): Value3011 =
  nil
