discard """
  output: '''x
[10, 11, 12, 13]'''
"""

# bug #14805

type Foo = object
  a: string

proc bar(f: var Foo): lent string =
  result = f.a

var foo = Foo(a: "x")
echo bar(foo)


# bug #14878

# proc byLentImpl[T](a: T): lent T = a
proc byLentVar[T](a: var T): lent T =
  result = a
  # result = a.byLentImpl # this doesn't help

var x = 3 # error: cannot take the address of an rvalue of type 'NI *'

var xs = [10,11,12,13] # SIGSEGV

let x2 = x.byLentVar

let xs2 = xs.byLentVar
echo xs2

# bug #22138

type Xxx = object

type
  Opt[T] = object
    case oResultPrivate*: bool
    of false:
      discard
    of true:
      vResultPrivate*: T

func value*[T: not void](self: Opt[T]): lent T {.inline.} =
  self.vResultPrivate
template get*[T: not void](self: Opt[T]): T = self.value()

method connect*(
  self: Opt[(int, int)]) =
  discard self.get()[0]

block: # bug #23454
  type
    Letter = enum
      A

    LetterPairs = object
      values: seq[(Letter, string)]

  iterator items(list: var LetterPairs): lent (Letter, string) =
    for item in list.values:
      yield item

  var instance = LetterPairs(values: @[(A, "foo")])

  for (a, _) in instance:
    case a
    of A: discard

block: # bug #23454
  type
    Letter = enum
      A

    LetterPairs = object
      values: seq[(Letter, string)]

  iterator items(list: var LetterPairs): var (Letter, string) =
    for item in list.values.mItems:
      yield item

  var instance = LetterPairs(values: @[(A, "foo")])

  for (a, _) in instance:
    case a
    of A: discard

block: # bug #24034
  type T = object
    v: array[100, byte]


  iterator pairs(t: T): (int, lent array[100, byte]) =
    yield (0, t.v)


  block:
    for a, b in default(T):
      doAssert a == 0
      doAssert b.len == 100

  block:
    for (a, b) in pairs(default(T)):
      doAssert a == 0
      doAssert b.len == 100
