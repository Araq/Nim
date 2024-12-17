discard """
  matrix: "--mm:refc; --mm:orc"
  targets: "c js"
"""

import experimental/diff
import std/strutils
import std/assertions

proc testHelper(f: seq[Item]): string =
  result = ""
  for it in f:
    result.add(
      $it.deletedA & "." & $it.insertedB & "." & $it.startA & "." & $it.startB & "*"
    )

proc main() =
  var a, b: string

  # Diff Self Test
  # test all changes
  a = "a,b,c,d,e,f,g,h,i,j,k,l".replace(',', '\n')
  b = "0,1,2,3,4,5,6,7,8,9".replace(',', '\n')
  doAssert(testHelper(diffText(a, b)) ==
    "12.10.0.0*",
    "all-changes test failed.")
  # test all same
  a = "a,b,c,d,e,f,g,h,i,j,k,l".replace(',', '\n')
  b = a
  doAssert(testHelper(diffText(a, b)) ==
    "",
    "all-same test failed.")

  # test snake
  a = "a,b,c,d,e,f".replace(',', '\n')
  b = "b,c,d,e,f,x".replace(',', '\n')
  doAssert(testHelper(diffText(a, b)) ==
    "1.0.0.0*0.1.6.5*",
    "snake test failed.")

  # 2002.09.20 - repro
  a = "c1,a,c2,b,c,d,e,g,h,i,j,c3,k,l".replace(',', '\n')
  b = "C1,a,C2,b,c,d,e,I1,e,g,h,i,j,C3,k,I2,l".replace(',', '\n')
  doAssert(testHelper(diffText(a, b)) ==
    "1.1.0.0*1.1.2.2*0.2.7.7*1.1.11.13*0.1.13.15*",
    "repro20020920 test failed.")

  # 2003.02.07 - repro
  a = "F".replace(',', '\n')
  b = "0,F,1,2,3,4,5,6,7".replace(',', '\n')
  doAssert(testHelper(diffText(a, b)) ==
    "0.1.0.0*0.7.1.2*",
    "repro20030207 test failed.")

  # Muegel - repro
  a = "HELLO\nWORLD"
  b = "\n\nhello\n\n\n\nworld\n"
  doAssert(testHelper(diffText(a, b)) ==
    "2.8.0.0*",
    "repro20030409 test failed.")

  # test some differences
  a = "a,b,-,c,d,e,f,f".replace(',', '\n')
  b = "a,b,x,c,e,f".replace(',', '\n')
  doAssert(testHelper(diffText(a, b)) ==
    "1.1.2.2*1.0.4.4*1.0.7.6*",
    "some-changes test failed.")

  # test one change within long chain of repeats
  a = "a,a,a,a,a,a,a,a,a,a".replace(',', '\n')
  b = "a,a,a,a,-,a,a,a,a,a".replace(',', '\n')
  doAssert(testHelper(diffText(a, b)) ==
    "0.1.4.4*1.0.9.10*",
    "long chain of repeats test failed.")
main()
static: main()
