discard """
  matrix: "--mm:refc; --mm:orc"
"""

import std/[strscans, strutils, assertions]

block ParsePasswd:
  proc parsePasswd(content: string): seq[string] =
    result = @[]
    var idx = 0
    while true:
      var entry = ""
      if scanp(content, idx, +(~{'\L', '\0'} -> entry.add($_)), '\L'):
        result.add entry
      else:
        break

  const etcPasswd = """root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/bin/sh
bin:x:2:2:bin:/bin:/bin/sh
sys:x:3:3:sys:/dev:/bin/sh
nobody:x:65534:65534:nobody:/nonexistent:/bin/sh
messagebus:x:103:107::/var/run/dbus:/bin/false
"""

  const parsedEtcPasswd = @[
    "root:x:0:0:root:/root:/bin/bash",
    "daemon:x:1:1:daemon:/usr/sbin:/bin/sh",
    "bin:x:2:2:bin:/bin:/bin/sh",
    "sys:x:3:3:sys:/dev:/bin/sh",
    "nobody:x:65534:65534:nobody:/nonexistent:/bin/sh",
    "messagebus:x:103:107::/var/run/dbus:/bin/false",
    ]
  doAssert etcPasswd.parsePasswd == parsedEtcPasswd

block LastNot:
  var idx : int

  idx = 0
  doAssert scanp("foo", idx,  'f', 'o', ~'a')

  idx = 0
  doAssert scanp("foo", idx,  'f', 'o', ~'o') == false

  idx = 0
  doAssert scanp("foox", idx,  'f', 'o', ~'o') == false

  idx = 0
  doAssert scanp("foox", idx,  'f', 'o', ~'a')

block LastOptional:
  var idx = 0
  doAssert scanp("foo", idx, 'f', 'o', 'o', ?'o')

block Tuple:
  var idx = 0
  doAssert scanp("foo", idx,  ('f', 'o', 'o'))

block NotWithOptional:
  var idx : int

  idx = 0
  doAssert scanp("bc", idx, ~(?'b', 'c')) == false

  idx = 0
  doAssert scanp("c", idx, ~(?'b', 'c')) == false

  idx = 0
  doAssert scanp("b", idx, ~(?'b', 'c'))

block NotEmpty:
  var idx = 0
  doAssert scanp("", idx, ~()) == false

block EmptyTuple:
  var idx = 0
  doAssert scanp("ab", idx, 'a', (), 'b')

block Arrow:
  let text = "foo;bar;baz;"
  var idx = 0
  doAssert scanp(text, idx, +(~{';','\0'} -> (discard $_)), ';')
  doAssert scanp(text, idx, +(~{';','\0'} -> (discard $_)), ';')
  doAssert scanp(text, idx, +(~{';','\0'} -> (discard $_)), ';')
  doAssert scanp(text, idx, +(~{';','\0'} -> (discard $_)), ';') == false


block issue15064:
  var nick1, msg1: string
  doAssert scanf("<abcd> a", "<$+> $+", nick1, msg1)
  doAssert nick1 == "abcd"
  doAssert msg1 == "a"

  var nick2, msg2: string
  doAssert(not scanf("<abcd> ", "<$+> $+", nick2, msg2))

  var nick3, msg3: string
  doAssert scanf("<abcd> ", "<$+> $*", nick3, msg3)
  doAssert nick3 == "abcd"
  doAssert msg3 == ""


block:
  proc twoDigits(input: string; x: var int; start: int): int =
    if start+1 < input.len and input[start] == '0' and input[start+1] == '0':
      result = 2
      x = 13
    else:
      result = 0

  proc someSep(input: string; start: int; seps: set[char] = {';', ',', '-', '.'}): int =
    result = 0
    while start+result < input.len and input[start+result] in seps: inc result

  proc demangle(s: string; res: var string; start: int): int =
    result = 0
    while result+start < s.len and s[result+start] in {'_', '@'}: inc result
    res = ""
    while result+start < s.len and s[result+start] > ' ' and s[result+start] != '_':
      res.add s[result+start]
      inc result
    while result+start < s.len and s[result+start] > ' ':
      inc result

  proc parseGDB(resp: string): seq[string] =
    const
      digits = {'0'..'9'}
      hexdigits = digits + {'a'..'f', 'A'..'F'}
      whites = {' ', '\t', '\C', '\L'}
    result = @[]
    var idx = 0
    while true:
      var prc = ""
      var info = ""
      if scanp(resp, idx, *`whites`, '#', *`digits`, +`whites`, ?("0x", *`hexdigits`, " in "),
               demangle($input, prc, $index), *`whites`, '(', * ~ ')', ')',
                *`whites`, "at ", +(~{'\C', '\L'} -> info.add($_))):
        result.add prc & " " & info
      else:
        break

  var key, val: string
  var intVal: int
  var floatVal: float
  doAssert scanf("abc:: xyz 89  33.25", "$w$s::$s$w$s$i  $f", key, val, intVal, floatVal)
  doAssert key == "abc"
  doAssert val == "xyz"
  doAssert intVal == 89
  doAssert floatVal == 33.25

  var binVal: int
  var octVal: int
  var hexVal: int
  doAssert scanf("0b0101 0o1234 0xabcd", "$b$s$o$s$h", binVal, octVal, hexVal)
  doAssert binVal == 0b0101
  doAssert octVal == 0o1234
  doAssert hexVal == 0xabcd

  let xx = scanf("$abc", "$$$i", intVal)
  doAssert xx == false


  let xx2 = scanf("$1234", "$$$i", intVal)
  doAssert xx2

  let yy = scanf(";.--Breakpoint00 [output]",
      "$[someSep]Breakpoint${twoDigits}$[someSep({';','.','-'})] [$+]$.",
      intVal, key)
  doAssert yy
  doAssert key == "output"
  doAssert intVal == 13

  var ident = ""
  var idx = 0
  let zz = scanp("foobar x x  x   xWZ", idx, +{'a'..'z'} -> add(ident, $_), *(*{
      ' ', '\t'}, "x"), ~'U', "Z")
  doAssert zz
  doAssert ident == "foobar"

  const digits = {'0'..'9'}
  var year = 0
  var idx2 = 0
  if scanp("201655-8-9", idx2, `digits`{4, 6} -> (year = year * 10 + ord($_) -
      ord('0')), "-8", "-9"):
    doAssert year == 201655

  const gdbOut = """
      #0  @foo_96013_1208911747@8 (x0=...)
          at c:/users/anwender/projects/nim/temp.nim:11
      #1  0x00417754 in tempInit000 () at c:/users/anwender/projects/nim/temp.nim:13
      #2  0x0041768d in NimMainInner ()
          at c:/users/anwender/projects/nim/lib/system.nim:2605
      #3  0x004176b1 in NimMain ()
          at c:/users/anwender/projects/nim/lib/system.nim:2613
      #4  0x004176db in main (argc=1, args=0x712cc8, env=0x711ca8)
          at c:/users/anwender/projects/nim/lib/system.nim:2620"""
  const result = @["foo c:/users/anwender/projects/nim/temp.nim:11",
          "tempInit000 c:/users/anwender/projects/nim/temp.nim:13",
          "NimMainInner c:/users/anwender/projects/nim/lib/system.nim:2605",
          "NimMain c:/users/anwender/projects/nim/lib/system.nim:2613",
          "main c:/users/anwender/projects/nim/lib/system.nim:2620"]
  doAssert parseGDB(gdbOut) == result

  # bug #6487
  var count = 0

  proc test(): string =
    inc count
    result = ",123123"

  var a: int
  discard scanf(test(), ",$i", a)
  doAssert count == 1


block:
  let input = """1-3 s: abc
15-18 9: def
15-18 A: ghi
15-18 _: jkl
"""
  var
    lo, hi: int
    w: string
    c: char
    res: int
  for line in input.splitLines:
    if line.scanf("$i-$i $c: $w", lo, hi, c, w):
      inc res
  doAssert res == 4

block:
  #whenscanf testing
  let input = """1-3 s: abc
15-18 9: def
15-18 A: ghi
15-18 _: jkl
"""
  proc twoDigits(input: string; x: var int; start: int): int =
    if start+1 < input.len and input[start] == '0' and input[start+1] == '0':
      result = 2
      x = 13
    else:
      result = 0

  proc someSep(input: string; start: int; seps: set[char] = {';', ',', '-', '.'}): int =
    result = 0
    while start+result < input.len and input[start+result] in seps: inc result

  type
    ScanRetType = tuple
      success: bool
      lo: int
      hi: int
      ch: char
      word: string

  var res = 0
  for line in input.splitLines:
    let ret: ScanRetType = scanTuple(line, "$i-$i $c: $w")
    if ret.success:
      inc res
  doAssert res == 4

  let (_, key, val, intVal, floatVal) = scanTuple("abc:: xyz 89  33.25", "$w$s::$s$w$s$i  $f")
  doAssert key == "abc"
  doAssert val == "xyz"
  doAssert intVal == 89
  doAssert floatVal == 33.25


  let (_, binVal, octVal, hexVal) = scanTuple("0b0101 0o1234 0xabcd", "$b$s$o$s$h", binVal, octVal, hexVal)
  doAssert binVal == 0b0101
  doAssert octVal == 0o1234
  doAssert hexVal == 0xabcd

  var (xx,_) = scanTuple("$abc", "$$$i")
  doAssert xx == false


  let (xx2, _) = block: scanTuple("$1234", "$$$i")
  doAssert xx2

  var (yy, intVal2, key2) = scanTuple(";.--Breakpoint00 [output]",
      "$[someSep]Breakpoint${twoDigits}$[someSep({';','.','-'})] [$+]$.",
      int)
  doAssert yy
  doAssert key2 == "output"
  doAssert intVal2 == 13
