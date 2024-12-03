#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# string & sequence handling procedures needed by the code generator

# strings are dynamically resized, have a length field
# and are zero-terminated, so they can be casted to C
# strings easily
# we don't use refcounts because that's a behaviour
# the programmer may not want


proc dataPointer(a: PGenericSeq, elemAlign: int): pointer =
  cast[pointer](cast[int](a) +% align(GenericSeqSize, elemAlign))

proc dataPointer(a: PGenericSeq, elemAlign, elemSize, index: int): pointer =
  cast[pointer](cast[int](a) +% align(GenericSeqSize, elemAlign) +% (index*%elemSize))

proc resize(old: int): int {.inline.} =
  if old <= 0: result = 4
  elif old < 65536: result = old * 2
  else: result = old div 2 + old # for large arrays * 3/2 is better

when declared(allocAtomic):
  template allocStr(size: untyped): untyped =
    cast[NimString](allocAtomic(size))

  template allocStrNoInit(size: untyped): untyped =
    cast[NimString](boehmAllocAtomic(size))
elif defined(gcRegions):
  template allocStr(size: untyped): untyped =
    cast[NimString](newStr(addr(strDesc), size, true))

  template allocStrNoInit(size: untyped): untyped =
    cast[NimString](newStr(addr(strDesc), size, false))

else:
  template allocStr(size: untyped): untyped =
    cast[NimString](newObj(addr(strDesc), size))

  template allocStrNoInit(size: untyped): untyped =
    cast[NimString](newObjNoInit(addr(strDesc), size))

proc rawNewStringNoInit(space: int): NimString =
  let s = max(space, 7)
  result = allocStrNoInit(sizeof(TGenericSeq) + s + 1)
  result.reserved = s
  when defined(gogc):
    result.elemSize = 1

proc rawNewString(space: int): NimString {.compilerproc.} =
  result = rawNewStringNoInit(space)
  result.len = 0
  result.data[0] = '\0'

proc mnewString(len: int): NimString {.compilerproc.} =
  result = rawNewStringNoInit(len)
  result.len = len
  zeroMem(addr result.data[0], len + 1)

proc copyStrLast(s: NimString, start, last: int): NimString {.compilerproc.} =
  # This is not used by most recent versions of the compiler anymore, but
  # required for bootstrapping purposes.
  let start = max(start, 0)
  if s == nil: return nil
  let len = min(last, s.len-1) - start + 1
  result = rawNewStringNoInit(len)
  result.len = len
  copyMem(addr(result.data), addr(s.data[start]), len)
  result.data[len] = '\0'

proc copyStr(s: NimString, start: int): NimString {.compilerproc.} =
  # This is not used by most recent versions of the compiler anymore, but
  # required for bootstrapping purposes.
  if s == nil: return nil
  result = copyStrLast(s, start, s.len-1)

proc nimToCStringConv(s: NimString): cstring {.compilerproc, nonReloadable, inline.} =
  if s == nil or s.len == 0: result = cstring""
  else: result = cast[cstring](addr s.data)

proc toNimStr(str: cstring, len: int): NimString {.compilerproc.} =
  result = rawNewStringNoInit(len)
  result.len = len
  copyMem(addr(result.data), str, len)
  result.data[len] = '\0'

proc cstrToNimstr(str: cstring): NimString {.compilerRtl.} =
  if str == nil: NimString(nil)
  else: toNimStr(str, str.len)

proc copyString(src: NimString): NimString {.compilerRtl.} =
  if src != nil:
    if (src.reserved and seqShallowFlag) != 0:
      result = src
    else:
      result = rawNewStringNoInit(src.len)
      result.len = src.len
      copyMem(addr(result.data), addr(src.data), src.len + 1)
      sysAssert((seqShallowFlag and result.reserved) == 0, "copyString")
      when defined(nimShallowStrings):
        if (src.reserved and strlitFlag) != 0:
          result.reserved = (result.reserved and not strlitFlag) or seqShallowFlag

proc newOwnedString(src: NimString; n: int): NimString =
  result = rawNewStringNoInit(n)
  result.len = n
  copyMem(addr(result.data), addr(src.data), n)
  result.data[n] = '\0'

proc copyStringRC1(src: NimString): NimString {.compilerRtl.} =
  if src != nil:
    if (src.reserved and seqShallowFlag) != 0:
      result = src
      when declared(incRef):
        incRef(usrToCell(result))
    else:
      when declared(newObjRC1) and not defined(gcRegions):
        var s = src.len
        if s < 7: s = 7
        result = cast[NimString](newObjRC1(addr(strDesc), sizeof(TGenericSeq) +
                                s+1))
        result.reserved = s
        when defined(gogc):
          result.elemSize = 1
      else:
        result = rawNewStringNoInit(src.len)
      result.len = src.len
      copyMem(addr(result.data), addr(src.data), src.len + 1)
      sysAssert((seqShallowFlag and result.reserved) == 0, "copyStringRC1")
      when defined(nimShallowStrings):
        if (src.reserved and strlitFlag) != 0:
          result.reserved = (result.reserved and not strlitFlag) or seqShallowFlag

proc copyDeepString(src: NimString): NimString {.inline.} =
  if src != nil:
    result = rawNewStringNoInit(src.len)
    result.len = src.len
    copyMem(addr(result.data), addr(src.data), src.len + 1)

proc addChar(s: NimString, c: char): NimString =
  # is compilerproc!
  if s == nil:
    result = rawNewStringNoInit(1)
    result.len = 0
  else:
    result = s
    if result.len >= result.space:
      let r = resize(result.space)
      result = rawNewStringNoInit(r)
      result.len = s.len
      copyMem(addr result.data[0], unsafeAddr(s.data[0]), s.len+1)
      result.reserved = r
  result.data[result.len] = c
  result.data[result.len+1] = '\0'
  inc(result.len)

# These routines should be used like following:
#   <Nim code>
#   s &= "Hello " & name & ", how do you feel?"
#
#   <generated C code>
#   {
#     s = resizeString(s, 6 + name->len + 17);
#     appendString(s, strLit1);
#     appendString(s, strLit2);
#     appendString(s, strLit3);
#   }
#
#   <Nim code>
#   s = "Hello " & name & ", how do you feel?"
#
#   <generated C code>
#   {
#     string tmp0;
#     tmp0 = rawNewString(6 + name->len + 17);
#     appendString(s, strLit1);
#     appendString(s, strLit2);
#     appendString(s, strLit3);
#     s = tmp0;
#   }
#
#   <Nim code>
#   s = ""
#
#   <generated C code>
#   s = rawNewString(0);

proc resizeString(dest: NimString, addlen: int): NimString {.compilerRtl.} =
  if dest == nil:
    result = rawNewString(addlen)
  elif dest.len + addlen <= dest.space:
    result = dest
  else: # slow path:
    let sp = max(resize(dest.space), dest.len + addlen)
    result = rawNewStringNoInit(sp)
    result.len = dest.len
    copyMem(addr result.data[0], unsafeAddr(dest.data[0]), dest.len+1)
    result.reserved = sp
    #result = rawNewString(sp)
    #copyMem(result, dest, dest.len + sizeof(TGenericSeq))
    # DO NOT UPDATE LEN YET: dest.len = newLen

proc appendString(dest, src: NimString) {.compilerproc, inline.} =
  if src != nil:
    copyMem(addr(dest.data[dest.len]), addr(src.data), src.len + 1)
    inc(dest.len, src.len)

proc appendChar(dest: NimString, c: char) {.compilerproc, inline.} =
  dest.data[dest.len] = c
  dest.data[dest.len+1] = '\0'
  inc(dest.len)

proc setLengthStr(s: NimString, newLen: int): NimString {.compilerRtl.} =
  let n = max(newLen, 0)
  if s == nil:
    if n == 0:
      return s
    else:
      result = mnewString(n)
  elif n <= s.space:
    result = s
  else:
    let sp = max(resize(s.space), n)
    result = rawNewStringNoInit(sp)
    result.len = s.len
    copyMem(addr result.data[0], unsafeAddr(s.data[0]), s.len)
    zeroMem(addr result.data[s.len], n - s.len)
    result.reserved = sp
  result.len = n
  result.data[n] = '\0'

# ----------------- sequences ----------------------------------------------

proc incrSeq(seq: PGenericSeq, elemSize, elemAlign: int): PGenericSeq {.compilerproc.} =
  # increments the length by one:
  # this is needed for supporting ``add``;
  #
  #  add(seq, x)  generates:
  #  seq = incrSeq(seq, sizeof(x));
  #  seq[seq->len-1] = x;
  result = seq
  if result.len >= result.space:
    let r = resize(result.space)
    result = cast[PGenericSeq](growObj(result, align(GenericSeqSize, elemAlign) + elemSize * r))
    result.reserved = r
  inc(result.len)

proc incrSeqV2(seq: PGenericSeq, elemSize, elemAlign: int): PGenericSeq {.compilerproc.} =
  # incrSeq version 2
  result = seq
  if result.len >= result.space:
    let r = resize(result.space)
    result = cast[PGenericSeq](growObj(result, align(GenericSeqSize, elemAlign) + elemSize * r))
    result.reserved = r

proc incrSeqV3(s: PGenericSeq, typ: PNimType): PGenericSeq {.compilerproc.} =
  if s == nil:
    result = cast[PGenericSeq](newSeq(typ, 1))
    result.len = 0
  else:
    result = s
    if result.len >= result.space:
      let r = resize(result.space)
      result = cast[PGenericSeq](newSeq(typ, r))
      result.len = s.len
      copyMem(dataPointer(result, typ.base.align), dataPointer(s, typ.base.align), s.len * typ.base.size)
      # since we steal the content from 's', it's crucial to set s's len to 0.
      s.len = 0

proc setLengthSeq(seq: PGenericSeq, elemSize, elemAlign, newLen: int): PGenericSeq {.
    compilerRtl, inl.} =
  result = seq
  if result.space < newLen:
    let r = max(resize(result.space), newLen)
    result = cast[PGenericSeq](growObj(result, align(GenericSeqSize, elemAlign) + elemSize * r))
    result.reserved = r
  elif newLen < result.len:
    # we need to decref here, otherwise the GC leaks!
    when not defined(boehmGC) and not defined(nogc) and
         not defined(gcMarkAndSweep) and not defined(gogc) and
         not defined(gcRegions):
      if ntfNoRefs notin extGetCellType(result).base.flags:
        for i in newLen..result.len-1:
          forAllChildrenAux(dataPointer(result, elemAlign, elemSize, i),
                            extGetCellType(result).base, waZctDecRef)

    # XXX: zeroing out the memory can still result in crashes if a wiped-out
    # cell is aliased by another pointer (ie proc parameter or a let variable).
    # This is a tough problem, because even if we don't zeroMem here, in the
    # presence of user defined destructors, the user will expect the cell to be
    # "destroyed" thus creating the same problem. We can destroy the cell in the
    # finalizer of the sequence, but this makes destruction non-deterministic.
    zeroMem(dataPointer(result, elemAlign, elemSize, newLen), (result.len-%newLen) *% elemSize)
  result.len = newLen

proc setLengthSeqV2(s: PGenericSeq, typ: PNimType, newLen: int): PGenericSeq {.
    compilerRtl.} =
  sysAssert typ.kind == tySequence, "setLengthSeqV2: type is not a seq"
  if s == nil:
    if newLen == 0:
      result = s
    else:
      result = cast[PGenericSeq](newSeq(typ, newLen))
  else:
    let elemSize = typ.base.size
    let elemAlign = typ.base.align
    if s.space < newLen:
      let r = max(resize(s.space), newLen)
      result = cast[PGenericSeq](newSeq(typ, r))
      copyMem(dataPointer(result, elemAlign), dataPointer(s, elemAlign), s.len * elemSize)
      # since we steal the content from 's', it's crucial to set s's len to 0.
      s.len = 0
    elif newLen < s.len:
      result = s
      # we need to decref here, otherwise the GC leaks!
      when not defined(boehmGC) and not defined(nogc) and
          not defined(gcMarkAndSweep) and not defined(gogc) and
          not defined(gcRegions):
        if ntfNoRefs notin typ.base.flags:
          for i in newLen..result.len-1:
            forAllChildrenAux(dataPointer(result, elemAlign, elemSize, i),
                              extGetCellType(result).base, waZctDecRef)

      # XXX: zeroing out the memory can still result in crashes if a wiped-out
      # cell is aliased by another pointer (ie proc parameter or a let variable).
      # This is a tough problem, because even if we don't zeroMem here, in the
      # presence of user defined destructors, the user will expect the cell to be
      # "destroyed" thus creating the same problem. We can destroy the cell in the
      # finalizer of the sequence, but this makes destruction non-deterministic.
      zeroMem(dataPointer(result, elemAlign, elemSize, newLen), (result.len-%newLen) *% elemSize)
    else:
      result = s
      zeroMem(dataPointer(result, elemAlign, elemSize, result.len), (newLen-%result.len) *% elemSize)
    result.len = newLen

func capacity*(self: string): int {.inline.} =
  ## Returns the current capacity of the string.
  # See https://github.com/nim-lang/RFCs/issues/460
  runnableExamples:
    var str = newStringOfCap(cap = 42)
    str.add "Nim"
    assert str.capacity == 42

  let str = cast[NimString](self)
  result = if str != nil: str.space else: 0

func capacity*[T](self: seq[T]): int {.inline.} =
  ## Returns the current capacity of the seq.
  # See https://github.com/nim-lang/RFCs/issues/460
  runnableExamples:
    var lst = newSeqOfCap[string](cap = 42)
    lst.add "Nim"
    assert lst.capacity == 42

  let sek = cast[PGenericSeq](self)
  result = if sek != nil: sek.space else: 0
