import std/[strutils, strscans, parseutils, assertions]

type
  Segment = object
    ## Segment refers to a block of something in the JS output.
    ## This could be a token or an entire line
    original: int # Column in the Nim source
    generated: int # Column in the generated JS
    name: int # Index into names list (-1 for no name)

  Mapping = object
    ## Mapping refers to a line in the JS output.
    ## It is made up of segments which refer to the tokens in the line
    case inSource: bool # Whether the line in JS has Nim equivalent
    of true:
      file: int # Index into files list
      line: int # 0 indexed line of code in the Nim source
      segments: seq[Segment]
    else: discard

  SourceInfo = object
    mappings: seq[Mapping]
    names, files: seq[string]

  SourceMap* = object
    version*:   int
    sources*:   seq[string]
    names*:     seq[string]
    mappings*:  string
    file*:      string

func addSegment(info: var SourceInfo, original, generated: int, name: string = "") {.raises: [].} =
  ## Adds a new segment into the current line
  assert info.mappings.len > 0, "No lines have been added yet"
  var segment = Segment(original: original, generated: generated, name: -1)
  if name != "":
    # Make name be index into names list
    segment.name = info.names.find(name)
    if segment.name == -1:
      segment.name = info.names.len
      info.names &= name

  assert info.mappings[^1].inSource, "Current line isn't in Nim source"
  info.mappings[^1].segments &= segment

func newLine(info: var SourceInfo) {.raises: [].} =
  ## Add new mapping which doesn't appear in the Nim source
  info.mappings &= Mapping(inSource: false)

func newLine(info: var SourceInfo, file: string, line: int) {.raises: [].} =
  ## Starts a new line in the mappings. Call addSegment after this to add
  ## segments into the line
  var mapping = Mapping(inSource: true, line: line)
  # Set file to file position. Add in if needed
  mapping.file = info.files.find(file)
  if mapping.file == -1:
    mapping.file = info.files.len
    info.files &= file
  info.mappings &= mapping


# base64_VLQ
func encode*(values: seq[int]): string {.raises: [].} =
  ## Encodes a series of integers into a VLQ base64 encoded string
  # References:
  #   - https://www.lucidchart.com/techblog/2019/08/22/decode-encoding-base64-vlqs-source-maps/
  #   - https://github.com/rails/sprockets/blob/main/guides/source_maps.md#source-map-file
  const
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    shift = 5
    continueBit = 1 shl 5
    mask = continueBit - 1
  result = ""
  for val in values:
    # Sign is stored in first bit
    var newVal = abs(val) shl 1
    if val < 0:
      newVal = newVal or 1
    # Now comes the variable length part
    # This is how we are able to store large numbers
    while true:
      # We only encode 5 bits.
      var masked = newVal and mask
      newVal = newVal shr shift
      # If there is still something left
      # then signify with the continue bit that the
      # decoder should keep decoding
      if newVal > 0:
        masked = masked or continueBit
      result &= alphabet[masked]
      # If the value is zero then we have nothing left to encode
      if newVal == 0:
        break

iterator tokenize*(line: string): (int, string) =
  ## Goes through a line and splits it into Nim identifiers and
  ## normal JS code. This allows us to map mangled names back to Nim names.
  ## Yields (column, name). Doesn't yield anything but identifiers.
  ## See mangleName in compiler/jsgen.nim for how name mangling is done
  var
    col = 0
    token = ""
  while col < line.len:
    var
      token: string = ""
      name: string = ""
    # First we find the next identifier
    col += line.skipWhitespace(col)
    col += line.skipUntil(IdentStartChars, col)
    let identStart = col
    col += line.parseIdent(token, col)
    # Idents will either be originalName_randomInt or HEXhexCode_randomInt
    if token.startsWith("HEX"):
      var hex: int = 0
      # 3 = "HEX".len and we only want to parse the two integers after it
      discard token[3 ..< 5].parseHex(hex)
      name = $chr(hex)
    elif not token.endsWith("_Idx"): # Ignore address indexes
      # It might be in the form originalName_randomInt
      let lastUnderscore = token.rfind('_')
      if lastUnderscore != -1:
        name = token[0..<lastUnderscore]
    if name != "":
      yield (identStart, name)

func parse*(source: string): SourceInfo =
  ## Parses the JS output for embedded line info
  ## So it can convert those into a series of mappings
  result = default(SourceInfo)
  var
    skipFirstLine = true
    currColumn = 0
    currLine = 0
    currFile = ""
  # Add each line as a node into the output
  for line in source.splitLines():
    var
      lineNumber: int = 0
      linePath: string = ""
      column: int = 0
    if line.strip().scanf("/* line $i:$i \"$+\" */", lineNumber, column, linePath):
      # When we reach the first line mappinsegmentg then we can assume
      # we can map the rest of the JS lines to Nim lines
      currColumn = column # Column is already zero indexed
      currLine = lineNumber - 1
      currFile = linePath
      # Lines are zero indexed
      result.newLine(currFile, currLine)
      # Skip whitespace to find the starting column
      result.addSegment(currColumn, line.skipWhitespace())
    elif currFile != "":
      result.newLine(currFile, currLine)
      # There mightn't be any tokens so add a starting segment
      result.addSegment(currColumn, line.skipWhitespace())
      for jsColumn, token in line.tokenize:
        result.addSegment(currColumn, jsColumn, token)
    else:
      result.newLine()

func toSourceMap*(info: SourceInfo, file: string): SourceMap {.raises: [].} =
  ## Convert from high level SourceInfo into the required SourceMap object
  # Add basic info
  result = SourceMap(version: 3, file: file, sources: info.files, names: info.names)
  # Convert nodes into mappings.
  # Mappings are split into blocks where each block referes to a line in the outputted JS.
  # Blocks can be separated into statements which refere to tokens on the line.
  # Since the mappings depend on previous values we need to
  # keep track of previous file, name, etc
  var
    prevFile = 0
    prevLine = 0
    prevName = 0
    prevNimCol = 0

  for mapping in info.mappings:
    # We know need to encode segments with the following fields
    # All these fields are relative to their previous values
    # - 0: Column in generated code
    # - 1: Index of Nim file in source list
    # - 2: Line in Nim source
    # - 3: Column in Nim source
    # - 4: Index in names list
    if mapping.inSource:
      # JS Column is special in that it is reset after every line
      var prevJSCol = 0
      for segment in mapping.segments:
        var values = @[segment.generated - prevJSCol, mapping.file - prevFile, mapping.line - prevLine, segment.original - prevNimCol]
        # Add name field if needed
        if segment.name != -1:
          values &= segment.name - prevName
          prevName = segment.name
        prevJSCol = segment.generated
        prevNimCol = segment.original
        prevFile = mapping.file
        prevLine = mapping.line
        result.mappings &= encode(values) & ","
      # Remove trailing ,
      if mapping.segments.len > 0:
        result.mappings.setLen(result.mappings.len - 1)

    result.mappings &= ";"

proc genSourceMap*(source: string, outFile: string): SourceMap =
  let node = parse(source)
  result = node.toSourceMap(outFile)

