discard """
  valgrind: true
  cmd: '''nim c -d:nimAllocStats --mm:arc -d:useMalloc $file'''
  output: '''
@[(input: @["KXSC", "BGMC"]), (input: @["PXFX"]), (input: @["WXRQ", "ZSCZD"])]
14
First tasks completed.
Second tasks completed.
test1'''
"""

import strutils, os, std / wordwrap

import system / ansi_c

# bug #11004
proc retTuple(): (seq[int], int) =
  return (@[1], 1)

# bug #12899

import sequtils, strmisc

const input = ["KXSC, BGMC => 7 PTHL", "PXFX => LBZJ", "WXRQ, ZSCZD => HLQM"]

type
  Reaction = object
    input: seq[string]

proc bug12899 =
  var reactions: seq[Reaction] = @[]
  for l in input:
    let x = l.partition(" => ")
    reactions.add Reaction(input: @(x[0].split(", ")))

  let x = $reactions
  echo x

bug12899()


proc nonStaticTests =
  doAssert formatBiggestFloat(1234.567, ffDecimal, -1) == "1234.567000"
  doAssert formatBiggestFloat(1234.567, ffDecimal, 0) == "1235." # bugs 8242, 12586
  doAssert formatBiggestFloat(1234.567, ffDecimal, 1) == "1234.6"
  doAssert formatBiggestFloat(0.00000000001, ffDecimal, 11) == "0.00000000001"
  doAssert formatBiggestFloat(0.00000000001, ffScientific, 1, ',') in
                                                    ["1,0e-11", "1,0e-011"]

  doAssert "$# $3 $# $#" % ["a", "b", "c"] == "a c b c"
  doAssert "${1}12 ${-1}$2" % ["a", "b"] == "a12 bb"

  block: # formatSize tests
    when not defined(js):
      doAssert formatSize((1'i64 shl 31) + (300'i64 shl 20)) == "2.293GiB"   # <=== bug #8231
    doAssert formatSize((2.234*1024*1024).int) == "2.234MiB"
    doAssert formatSize(4096) == "4KiB"
    doAssert formatSize(4096, prefix=bpColloquial, includeSpace=true) == "4 kB"
    doAssert formatSize(4096, includeSpace=true) == "4 KiB"
    doAssert formatSize(5_378_934, prefix=bpColloquial, decimalSep=',') == "5,13MB"

  block: # formatEng tests
    doAssert formatEng(0, 2, trim=false) == "0.00"
    doAssert formatEng(0, 2) == "0"
    doAssert formatEng(53, 2, trim=false) == "53.00"
    doAssert formatEng(0.053, 2, trim=false) == "53.00e-3"
    doAssert formatEng(0.053, 4, trim=false) == "53.0000e-3"
    doAssert formatEng(0.053, 4, trim=true) == "53e-3"
    doAssert formatEng(0.053, 0) == "53e-3"
    doAssert formatEng(52731234) == "52.731234e6"
    doAssert formatEng(-52731234) == "-52.731234e6"
    doAssert formatEng(52731234, 1) == "52.7e6"
    doAssert formatEng(-52731234, 1) == "-52.7e6"
    doAssert formatEng(52731234, 1, decimalSep=',') == "52,7e6"
    doAssert formatEng(-52731234, 1, decimalSep=',') == "-52,7e6"

    doAssert formatEng(4100, siPrefix=true, unit="V") == "4.1 kV"
    doAssert formatEng(4.1, siPrefix=true, unit="V", useUnitSpace=true) == "4.1 V"
    doAssert formatEng(4.1, siPrefix=true) == "4.1" # Note lack of space
    doAssert formatEng(4100, siPrefix=true) == "4.1 k"
    doAssert formatEng(4.1, siPrefix=true, unit="", useUnitSpace=true) == "4.1 " # Includes space
    doAssert formatEng(4100, siPrefix=true, unit="") == "4.1 k"
    doAssert formatEng(4100) == "4.1e3"
    doAssert formatEng(4100, unit="V", useUnitSpace=true) == "4.1e3 V"
    doAssert formatEng(4100, unit="", useUnitSpace=true) == "4.1e3 "
    # Don't use SI prefix as number is too big
    doAssert formatEng(3.1e22, siPrefix=true, unit="a", useUnitSpace=true) == "31e21 a"
    # Don't use SI prefix as number is too small
    doAssert formatEng(3.1e-25, siPrefix=true, unit="A", useUnitSpace=true) == "310e-27 A"

proc staticTests =
  doAssert align("abc", 4) == " abc"
  doAssert align("a", 0) == "a"
  doAssert align("1232", 6) == "  1232"
  doAssert align("1232", 6, '#') == "##1232"

  doAssert alignLeft("abc", 4) == "abc "
  doAssert alignLeft("a", 0) == "a"
  doAssert alignLeft("1232", 6) == "1232  "
  doAssert alignLeft("1232", 6, '#') == "1232##"

  let
    inp = """ this is a long text --  muchlongerthan10chars and here
                it goes"""
    outp = " this is a\nlong text\n--\nmuchlongerthan10chars\nand here\nit goes"
  doAssert wrapWords(inp, 10, false) == outp

  let
    longInp = """ThisIsOneVeryLongStringWhichWeWillSplitIntoEightSeparatePartsNow"""
    longOutp = "ThisIsOn\neVeryLon\ngStringW\nhichWeWi\nllSplitI\nntoEight\nSeparate\nPartsNow"
  doAssert wrapWords(longInp, 8, true) == longOutp

  doAssert "$animal eats $food." % ["animal", "The cat", "food", "fish"] ==
            "The cat eats fish."

  doAssert "-ld a-ldz -ld".replaceWord("-ld") == " a-ldz "
  doAssert "-lda-ldz -ld abc".replaceWord("-ld") == "-lda-ldz  abc"

  doAssert "-lda-ldz -ld abc".replaceWord("") == "-lda-ldz -ld abc"
  doAssert "oo".replace("", "abc") == "oo"

  type MyEnum = enum enA, enB, enC, enuD, enE
  doAssert parseEnum[MyEnum]("enu_D") == enuD

  doAssert parseEnum("invalid enum value", enC) == enC

  doAssert center("foo", 13) == "     foo     "
  doAssert center("foo", 0) == "foo"
  doAssert center("foo", 3, fillChar = 'a') == "foo"
  doAssert center("foo", 10, fillChar = '\t') == "\t\t\tfoo\t\t\t\t"

  doAssert count("foofoofoo", "foofoo") == 1
  doAssert count("foofoofoo", "foofoo", overlapping = true) == 2
  doAssert count("foofoofoo", 'f') == 3
  doAssert count("foofoofoobar", {'f','b'}) == 4

  doAssert strip("  foofoofoo  ") == "foofoofoo"
  doAssert strip("sfoofoofoos", chars = {'s'}) == "foofoofoo"
  doAssert strip("barfoofoofoobar", chars = {'b', 'a', 'r'}) == "foofoofoo"
  doAssert strip("stripme but don't strip this stripme",
                  chars = {'s', 't', 'r', 'i', 'p', 'm', 'e'}) ==
                  " but don't strip this "
  doAssert strip("sfoofoofoos", leading = false, chars = {'s'}) == "sfoofoofoo"
  doAssert strip("sfoofoofoos", trailing = false, chars = {'s'}) == "foofoofoos"

  doAssert "  foo\n  bar".indent(4, "Q") == "QQQQ  foo\nQQQQ  bar"

  doAssert "abba".multiReplace(("a", "b"), ("b", "a")) == "baab"
  doAssert "Hello World.".multiReplace(("ello", "ELLO"), ("World.", "PEOPLE!")) == "HELLO PEOPLE!"
  doAssert "aaaa".multiReplace(("a", "aa"), ("aa", "bb")) == "aaaaaaaa"

  doAssert rsplit("foo bar", seps=Whitespace) == @["foo", "bar"]
  doAssert rsplit(" foo bar", seps=Whitespace, maxsplit=1) == @[" foo", "bar"]
  doAssert rsplit(" foo bar ", seps=Whitespace, maxsplit=1) == @[" foo bar", ""]
  doAssert rsplit(":foo:bar", sep=':') == @["", "foo", "bar"]
  doAssert rsplit(":foo:bar", sep=':', maxsplit=2) == @["", "foo", "bar"]
  doAssert rsplit(":foo:bar", sep=':', maxsplit=3) == @["", "foo", "bar"]
  doAssert rsplit("foothebar", sep="the") == @["foo", "bar"]

  doAssert(unescape(r"\x013", "", "") == "\x013")

  doAssert join(["foo", "bar", "baz"]) == "foobarbaz"
  doAssert join(@["foo", "bar", "baz"], ", ") == "foo, bar, baz"
  doAssert join([1, 2, 3]) == "123"
  doAssert join(@[1, 2, 3], ", ") == "1, 2, 3"

  doAssert """~~!!foo
~~!!bar
~~!!baz""".unindent(2, "~~!!") == "foo\nbar\nbaz"

  doAssert """~~!!foo
~~!!bar
~~!!baz""".unindent(2, "~~!!aa") == "~~!!foo\n~~!!bar\n~~!!baz"
  doAssert """~~foo
~~  bar
~~  baz""".unindent(4, "~") == "foo\n  bar\n  baz"
  doAssert """foo
  bar
    baz
  """.unindent(4) == "foo\nbar\nbaz\n"
  doAssert """foo
    bar
    baz
  """.unindent(2) == "foo\n  bar\n  baz\n"
  doAssert """foo
      bar
      baz
    """.unindent(100) == "foo\nbar\nbaz\n"

  doAssert """foo
      foo
      bar
    """.unindent() == "foo\nfoo\nbar\n"

  let s = " this is an example  "
  let s2 = ":this;is;an:example;;"

  doAssert s.split() == @["", "this", "is", "an", "example", "", ""]
  doAssert s2.split(seps={':', ';'}) == @["", "this", "is", "an", "example", "", ""]
  doAssert s.split(maxsplit=4) == @["", "this", "is", "an", "example  "]
  doAssert s.split(' ', maxsplit=1) == @["", "this is an example  "]
  doAssert s.split(" ", maxsplit=4) == @["", "this", "is", "an", "example  "]

  doAssert s.splitWhitespace() == @["this", "is", "an", "example"]
  doAssert s.splitWhitespace(maxsplit=1) == @["this", "is an example  "]
  doAssert s.splitWhitespace(maxsplit=2) == @["this", "is", "an example  "]
  doAssert s.splitWhitespace(maxsplit=3) == @["this", "is", "an", "example  "]
  doAssert s.splitWhitespace(maxsplit=4) == @["this", "is", "an", "example"]

  discard retTuple()

nonStaticTests()
staticTests()

# bug #12965
let xaa = @[""].join()
let xbb = @["", ""].join()

# bug #16365

# Task 1:
when true:
  # Task 1_a:
  var test_string_a = "name_something"
  echo test_string_a.len()
  let new_len_a = test_string_a.len - "_something".len()
  test_string_a.setLen new_len_a

  echo "First tasks completed."

# Task 2:
when true:
  # Task 2_a
  var test_string: string
  let some_string = "something"
  for i in some_string.items:
    test_string.add $i

  # Task 2_b
  var test_string_b = "name_something"
  let new_len_b = test_string_b.len - "_something".len()
  test_string_b.setLen new_len_b

  echo "Second tasks completed."

# bug #17450
proc main =
  var i = 1
  echo:
    block:
      "test" & $i

main()


block:
  block:
    type
      JsonNode = ref object

    proc foo(d: JsonNode) =
      discard

    proc test_something()=
      var a = JsonNode()
      foo ensureMove(a)

    test_something()

  block:
    type
      JsonNode = object
        data: int

    proc foo(d: JsonNode) =
      discard

    proc test_something()=
      var a = JsonNode()
      foo ensureMove(a)

    test_something()

  block:
    type
      JsonNode = object
        data: int

    proc `=destroy`(x: JsonNode) = discard

    proc foo(d: JsonNode) =
      discard

    proc test_something()=
      var a = JsonNode()
      foo ensureMove(a)

    test_something()

