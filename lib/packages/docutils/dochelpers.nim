#
#
#            Nim's Runtime Library
#        (c) Copyright 2021 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Integration helpers between ``docgen.nim`` and ``rst.nim``.
##
## Function `toLangSymbol(linkText)`_ produces a signature `docLink` of
## `type LangSymbol`_ in ``rst.nim``, while `match(generated, docLink)`_
## matches it with `generated`, produced from `PNode` by ``docgen.rst``.

import rstast
import std/strutils

when defined(nimPreviewSlimSystem):
  import std/[assertions, syncio]
  from std/objectequals import nil


type
  LangSymbol* = object       ## symbol signature in Nim
    symKind*: string           ## "proc", "const", "type", etc
    symTypeKind*: string       ## ""|enum|object|tuple -
                               ## valid only when `symKind == "type"`
    name*: string              ## plain symbol name without any parameters
    generics*: string          ## generic parameters (without brackets)
    isGroup*: bool             ## is LangSymbol a group with overloads?
    # the following fields are valid iff `isGroup` == false
    # (always false when parsed by `toLangSymbol` because link like foo_
    # can point to just a single symbol foo, e.g. proc).
    parametersProvided*: bool  ## to disambiguate `proc f`_ and `proc f()`_
    parameters*: seq[tuple[name: string, `type`: string]]
                               ## name-type seq, e.g. for proc
    outType*: string           ## result type, e.g. for proc

proc `$`*(s: LangSymbol): string =  # for debug
  ("(symkind=$1, symTypeKind=$2, name=$3, generics=$4, isGroup=$5, " &
   "parametersProvided=$6, parameters=$7, outType=$8)") % [
      s.symKind, s.symTypeKind , s.name, s.generics, $s.isGroup,
      $s.parametersProvided, $s.parameters, s.outType]

when defined(nimPreviewSlimSystem):
  proc `==`*(a, b: LangSymbol): bool {.inline.} =
    result = objectequals.`==`(a, b)

func nimIdentBackticksNormalize*(s: string): string =
  ## Normalizes the string `s` as a Nim identifier.
  ##
  ## Unlike `nimIdentNormalize` removes spaces and backticks.
  ##
  ## .. Warning:: No checking (e.g. that identifiers cannot start from
  ##    digits or '_', or that number of backticks is even) is performed.
  runnableExamples:
    doAssert nimIdentBackticksNormalize("Foo_bar") == "Foobar"
    doAssert nimIdentBackticksNormalize("FoO BAr") == "Foobar"
    doAssert nimIdentBackticksNormalize("`Foo BAR`") == "Foobar"
    doAssert nimIdentBackticksNormalize("` Foo BAR `") == "Foobar"
    # not a valid identifier:
    doAssert nimIdentBackticksNormalize("`_x_y`") == "_xy"
  result = newString(s.len)
  var firstChar = true
  var j = 0
  for i in 0..len(s) - 1:
    if s[i] in {'A'..'Z'}:
      if not firstChar:  # to lowercase
        result[j] = chr(ord(s[i]) + (ord('a') - ord('A')))
      else:
        result[j] = s[i]
        firstChar = false
      inc j
    elif s[i] notin {'_', ' ', '`'}:
      result[j] = s[i]
      inc j
      firstChar = false
    elif s[i] == '_' and firstChar:
      result[j] = '_'
      inc j
      firstChar = false
    else: discard  # just omit '`' or ' '
  if j != s.len: setLen(result, j)

proc langSymbolGroup*(kind: string, name: string): LangSymbol =
  if kind notin ["proc", "func", "macro", "method", "iterator",
                 "template", "converter"]:
    raise newException(ValueError, "unknown symbol kind $1" % [kind])
  result = LangSymbol(symKind: kind, name: name, isGroup: true)

proc toLangSymbol*(linkText: PRstNode): LangSymbol =
  ## Parses `linkText` into a more structured form using a state machine.
  ##
  ## This proc is designed to allow link syntax with operators even
  ## without escaped backticks inside:
  ##   
  ##     `proc *`_
  ##     `proc []`_
  ##
  ## This proc should be kept in sync with the `renderTypes` proc from
  ## ``compiler/typesrenderer.nim``.
  template fail(msg: string) =
    raise newException(ValueError, msg)
  if linkText.kind notin {rnRstRef, rnInner}:
    fail("toLangSymbol: wrong input kind " & $linkText.kind)

  const NimDefs = ["proc", "func", "macro", "method", "iterator",
                   "template", "converter", "const", "type", "var",
                   "enum", "object", "tuple", "module"]
  template resolveSymKind(x: string) =
    if x in ["enum", "object", "tuple"]:
      result.symKind = "type"
      result.symTypeKind = x
    else:
      result.symKind = x
  type
    State = enum
      inBeginning
      afterSymKind
      beforeSymbolName  # auxiliary state to catch situations like `proc []`_ after space
      atSymbolName
      afterSymbolName
      genericsPar
      parameterName
      parameterType
      outType
  var state = inBeginning
  var curIdent = ""
  template flushIdent() =
    if curIdent != "":
      case state
      of inBeginning:  fail("incorrect state inBeginning")
      of afterSymKind:  resolveSymKind curIdent
      of beforeSymbolName:  fail("incorrect state beforeSymbolName")
      of atSymbolName: result.name = curIdent.nimIdentBackticksNormalize
      of afterSymbolName: fail("incorrect state afterSymbolName")
      of genericsPar: result.generics = curIdent
      of parameterName: result.parameters.add (curIdent, "")
      of parameterType:
        for a in countdown(result.parameters.len - 1, 0):
          if result.parameters[a].`type` == "":
            result.parameters[a].`type` = curIdent
      of outType: result.outType = curIdent
      curIdent = ""
  var parens = 0
  let L = linkText.sons.len
  template s(i: int): string = linkText.sons[i].text
  var i = 0
  template nextState =
    case s(i)
    of " ":
      if state == afterSymKind:
        flushIdent
        state = beforeSymbolName
    of "`":
      curIdent.add "`"
      inc i
      while i < L:  # add contents between ` ` as a whole
        curIdent.add s(i)
        if s(i) == "`":
          break
        inc i
      curIdent = curIdent.nimIdentBackticksNormalize
      if state in {inBeginning, afterSymKind, beforeSymbolName}:
        state = atSymbolName
        flushIdent
        state = afterSymbolName
    of "[":
      if state notin {inBeginning, afterSymKind, beforeSymbolName}:
        inc parens
      if state in {inBeginning, afterSymKind, beforeSymbolName}:
        state = atSymbolName
        curIdent.add s(i)
      elif state in {atSymbolName, afterSymbolName} and parens == 1:
        flushIdent
        state = genericsPar
        curIdent.add s(i)
      else: curIdent.add s(i)
    of "]":
      if state notin {inBeginning, afterSymKind, beforeSymbolName, atSymbolName}:
        dec parens
      if state == genericsPar and parens == 0:
        curIdent.add s(i)
        flushIdent
      else: curIdent.add s(i)
    of "(":
      inc parens
      if state in {inBeginning, afterSymKind, beforeSymbolName}:
        result.parametersProvided = true
        state = atSymbolName
        flushIdent
        state = parameterName
      elif state in {atSymbolName, afterSymbolName, genericsPar} and parens == 1:
        result.parametersProvided = true
        flushIdent
        state = parameterName
      else: curIdent.add s(i)
    of ")":
      dec parens
      if state in {parameterName, parameterType} and parens == 0:
        flushIdent
        state = outType
      else: curIdent.add s(i)
    of "{":  # remove pragmas
      while i < L:
        if s(i) == "}":
          break
        inc i
    of ",", ";":
      if state in {parameterName, parameterType} and parens == 1:
        flushIdent
        state = parameterName
      else: curIdent.add s(i)
    of "*":  # skip export symbol
      if state == atSymbolName:
        flushIdent
        state = afterSymbolName
      elif state == afterSymbolName:
        discard
      else: curIdent.add "*"
    of ":":
      if state == outType: discard
      elif state == parameterName:
        flushIdent
        state = parameterType
      else: curIdent.add ":"
    else:
      let isPostfixSymKind = i > 0 and i == L - 1 and
          result.symKind == "" and s(i) in NimDefs
      if isPostfixSymKind:  # for links like `foo proc`_
        resolveSymKind s(i)
      else:
        case state
        of inBeginning:
          if s(i) in NimDefs:
            state = afterSymKind
          else:
            state = atSymbolName
          curIdent.add s(i)
        of afterSymKind, beforeSymbolName:
          state = atSymbolName
          curIdent.add s(i)
        of parameterType:
          case s(i)
          of "ref": curIdent.add "ref."
          of "ptr": curIdent.add "ptr."
          of "var": discard
          else: curIdent.add s(i).nimIdentBackticksNormalize
        of atSymbolName:
          curIdent.add s(i)
        else:
          curIdent.add s(i).nimIdentBackticksNormalize
  while i < L:
    nextState
    inc i
  if state == afterSymKind:  # treat `type`_ as link to symbol `type`
    state = atSymbolName
  flushIdent
  result.isGroup = false

proc match*(generated: LangSymbol, docLink: LangSymbol): bool =
  ## Returns true if `generated` can be a target for `docLink`.
  ## If `generated` is an overload group then only `symKind` and `name`
  ## are compared for success.
  result = true
  if docLink.symKind != "":
    if generated.symKind == "proc":
      result = docLink.symKind in ["proc", "func"]
    else:
      result = generated.symKind == docLink.symKind
      if result and docLink.symKind == "type" and docLink.symTypeKind != "":
        result = generated.symTypeKind == docLink.symTypeKind
    if not result: return
  result = generated.name == docLink.name
  if not result: return
  if generated.isGroup:
    # if `()` were added then it's not a reference to the whole group:
    return not docLink.parametersProvided
  if docLink.generics != "":
    result = generated.generics == docLink.generics
    if not result: return
  if docLink.outType != "":
    result = generated.outType == docLink.outType
    if not result: return
  if docLink.parametersProvided:
    result = generated.parameters.len == docLink.parameters.len
    if not result: return
    var onlyType = false
    for i in 0 ..< generated.parameters.len:
      let g = generated.parameters[i]
      let d = docLink.parameters[i]
      if i == 0:
        if g.`type` == d.name:
          onlyType = true  # only types, not names, are provided in `docLink`
      if onlyType:
        result = g.`type` == d.name
      else:
        if d.`type` != "":
          result = g.`type` == d.`type`
          if not result: return
        result = g.name == d.name
      if not result: return
