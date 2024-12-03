discard """
  matrix: "--mm:refc; --mm:orc; --backend:cpp; --backend:js --jsbigint64:off -d:nimStringHash2; --backend:js --jsbigint64:on"
"""

import std/strutils
from stdtest/testutils import disableVm
import std/assertions
import std/private/jsutils
# xxx each instance of `disableVm` and `when not defined js:` should eventually be fixed

template rejectParse(e) =
  try:
    discard e
    raise newException(AssertionDefect, "This was supposed to fail: $#!" % astToStr(e))
  except ValueError: discard

template main() =
  block: # strip
    doAssert strip("  ha  ") == "ha"
    doAssert strip("  foofoofoo  ") == "foofoofoo"
    doAssert strip("sfoofoofoos", chars = {'s'}) == "foofoofoo"
    doAssert strip("barfoofoofoobar", chars = {'b', 'a', 'r'}) == "foofoofoo"
    doAssert strip("stripme but don't strip this stripme",
                   chars = {'s', 't', 'r', 'i', 'p', 'm', 'e'}) ==
                   " but don't strip this "
    doAssert strip("sfoofoofoos", leading = false, chars = {'s'}) == "sfoofoofoo"
    doAssert strip("sfoofoofoos", trailing = false, chars = {'s'}) == "foofoofoos"

    block:
      let a = "xxxxxx"
      doAssert a.strip(chars={'x'}).len == 0

    doAssert "".strip(chars={'x'}).len == 0
    doAssert "         ".strip(chars={'x'}) == "         "
    doAssert "xxx xxx".strip(chars={'x'}) == " "
    doAssert "xxx  wind".strip(chars={'x'}) == "  wind"
    doAssert "xxx  iii".strip(chars={'i'}) == "xxx  "
    doAssert "x".strip(leading = false, chars={'x'}).len == 0
    doAssert "x".strip(trailing = false, chars={'x'}).len == 0
    doAssert "x".strip(leading = false, trailing = false, chars={'x'}) == "x"

  block: # split
    var ret: seq[string] # or use `toSeq` or `collect`
    for p in split("/home/a1:xyz:/usr/bin", {':'}): ret.add p
    doAssert ret == @["/home/a1", "xyz", "/usr/bin"]

    let s = " this is an example  "
    let s2 = ":this;is;an:example;;"

    doAssert s.split() == @["", "this", "is", "an", "example", "", ""]
    doAssert s2.split(seps = {':', ';'}) == @["", "this", "is", "an", "example",
        "", ""]
    doAssert s.split(maxsplit = 4) == @["", "this", "is", "an", "example  "]
    doAssert s.split(' ', maxsplit = 1) == @["", "this is an example  "]
    doAssert s.split(" ", maxsplit = 4) == @["", "this", "is", "an", "example  "]
    # Empty string:
    doAssert "".split() == @[""]
    doAssert "".split(" ") == @[""]
    doAssert "".split({' '}) == @[""]
    # Empty separators:
    doAssert "".split({}) == @[""]
    doAssert "".split("") == @[""]
    doAssert s.split({}) == @[s]
    doAssert s.split("") == @[s]

  block: # splitLines
    let fixture = "a\nb\rc\r\nd"
    doAssert len(fixture.splitLines) == 4
    doAssert splitLines(fixture) == @["a", "b", "c", "d"]
    doAssert splitLines(fixture, keepEol=true) == @["a\n", "b\r", "c\r\n", "d"]

  block: # rsplit
    doAssert rsplit("foo bar", seps = Whitespace) == @["foo", "bar"]
    doAssert rsplit(" foo bar", seps = Whitespace, maxsplit = 1) == @[" foo", "bar"]
    doAssert rsplit(" foo bar ", seps = Whitespace, maxsplit = 1) == @[" foo bar", ""]
    doAssert rsplit(":foo:bar", sep = ':') == @["", "foo", "bar"]
    doAssert rsplit(":foo:bar", sep = ':', maxsplit = 2) == @["", "foo", "bar"]
    doAssert rsplit(":foo:bar", sep = ':', maxsplit = 3) == @["", "foo", "bar"]
    doAssert rsplit("foothebar", sep = "the") == @["foo", "bar"]
    # Empty string:
    doAssert "".rsplit() == @[""]
    doAssert "".rsplit(" ") == @[""]
    doAssert "".rsplit({' '}) == @[""]
    # Empty separators:
    let s = " this is an example  "
    doAssert "".rsplit({}) == @[""]
    doAssert "".rsplit("") == @[""]
    doAssert s.rsplit({}) == @[s]
    doAssert s.rsplit("") == @[s]

  block: # splitWhitespace
    let s = " this is an example  "
    doAssert s.splitWhitespace() == @["this", "is", "an", "example"]
    doAssert s.splitWhitespace(maxsplit = 1) == @["this", "is an example  "]
    doAssert s.splitWhitespace(maxsplit = 2) == @["this", "is", "an example  "]
    doAssert s.splitWhitespace(maxsplit = 3) == @["this", "is", "an", "example  "]
    doAssert s.splitWhitespace(maxsplit = 4) == @["this", "is", "an", "example"]

  block: # removeSuffix
    var s = "hello\n\r"
    s.removeSuffix
    doAssert s == "hello"
    s.removeSuffix
    doAssert s == "hello"

    s = "hello\n\n"
    s.removeSuffix
    doAssert s == "hello"

    s = "hello\r"
    s.removeSuffix
    doAssert s == "hello"

    s = "hello \n there"
    s.removeSuffix
    doAssert s == "hello \n there"

    s = "hello"
    s.removeSuffix("llo")
    doAssert s == "he"
    s.removeSuffix('e')
    doAssert s == "h"

    s = "hellos"
    s.removeSuffix({'s','z'})
    doAssert s == "hello"
    s.removeSuffix({'l','o'})
    doAssert s == "he"

    s = "aeiou"
    s.removeSuffix("")
    doAssert s == "aeiou"

    s = ""
    s.removeSuffix("")
    doAssert s == ""

    s = "  "
    s.removeSuffix
    doAssert s == "  "

    s = "  "
    s.removeSuffix("")
    doAssert s == "  "

    s = "    "
    s.removeSuffix(" ")
    doAssert s == "   "

    s = "    "
    s.removeSuffix(' ')
    doAssert s == ""

    # Contrary to Chomp in other languages
    # empty string does not change behaviour
    s = "hello\r\n\r\n"
    s.removeSuffix("")
    doAssert s == "hello\r\n\r\n"

  block: # removePrefix
    var s = "\n\rhello"
    s.removePrefix
    doAssert s == "hello"
    s.removePrefix
    doAssert s == "hello"

    s = "\n\nhello"
    s.removePrefix
    doAssert s == "hello"

    s = "\rhello"
    s.removePrefix
    doAssert s == "hello"

    s = "hello \n there"
    s.removePrefix
    doAssert s == "hello \n there"

    s = "hello"
    s.removePrefix("hel")
    doAssert s == "lo"
    s.removePrefix('l')
    doAssert s == "o"

    s = "hellos"
    s.removePrefix({'h','e'})
    doAssert s == "llos"
    s.removePrefix({'l','o'})
    doAssert s == "s"

    s = "aeiou"
    s.removePrefix("")
    doAssert s == "aeiou"

    s = ""
    s.removePrefix("")
    doAssert s == ""

    s = "  "
    s.removePrefix
    doAssert s == "  "

    s = "  "
    s.removePrefix("")
    doAssert s == "  "

    s = "    "
    s.removePrefix(" ")
    doAssert s == "   "

    s = "    "
    s.removePrefix(' ')
    doAssert s == ""

    # Contrary to Chomp in other languages
    # empty string does not change behaviour
    s = "\r\n\r\nhello"
    s.removePrefix("")
    doAssert s == "\r\n\r\nhello"

  block: # delete(slice)
    var s = "0123456789ABCDEFGH"
    delete(s, 4 .. 5)
    doAssert s == "01236789ABCDEFGH"
    delete(s, s.len-1 .. s.len-1)
    doAssert s == "01236789ABCDEFG"
    delete(s, 0..0)
    doAssert s == "1236789ABCDEFG"
    s = ""
    doAssertRaises(IndexDefect): delete(s, 0..0)
    doAssert s == ""
    s = "abc"
    doAssertRaises(IndexDefect): delete(s, -1 .. -2)
    doAssertRaises(IndexDefect): delete(s, 2..3)
    doAssertRaises(IndexDefect): delete(s, 3..2)
    delete(s, 2..2)
    doAssert s == "ab"
    delete(s, 1..0)
    doAssert s == "ab"
    delete(s, 0..0)
    doAssert s == "b"

  block: # delete(first, last)
    {.push warning[deprecated]:off.}
    var s = "0123456789ABCDEFGH"
    delete(s, 4, 5)
    doAssert s == "01236789ABCDEFGH"
    delete(s, s.len-1, s.len-1)
    doAssert s == "01236789ABCDEFG"
    delete(s, 0, 0)
    doAssert s == "1236789ABCDEFG"
    {.pop.}

  block: # find
    const haystack: string = "0123456789ABCDEFGH"
    doAssert haystack.find('A') == 10
    doAssert haystack.find('A', 5) == 10
    doAssert haystack.find('A', 5, 10) == 10
    doAssert haystack.find('A', 5, 9) == -1
    doAssert haystack.find("A") == 10
    doAssert haystack.find("A", 5) == 10
    doAssert haystack.find("A", 5, 10) == 10
    doAssert haystack.find("A", 5, 9) == -1
    doAssert haystack.find({'A'..'C'}) == 10
    doAssert haystack.find({'A'..'C'}, 5) == 10
    doAssert haystack.find({'A'..'C'}, 5, 10) == 10
    doAssert haystack.find({'A'..'C'}, 5, 9) == -1
    doAssert haystack.find('A', 0, 0) == -1 # search limited to the first char
    doAssert haystack.find('A', 5, 0) == -1 # last < start
    doAssert haystack.find('A', 5, 4) == -1 # last < start

    block:
      const haystack: string = "ABCABABABABCAB"
      doAssert haystack.len == 14

      # only last argument
      doAssert haystack.find("ABC") == 0
      doAssert haystack.find("ABC", last=13) == 0 # after the second ABC
      doAssert haystack.find("ABC", last=5) == 0 # before the second ABC

      # only start argument
      doAssert haystack.find("ABC", start=0) == 0
      doAssert haystack.find("ABC", start=1) == 9
      doAssert haystack.find("ABC", start=9) == 9
      doAssert haystack.find("ABC", start=10) == -1

      # both start and last arguments
      doAssert haystack.find("ABC", start=0, last=14) == 0
      doAssert haystack.find("ABC", start=0, last=13) == 0
      doAssert haystack.find("ABC", start=0, last=12) == 0
      doAssert haystack.find("ABC", start=1, last=13) == 9
      doAssert haystack.find("ABC", start=1, last=12) == 9
      doAssert haystack.find("ABC", start=1, last=11) == 9
      doAssert haystack.find("ABC", start=1, last=10) == -1

    doAssert "".find("/") == -1
    doAssert "/".find("/") == 0
    doAssert "/".find("//") == -1
    doAssert "///".find("//", start=3) == -1

    # searching for empty string
    doAssert "".find("") == 0
    doAssert "abc".find("") == 0
    doAssert "abc".find("", start=1) == 1
    doAssert "abc".find("", start=2) == 2
    doAssert "abc".find("", start=3) == 3
    doAssert "abc".find("", start=4) == -1
    doAssert "abc".find("", start=400) == -1
    doAssert "abc".find("", start=1, last=3) == 1
    doAssert "abc".find("", start=1, last=2) == 1
    doAssert "abc".find("", start=1, last=1) == 1
    doAssert "abc".find("", start=1, last=0) == 1
    doAssert "abc".find("", start=1, last = -1) == 1

    # when last <= start, searching for non-empty string
    block:
      let last: int = -1 # searching through whole line
      doAssert "abcd".find("ab", start=0, last=last) == 0
      doAssert "abcd".find("ab", start=1, last=last) == -1
      doAssert "abcd".find("bc", start=1, last=last) == 1
      doAssert "abcd".find("bc", start=2, last=last) == -1
    block:
      let last: int = 0
      doAssert "abcd".find("ab", start=0, last=last) == -1
      doAssert "abcd".find("ab", start=1, last=last) == -1
      doAssert "abcd".find("bc", start=1, last=last) == -1
      doAssert "abcd".find("bc", start=2, last=last) == -1
    block:
      let last: int = 1
      doAssert "abcd".find("ab", start=0, last=last) == 0
      doAssert "abcd".find("ab", start=1, last=last) == -1
      doAssert "abcd".find("bc", start=1, last=last) == -1
      doAssert "abcd".find("bc", start=2, last=last) == -1

  block: # rfind
    doAssert "0123456789ABCDEFGAH".rfind('A') == 17
    doAssert "0123456789ABCDEFGAH".rfind('A', last=13) == 10
    doAssert "0123456789ABCDEFGAH".rfind('H', last=13) == -1
    doAssert "0123456789ABCDEFGAH".rfind("A") == 17
    doAssert "0123456789ABCDEFGAH".rfind("A", last=13) == 10
    doAssert "0123456789ABCDEFGAH".rfind("H", last=13) == -1
    doAssert "0123456789ABCDEFGAH".rfind({'A'..'C'}) == 17
    doAssert "0123456789ABCDEFGAH".rfind({'A'..'C'}, last=13) == 12
    doAssert "0123456789ABCDEFGAH".rfind({'G'..'H'}, last=13) == -1
    doAssert "0123456789ABCDEFGAH".rfind('A', start=18) == -1
    doAssert "0123456789ABCDEFGAH".rfind('A', start=11, last=17) == 17
    doAssert "0123456789ABCDEFGAH".rfind("0", start=0) == 0
    doAssert "0123456789ABCDEFGAH".rfind("0", start=1) == -1
    doAssert "0123456789ABCDEFGAH".rfind("H", start=11) == 18
    doAssert "0123456789ABCDEFGAH".rfind({'0'..'9'}, start=5) == 9
    doAssert "0123456789ABCDEFGAH".rfind({'0'..'9'}, start=10) == -1

    doAssert "/1/2/3".rfind('/') == 4
    doAssert "/1/2/3".rfind('/', last=1) == 0
    doAssert "/1/2/3".rfind('0') == -1

    block:
      const haystack: string = "ABCABABABABCAB"
      doAssert haystack.len == 14
      doAssert haystack.rfind("ABC") == 9
      doAssert haystack.rfind("ABC", last=13) == 9
      doAssert haystack.rfind("ABC", last=12) == 9
      doAssert haystack.rfind("ABC", last=11) == 9
      doAssert haystack.rfind("ABC", last=10) == 0

      doAssert haystack.rfind("ABC", start=0) == 9
      doAssert haystack.rfind("ABC", start=1) == 9
      doAssert haystack.rfind("ABC", start=9) == 9
      doAssert haystack.rfind("ABC", start=10) == -1

      doAssert haystack.rfind("ABC", start=0, last=13) == 9
      doAssert haystack.rfind("ABC", start=0, last=12) == 9
      doAssert haystack.rfind("ABC", start=0, last=11) == 9
      doAssert haystack.rfind("ABC", start=0, last=10) == 0
      doAssert haystack.rfind("ABC", start=1, last=10) == -1

    doAssert "".rfind("/") == -1
    doAssert "/".rfind("/") == 0
    doAssert "/".rfind("//") == -1
    doAssert "///".rfind("//", start=3) == -1

    # searching for empty string
    doAssert "".rfind("") == 0
    doAssert "abc".rfind("") == 3
    doAssert "abc".rfind("", start=1) == 3
    doAssert "abc".rfind("", start=2) == 3
    doAssert "abc".rfind("", start=3) == 3
    doAssert "abc".rfind("", start=4) == 4
    doAssert "abc".rfind("", start=400) == 400

    doAssert "abc".rfind("", start=1, last=3) == 3
    doAssert "abc".rfind("", start=1, last=2) == 2
    doAssert "abc".rfind("", start=1, last=1) == 1
    # This returns the start index instead of the last index
    # because start > last
    doAssert "abc".rfind("", start=1, last=0) == 1
    doAssert "abc".rfind("", start=1, last = -1) == 3
    
    doAssert "abc".rfind("", start=0, last=0) == 0

    # when last <= start, searching for non-empty string
    block:
      let last: int = -1
      doAssert "abcd".rfind("ab", start=0, last=last) == 0
      doAssert "abcd".rfind("ab", start=1, last=last) == -1
      doAssert "abcd".rfind("bc", start=1, last=last) == 1
      doAssert "abcd".rfind("bc", start=2, last=last) == -1
    block:
      let last: int = 0
      doAssert "abcd".rfind("ab", start=0, last=last) == -1
      doAssert "abcd".rfind("ab", start=1, last=last) == -1
      doAssert "abcd".rfind("bc", start=1, last=last) == -1
      doAssert "abcd".rfind("bc", start=2, last=last) == -1
    block:
      let last: int = 1
      doAssert "abcd".rfind("ab", start=0, last=last) == 0
      doAssert "abcd".rfind("ab", start=1, last=last) == -1
      doAssert "abcd".rfind("bc", start=1, last=last) == -1
      doAssert "abcd".rfind("bc", start=2, last=last) == -1

  block: # trimZeros
    var x = "1200"
    x.trimZeros()
    doAssert x == "1200"
    x = "120.0"
    x.trimZeros()
    doAssert x == "120"
    x = "0."
    x.trimZeros()
    doAssert x == "0"
    x = "1.0e2"
    x.trimZeros()
    doAssert x == "1e2"
    x = "78.90"
    x.trimZeros()
    doAssert x == "78.9"
    x = "1.23e4"
    x.trimZeros()
    doAssert x == "1.23e4"
    x = "1.01"
    x.trimZeros()
    doAssert x == "1.01"
    x = "1.1001"
    x.trimZeros()
    doAssert x == "1.1001"
    x = "0.0"
    x.trimZeros()
    doAssert x == "0"
    x = "0.01"
    x.trimZeros()
    doAssert x == "0.01"
    x = "1e0"
    x.trimZeros()
    doAssert x == "1e0"
    x = "1.23"
    x.trimZeros()
    doAssert x == "1.23"

  block: # countLines
    proc assertCountLines(s: string) = doAssert s.countLines == s.splitLines.len
    assertCountLines("")
    assertCountLines("\n")
    assertCountLines("\n\n")
    assertCountLines("abc")
    assertCountLines("abc\n123")
    assertCountLines("abc\n123\n")
    assertCountLines("\nabc\n123")
    assertCountLines("\nabc\n123\n")

  block: # parseBinInt, parseHexInt, parseOctInt
    # binary
    doAssert "0b1111".parseBinInt == 15
    doAssert "0B1111".parseBinInt == 15
    doAssert "1111".parseBinInt == 15
    doAssert "1110".parseBinInt == 14
    doAssert "1_1_1_1".parseBinInt == 15
    doAssert "0b1_1_1_1".parseBinInt == 15
    rejectParse "".parseBinInt
    rejectParse "_".parseBinInt
    rejectParse "0b".parseBinInt
    rejectParse "0b1234".parseBinInt
    # hex
    doAssert "0x72".parseHexInt == 114
    doAssert "0X72".parseHexInt == 114
    doAssert "#72".parseHexInt == 114
    doAssert "72".parseHexInt == 114
    doAssert "FF".parseHexInt == 255
    doAssert "ff".parseHexInt == 255
    doAssert "fF".parseHexInt == 255
    doAssert "0x7_2".parseHexInt == 114
    rejectParse "".parseHexInt
    rejectParse "_".parseHexInt
    rejectParse "0x".parseHexInt
    rejectParse "0xFFG".parseHexInt
    rejectParse "reject".parseHexInt
    # octal
    doAssert "0o17".parseOctInt == 15
    doAssert "0O17".parseOctInt == 15
    doAssert "17".parseOctInt == 15
    doAssert "10".parseOctInt == 8
    doAssert "0o1_0_0".parseOctInt == 64
    rejectParse "".parseOctInt
    rejectParse "_".parseOctInt
    rejectParse "0o".parseOctInt
    rejectParse "9".parseOctInt
    rejectParse "0o9".parseOctInt
    rejectParse "reject".parseOctInt

  block: # parseHexStr
    doAssert "".parseHexStr == ""
    doAssert "00Ff80".parseHexStr == "\0\xFF\x80"
    try:
      discard "00Ff8".parseHexStr
      doAssert false, "Should raise ValueError"
    except ValueError:
      discard

    try:
      discard "0k".parseHexStr
      doAssert false, "Should raise ValueError"
    except ValueError:
      discard

    doAssert "".toHex == ""
    doAssert "\x00\xFF\x80".toHex == "00FF80"
    doAssert "0123456789abcdef".parseHexStr.toHex == "0123456789ABCDEF"

  block: # toHex
    doAssert(toHex(100i16, 32) == "00000000000000000000000000000064")
    when hasWorkingInt64:
      doAssert(toHex(-100i16, 32) == "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFF9C")
      doAssert(toHex(high(uint64)) == "FFFFFFFFFFFFFFFF")
      doAssert(toHex(high(uint64), 16) == "FFFFFFFFFFFFFFFF")
      doAssert(toHex(high(uint64), 32) == "0000000000000000FFFFFFFFFFFFFFFF")

  block: # insertSep
    doAssert(insertSep($1000_000) == "1_000_000")
    doAssert(insertSep($232) == "232")
    doAssert(insertSep($12345, ',') == "12,345")
    doAssert(insertSep($0) == "0")

  block: # repeat, spaces
    doAssert(' '.repeat(8) == "        ")
    doAssert(" ".repeat(8) == "        ")
    doAssert(spaces(8) == "        ")

    doAssert(' '.repeat(0) == "")
    doAssert(" ".repeat(0) == "")
    doAssert(spaces(0) == "")

  block: # toBin, toOct
    when hasWorkingInt64:
      # bug #11369
      var num: int64 = -1
      doAssert num.toBin(64) == "1111111111111111111111111111111111111111111111111111111111111111"
      doAssert num.toOct(24) == "001777777777777777777777"

  block: # replace
    doAssert "oo".replace("", "abc") == "oo"
    # bug #8911
    static:
      let a = ""
      let a2 = a.replace("\n", "\\n")

    static:
      let b = "b"
      let b2 = b.replace("\n", "\\n")

    block:
      let c = ""
      let c2 = c.replace("\n", "\\n")

  block: # replaceWord
    doAssert "-ld a-ldz -ld".replaceWord("-ld") == " a-ldz "
    doAssert "-lda-ldz -ld abc".replaceWord("-ld") == "-lda-ldz  abc"
    doAssert "-lda-ldz -ld abc".replaceWord("") == "-lda-ldz -ld abc"

  block: # multiReplace
    doAssert "abba".multiReplace(("a", "b"), ("b", "a")) == "baab"
    doAssert "Hello World.".multiReplace(("ello", "ELLO"), ("World.",
        "PEOPLE!")) == "HELLO PEOPLE!"
    doAssert "aaaa".multiReplace(("a", "aa"), ("aa", "bb")) == "aaaaaaaa"

  # `parseEnum`, ref issue #14030
  # check enum defined at top level # xxx this is probably irrelevant, and pollutes scope
  # for remaining tests
  type
    Foo = enum
      A = -10
      B = "bb"
      C = (-5, "ccc")
      D = 15
      E = "ee" # check that we count enum fields correctly

  block: # parseEnum
    block:
      let a = parseEnum[Foo]("A")
      let b = parseEnum[Foo]("bb")
      let c = parseEnum[Foo]("ccc")
      let d = parseEnum[Foo]("D")
      let e = parseEnum[Foo]("ee")
      doAssert a == A
      doAssert b == B
      doAssert c == C
      doAssert d == D
      doAssert e == E
      try:
        let f = parseEnum[Foo]("Bar")
        doAssert false
      except ValueError:
        discard

      # finally using default
      let g = parseEnum[Foo]("Bar", A)
      doAssert g == A

    block: # bug #19463
      const CAMPAIGN_TABLE = "wikientries_campaign"
      const CHARACTER_TABLE = "wikientries_character"

      type Tables = enum
        a = CAMPAIGN_TABLE,
        b = CHARACTER_TABLE,

      let myA = CAMPAIGN_TABLE
      doAssert $parseEnum[Tables](myA) == "wikientries_campaign"

    block: # check enum defined in block
      type
        Bar = enum
          V
          W = "ww"
          X = (3, "xx")
          Y = 10
          Z = "zz" # check that we count enum fields correctly

      let a = parseEnum[Bar]("V")
      let b = parseEnum[Bar]("ww")
      let c = parseEnum[Bar]("xx")
      let d = parseEnum[Bar]("Y")
      let e = parseEnum[Bar]("zz")
      doAssert a == V
      doAssert b == W
      doAssert c == X
      doAssert d == Y
      doAssert e == Z
      try:
        let f = parseEnum[Bar]("Baz")
        doAssert false
      except ValueError:
        discard

      # finally using default
      let g = parseEnum[Bar]("Baz", V)
      doAssert g == V

    block: # check ambiguous enum fails to parse
      type
        Ambig = enum
          f1 = "A"
          f2 = "B"
          f3 = "A"

      doAssert not compiles((let a = parseEnum[Ambig]("A")))

    block: # check almost ambiguous enum
      type
        AlmostAmbig = enum
          f1 = "someA"
          f2 = "someB"
          f3 = "SomeA"

      let a = parseEnum[AlmostAmbig]("someA")
      let b = parseEnum[AlmostAmbig]("someB")
      let c = parseEnum[AlmostAmbig]("SomeA")
      doAssert a == f1
      doAssert b == f2
      doAssert c == f3

    block:
      type MyEnum = enum enA, enB, enC, enuD, enE
      doAssert parseEnum[MyEnum]("enu_D") == enuD

      doAssert parseEnum("invalid enum value", enC) == enC
    
    block: # issue #22726
      type SomeEnum = enum A, B, C

      proc assignEnum(dest: var enum, s: string) =
        type ty = typeof(dest)
        dest = parseEnum[ty](s)
      
      var v: SomeEnum
      v.assignEnum("A")
      doAssert v == A

  block: # indentation
    doAssert 0 == indentation """
hey
  low
    there
"""
    doAssert 2 == indentation """
  hey
    low
      there
"""
    doAssert 2 == indentation """  hey
    low
      there
"""
    doAssert 2 == indentation """  hey
    low
      there"""
    doAssert 0 == indentation ""
    doAssert 0 == indentation "  \n  \n"
    doAssert 0 == indentation "    "

  block: # indent
    doAssert "  foo\n  bar".indent(4, "Q") == "QQQQ  foo\nQQQQ  bar"

  block: # unindent
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

  block: # formatBiggestFloat
    disableVm:
      doAssert formatBiggestFloat(1234.567, ffDecimal, -1) == "1234.567000"
      when not defined(js):
        doAssert formatBiggestFloat(1234.567, ffDecimal, 0) == "1235." # bugs 8242, 12586
      doAssert formatBiggestFloat(1234.567, ffDecimal, 1) == "1234.6"
      doAssert formatBiggestFloat(0.00000000001, ffDecimal, 11) == "0.00000000001"
      doAssert formatBiggestFloat(0.00000000001, ffScientific, 1, ',') in
                                                      ["1,0e-11", "1,0e-011"]
  block: # formatFloat
    disableVm:
      # bug #6589
      when not defined(js):
        doAssert formatFloat(123.456, ffScientific, precision = -1) == "1.234560e+02"

  block: # `%`
    doAssert "$# $3 $# $#" % ["a", "b", "c"] == "a c b c"
    doAssert "${1}12 ${-1}$2" % ["a", "b"] == "a12 bb"
    doAssert "$animal eats $food." % ["animal", "The cat", "food", "fish"] ==
             "The cat eats fish."

  block: # formatSize
    disableVm:
      when hasWorkingInt64:
        doAssert formatSize((1'i64 shl 31) + (300'i64 shl 20)) == "2.293GiB" # <=== bug #8231
      doAssert formatSize((2.234*1024*1024).int) == "2.234MiB"
      doAssert formatSize(4096) == "4KiB"
      doAssert formatSize(4096, prefix = bpColloquial, includeSpace = true) == "4 kB"
      doAssert formatSize(4096, includeSpace = true) == "4 KiB"
      doAssert formatSize(5_378_934, prefix = bpColloquial, decimalSep = ',') == "5,13MB"

  block: # formatEng
    disableVm:
      doAssert formatEng(0, 2, trim = false) == "0.00"
      doAssert formatEng(0, 2) == "0"
      doAssert formatEng(53, 2, trim = false) == "53.00"
      doAssert formatEng(0.053, 2, trim = false) == "53.00e-3"
      doAssert formatEng(0.053, 4, trim = false) == "53.0000e-3"
      doAssert formatEng(0.053, 4, trim = true) == "53e-3"
      doAssert formatEng(0.053, 0) == "53e-3"
      doAssert formatEng(52731234) == "52.731234e6"
      doAssert formatEng(-52731234) == "-52.731234e6"
      doAssert formatEng(52731234, 1) == "52.7e6"
      doAssert formatEng(-52731234, 1) == "-52.7e6"
      doAssert formatEng(52731234, 1, decimalSep = ',') == "52,7e6"
      doAssert formatEng(-52731234, 1, decimalSep = ',') == "-52,7e6"

      doAssert formatEng(4100, siPrefix = true, unit = "V") == "4.1 kV"
      doAssert formatEng(4.1, siPrefix = true, unit = "V",
          useUnitSpace = true) == "4.1 V"
      doAssert formatEng(4.1, siPrefix = true) == "4.1" # Note lack of space
      doAssert formatEng(4100, siPrefix = true) == "4.1 k"
      doAssert formatEng(4.1, siPrefix = true, unit = "",
          useUnitSpace = true) == "4.1 " # Includes space
      doAssert formatEng(4100, siPrefix = true, unit = "") == "4.1 k"
      doAssert formatEng(4100) == "4.1e3"
      doAssert formatEng(4100, unit = "V", useUnitSpace = true) == "4.1e3 V"
      doAssert formatEng(4100, unit = "", useUnitSpace = true) == "4.1e3 "
      # Don't use SI prefix as number is too big
      doAssert formatEng(3.1e22, siPrefix = true, unit = "a",
          useUnitSpace = true) == "31e21 a"
      # Don't use SI prefix as number is too small
      doAssert formatEng(3.1e-25, siPrefix = true, unit = "A",
          useUnitSpace = true) == "310e-27 A"

  block: # align
    doAssert align("abc", 4) == " abc"
    doAssert align("a", 0) == "a"
    doAssert align("1232", 6) == "  1232"
    doAssert align("1232", 6, '#') == "##1232"

  block: # alignLeft
    doAssert alignLeft("abc", 4) == "abc "
    doAssert alignLeft("a", 0) == "a"
    doAssert alignLeft("1232", 6) == "1232  "
    doAssert alignLeft("1232", 6, '#') == "1232##"

  block: # center
    doAssert center("foo", 13) == "     foo     "
    doAssert center("foo", 0) == "foo"
    doAssert center("foo", 3, fillChar = 'a') == "foo"
    doAssert center("foo", 10, fillChar = '\t') == "\t\t\tfoo\t\t\t\t"

  block: # count
    doAssert count("foofoofoo", "foofoo") == 1
    doAssert count("foofoofoo", "foofoo", overlapping = true) == 2
    doAssert count("foofoofoo", 'f') == 3
    doAssert count("foofoofoobar", {'f', 'b'}) == 4

  block: # isAlphaAscii
    doAssert isAlphaAscii('r')
    doAssert isAlphaAscii('A')
    doAssert(not isAlphaAscii('$'))

  block: # isAlphaNumeric
    doAssert isAlphaNumeric('3')
    doAssert isAlphaNumeric('R')
    doAssert(not isAlphaNumeric('!'))

  block: # isDigit
    doAssert isDigit('3')
    doAssert(not isDigit('a'))
    doAssert(not isDigit('%'))

  block: # isSpaceAscii
    doAssert isSpaceAscii('\t')
    doAssert isSpaceAscii('\l')
    doAssert(not isSpaceAscii('A'))

  block: # isEmptyOrWhitespace
    doAssert(isEmptyOrWhitespace(""))
    doAssert(isEmptyOrWhitespace("       "))
    doAssert(isEmptyOrWhitespace("\t\l \v\r\f"))
    doAssert(not isEmptyOrWhitespace("ABc   \td"))

  block: # isLowerAscii
    doAssert isLowerAscii('a')
    doAssert isLowerAscii('z')
    doAssert(not isLowerAscii('A'))
    doAssert(not isLowerAscii('5'))
    doAssert(not isLowerAscii('&'))
    doAssert(not isLowerAscii(' '))

  block: # isUpperAscii
    doAssert isUpperAscii('A')
    doAssert(not isUpperAscii('b'))
    doAssert(not isUpperAscii('5'))
    doAssert(not isUpperAscii('%'))

  block: # unescape
    doAssert(unescape(r"\x013", "", "") == "\x013")

  block: # join
    doAssert join(["foo", "bar", "baz"]) == "foobarbaz"
    doAssert join(@["foo", "bar", "baz"], ", ") == "foo, bar, baz"
    doAssert join([1, 2, 3]) == "123"
    doAssert join(@[1, 2, 3], ", ") == "1, 2, 3"

  block: # startsWith / endsWith
    var s = "abcdef"
    doAssert s.startsWith('a')
    doAssert s.startsWith('b') == false
    doAssert s.endsWith('f')
    doAssert s.endsWith('a') == false
    doAssert s.endsWith('\0') == false

  block: # nimIdentNormalize
    doAssert nimIdentNormalize("") == ""
    doAssert nimIdentNormalize("foo") == "foo"
    doAssert nimIdentNormalize("foo_bar") == "foobar"
    doAssert nimIdentNormalize("Foo_bar") == "Foobar"
    doAssert nimIdentNormalize("_Foo_bar") == "_foobar"

  block: # bug #19500
    doAssert "abc \0 def".find("def") == 6
    doAssert "abc \0 def".find('d') == 6


static: main()
main()
