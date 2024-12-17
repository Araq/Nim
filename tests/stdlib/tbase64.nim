discard """
  matrix: "--mm:refc; --mm:orc"
  targets: "c js"
"""
import std/assertions
import std/base64

template main() =
  doAssert encode("a") == "YQ=="
  doAssert encode("Hello World") == "SGVsbG8gV29ybGQ="
  doAssert encode("leasure.") == "bGVhc3VyZS4="
  doAssert encode("easure.") == "ZWFzdXJlLg=="
  doAssert encode("asure.") == "YXN1cmUu"
  doAssert encode("sure.") == "c3VyZS4="
  doAssert encode([1,2,3]) == "AQID"
  doAssert encode(['h','e','y']) == "aGV5"

  doAssert encode("") == ""
  doAssert decode("") == ""

  doAssert decode(" ") == ""

  const testInputExpandsTo76 = "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
  const testInputExpands = "++++++++++++++++++++++++++++++"
  const longText = """Man is distinguished, not only by his reason, but by this
    singular passion from other animals, which is a lust of the mind,
    that by a perseverance of delight in the continued and indefatigable
    generation of knowledge, exceeds the short vehemence of any carnal
    pleasure."""
  const tests = ["", "abc", "xyz", "man", "leasure.", "sure.", "easure.",
                 "asure.", longText, testInputExpandsTo76, testInputExpands]

  doAssert encodeMime("foobarbaz", lineLen=4) == "Zm9v\r\nYmFy\r\nYmF6"
  doAssert decode("Zm9v\r\nYmFy\r\nYmF6") == "foobarbaz"

  for t in items(tests):
    doAssert decode(encode(t)) == t
    doAssert decode(encodeMime(t, lineLen=40)) == t
    doAssert decode(encodeMime(t, lineLen=76)) == t

  doAssertRaises(ValueError): discard decode("SGVsbG\x008gV29ybGQ=")

  block base64urlSafe:
    doAssert encode("c\xf7>", safe = true) == "Y_c-"
    doAssert encode("c\xf7>", safe = false) == "Y/c+" # Not a nice URL :(
    doAssert decode("Y/c+") == decode("Y_c-")
    # Output must not change with safe=true
    doAssert encode("Hello World", safe = true) == "SGVsbG8gV29ybGQ="
    doAssert encode("leasure.", safe = true)  == "bGVhc3VyZS4="
    doAssert encode("easure.", safe = true) == "ZWFzdXJlLg=="
    doAssert encode("asure.", safe = true) == "YXN1cmUu"
    doAssert encode("sure.", safe = true) == "c3VyZS4="
    doAssert encode([1,2,3], safe = true) == "AQID"
    doAssert encode(['h','e','y'], safe = true) == "aGV5"
    doAssert encode("", safe = true) == ""
    doAssert encode("the quick brown dog jumps over the lazy fox", safe = true) == "dGhlIHF1aWNrIGJyb3duIGRvZyBqdW1wcyBvdmVyIHRoZSBsYXp5IGZveA=="

func mainNoSideEffects() = main()

static: main()
main()
static: mainNoSideEffects()
mainNoSideEffects()
