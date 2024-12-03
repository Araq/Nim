#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# The generic ``repr`` procedure. It is an invaluable debugging tool.

when not defined(useNimRtl):
  proc reprAny(p: pointer, typ: PNimType): string {.compilerRtl, gcsafe.}

proc reprInt(x: int64): string {.compilerproc.} = return $x
proc reprFloat(x: float): string {.compilerproc.} = return $x

proc reprPointer(x: pointer): string {.compilerproc.} =
  result = newString(60)
  let n = c_snprintf(cast[cstring](addr result[0]), csize_t(60), "%p", x)
  setLen(result, n)

proc reprStrAux(result: var string, s: cstring; len: int) =
  if cast[pointer](s) == nil:
    add result, "nil"
    return
  if len > 0:
    add result, reprPointer(cast[pointer](s))
  add result, "\""
  for i in 0 .. pred(len):
    let c = s[i]
    case c
    of '"': add result, "\\\""
    of '\\': add result, "\\\\" # BUGFIX: forgotten
    of '\10': add result, "\\10\"\n\"" # " \n " # better readability
    of '\127' .. '\255', '\0'..'\9', '\11'..'\31':
      add result, "\\" & reprInt(ord(c))
    else:
      result.add(c)
  add result, "\""

proc reprStr(s: string): string {.compilerRtl.} =
  result = ""
  reprStrAux(result, s, s.len)

proc reprBool(x: bool): string {.compilerRtl.} =
  if x: result = "true"
  else: result = "false"

proc reprChar(x: char): string {.compilerRtl.} =
  result = "\'"
  case x
  of '"': add result, "\\\""
  of '\\': add result, "\\\\"
  of '\127' .. '\255', '\0'..'\31': add result, "\\" & reprInt(ord(x))
  else: add result, x
  add result, "\'"

proc reprEnum(e: int, typ: PNimType): string {.compilerRtl.} =
  ## Return string representation for enumeration values
  var n = typ.node
  if ntfEnumHole notin typ.flags:
    let o = e - n.sons[0].offset
    if o >= 0 and o <% typ.node.len:
      return $n.sons[o].name
  else:
    # ugh we need a slow linear search:
    var s = n.sons
    for i in 0 .. n.len-1:
      if s[i].offset == e:
        return $s[i].name

  result = $e & " (invalid data!)"

include system/repr_impl

type
  PByteArray = ptr UncheckedArray[byte] # array[0xffff, byte]

proc addSetElem(result: var string, elem: int, typ: PNimType) {.benign.} =
  case typ.kind
  of tyEnum: add result, reprEnum(elem, typ)
  of tyBool: add result, reprBool(bool(elem))
  of tyChar: add result, reprChar(chr(elem))
  of tyRange: addSetElem(result, elem, typ.base)
  of tyInt..tyInt64, tyUInt8, tyUInt16: add result, reprInt(elem)
  else: # data corrupt --> inform the user
    add result, " (invalid data!)"

proc reprSetAux(result: var string, p: pointer, typ: PNimType) =
  # "typ.slots.len" field is for sets the "first" field
  var elemCounter = 0  # we need this flag for adding the comma at
                       # the right places
  add result, "{"
  var u: uint64
  case typ.size
  of 1: u = cast[ptr uint8](p)[]
  of 2: u = cast[ptr uint16](p)[]
  of 4: u = cast[ptr uint32](p)[]
  of 8: u = cast[ptr uint64](p)[]
  else:
    u = uint64(0)
    var a = cast[PByteArray](p)
    for i in 0 .. typ.size*8-1:
      if (uint(a[i shr 3]) and (1'u shl (i and 7))) != 0:
        if elemCounter > 0: add result, ", "
        addSetElem(result, i+typ.node.len, typ.base)
        inc(elemCounter)
  if typ.size <= 8:
    for i in 0..sizeof(int64)*8-1:
      if (u and (1'u64 shl uint64(i))) != 0'u64:
        if elemCounter > 0: add result, ", "
        addSetElem(result, i+typ.node.len, typ.base)
        inc(elemCounter)
  add result, "}"

proc reprSet(p: pointer, typ: PNimType): string {.compilerRtl.} =
  result = ""
  reprSetAux(result, p, typ)

type
  ReprClosure {.final.} = object # we cannot use a global variable here
                                  # as this wouldn't be thread-safe
    when declared(CellSet):
      marked: CellSet
    recdepth: int       # do not recurse endlessly
    indent: int         # indentation

when not defined(useNimRtl):
  proc initReprClosure(cl: var ReprClosure) =
    # Important: cellsets does not lock the heap when doing allocations! We
    # have to do it here ...
    when hasThreadSupport and hasSharedHeap and declared(heapLock):
      AcquireSys(HeapLock)
    when declared(CellSet):
      init(cl.marked)
    cl.recdepth = -1      # default is to display everything!
    cl.indent = 0

  proc deinitReprClosure(cl: var ReprClosure) =
    when declared(CellSet): deinit(cl.marked)
    when hasThreadSupport and hasSharedHeap and declared(heapLock):
      ReleaseSys(HeapLock)

  proc reprBreak(result: var string, cl: ReprClosure) =
    add result, "\n"
    for i in 0..cl.indent-1: add result, ' '

  proc reprAux(result: var string, p: pointer, typ: PNimType,
               cl: var ReprClosure) {.benign.}

  proc reprArray(result: var string, p: pointer, typ: PNimType,
                 cl: var ReprClosure) =
    add result, "["
    var bs = typ.base.size
    for i in 0..typ.size div bs - 1:
      if i > 0: add result, ", "
      reprAux(result, cast[pointer](cast[int](p) + i*bs), typ.base, cl)
    add result, "]"

  when defined(nimSeqsV2):
    type
      GenericSeq = object
        len: int
        p: pointer
      PGenericSeq = ptr GenericSeq
    const payloadOffset = sizeof(int) + sizeof(pointer)
      # see seqs.nim:    cap: int
      #                  region: Allocator

    template payloadPtr(x: untyped): untyped = cast[PGenericSeq](x).p
  else:
    const payloadOffset = GenericSeqSize ## the payload offset always depends on the alignment of the member type.
    template payloadPtr(x: untyped): untyped = x

  proc reprSequence(result: var string, p: pointer, typ: PNimType,
                    cl: var ReprClosure) =
    if p == nil:
      add result, "[]"
      return
    result.add(reprPointer(p))
    result.add "@["
    var bs = typ.base.size
    for i in 0..cast[PGenericSeq](p).len-1:
      if i > 0: add result, ", "
      reprAux(result, cast[pointer](cast[int](payloadPtr(p)) + align(payloadOffset, typ.align) + i*bs),
              typ.base, cl)
    add result, "]"

  proc reprRecordAux(result: var string, p: pointer, n: ptr TNimNode,
                     cl: var ReprClosure) {.benign.} =
    case n.kind
    of nkNone: sysAssert(false, "reprRecordAux")
    of nkSlot:
      add result, $n.name
      add result, " = "
      reprAux(result, cast[pointer](cast[int](p) + n.offset), n.typ, cl)
    of nkList:
      for i in 0..n.len-1:
        if i > 0: add result, ",\n"
        reprRecordAux(result, p, n.sons[i], cl)
    of nkCase:
      var m = selectBranch(p, n)
      reprAux(result, cast[pointer](cast[int](p) + n.offset), n.typ, cl)
      if m != nil: reprRecordAux(result, p, m, cl)

  proc reprRecord(result: var string, p: pointer, typ: PNimType,
                  cl: var ReprClosure) =
    add result, "["
    var curTyp = typ
    var first = true
    while curTyp != nil:
      var part = ""
      reprRecordAux(part, p, curTyp.node, cl)
      if part.len > 0:
        if not first:
          add result, ",\n"
        add result, part
        first = false
      curTyp = curTyp.base
    add result, "]"

  proc reprRef(result: var string, p: pointer, typ: PNimType,
               cl: var ReprClosure) =
    # we know that p is not nil here:
    when declared(CellSet):
      when defined(boehmGC) or defined(gogc) or defined(nogc) or usesDestructors:
        var cell = cast[PCell](p)
      else:
        var cell = usrToCell(p)
      add result, if typ.kind == tyPtr: "ptr " else: "ref "
      add result, reprPointer(p)
      if cell notin cl.marked:
        # only the address is shown:
        incl(cl.marked, cell)
        add result, " --> "
        reprAux(result, p, typ.base, cl)

  proc getInt(p: pointer, size: int): int =
    case size
    of 1: return int(cast[ptr uint8](p)[])
    of 2: return int(cast[ptr uint16](p)[])
    of 4: return int(cast[ptr uint32](p)[])
    of 8: return int(cast[ptr uint64](p)[])
    else: discard

  proc reprAux(result: var string, p: pointer, typ: PNimType,
               cl: var ReprClosure) =
    if cl.recdepth == 0:
      add result, "..."
      return
    dec(cl.recdepth)
    case typ.kind
    of tySet: reprSetAux(result, p, typ)
    of tyArray, tyArrayConstr: reprArray(result, p, typ, cl)
    of tyTuple: reprRecord(result, p, typ, cl)
    of tyObject:
      var t = cast[ptr PNimType](p)[]
      reprRecord(result, p, t, cl)
    of tyRef, tyPtr:
      sysAssert(p != nil, "reprAux")
      if cast[PPointer](p)[] == nil: add result, "nil"
      else: reprRef(result, cast[PPointer](p)[], typ, cl)
    of tySequence:
      reprSequence(result, cast[PPointer](p)[], typ, cl)
    of tyInt: add result, $(cast[ptr int](p)[])
    of tyInt8: add result, $int(cast[ptr int8](p)[])
    of tyInt16: add result, $int(cast[ptr int16](p)[])
    of tyInt32: add result, $int(cast[ptr int32](p)[])
    of tyInt64: add result, $(cast[ptr int64](p)[])
    of tyUInt: add result, $(cast[ptr uint](p)[])
    of tyUInt8: add result, $(cast[ptr uint8](p)[])
    of tyUInt16: add result, $(cast[ptr uint16](p)[])
    of tyUInt32: add result, $(cast[ptr uint32](p)[])
    of tyUInt64: add result, $(cast[ptr uint64](p)[])

    of tyFloat: add result, $(cast[ptr float](p)[])
    of tyFloat32: add result, $(cast[ptr float32](p)[])
    of tyFloat64: add result, $(cast[ptr float64](p)[])
    of tyEnum: add result, reprEnum(getInt(p, typ.size), typ)
    of tyBool: add result, reprBool(cast[ptr bool](p)[])
    of tyChar: add result, reprChar(cast[ptr char](p)[])
    of tyString:
      let sp = cast[ptr string](p)
      reprStrAux(result, sp[].cstring, sp[].len)
    of tyCstring:
      let cs = cast[ptr cstring](p)[]
      if cs.isNil: add result, "nil"
      else: reprStrAux(result, cs, cs.len)
    of tyRange: reprAux(result, p, typ.base, cl)
    of tyProc, tyPointer:
      if cast[PPointer](p)[] == nil: add result, "nil"
      else: add result, reprPointer(cast[PPointer](p)[])
    of tyUncheckedArray:
      add result, "[...]"
    else:
      add result, "(invalid data!)"
    inc(cl.recdepth)

when not defined(useNimRtl):
  proc reprOpenArray(p: pointer, length: int, elemtyp: PNimType): string {.
                     compilerRtl.} =
    var
      cl: ReprClosure
    initReprClosure(cl)
    result = "["
    var bs = elemtyp.size
    for i in 0..length - 1:
      if i > 0: add result, ", "
      reprAux(result, cast[pointer](cast[int](p) + i*bs), elemtyp, cl)
    add result, "]"
    deinitReprClosure(cl)

when not defined(useNimRtl):
  proc reprAny(p: pointer, typ: PNimType): string =
    var
      cl: ReprClosure
    initReprClosure(cl)
    result = ""
    if typ.kind in {tyObject, tyTuple, tyArray, tyArrayConstr, tySet}:
      reprAux(result, p, typ, cl)
    else:
      var p = p
      reprAux(result, addr(p), typ, cl)
    when defined(nimLegacyReprWithNewline): # see PR #16034
      add result, "\n"
    deinitReprClosure(cl)
