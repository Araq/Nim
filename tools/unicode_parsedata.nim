import strutils, algorithm

let
  # this file was obtained from:
  # https://www.unicode.org/Public/UCD/latest/ucd/UnicodeData.txt
  filename = "tools/UnicodeData.txt"
  data = readFile(filename).strip.splitLines()

const
  # see the table here:
  # https://www.unicode.org/reports/tr44/#GC_Values_Table
  letters = ["Lu", "Ll", "Lt", "Lm", "Lo"]
  spaces = ["Zs", "Zl", "Zp"]

type
  Ranges = tuple[start, stop, diff: int]
  Singlets = tuple[code, diff: int]
  NonLetterRanges = tuple[start, stop: int]

var
  toUpper = newSeq[Singlets]()
  toLower = newSeq[Singlets]()
  toTitle = newSeq[Singlets]()
  alphas = newSeq[int]()
  unispaces = newSeq[int]()


proc parseData(data: seq[string]) =
  proc doAdd(firstCode, lastCode: int, category, uc, lc, tc: string) =
    if category notin spaces and category notin letters:
      return

    if firstCode != lastCode:
      doAssert uc == "" and lc == "" and tc == ""
    if uc.len > 0:
      let diff = 500 + uc.parseHexInt() - firstCode
      toUpper.add (firstCode, diff)
    if lc.len > 0:
      let diff = 500 + lc.parseHexInt() - firstCode
      toLower.add (firstCode, diff)
    if tc.len > 0 and tc != uc:
      # if titlecase is different than uppercase
      let diff = 500 + tc.parseHexInt() - firstCode
      if diff != 500:
        toTitle.add (firstCode, diff)

    for code in firstCode..lastCode:
      if category in spaces:
        unispaces.add code
      else:
        alphas.add code

  var idx = 0
  while idx < data.len:
    let
      line = data[idx]
      fields = line.split(';')
      code = fields[0].parseHexInt()
      name = fields[1]
      category = fields[2]
      uc = fields[12]
      lc = fields[13]
      tc = fields[14]
    inc(idx)
    if name.endsWith(", First>"):
      doAssert idx < data.len
      let
        nextLine = data[idx]
        nextFields = nextLine.split(';')
        nextCode = nextFields[0].parseHexInt()
        nextName = nextFields[1]
      inc(idx)
      doAssert nextName.endsWith(", Last>")
      doAdd(code, nextCode, category, uc, lc, tc)
    else:
      doAdd(code, code, category, uc, lc, tc)

proc splitRanges(a: seq[Singlets], r: var seq[Ranges], s: var seq[Singlets]) =
  ## Splits `toLower`, `toUpper` and `toTitle` into separate sequences:
  ## - `r` contains continuous ranges with the same characteristics
  ##   (their upper/lower version is the same distance away)
  ## - `s` contains single code points
  var i, j: int
  while i < a.len:
    j = 1
    let
      startCode = a[i].code
      startDiff = a[i].diff
    while i + j <= a.len:
      if i+j >= a.len or a[i+j].code != startCode+j or a[i+j].diff != startDiff:
        if j == 1:
          s.add (startCode, startDiff)
        else:
          r.add (startCode, a[i+j-1].code, startDiff)
        i += j-1
        break
      else:
        inc j
    inc i

proc splitRanges(a: seq[int], r: var seq[NonLetterRanges], s: var seq[int]) =
  ## Splits `alphas` and `unispaces` into separate sequences:
  ## - `r` contains continuous ranges
  ## - `s` contains single code points
  var i, j: int
  while i < a.len:
    j = 1
    let startCode = a[i]
    while i + j <= a.len:
      if i+j >= a.len or a[i+j] != startCode+j:
        if j == 1:
          s.add startCode
        else:
          r.add (startCode, a[i+j-1])
        i += j-1
        break
      else:
        inc j
    inc i

proc splitSpaces(a: seq[int], r: var seq[NonLetterRanges], s: var seq[int]) =
  ## Spaces are special because of the way how `isWhiteSpace` and `split`
  ## are implemented.
  ##
  ## All spaces are added both to `r` (ranges) and `s` (singlets).
  var i, j: int
  while i < a.len:
    j = 1
    let startCode = a[i]
    while i + j <= a.len:
      if i+j >= a.len or a[i+j] != startCode+j:
        r.add (startCode, a[i+j-1])
        i += j-1
        break
      else:
        inc j
    inc i
  s = a


var
  toupperRanges = newSeq[Ranges]()
  toupperSinglets = newSeq[Singlets]()
  tolowerRanges = newSeq[Ranges]()
  tolowerSinglets = newSeq[Singlets]()
  totitleRanges = newSeq[Ranges]()
  totitleSinglets = newSeq[Singlets]()
  spaceRanges = newSeq[NonLetterRanges]()
  unicodeSpaces = newSeq[int]()
  alphaRanges = newSeq[NonLetterRanges]()
  alphaSinglets = newSeq[int]()

parseData(data)
splitRanges(toLower, tolowerRanges, tolowerSinglets)
splitRanges(toUpper, toUpperRanges, toUpperSinglets)
splitRanges(toTitle, toTitleRanges, toTitleSinglets)
splitRanges(alphas, alphaRanges, alphaSinglets)

# manually add "special" spaces
for i in 9 .. 13:
  unispaces.add i
unispaces.add 0x85
unispaces.sort()

splitSpaces(unispaces, spaceRanges, unicodeSpaces)


var output: string

proc createHeader(output: var string) =
  output.add "# This file was created from a script.\n\n"
  output.add "const\n"

proc `$`(r: Ranges): string =
  let
    start = "0x" & toHex(r.start, 5) & "'i32"
    stop = "0x" & toHex(r.stop, 5) & "'i32"
  result = "$#, $#, $#,\n" % [start, stop, $r.diff]

proc `$`(r: Singlets): string =
  let code = "0x" & toHex(r.code, 5) & "'i32"
  result = "$#, $#,\n" % [code, $r.diff]

proc `$`(r: NonLetterRanges): string =
  let
    start = "0x" & toHex(r.start, 5) & "'i32"
    stop = "0x" & toHex(r.stop, 5) & "'i32"
  result = "$#, $#,\n" % [start, stop]


proc outputSeq(s: seq[Ranges|Singlets|NonLetterRanges], name: string,
               output: var string) =
  output.add "  $# = [\n" % name
  for r in s:
    output.add "    " & $r
  output.add "  ]\n\n"

proc outputSeq(s: seq[int], name: string, output: var string) =
  output.add "  $# = [\n" % name
  for i in s:
    output.add "    0x$#'i32,\n" % toHex(i, 5)
  output.add "  ]\n\n"

proc outputSpaces(s: seq[int], name: string, output: var string) =
  output.add "  $# = [\n" % name
  for i in s:
    output.add "    Rune 0x$#,\n" % toHex(i, 5)
  output.add "  ]\n\n"


output.createHeader()
outputSeq(tolowerRanges,   "toLowerRanges",   output)
outputSeq(tolowerSinglets, "toLowerSinglets", output)
outputSeq(toupperRanges,   "toUpperRanges",   output)
outputSeq(toupperSinglets, "toUpperSinglets", output)
outputSeq(totitleSinglets, "toTitleSinglets", output)
outputSeq(alphaRanges,     "alphaRanges",     output)
outputSeq(alphaSinglets,   "alphaSinglets",   output)
outputSeq(spaceRanges,     "spaceRanges",     output)
outputSpaces(unispaces,    "unicodeSpaces",   output) # array of runes


let outfile = "lib/pure/includes/unicode_ranges.nim"
outfile.writeFile(output)
