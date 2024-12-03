discard """
  matrix: "--mm:refc; --mm:orc"
  output: '''[1, 0, 0, 0, 0, 0, 0, 0] CTBool[Ct[system.uint32]]'''
"""

block tconstraints:
  proc myGenericProc[T: object|tuple|int|ptr|ref|distinct](x: T): string =
    result = $x

  type TMyObj = tuple[x, y: int]

  var x: TMyObj

  assert myGenericProc(232) == "232"
  assert myGenericProc(x) == "(x: 0, y: 0)"



block tfieldaccessor:
  type
    Test = object
      x: int
      case p: bool
      of true:
        a: int
      else:
        case q: bool
        of true:
          b: int
        else:
          discard

  proc f[T](t: typedesc[T]): int =
    1

  assert Test.f == 1



block tprocbothmeta:
  proc myFun[A](x: A): auto =
    result = float(x+10)

  proc myMap[T,S](sIn: seq[T], f: proc (q: T): S): seq[S] =
    result = newSeq[S](sIn.len)
    for i in 0..<sIn.len:
      result[i] = f(sIn[i])

  assert myMap(@[1,2,3], myFun) == @[11.0, 12.0, 13.0]


# https://github.com/nim-lang/Nim/issues/13646

type
  BaseUint* = SomeUnsignedInt or byte
  Ct*[T] = distinct T
    ## Constant-Time wrapper
    ## Only constant-time operations in particular the ternary operator equivalent
    ##   condition: if true: a else: b
    ## are allowed

  CTBool*[T] = distinct range[T(0)..T(1)]
    ## Constant-Time boolean wrapper

var x: array[8, CTBool[Ct[uint32]]]
x[0] = (CTBool[Ct[uint32]])(1)
echo x.repr, " ", typeof(x[0])

block: # bug #23139
  type Foo = enum a, b

  var x: range[a..b]
  doAssert (repr x) == "a"
