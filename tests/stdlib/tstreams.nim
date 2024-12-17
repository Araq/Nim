discard """
  matrix: "--mm:refc; --mm:orc"
  input: "Arne"
  output: '''
Hello! What is your name?
Nice name: Arne
fs is: nil
threw exception
_heh_
'''
  nimout: '''
I
AM
GROOT
'''
"""


import std/[syncio, streams, assertions]


block tstreams:
  var outp = newFileStream(stdout)
  var inp = newFileStream(stdin)
  writeLine(outp, "Hello! What is your name?")
  var line = readLine(inp)
  writeLine(outp, "Nice name: " & line)


block tstreams2:
  var
    fs = newFileStream("amissingfile.txt")
    line = ""
  echo "fs is: ",repr(fs)
  if not isNil(fs):
    while fs.readLine(line):
      echo line
    fs.close()


block tstreams3:
  try:
    var fs = openFileStream("shouldneverexist.txt")
  except IOError:
    echo "threw exception"

  static:
    var s = newStringStream("I\nAM\nGROOT")
    for line in s.lines:
      echo line
    s.close


block:
  let fs = newFileStream("amissingfile.txt")
  defer: fs.close()
  doAssert isNil(fs)

# bug #12410

var a = newStringStream "hehohihahuhyh"
a.readDataStrImpl = nil

var buffer = "_ooo_"

doAssert a.readDataStr(buffer, 1..3) == 3

echo buffer


block:
  var ss = newStringStream("The quick brown fox jumped over the lazy dog.\nThe lazy dog ran")
  doAssert(ss.getPosition == 0)
  doAssert(ss.peekStr(5) == "The q")
  doAssert(ss.getPosition == 0) # haven't moved
  doAssert(ss.readStr(5) == "The q")
  doAssert(ss.getPosition == 5) # did move
  doAssert(ss.peekLine() == "uick brown fox jumped over the lazy dog.")
  doAssert(ss.getPosition == 5) # haven't moved
  var str = newString(100)
  doAssert(ss.peekLine(str))
  doAssert(str == "uick brown fox jumped over the lazy dog.")
  doAssert(ss.getPosition == 5) # haven't moved
  # bug #19707 - Ensure we dont error with writing over literals on arc/orc
  ss.setPosition(0)
  ss.write("hello")
  ss.setPosition(0)
  doAssert(ss.peekStr(5) == "hello")

# bug #19716
static: # Ensure streams it doesnt break with nimscript on arc/orc #19716
  let s = newStringStream("a")
  doAssert s.data == "a"

static: # issue #24054, readStr
  var s = newStringStream("foo bar baz")
  doAssert s.readStr(3) == "foo"

template main =
  var strm = newStringStream("abcde")
  var buffer = "12345"
  doAssert strm.readDataStr(buffer, 0..3) == 4
  doAssert buffer == "abcd5"
  strm.close()

static: main()
main()
