discard """
  matrix: "--mm:refc; --mm:orc"
"""

import std/re
import std/assertions

proc testAll() =
  doAssert match("(a b c)", rex"\( .* \)")
  doAssert match("WHiLe", re("while", {reIgnoreCase}))

  doAssert "0158787".match(re"\d+")
  doAssert "ABC 0232".match(re"\w+\s+\d+")
  doAssert "ABC".match(rex"\d+ | \w+")

  {.push warnings:off.}
  doAssert matchLen("key", re"\b[a-zA-Z_]+[a-zA-Z_0-9]*\b") == 3
  {.pop.}

  var pattern = re"[a-z0-9]+\s*=\s*[a-z0-9]+"
  doAssert matchLen("key1=  cal9", pattern) == 11

  doAssert find("_____abc_______", re"abc") == 5
  doAssert findBounds("_____abc_______", re"abc") == (5,7)

  var matches: array[6, string] = default(array[6, string])
  if match("abcdefg", re"c(d)ef(g)", matches, 2):
    doAssert matches[0] == "d"
    doAssert matches[1] == "g"
  else:
    doAssert false

  if "abc" =~ re"(a)bcxyz|(\w+)":
    doAssert matches[1] == "abc"
  else:
    doAssert false

  if "abc" =~ re"(cba)?.*":
    doAssert matches[0] == ""
  else: doAssert false

  if "abc" =~ re"().*":
    doAssert matches[0] == ""
  else: doAssert false

  doAssert "var1=key; var2=key2".endsWith(re"\w+=\w+")
  doAssert("var1=key; var2=key2".replacef(re"(\w+)=(\w+)", "$1<-$2$2") ==
         "var1<-keykey; var2<-key2key2")
  doAssert("var1=key; var2=key2".replace(re"(\w+)=(\w+)", "$1<-$2$2") ==
         "$1<-$2$2; $1<-$2$2")

  var accum: seq[string] = @[]
  for word in split("00232this02939is39an22example111", re"\d+"):
    accum.add(word)
  doAssert(accum == @["", "this", "is", "an", "example", ""])

  accum = @[]
  for word in split("00232this02939is39an22example111", re"\d+", maxsplit=2):
    accum.add(word)
  doAssert(accum == @["", "this", "is39an22example111"])

  accum = @[]
  for word in split("AAA :   : BBB", re"\s*:\s*"):
    accum.add(word)
  doAssert(accum == @["AAA", "", "BBB"])

  doAssert(split("abc", re"") == @["a", "b", "c"])
  doAssert(split("", re"") == @[])

  doAssert(split("a;b;c", re";") == @["a", "b", "c"])
  doAssert(split(";a;b;c", re";") == @["", "a", "b", "c"])
  doAssert(split(";a;b;c;", re";") == @["", "a", "b", "c", ""])
  doAssert(split("a;b;c;", re";") == @["a", "b", "c", ""])
  doAssert(split("00232this02939is39an22example111", re"\d+", maxsplit=2) == @["", "this", "is39an22example111"])


  for x in findAll("abcdef", re"^{.}", 3):
    doAssert x == "d"
  accum = @[]
  for x in findAll("abcdef", re".", 3):
    accum.add(x)
  doAssert(accum == @["d", "e", "f"])

  doAssert("XYZ".find(re"^\d*") == 0)
  doAssert("XYZ".match(re"^\d*") == true)

  block:
    var matches: array[16, string] = default(array[16, string])
    if match("abcdefghijklmnop", re"(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)(l)(m)(n)(o)(p)", matches):
      for i in 0..matches.high:
        doAssert matches[i] == $chr(i + 'a'.ord)
    else:
      doAssert false

  block:   # Buffer based RE
    var cs: cstring = "_____abc_______"
    doAssert(cs.find(re"abc", bufSize=15) == 5)
    doAssert(cs.matchLen(re"_*abc", bufSize=15) == 8)
    doAssert(cs.matchLen(re"abc", start=5, bufSize=15) == 3)
    doAssert(cs.matchLen(re"abc", start=5, bufSize=7) == -1)
    doAssert(cs.matchLen(re"abc_*", start=5, bufSize=10) == 5)
    var accum: seq[string] = @[]
    for x in cs.findAll(re"[a-z]", start=3, bufSize=15):
      accum.add($x)
    doAssert(accum == @["a","b","c"])

  block: # bug #9306
    doAssert replace("bar", re"^", "foo") == "foobar"
    doAssert replace("foo", re"$", "bar") == "foobar"


  block: # bug #9437
    doAssert replace("foo", re"", "-") == "-f-o-o-"
    doAssert replace("ooo", re"o", "-") == "---"

  block: # bug #14468
    accum = @[]
    for word in split("this is an example", re"\b"):
      accum.add(word)
    doAssert(accum == @["this", " ", "is", " ", "an", " ", "example"])

testAll()
