#
#
#            Nim's Runtime Library
#        (c) Copyright 2017 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Default new string implementation used by Nim's core.

type
  NimStrPayloadBase = object
    cap: int

  NimStrPayload {.core.} = object
    cap: int
    data: UncheckedArray[char]

  NimStringV2 {.core.} = object
    len: int
    p: ptr NimStrPayload ## can be nil if len == 0.

const nimStrVersion {.core.} = 2

template isLiteral(s): bool = (s.p == nil) or (s.p.cap and strlitFlag) == strlitFlag

template contentSize(cap): int = cap + 1 + sizeof(NimStrPayloadBase)

template frees(s) =
  if not isLiteral(s):
    when compileOption("threads"):
      deallocShared(s.p)
    else:
      dealloc(s.p)

template allocPayload(newLen: int): ptr NimStrPayload =
  when compileOption("threads"):
    cast[ptr NimStrPayload](allocShared(contentSize(newLen)))
  else:
    cast[ptr NimStrPayload](alloc(contentSize(newLen)))

template allocPayload0(newLen: int): ptr NimStrPayload =
  when compileOption("threads"):
    cast[ptr NimStrPayload](allocShared0(contentSize(newLen)))
  else:
    cast[ptr NimStrPayload](alloc0(contentSize(newLen)))

template reallocPayload(p: pointer, newLen: int): ptr NimStrPayload =
  when compileOption("threads"):
    cast[ptr NimStrPayload](reallocShared(p, contentSize(newLen)))
  else:
    cast[ptr NimStrPayload](realloc(p, contentSize(newLen)))

template reallocPayload0(p: pointer; oldLen, newLen: int): ptr NimStrPayload =
  when compileOption("threads"):
    cast[ptr NimStrPayload](reallocShared0(p, contentSize(oldLen), contentSize(newLen)))
  else:
    cast[ptr NimStrPayload](realloc0(p, contentSize(oldLen), contentSize(newLen)))

proc resize(old: int): int {.inline.} =
  if old <= 0: result = 4
  elif old <= high(int16): result = old * 2
  else: result = old div 2 + old # for large arrays * 3/2 is better

proc prepareAdd(s: var NimStringV2; addLen: int) {.compilerRtl.} =
  let newLen = s.len + addLen
  if isLiteral(s):
    let oldP = s.p
    # can't mutate a literal, so we need a fresh copy here:
    s.p = allocPayload(newLen)
    s.p.cap = newLen
    if s.len > 0:
      # we are about to append, so there is no need to copy the \0 terminator:
      copyMem(unsafeAddr s.p.data[0], unsafeAddr oldP.data[0], min(s.len, newLen))
    elif oldP == nil:
      # In the case of `newString(0) & ""`, since `src.len == 0`, `appendString`
      # will not set the `\0` terminator, so we set it here.
      s.p.data[0] = '\0'
  else:
    let oldCap = s.p.cap and not strlitFlag
    if newLen > oldCap:
      let newCap = max(newLen, resize(oldCap))
      s.p = reallocPayload(s.p, newCap)
      s.p.cap = newCap
      if newLen < newCap:
        zeroMem(cast[pointer](addr s.p.data[newLen+1]), newCap - newLen)

proc nimAddCharV1(s: var NimStringV2; c: char) {.compilerRtl, inl.} =
  #if (s.p == nil) or (s.len+1 > s.p.cap and not strlitFlag):
  prepareAdd(s, 1)
  s.p.data[s.len] = c
  inc s.len
  s.p.data[s.len] = '\0'

proc toNimStr(str: cstring, len: int): NimStringV2 {.compilerproc.} =
  if len <= 0:
    result = NimStringV2(len: 0, p: nil)
  else:
    var p = allocPayload(len)
    p.cap = len
    copyMem(unsafeAddr p.data[0], str, len+1)
    result = NimStringV2(len: len, p: p)

proc cstrToNimstr(str: cstring): NimStringV2 {.compilerRtl.} =
  if str == nil: toNimStr(str, 0)
  else: toNimStr(str, str.len)

proc nimToCStringConv(s: NimStringV2): cstring {.compilerproc, nonReloadable, inline.} =
  if s.len == 0: result = cstring""
  else: result = cast[cstring](unsafeAddr s.p.data)

proc appendString(dest: var NimStringV2; src: NimStringV2) {.compilerproc, inline.} =
  if src.len > 0:
    # also copy the \0 terminator:
    copyMem(unsafeAddr dest.p.data[dest.len], unsafeAddr src.p.data[0], src.len+1)
    inc dest.len, src.len

proc appendChar(dest: var NimStringV2; c: char) {.compilerproc, inline.} =
  dest.p.data[dest.len] = c
  inc dest.len
  dest.p.data[dest.len] = '\0'

proc rawNewString(space: int): NimStringV2 {.compilerproc.} =
  # this is also 'system.newStringOfCap'.
  if space <= 0:
    result = NimStringV2(len: 0, p: nil)
  else:
    var p = allocPayload(space)
    p.cap = space
    p.data[0] = '\0'
    result = NimStringV2(len: 0, p: p)

proc mnewString(len: int): NimStringV2 {.compilerproc.} =
  if len <= 0:
    result = NimStringV2(len: 0, p: nil)
  else:
    var p = allocPayload0(len)
    p.cap = len
    result = NimStringV2(len: len, p: p)

proc setLengthStrV2(s: var NimStringV2, newLen: int) {.compilerRtl.} =
  if newLen == 0:
    discard "do not free the buffer here, pattern 's.setLen 0' is common for avoiding allocations"
  else:
    if isLiteral(s):
      let oldP = s.p
      s.p = allocPayload(newLen)
      s.p.cap = newLen
      if s.len > 0:
        copyMem(unsafeAddr s.p.data[0], unsafeAddr oldP.data[0], min(s.len, newLen))
        if newLen > s.len:
          zeroMem(cast[pointer](addr s.p.data[s.len]), newLen - s.len + 1)
        else:
          s.p.data[newLen] = '\0'
      else:
        zeroMem(cast[pointer](addr s.p.data[0]), newLen + 1)
    elif newLen > s.len:
      let oldCap = s.p.cap and not strlitFlag
      if newLen > oldCap:
        let newCap = max(newLen, resize(oldCap))
        s.p = reallocPayload0(s.p, oldCap, newCap)
        s.p.cap = newCap

    s.p.data[newLen] = '\0'
  s.len = newLen

proc nimAsgnStrV2(a: var NimStringV2, b: NimStringV2) {.compilerRtl.} =
  if a.p == b.p and a.len == b.len: return
  if isLiteral(b):
    # we can shallow copy literals:
    frees(a)
    a.len = b.len
    a.p = b.p
  else:
    if isLiteral(a) or (a.p.cap and not strlitFlag) < b.len:
      # we have to allocate the 'cap' here, consider
      # 'let y = newStringOfCap(); var x = y'
      # on the other hand... These get turned into moves now.
      frees(a)
      a.p = allocPayload(b.len)
      a.p.cap = b.len
    a.len = b.len
    copyMem(unsafeAddr a.p.data[0], unsafeAddr b.p.data[0], b.len+1)

proc nimPrepareStrMutationImpl(s: var NimStringV2) =
  let oldP = s.p
  # can't mutate a literal, so we need a fresh copy here:
  s.p = allocPayload(s.len)
  s.p.cap = s.len
  copyMem(unsafeAddr s.p.data[0], unsafeAddr oldP.data[0], s.len+1)

proc nimPrepareStrMutationV2(s: var NimStringV2) {.compilerRtl, inl.} =
  if s.p != nil and (s.p.cap and strlitFlag) == strlitFlag:
    nimPrepareStrMutationImpl(s)

proc prepareMutation*(s: var string) {.inline.} =
  # string literals are "copy on write", so you need to call
  # `prepareMutation` before modifying the strings via `addr`.
  {.cast(noSideEffect).}:
    let s = unsafeAddr s
    nimPrepareStrMutationV2(cast[ptr NimStringV2](s)[])

proc nimAddStrV1(s: var NimStringV2; src: NimStringV2) {.compilerRtl, inl.} =
  #if (s.p == nil) or (s.len+1 > s.p.cap and not strlitFlag):
  prepareAdd(s, src.len)
  appendString s, src

proc nimDestroyStrV1(s: NimStringV2) {.compilerRtl, inl.} =
  frees(s)

proc nimStrAtLe(s: string; idx: int; ch: char): bool {.compilerRtl, inl.} =
  result = idx < s.len and s[idx] <= ch

func capacity*(self: string): int {.inline.} =
  ## Returns the current capacity of the string.
  # See https://github.com/nim-lang/RFCs/issues/460
  runnableExamples:
    var str = newStringOfCap(cap = 42)
    str.add "Nim"
    assert str.capacity == 42

  let str = cast[ptr NimStringV2](unsafeAddr self)
  result = if str.p != nil: str.p.cap and not strlitFlag else: 0
