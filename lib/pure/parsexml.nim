#
#
#            Nim's Runtime Library
#        (c) Copyright 2010 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements a simple high performance `XML`:idx: / `HTML`:idx:
## parser.
## The only encoding that is supported is UTF-8. The parser has been designed
## to be somewhat error correcting, so that even most "wild HTML" found on the
## web can be parsed with it. **Note:** This parser does not check that each
## ``<tag>`` has a corresponding ``</tag>``! These checks have do be
## implemented by the client code for various reasons:
##
## * Old HTML contains tags that have no end tag: ``<br>`` for example.
## * HTML tags are case insensitive, XML tags are case sensitive. Since this
##   library can parse both, only the client knows which comparison is to be
##   used.
## * Thus the checks would have been very difficult to implement properly with
##   little benefit, especially since they are simple to implement in the
##   client. The client should use the `errorMsgExpected` proc to generate
##   a nice error message that fits the other error messages this library
##   creates.
##
##

##[

Example 1: Retrieve HTML title
==============================

The file ``examples/htmltitle.nim`` demonstrates how to use the
XML parser to accomplish a simple task: To determine the title of an HTML
document.

  ```nim
  # Example program to show the parsexml module
  # This program reads an HTML file and writes its title to stdout.
  # Errors and whitespace are ignored.

  import std/[os, streams, parsexml, strutils]

  if paramCount() < 1:
    quit("Usage: htmltitle filename[.html]")

  var filename = addFileExt(paramStr(1), "html")
  var s = newFileStream(filename, fmRead)
  if s == nil: quit("cannot open the file " & filename)
  var x: XmlParser
  open(x, s, filename)
  while true:
    x.next()
    case x.kind
    of xmlElementStart:
      if cmpIgnoreCase(x.elementName, "title") == 0:
        var title = ""
        x.next()  # skip "<title>"
        while x.kind == xmlCharData:
          title.add(x.charData)
          x.next()
        if x.kind == xmlElementEnd and cmpIgnoreCase(x.elementName, "title") == 0:
          echo("Title: " & title)
          quit(0) # Success!
        else:
          echo(x.errorMsgExpected("/title"))

    of xmlEof: break # end of file reached
    else: discard # ignore other events

  x.close()
  quit("Could not determine title!")
  ```

]##

##[

Example 2: Retrieve all HTML links
==================================

The file ``examples/htmlrefs.nim`` demonstrates how to use the
XML parser to accomplish another simple task: To determine all the links
an HTML document contains.

  ```nim
  # Example program to show the new parsexml module
  # This program reads an HTML file and writes all its used links to stdout.
  # Errors and whitespace are ignored.

  import std/[os, streams, parsexml, strutils]

  proc `=?=` (a, b: string): bool =
    # little trick: define our own comparator that ignores case
    return cmpIgnoreCase(a, b) == 0

  if paramCount() < 1:
    quit("Usage: htmlrefs filename[.html]")

  var links = 0 # count the number of links
  var filename = addFileExt(paramStr(1), "html")
  var s = newFileStream(filename, fmRead)
  if s == nil: quit("cannot open the file " & filename)
  var x: XmlParser
  open(x, s, filename)
  next(x) # get first event
  block mainLoop:
    while true:
      case x.kind
      of xmlElementOpen:
        # the <a href = "xyz"> tag we are interested in always has an attribute,
        # thus we search for ``xmlElementOpen`` and not for ``xmlElementStart``
        if x.elementName =?= "a":
          x.next()
          if x.kind == xmlAttribute:
            if x.attrKey =?= "href":
              var link = x.attrValue
              inc(links)
              # skip until we have an ``xmlElementClose`` event
              while true:
                x.next()
                case x.kind
                of xmlEof: break mainLoop
                of xmlElementClose: break
                else: discard
              x.next() # skip ``xmlElementClose``
              # now we have the description for the ``a`` element
              var desc = ""
              while x.kind == xmlCharData:
                desc.add(x.charData)
                x.next()
              echo(desc & ": " & link)
        else:
          x.next()
      of xmlEof: break # end of file reached
      of xmlError:
        echo(errorMsg(x))
        x.next()
      else: x.next() # skip other events

  echo($links & " link(s) found!")
  x.close()
  ```

]##

import
  std/[strutils, lexbase, streams, unicode]

when defined(nimPreviewSlimSystem):
  import std/[assertions, syncio]

# the parser treats ``<br />`` as ``<br></br>``

#  xmlElementCloseEnd, ## ``/>``

type
  XmlEventKind* = enum ## enumeration of all events that may occur when parsing
    xmlError,          ## an error occurred during parsing
    xmlEof,            ## end of file reached
    xmlCharData,       ## character data
    xmlWhitespace,     ## whitespace has been parsed
    xmlComment,        ## a comment has been parsed
    xmlPI,             ## processing instruction (``<?name something ?>``)
    xmlElementStart,   ## ``<elem>``
    xmlElementEnd,     ## ``</elem>``
    xmlElementOpen,    ## ``<elem
    xmlAttribute,      ## ``key = "value"`` pair
    xmlElementClose,   ## ``>``
    xmlCData,          ## ``<![CDATA[`` ... data ... ``]]>``
    xmlEntity,         ## &entity;
    xmlSpecial         ## ``<! ... data ... >``

  XmlErrorKind* = enum        ## enumeration that lists all errors that can occur
    errNone,                  ## no error
    errEndOfCDataExpected,    ## ``]]>`` expected
    errNameExpected,          ## name expected
    errSemicolonExpected,     ## ``;`` expected
    errQmGtExpected,          ## ``?>`` expected
    errGtExpected,            ## ``>`` expected
    errEqExpected,            ## ``=`` expected
    errQuoteExpected,         ## ``"`` or ``'`` expected
    errEndOfCommentExpected   ## ``-->`` expected
    errAttributeValueExpected ## non-empty attribute value expected

  ParserState = enum
    stateStart, stateNormal, stateAttr, stateEmptyElementTag, stateError

  XmlParseOption* = enum ## options for the XML parser
    reportWhitespace,    ## report whitespace
    reportComments       ## report comments
    allowUnquotedAttribs ## allow unquoted attribute values (for HTML)
    allowEmptyAttribs    ## allow empty attributes (without explicit value)

  XmlParser* = object of BaseLexer ## the parser object.
    a, b, c: string
    kind: XmlEventKind
    err: XmlErrorKind
    state: ParserState
    cIsEmpty: bool
    filename: string
    options: set[XmlParseOption]

const
  errorMessages: array[XmlErrorKind, string] = [
    "no error",
    "']]>' expected",
    "name expected",
    "';' expected",
    "'?>' expected",
    "'>' expected",
    "'=' expected",
    "'\"' or \"'\" expected",
    "'-->' expected",
    "attribute value expected"
  ]

proc open*(my: var XmlParser, input: Stream, filename: string,
           options: set[XmlParseOption] = {}) =
  ## initializes the parser with an input stream. `Filename` is only used
  ## for nice error messages. The parser's behaviour can be controlled by
  ## the `options` parameter: If `options` contains ``reportWhitespace``
  ## a whitespace token is reported as an ``xmlWhitespace`` event.
  ## If `options` contains ``reportComments`` a comment token is reported as an
  ## ``xmlComment`` event.
  lexbase.open(my, input, 8192, {'\c', '\L', '/'})
  my.filename = filename
  my.state = stateStart
  my.kind = xmlError
  my.a = ""
  my.b = ""
  my.c = ""
  my.cIsEmpty = true
  my.options = options

proc close*(my: var XmlParser) {.inline.} =
  ## closes the parser `my` and its associated input stream.
  lexbase.close(my)

proc kind*(my: XmlParser): XmlEventKind {.inline.} =
  ## returns the current event type for the XML parser
  return my.kind

template charData*(my: XmlParser): string =
  ## returns the character data for the events: ``xmlCharData``,
  ## ``xmlWhitespace``, ``xmlComment``, ``xmlCData``, ``xmlSpecial``
  ## Raises an assertion in debug mode if ``my.kind`` is not one
  ## of those events. In release mode, this will not trigger an error
  ## but the value returned will not be valid.
  assert(my.kind in {xmlCharData, xmlWhitespace, xmlComment, xmlCData,
                     xmlSpecial})
  my.a

template elementName*(my: XmlParser): string =
  ## returns the element name for the events: ``xmlElementStart``,
  ## ``xmlElementEnd``, ``xmlElementOpen``
  ## Raises an assertion in debug mode if ``my.kind`` is not one
  ## of those events. In release mode, this will not trigger an error
  ## but the value returned will not be valid.
  assert(my.kind in {xmlElementStart, xmlElementEnd, xmlElementOpen})
  my.a

template entityName*(my: XmlParser): string =
  ## returns the entity name for the event: ``xmlEntity``
  ## Raises an assertion in debug mode if ``my.kind`` is not
  ## ``xmlEntity``. In release mode, this will not trigger an error
  ## but the value returned will not be valid.
  assert(my.kind == xmlEntity)
  my.a

template attrKey*(my: XmlParser): string =
  ## returns the attribute key for the event ``xmlAttribute``
  ## Raises an assertion in debug mode if ``my.kind`` is not
  ## ``xmlAttribute``. In release mode, this will not trigger an error
  ## but the value returned will not be valid.
  assert(my.kind == xmlAttribute)
  my.a

template attrValue*(my: XmlParser): string =
  ## returns the attribute value for the event ``xmlAttribute``
  ## Raises an assertion in debug mode if ``my.kind`` is not
  ## ``xmlAttribute``. In release mode, this will not trigger an error
  ## but the value returned will not be valid.
  assert(my.kind == xmlAttribute)
  my.b

template piName*(my: XmlParser): string =
  ## returns the processing instruction name for the event ``xmlPI``
  ## Raises an assertion in debug mode if ``my.kind`` is not
  ## ``xmlPI``. In release mode, this will not trigger an error
  ## but the value returned will not be valid.
  assert(my.kind == xmlPI)
  my.a

template piRest*(my: XmlParser): string =
  ## returns the rest of the processing instruction for the event ``xmlPI``
  ## Raises an assertion in debug mode if ``my.kind`` is not
  ## ``xmlPI``. In release mode, this will not trigger an error
  ## but the value returned will not be valid.
  assert(my.kind == xmlPI)
  my.b

proc rawData*(my: var XmlParser): lent string {.inline.} =
  ## returns the underlying 'data' string by reference.
  ## This is only used for speed hacks.
  result = my.a

proc rawData2*(my: var XmlParser): lent string {.inline.} =
  ## returns the underlying second 'data' string by reference.
  ## This is only used for speed hacks.
  result = my.b

proc getColumn*(my: XmlParser): int {.inline.} =
  ## get the current column the parser has arrived at.
  result = getColNumber(my, my.bufpos)

proc getLine*(my: XmlParser): int {.inline.} =
  ## get the current line the parser has arrived at.
  result = my.lineNumber

proc getFilename*(my: XmlParser): string {.inline.} =
  ## get the filename of the file that the parser processes.
  result = my.filename

proc errorMsg*(my: XmlParser): string =
  ## returns a helpful error message for the event ``xmlError``
  assert(my.kind == xmlError)
  result = "$1($2, $3) Error: $4" % [
    my.filename, $getLine(my), $getColumn(my), errorMessages[my.err]]

proc errorMsgExpected*(my: XmlParser, tag: string): string =
  ## returns an error message "<tag> expected" in the same format as the
  ## other error messages
  result = "$1($2, $3) Error: $4" % [
    my.filename, $getLine(my), $getColumn(my), "<$1> expected" % tag]

proc errorMsg*(my: XmlParser, msg: string): string =
  ## returns an error message with text `msg` in the same format as the
  ## other error messages
  result = "$1($2, $3) Error: $4" % [
    my.filename, $getLine(my), $getColumn(my), msg]

proc markError(my: var XmlParser, kind: XmlErrorKind) {.inline.} =
  my.err = kind
  my.state = stateError

proc parseCDATA(my: var XmlParser) =
  var pos = my.bufpos + len("<![CDATA[")
  while true:
    case my.buf[pos]
    of ']':
      if my.buf[pos+1] == ']' and my.buf[pos+2] == '>':
        inc(pos, 3)
        break
      add(my.a, ']')
      inc(pos)
    of '\0':
      markError(my, errEndOfCDataExpected)
      break
    of '\c':
      pos = lexbase.handleCR(my, pos)
      add(my.a, '\L')
    of '\L':
      pos = lexbase.handleLF(my, pos)
      add(my.a, '\L')
    of '/':
      pos = lexbase.handleRefillChar(my, pos)
      add(my.a, '/')
    else:
      add(my.a, my.buf[pos])
      inc(pos)
  my.bufpos = pos # store back
  my.kind = xmlCData

proc parseComment(my: var XmlParser) =
  var pos = my.bufpos + len("<!--")
  while true:
    case my.buf[pos]
    of '-':
      if my.buf[pos+1] == '-' and my.buf[pos+2] == '>':
        inc(pos, 3)
        break
      if my.options.contains(reportComments): add(my.a, '-')
      inc(pos)
    of '\0':
      markError(my, errEndOfCommentExpected)
      break
    of '\c':
      pos = lexbase.handleCR(my, pos)
      if my.options.contains(reportComments): add(my.a, '\L')
    of '\L':
      pos = lexbase.handleLF(my, pos)
      if my.options.contains(reportComments): add(my.a, '\L')
    of '/':
      pos = lexbase.handleRefillChar(my, pos)
      if my.options.contains(reportComments): add(my.a, '/')
    else:
      if my.options.contains(reportComments): add(my.a, my.buf[pos])
      inc(pos)
  my.bufpos = pos
  my.kind = xmlComment

proc parseWhitespace(my: var XmlParser, skip = false) =
  var pos = my.bufpos
  while true:
    case my.buf[pos]
    of ' ', '\t':
      if not skip: add(my.a, my.buf[pos])
      inc(pos)
    of '\c':
      # the specification says that CR-LF, CR are to be transformed to LF
      pos = lexbase.handleCR(my, pos)
      if not skip: add(my.a, '\L')
    of '\L':
      pos = lexbase.handleLF(my, pos)
      if not skip: add(my.a, '\L')
    else:
      break
  my.bufpos = pos

const
  NameStartChar = {'A'..'Z', 'a'..'z', '_', ':', '\128'..'\255'}
  NameChar = {'A'..'Z', 'a'..'z', '0'..'9', '.', '-', '_', ':', '\128'..'\255'}

proc parseName(my: var XmlParser, dest: var string) =
  var pos = my.bufpos
  if my.buf[pos] in NameStartChar:
    while true:
      add(dest, my.buf[pos])
      inc(pos)
      if my.buf[pos] notin NameChar: break
    my.bufpos = pos
  else:
    markError(my, errNameExpected)

proc parseEntity(my: var XmlParser, dest: var string) =
  var pos = my.bufpos+1
  my.kind = xmlCharData
  if my.buf[pos] == '#':
    var r: int = 0
    inc(pos)
    if my.buf[pos] == 'x':
      inc(pos)
      while true:
        case my.buf[pos]
        of '0'..'9': r = (r shl 4) or (ord(my.buf[pos]) - ord('0'))
        of 'a'..'f': r = (r shl 4) or (ord(my.buf[pos]) - ord('a') + 10)
        of 'A'..'F': r = (r shl 4) or (ord(my.buf[pos]) - ord('A') + 10)
        else: break
        inc(pos)
    else:
      while my.buf[pos] in {'0'..'9'}:
        r = r * 10 + (ord(my.buf[pos]) - ord('0'))
        inc(pos)
    add(dest, toUTF8(Rune(r)))
  elif my.buf[pos] == 'l' and my.buf[pos+1] == 't' and my.buf[pos+2] == ';':
    add(dest, '<')
    inc(pos, 2)
  elif my.buf[pos] == 'g' and my.buf[pos+1] == 't' and my.buf[pos+2] == ';':
    add(dest, '>')
    inc(pos, 2)
  elif my.buf[pos] == 'a' and my.buf[pos+1] == 'm' and my.buf[pos+2] == 'p' and
      my.buf[pos+3] == ';':
    add(dest, '&')
    inc(pos, 3)
  elif my.buf[pos] == 'a' and my.buf[pos+1] == 'p' and my.buf[pos+2] == 'o' and
      my.buf[pos+3] == 's' and my.buf[pos+4] == ';':
    add(dest, '\'')
    inc(pos, 4)
  elif my.buf[pos] == 'q' and my.buf[pos+1] == 'u' and my.buf[pos+2] == 'o' and
      my.buf[pos+3] == 't' and my.buf[pos+4] == ';':
    add(dest, '"')
    inc(pos, 4)
  else:
    my.bufpos = pos
    var name = ""
    parseName(my, name)
    pos = my.bufpos
    if my.err != errNameExpected and my.buf[pos] == ';':
      my.kind = xmlEntity
    else:
      add(dest, '&')
    add(dest, name)
  if my.buf[pos] == ';':
    inc(pos)
  else:
    my.err = errSemicolonExpected
    # do not overwrite 'my.state' here, it's a benign error
  my.bufpos = pos

proc parsePI(my: var XmlParser) =
  inc(my.bufpos, "<?".len)
  parseName(my, my.a)
  var pos = my.bufpos
  setLen(my.b, 0)
  while true:
    case my.buf[pos]
    of '\0':
      markError(my, errQmGtExpected)
      break
    of '?':
      if my.buf[pos+1] == '>':
        inc(pos, 2)
        break
      add(my.b, '?')
      inc(pos)
    of '\c':
      # the specification says that CR-LF, CR are to be transformed to LF
      pos = lexbase.handleCR(my, pos)
      add(my.b, '\L')
    of '\L':
      pos = lexbase.handleLF(my, pos)
      add(my.b, '\L')
    of '/':
      pos = lexbase.handleRefillChar(my, pos)
      add(my.b, '/')
    else:
      add(my.b, my.buf[pos])
      inc(pos)
  my.bufpos = pos
  my.kind = xmlPI

proc parseSpecial(my: var XmlParser) =
  # things that start with <!
  var pos = my.bufpos + 2
  var opentags = 0
  while true:
    case my.buf[pos]
    of '\0':
      markError(my, errGtExpected)
      break
    of '<':
      inc(opentags)
      inc(pos)
      add(my.a, '<')
    of '>':
      if opentags <= 0:
        inc(pos)
        break
      dec(opentags)
      inc(pos)
      add(my.a, '>')
    of '\c':
      pos = lexbase.handleCR(my, pos)
      add(my.a, '\L')
    of '\L':
      pos = lexbase.handleLF(my, pos)
      add(my.a, '\L')
    of '/':
      pos = lexbase.handleRefillChar(my, pos)
      add(my.b, '/')
    else:
      add(my.a, my.buf[pos])
      inc(pos)
  my.bufpos = pos
  my.kind = xmlSpecial

proc parseTag(my: var XmlParser) =
  inc(my.bufpos)
  parseName(my, my.a)
  # if we have no name, do not interpret the '<':
  if my.a.len == 0:
    my.kind = xmlCharData
    add(my.a, '<')
    return
  parseWhitespace(my, skip = true)
  if my.buf[my.bufpos] in NameStartChar:
    # an attribute follows:
    my.kind = xmlElementOpen
    my.state = stateAttr
    my.c = my.a # save for later
    my.cIsEmpty = false
  else:
    my.kind = xmlElementStart
    let slash = my.buf[my.bufpos] == '/'
    if slash:
      my.bufpos = lexbase.handleRefillChar(my, my.bufpos)
    if slash and my.buf[my.bufpos] == '>':
      inc(my.bufpos)
      my.state = stateEmptyElementTag
      my.c = ""
      my.cIsEmpty = true
    elif my.buf[my.bufpos] == '>':
      inc(my.bufpos)
    else:
      markError(my, errGtExpected)

proc parseEndTag(my: var XmlParser) =
  my.bufpos = lexbase.handleRefillChar(my, my.bufpos+1)
  #inc(my.bufpos, 2)
  parseName(my, my.a)
  parseWhitespace(my, skip = true)
  if my.buf[my.bufpos] == '>':
    inc(my.bufpos)
  else:
    markError(my, errGtExpected)
  my.kind = xmlElementEnd

proc parseAttribute(my: var XmlParser) =
  my.kind = xmlAttribute
  setLen(my.a, 0)
  setLen(my.b, 0)
  parseName(my, my.a)
  # if we have no name, we have '<tag attr= key %&$$%':
  if my.a.len == 0:
    markError(my, errGtExpected)
    return

  let startPos = my.bufpos
  parseWhitespace(my, skip = true)
  if my.buf[my.bufpos] != '=':
    if allowEmptyAttribs notin my.options or
        (my.buf[my.bufpos] != '>' and my.bufpos == startPos):
      markError(my, errEqExpected)
    return

  inc(my.bufpos)
  parseWhitespace(my, skip = true)

  var pos = my.bufpos
  if my.buf[pos] in {'\'', '"'}:
    var quote = my.buf[pos]
    var pendingSpace = false
    inc(pos)
    while true:
      case my.buf[pos]
      of '\0':
        markError(my, errQuoteExpected)
        break
      of '&':
        if pendingSpace:
          add(my.b, ' ')
          pendingSpace = false
        my.bufpos = pos
        parseEntity(my, my.b)
        my.kind = xmlAttribute # parseEntity overwrites my.kind!
        pos = my.bufpos
      of ' ', '\t':
        pendingSpace = true
        inc(pos)
      of '\c':
        pos = lexbase.handleCR(my, pos)
        pendingSpace = true
      of '\L':
        pos = lexbase.handleLF(my, pos)
        pendingSpace = true
      of '/':
        pos = lexbase.handleRefillChar(my, pos)
        add(my.b, '/')
      else:
        if my.buf[pos] == quote:
          inc(pos)
          break
        else:
          if pendingSpace:
            add(my.b, ' ')
            pendingSpace = false
          add(my.b, my.buf[pos])
          inc(pos)
  elif allowUnquotedAttribs in my.options:
    const disallowedChars = {'"', '\'', '`', '=', '<', '>', ' ',
                             '\0', '\t', '\L', '\F', '\f'}
    let startPos = pos
    while (let c = my.buf[pos]; c notin disallowedChars):
      if c == '&':
        my.bufpos = pos
        parseEntity(my, my.b)
        my.kind = xmlAttribute # parseEntity overwrites my.kind!
        pos = my.bufpos
      elif c == '/':
        pos = lexbase.handleRefillChar(my, pos)
        add(my.b, '/')
      else:
        add(my.b, c)
        inc(pos)
    if pos == startPos:
      markError(my, errAttributeValueExpected)
  else:
    markError(my, errQuoteExpected)
    # error corrections: guess what was meant
    while my.buf[pos] != '>' and my.buf[pos] > ' ':
      add(my.b, my.buf[pos])
      inc pos
  my.bufpos = pos
  parseWhitespace(my, skip = true)

proc parseCharData(my: var XmlParser) =
  var pos = my.bufpos
  while true:
    case my.buf[pos]
    of '\0', '<', '&': break
    of '\c':
      # the specification says that CR-LF, CR are to be transformed to LF
      pos = lexbase.handleCR(my, pos)
      add(my.a, '\L')
    of '\L':
      pos = lexbase.handleLF(my, pos)
      add(my.a, '\L')
    of '/':
      pos = lexbase.handleRefillChar(my, pos)
      add(my.a, '/')
    else:
      add(my.a, my.buf[pos])
      inc(pos)
  my.bufpos = pos
  my.kind = xmlCharData

proc rawGetTok(my: var XmlParser) =
  my.kind = xmlError
  setLen(my.a, 0)
  var pos = my.bufpos
  case my.buf[pos]
  of '<':
    case my.buf[pos+1]
    of '/':
      parseEndTag(my)
    of '!':
      if my.buf[pos+2] == '[' and my.buf[pos+3] == 'C' and
          my.buf[pos+4] == 'D' and my.buf[pos+5] == 'A' and
          my.buf[pos+6] == 'T' and my.buf[pos+7] == 'A' and
          my.buf[pos+8] == '[':
        parseCDATA(my)
      elif my.buf[pos+2] == '-' and my.buf[pos+3] == '-':
        parseComment(my)
      else:
        parseSpecial(my)
    of '?':
      parsePI(my)
    else:
      parseTag(my)
  of ' ', '\t', '\c', '\l':
    parseWhitespace(my)
    my.kind = xmlWhitespace
  of '\0':
    my.kind = xmlEof
  of '&':
    parseEntity(my, my.a)
  else:
    parseCharData(my)
  assert my.kind != xmlError

proc getTok(my: var XmlParser) =
  while true:
    let lastKind = my.kind
    rawGetTok(my)
    case my.kind
    of xmlComment:
      if my.options.contains(reportComments): break
    of xmlWhitespace:
      if my.options.contains(reportWhitespace) or lastKind in {xmlCharData,
          xmlComment, xmlEntity}:
        break
    else: break

proc next*(my: var XmlParser) =
  ## retrieves the first/next event. This controls the parser.
  case my.state
  of stateNormal:
    getTok(my)
  of stateStart:
    my.state = stateNormal
    getTok(my)
    if my.kind == xmlPI and my.a == "xml":
      # just skip the first ``<?xml >`` processing instruction
      getTok(my)
  of stateAttr:
    # parse an attribute key-value pair:
    if my.buf[my.bufpos] == '>':
      my.kind = xmlElementClose
      inc(my.bufpos)
      my.state = stateNormal
    elif my.buf[my.bufpos] == '/':
      my.bufpos = lexbase.handleRefillChar(my, my.bufpos)
      if my.buf[my.bufpos] == '>':
        my.kind = xmlElementClose
        inc(my.bufpos)
        my.state = stateEmptyElementTag
      else:
        markError(my, errGtExpected)
    else:
      parseAttribute(my)
      # state remains the same
  of stateEmptyElementTag:
    my.state = stateNormal
    my.kind = xmlElementEnd
    if not my.cIsEmpty:
      my.a = my.c
  of stateError:
    my.kind = xmlError
    my.state = stateNormal

when not defined(testing) and isMainModule:
  import std/os
  var s = newFileStream(paramStr(1), fmRead)
  if s == nil: quit("cannot open the file" & paramStr(1))
  var x: XmlParser
  open(x, s, paramStr(1))
  while true:
    next(x)
    case x.kind
    of xmlError: echo(x.errorMsg())
    of xmlEof: break
    of xmlCharData: echo(x.charData)
    of xmlWhitespace: echo("|$1|" % x.charData)
    of xmlComment: echo("<!-- $1 -->" % x.charData)
    of xmlPI: echo("<? $1 ## $2 ?>" % [x.piName, x.piRest])
    of xmlElementStart: echo("<$1>" % x.elementName)
    of xmlElementEnd: echo("</$1>" % x.elementName)

    of xmlElementOpen: echo("<$1" % x.elementName)
    of xmlAttribute:
      echo("Key: " & x.attrKey)
      echo("Value: " & x.attrValue)

    of xmlElementClose: echo(">")
    of xmlCData:
      echo("<![CDATA[$1]]>" % x.charData)
    of xmlEntity:
      echo("&$1;" % x.entityName)
    of xmlSpecial:
      echo("SPECIAL: " & x.charData)
  close(x)
