discard """
  targets: "c cpp js"
  matrix: "--mm:refc; --mm:orc"
"""

import std/[strbasics, sugar, assertions]

template strip2(input: string, args: varargs[untyped]): untyped =
  var a = input
  when varargsLen(args) > 0:
    strip(a, args)
  else:
    strip(a)
  a

proc main() =
  block: # strip
    block: # bug #17173
      var a = "  vhellov   "
      strip(a)
      doAssert a == "vhellov"

    doAssert strip2("  vhellov   ") == "vhellov"
    doAssert strip2("  vhellov   ", leading = false) == "  vhellov"
    doAssert strip2("  vhellov   ", trailing = false) == "vhellov   "
    doAssert strip2("vhellov", chars = {'v'}) == "hello"
    doAssert strip2("vhellov", leading = false, chars = {'v'}) == "vhello"
    doAssert strip2("blaXbla", chars = {'b', 'a'}) == "laXbl"
    doAssert strip2("blaXbla", chars = {'b', 'a', 'l'}) == "X"
    doAssert strip2("xxxxxx", chars={'x'}) == ""
    doAssert strip2("x", chars={'x'}) == ""
    doAssert strip2("x", chars={'1'}) == "x"
    doAssert strip2("", chars={'x'}) == ""
    doAssert strip2("xxx xxx", chars={'x'}) == " "
    doAssert strip2("xxx  wind", chars={'x'}) == "  wind"
    doAssert strip2("xxx  iii", chars={'i'}) == "xxx  "

    block:
      var a = "xxx  iii"
      doAssert a.dup(strip(chars = {'i'})) == "xxx  "
      doAssert a.dup(strip(chars = {' '})) == "xxx  iii"
      doAssert a.dup(strip(chars = {'x'})) == "  iii"
      doAssert a.dup(strip(chars = {'x', ' '})) == "iii"
      doAssert a.dup(strip(chars = {'x', 'i'})) == "  "
      doAssert a.dup(strip(chars = {'x', 'i', ' '})).len == 0

    block:
      var a = "x  i"
      doAssert a.dup(strip(chars = {'i'})) == "x  "
      doAssert a.dup(strip(chars = {' '})) == "x  i"
      doAssert a.dup(strip(chars = {'x'})) == "  i"
      doAssert a.dup(strip(chars = {'x', ' '})) == "i"
      doAssert a.dup(strip(chars = {'x', 'i'})) == "  "
      doAssert a.dup(strip(chars = {'x', 'i', ' '})).len == 0

    block:
      var a = ""
      doAssert a.dup(strip(chars = {'i'})).len == 0
      doAssert a.dup(strip(chars = {' '})).len == 0
      doAssert a.dup(strip(chars = {'x'})).len == 0
      doAssert a.dup(strip(chars = {'x', ' '})).len == 0
      doAssert a.dup(strip(chars = {'x', 'i'})).len == 0
      doAssert a.dup(strip(chars = {'x', 'i', ' '})).len == 0

    block:
      var a = " "
      doAssert a.dup(strip(chars = {'i'})) == " "
      doAssert a.dup(strip(chars = {' '})).len == 0
      doAssert a.dup(strip(chars = {'x'})) == " "
      doAssert a.dup(strip(chars = {'x', ' '})).len == 0
      doAssert a.dup(strip(chars = {'x', 'i'})) == " "
      doAssert a.dup(strip(chars = {'x', 'i', ' '})).len == 0

  block: # setSlice
    var a = "Hello, Nim!"
    doAssert a.dup(setSlice(7 .. 9)) == "Nim"
    doAssert a.dup(setSlice(0 .. 0)) == "H"
    doAssert a.dup(setSlice(0 .. 1)) == "He"
    doAssert a.dup(setSlice(0 .. 10)) == a
    doAssert a.dup(setSlice(1 .. 0)).len == 0
    doAssert a.dup(setSlice(20 .. -1)).len == 0

    doAssertRaises(AssertionDefect):
      discard a.dup(setSlice(-1 .. 1))

    doAssertRaises(AssertionDefect):
      discard a.dup(setSlice(1 .. 11))

  block: # add
    var a0 = "hi"
    var b0 = "foobar"
    when nimvm:
      discard # pending bug #15952
    else:
      a0.add b0.toOpenArray(1,3)
      doAssert a0 == "hioob"
    proc fn(c: openArray[char]): string =
      result = ""
      result.add c
    doAssert fn("def") == "def"
    doAssert fn(['d','\0', 'f'])[2] == 'f'

static: main()
main()
