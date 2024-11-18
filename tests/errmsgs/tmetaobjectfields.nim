discard """
  cmd: "nim check --hints:off $file"
  matrix: "--hints:off"
  action: "reject"
  nimout: '''
tmetaobjectfields.nim(27, 5) Error: 'T' is not a concrete type for 'array'
tmetaobjectfields.nim(31, 5) Error: 'seq' is not a concrete type
tmetaobjectfields.nim(35, 5) Error: 'set' is not a concrete type
tmetaobjectfields.nim(38, 3) Error: 'sink' is not a concrete type
tmetaobjectfields.nim(40, 3) Error: 'lent' is not a concrete type
tmetaobjectfields.nim(57, 16) Error: 'seq' is not a concrete type
tmetaobjectfields.nim(61, 5) Error: 'ptr' is not a concrete type
tmetaobjectfields.nim(62, 5) Error: 'ref' is not a concrete type
tmetaobjectfields.nim(63, 5) Error: 'auto' is not a concrete type
tmetaobjectfields.nim(64, 5) Error: 'UncheckedArray' is not a concrete type
tmetaobjectfields.nim(69, 5) Error: 'object' is not a concrete type for 'ref object'
tmetaobjectfields.nim(73, 5) Error: 'Type3011' is not a concrete type
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
