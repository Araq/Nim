discard """
  matrix: "--mm:refc; --mm:orc"
"""

import std/encodings
import std/assertions

var fromGBK = open("utf-8", "gbk")
var toGBK = open("gbk", "utf-8")

var fromGB2312 = open("utf-8", "gb2312")
var toGB2312 = open("gb2312", "utf-8")


block:
  let data = "\215\237\186\243\178\187\214\170\204\236\212\218\203\174\163\172\194\250\180\178\208\199\195\206\209\185\208\199\186\211"
  doAssert fromGBK.convert(data) == "醉后不知天在水，满床星梦压星河"

block:
  let data = "万两黄金容易得，知心一个也难求"
  doAssert toGBK.convert(data) == "\205\242\193\189\187\198\189\240\200\221\210\215\181\195\163\172\214\170\208\196\210\187\184\246\210\178\196\209\199\243"


block:
  let data = "\215\212\208\197\200\203\201\250\182\254\176\217\196\234\163\172\187\225\181\177\203\174\187\247\200\253\199\167\192\239"
  doAssert fromGB2312.convert(data) == "自信人生二百年，会当水击三千里"

block:
  let data = "谁怕？一蓑烟雨任平生"
  doAssert toGB2312.convert(data) == "\203\173\197\194\163\191\210\187\203\242\209\204\211\234\200\206\198\189\201\250"


when defined(windows):
  block should_throw_on_unsupported_conversions:
    let original = "some string"

    doAssertRaises(EncodingError):
      discard convert(original, "utf-8", "utf-32")

    doAssertRaises(EncodingError):
      discard convert(original, "utf-8", "unicodeFFFE")

    doAssertRaises(EncodingError):
      discard convert(original, "utf-8", "utf-32BE")

    doAssertRaises(EncodingError):
      discard convert(original, "unicodeFFFE", "utf-8")

    doAssertRaises(EncodingError):
      discard convert(original, "utf-32", "utf-8")

    doAssertRaises(EncodingError):
      discard convert(original, "utf-32BE", "utf-8")

  block should_convert_from_utf16_to_utf8:
    let original = "\x42\x04\x35\x04\x41\x04\x42\x04" # utf-16 little endian test string "тест"
    let result = convert(original, "utf-8", "utf-16")
    doAssert(result == "\xd1\x82\xd0\xb5\xd1\x81\xd1\x82")

  block should_convert_from_utf16_to_win1251:
    let original = "\x42\x04\x35\x04\x41\x04\x42\x04" # utf-16 little endian test string "тест"
    let result = convert(original, "windows-1251", "utf-16")
    doAssert(result == "\xf2\xe5\xf1\xf2")

  block should_convert_from_win1251_to_koi8r:
    let original = "\xf2\xe5\xf1\xf2" # win1251 test string "тест"
    let result = convert(original, "koi8-r", "windows-1251")
    doAssert(result == "\xd4\xc5\xd3\xd4")

  block should_convert_from_koi8r_to_win1251:
    let original = "\xd4\xc5\xd3\xd4" # koi8r test string "тест"
    let result = convert(original, "windows-1251", "koi8-r")
    doAssert(result == "\xf2\xe5\xf1\xf2")

  block should_convert_from_utf8_to_win1251:
    let original = "\xd1\x82\xd0\xb5\xd1\x81\xd1\x82" # utf-8 test string "тест"
    let result = convert(original, "windows-1251", "utf-8")
    doAssert(result == "\xf2\xe5\xf1\xf2")

  block should_convert_from_utf8_to_utf16:
    let original = "\xd1\x82\xd0\xb5\xd1\x81\xd1\x82" # utf-8 test string "тест"
    let result = convert(original, "utf-16", "utf-8")
    doAssert(result == "\x42\x04\x35\x04\x41\x04\x42\x04")

  block should_handle_empty_string_for_any_conversion:
    let original = ""
    var result = convert(original, "utf-16", "utf-8")
    doAssert(result == "")
    result = convert(original, "utf-8", "utf-16")
    doAssert(result == "")
    result = convert(original, "windows-1251", "koi8-r")
    doAssert(result == "")


block:
  let
    orig = "öäüß"
    cp1252 = convert(orig, "CP1252", "UTF-8")
    ibm850 = convert(cp1252, "ibm850", "CP1252")
    current = getCurrentEncoding()
  doAssert orig == "\195\182\195\164\195\188\195\159"
  doAssert ibm850 == "\148\132\129\225"
  doAssert convert(ibm850, current, "ibm850") == orig

block: # fixes about #23481
  doAssertRaises EncodingError:
    discard open(destEncoding="this is a invalid enc")
