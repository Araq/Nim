discard """
  matrix: "--mm:refc; --mm:orc"
"""

import std/unicode
import std/assertions

proc asRune(s: static[string]): Rune =
  ## Compile-time conversion proc for converting string literals to a Rune
  ## value. Returns the first Rune of the specified string.
  ##
  ## Shortcuts code like ``"å".runeAt(0)`` to ``"å".asRune`` and returns a
  ## compile-time constant.
  if s.len == 0: Rune(0)
  else: s.runeAt(0)

let
  someString = "öÑ"
  someRunes = toRunes(someString)
  compared = (someString == $someRunes)
doAssert compared == true

proc testReplacements(word: string): string =
  case word
  of "two":
    return "2"
  of "foo":
    return "BAR"
  of "βeta":
    return "beta"
  of "alpha":
    return "αlpha"
  else:
    return "12345"

doAssert translate("two not alpha foo βeta", testReplacements) == "2 12345 αlpha BAR beta"
doAssert translate("  two not foo βeta  ", testReplacements) == "  2 12345 BAR beta  "

doAssert title("foo bar") == "Foo Bar"
doAssert title("αlpha βeta γamma") == "Αlpha Βeta Γamma"
doAssert title("") == ""

doAssert capitalize("βeta") == "Βeta"
doAssert capitalize("foo") == "Foo"
doAssert capitalize("") == ""

doAssert swapCase("FooBar") == "fOObAR"
doAssert swapCase(" ") == " "
doAssert swapCase("Αlpha Βeta Γamma") == "αLPHA βETA γAMMA"
doAssert swapCase("a✓B") == "A✓b"
doAssert swapCase("Јамогујестистаклоитоминештети") == "јАМОГУЈЕСТИСТАКЛОИТОМИНЕШТЕТИ"
doAssert swapCase("ὕαλονϕαγεῖνδύναμαιτοῦτοοὔμεβλάπτει") == "ὝΑΛΟΝΦΑΓΕῖΝΔΎΝΑΜΑΙΤΟῦΤΟΟὔΜΕΒΛΆΠΤΕΙ"
doAssert swapCase("Կրնամապակիուտեևինծիանհանգիստչըներ") == "կՐՆԱՄԱՊԱԿԻՈՒՏԵևԻՆԾԻԱՆՀԱՆԳԻՍՏՉԸՆԵՐ"
doAssert swapCase("") == ""

doAssert isAlpha("r")
doAssert isAlpha("α")
doAssert isAlpha("ϙ")
doAssert isAlpha("ஶ")
doAssert isAlpha("网")
doAssert(not isAlpha("$"))
doAssert(not isAlpha(""))

doAssert isAlpha("Βeta")
doAssert isAlpha("Args")
doAssert isAlpha("𐌼𐌰𐌲𐌲𐌻𐌴𐍃𐍄𐌰𐌽")
doAssert isAlpha("ὕαλονϕαγεῖνδύναμαιτοῦτοοὔμεβλάπτει")
doAssert isAlpha("Јамогујестистаклоитоминештети")
doAssert isAlpha("Կրնամապակիուտեևինծիանհանգիստչըներ")
doAssert isAlpha("编程语言")
doAssert(not isAlpha("$Foo✓"))
doAssert(not isAlpha("⠙⠕⠑⠎⠝⠞"))

doAssert isSpace("\t")
doAssert isSpace("\l")
doAssert(not isSpace("Β"))
doAssert(not isSpace("Βeta"))

doAssert isSpace("\t\l \v\r\f")
doAssert isSpace("       ")
doAssert(not isSpace(""))
doAssert(not isSpace("ΑΓc   \td"))

doAssert(not isLower(' '.Rune))

doAssert(not isUpper(' '.Rune))

doAssert toUpper("Γ") == "Γ"
doAssert toUpper("b") == "B"
doAssert toUpper("α") == "Α"
doAssert toUpper("✓") == "✓"
doAssert toUpper("ϙ") == "Ϙ"
doAssert toUpper("") == ""

doAssert toUpper("ΑΒΓ") == "ΑΒΓ"
doAssert toUpper("AAccβ") == "AACCΒ"
doAssert toUpper("A✓$β") == "A✓$Β"

doAssert toLower("a") == "a"
doAssert toLower("γ") == "γ"
doAssert toLower("Γ") == "γ"
doAssert toLower("4") == "4"
doAssert toLower("Ϙ") == "ϙ"
doAssert toLower("") == ""

doAssert toLower("abcdγ") == "abcdγ"
doAssert toLower("abCDΓ") == "abcdγ"
doAssert toLower("33aaΓ") == "33aaγ"

doAssert reversed("Reverse this!") == "!siht esreveR"
doAssert reversed("先秦兩漢") == "漢兩秦先"
doAssert reversed("as⃝df̅") == "f̅ds⃝a"
doAssert reversed("a⃞b⃞c⃞") == "c⃞b⃞a⃞"
doAssert reversed("ὕαλονϕαγεῖνδύναμαιτοῦτοοὔμεβλάπτει") == "ιετπάλβεμὔοοτῦοτιαμανύδνῖεγαϕνολαὕ"
doAssert reversed("Јамогујестистаклоитоминештети") == "итетшенимотиолкатситсејугомаЈ"
doAssert reversed("Կրնամապակիուտեևինծիանհանգիստչըներ") == "րենըչտսիգնահնաիծնիևետւոիկապամանրԿ"
doAssert len(toRunes("as⃝df̅")) == runeLen("as⃝df̅")
const test = "as⃝"
doAssert lastRune(test, test.len-1)[1] == 3
doAssert graphemeLen("è", 0) == 2

# test for rune positioning and runeSubStr()
let s = "Hänsel  ««: 10,00€"

var t = ""
for c in s.utf8:
  t.add c

doAssert(s == t)

doAssert(runeReverseOffset(s, 1) == (20, 18))
doAssert(runeReverseOffset(s, 19) == (-1, 18))

doAssert(runeStrAtPos(s, 0) == "H")
doAssert(runeSubStr(s, 0, 1) == "H")
doAssert(runeStrAtPos(s, 10) == ":")
doAssert(runeSubStr(s, 10, 1) == ":")
doAssert(runeStrAtPos(s, 9) == "«")
doAssert(runeSubStr(s, 9, 1) == "«")
doAssert(runeStrAtPos(s, 17) == "€")
doAssert(runeSubStr(s, 17, 1) == "€")
# echo runeStrAtPos(s, 18) # index error

doAssert(runeSubStr(s, 0) == "Hänsel  ««: 10,00€")
doAssert(runeSubStr(s, -18) == "Hänsel  ««: 10,00€")
doAssert(runeSubStr(s, 10) == ": 10,00€")
doAssert(runeSubStr(s, 18) == "")
doAssert(runeSubStr(s, 0, 10) == "Hänsel  ««")

doAssert(runeSubStr(s, 12) == "10,00€")
doAssert(runeSubStr(s, -6) == "10,00€")

doAssert(runeSubStr(s, 12, 5) == "10,00")
doAssert(runeSubStr(s, 12, -1) == "10,00")
doAssert(runeSubStr(s, -6, 5) == "10,00")
doAssert(runeSubStr(s, -6, -1) == "10,00")

doAssert(runeSubStr(s, 0, 100) == "Hänsel  ««: 10,00€")
doAssert(runeSubStr(s, -100, 100) == "Hänsel  ««: 10,00€")
doAssert(runeSubStr(s, 0, -100) == "")
doAssert(runeSubStr(s, 100, -100) == "")

block splitTests:
  let s = " this is an example  "
  let s2 = ":this;is;an:example;;"
  let s3 = ":this×is×an:example××"
  doAssert s.split() == @["", "this", "is", "an", "example", "", ""]
  doAssert s2.split(seps = [':'.Rune, ';'.Rune]) == @["", "this", "is", "an",
      "example", "", ""]
  doAssert s3.split(seps = [':'.Rune, "×".asRune]) == @["", "this", "is",
      "an", "example", "", ""]
  doAssert s.split(maxsplit = 4) == @["", "this", "is", "an", "example  "]
  doAssert s.split(' '.Rune, maxsplit = 1) == @["", "this is an example  "]
  doAssert s3.split("×".runeAt(0)) == @[":this", "is", "an:example", "", ""]

block stripTests:
  doAssert(strip("") == "")
  doAssert(strip(" ") == "")
  doAssert(strip("y") == "y")
  doAssert(strip("  foofoofoo  ") == "foofoofoo")
  doAssert(strip("sfoofoofoos", runes = ['s'.Rune]) == "foofoofoo")

  block:
    let stripTestRunes = ['b'.Rune, 'a'.Rune, 'r'.Rune]
    doAssert(strip("barfoofoofoobar", runes = stripTestRunes) == "foofoofoo")
  doAssert(strip("sfoofoofoos", leading = false, runes = ['s'.Rune]) == "sfoofoofoo")
  doAssert(strip("sfoofoofoos", trailing = false, runes = ['s'.Rune]) == "foofoofoos")

  block:
    let stripTestRunes = ["«".asRune, "»".asRune]
    doAssert(strip("«TEXT»", runes = stripTestRunes) == "TEXT")
  doAssert(strip("copyright©", leading = false, runes = ["©".asRune]) == "copyright")
  doAssert(strip("¿Question?", trailing = false, runes = ["¿".asRune]) == "Question?")
  doAssert(strip("×text×", leading = false, runes = ["×".asRune]) == "×text")
  doAssert(strip("×text×", trailing = false, runes = ["×".asRune]) == "text×")

block repeatTests:
  doAssert repeat('c'.Rune, 5) == "ccccc"
  doAssert repeat("×".asRune, 5) == "×××××"

block alignTests:
  doAssert align("abc", 4) == " abc"
  doAssert align("a", 0) == "a"
  doAssert align("1232", 6) == "  1232"
  doAssert align("1232", 6, '#'.Rune) == "##1232"
  doAssert align("1232", 6, "×".asRune) == "××1232"
  doAssert alignLeft("abc", 4) == "abc "
  doAssert alignLeft("a", 0) == "a"
  doAssert alignLeft("1232", 6) == "1232  "
  doAssert alignLeft("1232", 6, '#'.Rune) == "1232##"
  doAssert alignLeft("1232", 6, "×".asRune) == "1232××"

block differentSizes:
  # upper and lower variants have different number of bytes
  doAssert toLower("AẞC") == "aßc"
  doAssert toLower("ȺẞCD") == "ⱥßcd"
  doAssert toUpper("ⱥbc") == "ȺBC"
  doAssert toUpper("rsⱦuv") == "RSȾUV"
  doAssert swapCase("ⱥbCd") == "ȺBcD"
  doAssert swapCase("XyꟆaB") == "xYᶎAb"
  doAssert swapCase("aᵹcᲈd") == "AꝽCꙊD"

block: # bug #17768
  let s1 = "abcdef"
  let s2 = "abcdéf"

  doAssert s1.runeSubStr(0, -1) == "abcde"
  doAssert s2.runeSubStr(0, -1) == "abcdé"
