discard """
matrix: "--mm:refc"
output: '''
abc
def
definition
prefix
xyz
def
definition
Hi Andreas! How do you feel, Rumpf?

@[0, 2, 1]
@[1, 0, 2]
@[1, 2, 0]
@[2, 0, 1]
@[2, 1, 0]
@[2, 0, 1]
@[1, 2, 0]
@[1, 0, 2]
@[0, 2, 1]
@[0, 1, 2]
055this should be the casehugh@["(", "+", " 1", " 2", ")"]
[5]
[4, 5]
[3, 4, 5]
[2, 3, 4, 5]
[2, 3, 4, 5, 6]
[1, 2, 3, 4, 5, 6]
<h1><a href="http://force7.de/nim">Nim</a></h1>
'''
"""

import
  std/[critbits, sets, strutils, tables, random, algorithm, re, ropes,
  segfaults, lists, parsesql, streams, os, htmlgen, xmltree, strtabs]
import std/[syncio, assertions]

block tcritbits:
  var r: CritBitTree[void]
  r.incl "abc"
  r.incl "xyz"
  r.incl "def"
  r.incl "definition"
  r.incl "prefix"
  doAssert r.contains"def"
  #r.del "def"

  for w in r.items:
    echo w
  for w in r.itemsWithPrefix("de"):
    echo w



block testequivalence:
  doAssert(toHashSet(@[1,2,3]) <= toHashSet(@[1,2,3,4]), "equivalent or subset")
  doAssert(toHashSet(@[1,2,3]) <= toHashSet(@[1,2,3]), "equivalent or subset")
  doAssert((not(toHashSet(@[1,2,3]) <= toHashSet(@[1,2]))), "equivalent or subset")
  doAssert(toHashSet(@[1,2,3]) <= toHashSet(@[1,2,3,4]), "strict subset")
  doAssert((not(toHashSet(@[1,2,3]) < toHashSet(@[1,2,3]))), "strict subset")
  doAssert((not(toHashSet(@[1,2,3]) < toHashSet(@[1,2]))), "strict subset")
  doAssert((not(toHashSet(@[1,2,3]) == toHashSet(@[1,2,3,4]))), "==")
  doAssert(toHashSet(@[1,2,3]) == toHashSet(@[1,2,3]), "==")
  doAssert((not(toHashSet(@[1,2,3]) == toHashSet(@[1,2]))), "==")



block tformat:
  echo("Hi $1! How do you feel, $2?\n" % ["Andreas", "Rumpf"])



block tnilecho:
  var x = @["1", "", "3"]
  doAssert $x == """@["1", "", "3"]"""



block torderedtable:
  var t = initOrderedTable[int,string]()

  # this tests issue #5917
  var data = newSeq[int]()
  for i in 0..<1000:
    var x = rand(1000)
    if x notin t: data.add(x)
    t[x] = "meh"

  # this checks that keys are re-inserted
  # in order when table is enlarged.
  var i = 0
  for k, v in t:
    doAssert(k == data[i])
    doAssert(v == "meh")
    inc(i)



block tpermutations:
  var v = @[0, 1, 2]
  while v.nextPermutation():
    echo v
  while v.prevPermutation():
    echo v



block treguse:
  proc main(a, b: int) =
    var x = 0
    write(stdout, x)
    if x == 0:
      var y = 55
      write(stdout, y)
      write(stdout, "this should be the case")
      var input = "<no input>"
      if input == "Andreas":
        write(stdout, "wow")
      else:
        write(stdout, "hugh")
    else:
      var z = 66
      write(stdout, z) # "bug!")

  main(45, 1000)



block treloop:
  let str = "(+ 1 2)"
  var tokenRE = re"""[\s,]*(~@|[\[\]{}()'`~^@]|"(?:\\.|[^\\"])*"|;.*|[^\s\[\]{}('"`,;)]*)"""
  echo str.findAll(tokenRE)



block tropes:
  var
    r1 = rope("")
    r2 = rope("123")
  doAssert r1.len == 0
  doAssert r2.len == 3
  doAssert $r1 == ""
  doAssert $r2 == "123"

  r1.add("123")
  r2.add("456")
  doAssert r1.len == 3
  doAssert r2.len == 6
  doAssert $r1 == "123"
  doAssert $r2 == "123456"
  doAssert $r1[1] == "2"
  doAssert $r2[2] == "3"



block tsegfaults:
  when not defined(arm64):
    var crashes = 0
    proc main =
      try:
        var x: ptr int = nil
        echo x[]
        try:
          raise newException(ValueError, "not a crash")
        except ValueError:
          discard
      except NilAccessDefect:
        inc crashes
    for i in 0..5:
      main()
    assert crashes == 6



block tsinglylinkedring:
  var r = initSinglyLinkedRing[int]()
  r.prepend(5)
  echo r
  r.prepend(4)
  echo r
  r.prepend(3)
  echo r
  r.prepend(2)
  echo r
  r.append(6)
  echo r
  r.prepend(1)
  echo r



block tsplit:
  var s = ""
  for w in split("|abc|xy|z", {'|'}):
    s.add("#")
    s.add(w)

  doAssert s == "##abc#xy#z"



block tsplit2:
  var s = ""
  for w in split("|abc|xy|z", {'|'}):
    s.add("#")
    s.add(w)

  doAssert "true".split("") == @["true"]



block tsqlparser:
  # Just check that we can parse 'somesql' and render it without crashes.
  var tree = parseSql(newFileStream( parentDir(currentSourcePath) / "somesql.sql"), "somesql")
  discard renderSql(tree)



block txmlgen:
  var nim = "Nim"
  echo h1(a(href="http://force7.de/nim", nim))



block txmltree:
  var x = <>a(href="nim.de", newText("www.nim-test.de"))

  doAssert($x == "<a href=\"nim.de\">www.nim-test.de</a>")
  doAssert(newText("foo").innerText == "foo")
  doAssert(newEntity("bar").innerText == "bar")
  doAssert(newComment("baz").innerText == "")

  let y = newXmlTree("x", [
    newText("foo"),
    newXmlTree("y", [
      newText("bar")
    ])
  ])
  doAssert(y.innerText == "foobar")
