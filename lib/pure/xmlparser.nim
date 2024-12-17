#
#
#            Nim's Runtime Library
#        (c) Copyright 2010 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module parses an XML document and creates its XML tree representation.

import std/[streams, parsexml, strtabs, xmltree]

when defined(nimPreviewSlimSystem):
  import std/syncio

type
  XmlError* = object of ValueError ## Exception that is raised
                                   ## for invalid XML.
    errors*: seq[string]           ## All detected parsing errors.

proc raiseInvalidXml(errors: seq[string]) =
  var e: ref XmlError
  new(e)
  e.msg = errors[0]
  e.errors = errors
  raise e

proc addNode(father, son: XmlNode) =
  if son != nil: add(father, son)

proc parse(x: var XmlParser, errors: var seq[string]): XmlNode {.gcsafe.}

proc untilElementEnd(x: var XmlParser, result: XmlNode,
                     errors: var seq[string]) =
  while true:
    case x.kind
    of xmlElementEnd:
      if x.elementName == result.tag:
        next(x)
      else:
        errors.add(errorMsg(x, "</" & result.tag & "> expected"))
        # do not skip it here!
      break
    of xmlEof:
      errors.add(errorMsg(x, "</" & result.tag & "> expected"))
      break
    else:
      result.addNode(parse(x, errors))

proc parse(x: var XmlParser, errors: var seq[string]): XmlNode =
  result = nil
  case x.kind
  of xmlComment:
    result = newComment(x.charData)
    next(x)
  of xmlCharData, xmlWhitespace:
    result = newText(x.charData)
    next(x)
  of xmlPI, xmlSpecial:
    # we just ignore processing instructions for now
    next(x)
  of xmlError:
    errors.add(errorMsg(x))
    next(x)
  of xmlElementStart: ## ``<elem>``
    result = newElement(x.elementName)
    next(x)
    untilElementEnd(x, result, errors)
  of xmlElementEnd:
    errors.add(errorMsg(x, "unexpected ending tag: " & x.elementName))
  of xmlElementOpen:
    result = newElement(x.elementName)
    next(x)
    result.attrs = newStringTable()
    while true:
      case x.kind
      of xmlAttribute:
        result.attrs[x.attrKey] = x.attrValue
        next(x)
      of xmlElementClose:
        next(x)
        break
      of xmlError:
        errors.add(errorMsg(x))
        next(x)
        break
      else:
        errors.add(errorMsg(x, "'>' expected"))
        next(x)
        break
    untilElementEnd(x, result, errors)
  of xmlAttribute, xmlElementClose:
    errors.add(errorMsg(x, "<some_tag> expected"))
    next(x)
  of xmlCData:
    result = newCData(x.charData)
    next(x)
  of xmlEntity:
    ## &entity;
    result = newEntity(x.entityName)
    next(x)
  of xmlEof: discard

proc parseXml*(s: Stream, filename: string,
               errors: var seq[string], options: set[XmlParseOption] = {reportComments}): XmlNode =
  ## Parses the XML from stream ``s`` and returns a ``XmlNode``. Every
  ## occurred parsing error is added to the ``errors`` sequence.
  result = nil
  var x: XmlParser = default(XmlParser)
  open(x, s, filename, options)
  while true:
    x.next()
    case x.kind
    of xmlElementOpen, xmlElementStart:
      result = parse(x, errors)
      break
    of xmlComment, xmlWhitespace, xmlSpecial, xmlPI: discard # just skip it
    of xmlError:
      errors.add(errorMsg(x))
    else:
      errors.add(errorMsg(x, "<some_tag> expected"))
      break
  close(x)

proc parseXml*(s: Stream, options: set[XmlParseOption] = {reportComments}): XmlNode =
  ## Parses the XML from stream ``s`` and returns a ``XmlNode``. All parsing
  ## errors are turned into an ``XmlError`` exception.
  var errors: seq[string] = @[]
  result = parseXml(s, "unknown_xml_doc", errors, options)
  if errors.len > 0: raiseInvalidXml(errors)

proc parseXml*(str: string, options: set[XmlParseOption] = {reportComments}): XmlNode =
  ## Parses the XML from string ``str`` and returns a ``XmlNode``. All parsing
  ## errors are turned into an ``XmlError`` exception.
  parseXml(newStringStream(str), options)

proc loadXml*(path: string, errors: var seq[string], options: set[XmlParseOption] = {reportComments}): XmlNode =
  ## Loads and parses XML from file specified by ``path``, and returns
  ## a ``XmlNode``. Every occurred parsing error is added to the ``errors``
  ## sequence.
  var s = newFileStream(path, fmRead)
  if s == nil: raise newException(IOError, "Unable to read file: " & path)
  result = parseXml(s, path, errors, options)

proc loadXml*(path: string, options: set[XmlParseOption] = {reportComments}): XmlNode =
  ## Loads and parses XML from file specified by ``path``, and returns
  ## a ``XmlNode``. All parsing errors are turned into an ``XmlError``
  ## exception.
  var errors: seq[string] = @[]
  result = loadXml(path, errors, options)
  if errors.len > 0: raiseInvalidXml(errors)

when isMainModule:
  when not defined(testing):
    import std/os

    var errors: seq[string] = @[]
    var x = loadXml(paramStr(1), errors)
    for e in items(errors): echo e

    var f: File
    if open(f, "xmltest.txt", fmWrite):
      f.write($x)
      f.close()
    else:
      quit("cannot write test.txt")
  else:
    block: # correctly parse ../../tests/testdata/doc1.xml
      let filePath = "tests/testdata/doc1.xml"
      var errors: seq[string] = @[]
      var xml = loadXml(filePath, errors)
      assert(errors.len == 0, "The file tests/testdata/doc1.xml should be parsed without errors.")

    block bug1518:
      var err: seq[string] = @[]
      assert $parsexml(newStringStream"<tag>One &amp; two</tag>", "temp.xml",
          err) == "<tag>One &amp; two</tag>"
