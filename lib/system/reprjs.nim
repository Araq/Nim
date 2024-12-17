#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
# The generic ``repr`` procedure for the javascript backend.

when defined(nimPreviewSlimSystem):
  import std/formatfloat

proc reprInt(x: int64): string {.compilerproc.} = $x
proc reprInt(x: uint64): string {.compilerproc.} = $x
proc reprInt(x: int): string {.compilerproc.} = $x
proc reprFloat(x: float): string {.compilerproc.} = $x

proc reprPointer(p: pointer): string {.compilerproc.} =
  # Do we need to generate the full 8bytes ? In js a pointer is an int anyway
  var tmp: int
  {.emit: "`tmp` = `p`_Idx || 0;".}
  result = $tmp

proc reprBool(x: bool): string {.compilerRtl.} =
  if x: result = "true"
  else: result = "false"

proc reprEnum(e: int, typ: PNimType): string {.compilerRtl.} =
  var tmp: bool
  let item = typ.node.sons[e]
  {.emit: "`tmp` = `item` !== undefined;".}
  if tmp:
    result = makeNimstrLit(item.name)
  else:
    result = $e & " (invalid data!)"

include system/repr_impl

proc reprChar(x: char): string {.compilerRtl.} =
  result = "\'"
  case x
  of '"': add(result, "\\\"")
  of '\\': add(result, "\\\\")
  of '\127'..'\255', '\0'..'\31': add(result, "\\" & reprInt(ord(x)))
  else: add(result, x)
  add(result, "\'")

proc reprStrAux(result: var string, s: cstring | string, len: int) =
  add(result, "\"")
  for i in 0 .. len-1:
    let c = s[i]
    case c
    of '"': add(result, "\\\"")
    of '\\': add(result, "\\\\")
    #of '\10': add(result, "\\10\"\n\"")
    of '\127'..'\255', '\0'..'\31':
      add(result, "\\" & reprInt(ord(c)))
    else:
      add(result, c)
  add(result, "\"")

proc reprStr(s: string): string {.compilerRtl.} =
  reprStrAux(result, s, s.len)

proc addSetElem(result: var string, elem: int, typ: PNimType) =
  # Dispatch each set element to the correct repr<Type> proc
  case typ.kind:
  of tyEnum: add(result, reprEnum(elem, typ))
  of tyBool: add(result, reprBool(bool(elem)))
  of tyChar: add(result, reprChar(chr(elem)))
  of tyRange: addSetElem(result, elem, typ.base) # Note the base to advance towards the element type
  of tyInt..tyInt64, tyUInt8, tyUInt16: add result, reprInt(elem)
  else: # data corrupt --> inform the user
    add(result, " (invalid data!)")

iterator setKeys(s: int): int {.inline.} =
  # The type of s is a lie, but it's expected to be a set.
  # Iterate over the JS object representing a set
  # and returns the keys as int.
  var len: int
  var yieldRes: int
  var i: int = 0
  {. emit: """
  var setObjKeys = Object.getOwnPropertyNames(`s`);
  `len` = setObjKeys.length;
  """ .}
  while i < len:
    {. emit: "`yieldRes` = parseInt(setObjKeys[`i`],10);\n" .}
    yield yieldRes
    inc i

proc reprSetAux(result: var string, s: int, typ: PNimType) =
  add(result, "{")
  var first: bool = true
  for el in setKeys(s):
    if first:
      first = false
    else:
      add(result, ", ")
    addSetElem(result, el, typ.base)
  add(result, "}")

proc reprSet(e: int, typ: PNimType): string {.compilerRtl.} =
  reprSetAux(result, e, typ)

type
  ReprClosure {.final.} = object
    recDepth: int       # do not recurse endlessly
    indent: int         # indentation

proc initReprClosure(cl: var ReprClosure) =
  cl.recDepth = -1 # default is to display everything!
  cl.indent = 0

proc reprAux(result: var string, p: pointer, typ: PNimType, cl: var ReprClosure)

proc reprArray(a: pointer, typ: PNimType,
              cl: var ReprClosure): string {.compilerRtl.} =
  # We prepend @ to seq, the C backend prepends the pointer to the seq.
  result = if typ.kind == tySequence: "@[" else: "["
  var len: int = 0

  {. emit: "`len` = `a`.length;\n" .}
  var dereffed: pointer = a
  for i in 0 .. len-1:
    if i > 0 :
      add(result, ", ")
    # advance pointer and point to element at index
    {. emit: """
    `dereffed`_Idx = `i`;
    `dereffed` = `a`[`dereffed`_Idx];
    """ .}
    reprAux(result, dereffed, typ.base, cl)

  add(result, "]")

proc isPointedToNil(p: pointer): bool =
  {. emit: "if (`p` === null) {`result` = true;}\n" .}

proc reprRef(result: var string, p: pointer, typ: PNimType,
          cl: var ReprClosure) =
  if p.isPointedToNil:
    add(result, "nil")
    return
  add(result, "ref " & reprPointer(p))
  add(result, " --> ")
  if typ.base.kind != tyArray:
    {. emit: """
    if (`p` != null && `p`.length > 0) {
      `p` = `p`[`p`_Idx];
    }
    """ .}
  reprAux(result, p, typ.base, cl)

proc reprRecordAux(result: var string, o: pointer, typ: PNimType, cl: var ReprClosure) =
  add(result, "[")

  var first = true
  var val = o
  if typ.node.len == 0:
    # if the object has only one field, len is 0  and sons is nil, the field is in node
    let key: cstring = typ.node.name
    add(result, $key & " = ")
    {. emit: "`val` = `o`[`key`];\n" .}
    reprAux(result, val, typ.node.typ, cl)
  else:
    # if the object has more than one field, sons is not nil and contains the fields.
    for i in 0 .. typ.node.len-1:
      if first: first = false
      else: add(result, ",\n")

      let key: cstring = typ.node.sons[i].name
      add(result, $key & " = ")
      {. emit: "`val` = `o`[`key`];\n" .} # access the field by name
      reprAux(result, val, typ.node.sons[i].typ, cl)
  add(result, "]")

proc reprRecord(o: pointer, typ: PNimType, cl: var ReprClosure): string {.compilerRtl.} =
  reprRecordAux(result, o, typ, cl)


proc reprJsonStringify(p: int): string {.compilerRtl.} =
  # As a last resort, use stringify
  # We use this for tyOpenArray, tyVarargs while genTypeInfo is not implemented
  var tmp: cstring
  {. emit: "`tmp` = JSON.stringify(`p`);\n" .}
  result = $tmp

proc reprAux(result: var string, p: pointer, typ: PNimType,
            cl: var ReprClosure) =
  if cl.recDepth == 0:
    add(result, "...")
    return
  dec(cl.recDepth)
  case typ.kind
  of tyInt..tyInt32, tyUInt..tyUInt32:
    add(result, reprInt(cast[int](p)))
  of tyInt64:
    add(result, reprInt(cast[int64](p)))
  of tyUInt64:
    add(result, reprInt(cast[uint64](p)))
  of tyChar:
    add(result, reprChar(cast[char](p)))
  of tyBool:
    add(result, reprBool(cast[bool](p)))
  of tyFloat..tyFloat128:
    add(result, reprFloat(cast[float](p)))
  of tyString:
    var fp: int
    {. emit: "`fp` = `p`;\n" .}
    add(result, reprStr(cast[string](p)))
  of tyCstring:
    var fp: cstring
    {. emit: "`fp` = `p`;\n" .}
    if fp.isNil:
      add(result, "nil")
    else:
      reprStrAux(result, fp, fp.len)
  of tyEnum, tyOrdinal:
    var fp: int
    {. emit: "`fp` = `p`;\n" .}
    add(result, reprEnum(fp, typ))
  of tySet:
    var fp: int
    {. emit: "`fp` = `p`;\n" .}
    add(result, reprSet(fp, typ))
  of tyRange: reprAux(result, p, typ.base, cl)
  of tyObject, tyTuple:
    add(result, reprRecord(p, typ, cl))
  of tyArray, tyArrayConstr, tySequence:
    add(result, reprArray(p, typ, cl))
  of tyPointer:
    add(result, reprPointer(p))
  of tyPtr, tyRef:
    reprRef(result, p, typ, cl)
  of tyProc:
    if p.isPointedToNil:
      add(result, "nil")
    else:
      add(result, reprPointer(p))
  else:
    add(result, "(invalid data!)" & reprJsonStringify(cast[int](p)))
  inc(cl.recDepth)

proc reprAny(p: pointer, typ: PNimType): string {.compilerRtl.} =
  var cl: ReprClosure
  initReprClosure(cl)
  reprAux(result, p, typ, cl)
  when defined(nimLegacyReprWithNewline): # see PR #16034
    add result, "\n"
