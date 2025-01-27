#
#
#           The Nim Compiler
#        (c) Copyright 2020 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Low level binary format used by the compiler to store and load various AST
## and related data.
##
## NB: this is incredibly low level and if you're interested in how the
##     compiler works and less a storage format, you're probably looking for
##     the `ic` or `packed_ast` modules to understand the logical format.

from std/typetraits import supportsCopyMem

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]

import std / tables

## Overview
## ========
## `RodFile` represents a Rod File (versioned binary format), and the
## associated data for common interactions such as IO and error tracking
## (`RodFileError`). The file format broken up into sections (`RodSection`)
## and preceded by a header (see: `cookie`). The precise layout, section
## ordering and data following the section are determined by the user. See
## `ic.loadRodFile`.
##
## A basic but "wrong" example of the lifecycle:
## ---------------------------------------------
## 1. `create` or `open`        - create a new one or open an existing
## 2. `storeHeader`             - header info
## 3. `storePrim` or `storeSeq` - save your stuff
## 4. `close`                   - and we're done
##
## Now read the bits below to understand what's missing.
##
## ### Issues with the Example
## Missing Sections:
## This is a low level API, so headers and sections need to be stored and
## loaded by the user, see `storeHeader` & `loadHeader` and `storeSection` &
## `loadSection`, respectively.
##
## No Error Handling:
## The API is centered around IO and prone to error, each operation checks or
## sets the `RodFile.err` field. A user of this API needs to handle these
## appropriately.
##
## API Notes
## =========
##
## Valid inputs for Rod files
## --------------------------
## ASTs, hopes, dreams, and anything as long as it and any children it may have
## support `copyMem`. This means anything that is not a pointer and that does not contain a pointer. At a glance these are:
## * string
## * objects & tuples (fields are recursed)
## * sequences AKA `seq[T]`
##
## Note on error handling style
## ----------------------------
## A flag based approach is used where operations no-op in case of a
## preexisting error and set the flag if they encounter one.
##
## Misc
## ----
## * 'Prim' is short for 'primitive', as in a non-sequence type

type
  RodSection* = enum
    versionSection
    configSection
    stringsSection
    checkSumsSection
    depsSection
    numbersSection
    exportsSection
    hiddenSection
    reexportsSection
    compilerProcsSection
    trmacrosSection
    convertersSection
    methodsSection
    pureEnumsSection
    toReplaySection
    topLevelSection
    bodiesSection
    symsSection
    typesSection
    typeInstCacheSection
    procInstCacheSection
    attachedOpsSection
    methodsPerGenericTypeSection
    enumToStringProcsSection
    methodsPerTypeSection
    dispatchersSection
    typeInfoSection  # required by the backend
    backendFlagsSection
    aliveSymsSection # beware, this is stored in a `.alivesyms` file.
    sideChannelSection
    namespaceSection
    symnamesSection

  RodFileError* = enum
    ok, tooBig, cannotOpen, ioFailure, wrongHeader, wrongSection, configMismatch,
    includeFileChanged

  RodFile* = object
    f*: File
    currentSection*: RodSection # for error checking
    err*: RodFileError # little experiment to see if this works
                       # better than exceptions.

const
  RodVersion = 2
  defaultCookie = [byte(0), byte('R'), byte('O'), byte('D'),
            byte(sizeof(int)*8), byte(system.cpuEndian), byte(0), byte(RodVersion)]

proc setError(f: var RodFile; err: RodFileError) {.inline.} =
  f.err = err
  #raise newException(IOError, "IO error")

proc storePrim*(f: var RodFile; s: string) =
  ## Stores a string.
  ## The len is prefixed to allow for later retreival.
  if f.err != ok: return
  if s.len >= high(int32):
    setError f, tooBig
    return
  var lenPrefix = int32(s.len)
  if writeBuffer(f.f, addr lenPrefix, sizeof(lenPrefix)) != sizeof(lenPrefix):
    setError f, ioFailure
  else:
    if s.len != 0:
      if writeBuffer(f.f, unsafeAddr(s[0]), s.len) != s.len:
        setError f, ioFailure

proc storePrim*[T](f: var RodFile; x: T) =
  ## Stores a non-sequence/string `T`.
  ## If `T` doesn't support `copyMem` and is an object or tuple then the fields
  ## are written -- the user from context will need to know which `T` to load.
  if f.err != ok: return
  when supportsCopyMem(T):
    if writeBuffer(f.f, unsafeAddr(x), sizeof(x)) != sizeof(x):
      setError f, ioFailure
  elif T is tuple:
    for y in fields(x):
      storePrim(f, y)
  elif T is object:
    for y in fields(x):
      when y is seq:
        storeSeq(f, y)
      else:
        storePrim(f, y)
  else:
    {.error: "unsupported type for 'storePrim'".}

proc storeSeq*[T](f: var RodFile; s: seq[T]) =
  ## Stores a sequence of `T`s, with the len as a prefix for later retrieval.
  if f.err != ok: return
  if s.len >= high(int32):
    setError f, tooBig
    return
  var lenPrefix = int32(s.len)
  if writeBuffer(f.f, addr lenPrefix, sizeof(lenPrefix)) != sizeof(lenPrefix):
    setError f, ioFailure
  else:
    for i in 0..<s.len:
      storePrim(f, s[i])

proc storeOrderedTable*[K, T](f: var RodFile; s: OrderedTable[K, T]) =
  if f.err != ok: return
  if s.len >= high(int32):
    setError f, tooBig
    return
  var lenPrefix = int32(s.len)
  if writeBuffer(f.f, addr lenPrefix, sizeof(lenPrefix)) != sizeof(lenPrefix):
    setError f, ioFailure
  else:
    for _, v in s:
      storePrim(f, v)

proc loadPrim*(f: var RodFile; s: var string) =
  ## Read a string, the length was stored as a prefix
  if f.err != ok: return
  var lenPrefix = int32(0)
  if readBuffer(f.f, addr lenPrefix, sizeof(lenPrefix)) != sizeof(lenPrefix):
    setError f, ioFailure
  else:
    s = newString(lenPrefix)
    if lenPrefix > 0:
      if readBuffer(f.f, unsafeAddr(s[0]), s.len) != s.len:
        setError f, ioFailure

proc loadPrim*[T](f: var RodFile; x: var T) =
  ## Load a non-sequence/string `T`.
  if f.err != ok: return
  when supportsCopyMem(T):
    if readBuffer(f.f, unsafeAddr(x), sizeof(x)) != sizeof(x):
      setError f, ioFailure
  elif T is tuple:
    for y in fields(x):
      loadPrim(f, y)
  elif T is object:
    for y in fields(x):
      when y is seq:
        loadSeq(f, y)
      else:
        loadPrim(f, y)
  else:
    {.error: "unsupported type for 'loadPrim'".}

proc loadSeq*[T](f: var RodFile; s: var seq[T]) =
  ## `T` must be compatible with `copyMem`, see `loadPrim`
  if f.err != ok: return
  var lenPrefix = int32(0)
  if readBuffer(f.f, addr lenPrefix, sizeof(lenPrefix)) != sizeof(lenPrefix):
    setError f, ioFailure
  else:
    s = newSeq[T](lenPrefix)
    for i in 0..<lenPrefix:
      loadPrim(f, s[i])

proc loadOrderedTable*[K, T](f: var RodFile; s: var OrderedTable[K, T]) =
  ## `T` must be compatible with `copyMem`, see `loadPrim`
  if f.err != ok: return
  var lenPrefix = int32(0)
  if readBuffer(f.f, addr lenPrefix, sizeof(lenPrefix)) != sizeof(lenPrefix):
    setError f, ioFailure
  else:
    s = initOrderedTable[K, T](lenPrefix)
    for i in 0..<lenPrefix:
      var x = default T
      loadPrim(f, x)
      s[x.id] = x

proc storeHeader*(f: var RodFile; cookie = defaultCookie) =
  ## stores the header which is described by `cookie`.
  if f.err != ok: return
  if f.f.writeBytes(cookie, 0, cookie.len) != cookie.len:
    setError f, ioFailure

proc loadHeader*(f: var RodFile; cookie = defaultCookie) =
  ## Loads the header which is described by `cookie`.
  if f.err != ok: return
  var thisCookie: array[cookie.len, byte] = default(array[cookie.len, byte])
  if f.f.readBytes(thisCookie, 0, thisCookie.len) != thisCookie.len:
    setError f, ioFailure
  elif thisCookie != cookie:
    setError f, wrongHeader

proc storeSection*(f: var RodFile; s: RodSection) =
  ## update `currentSection` and writes the bytes value of s.
  if f.err != ok: return
  assert f.currentSection < s
  f.currentSection = s
  storePrim(f, s)

proc loadSection*(f: var RodFile; expected: RodSection) =
  ## read the bytes value of s, sets and error if the section is incorrect.
  if f.err != ok: return
  var s: RodSection = default(RodSection)
  loadPrim(f, s)
  if expected != s and f.err == ok:
    setError f, wrongSection

proc create*(filename: string): RodFile =
  ## create the file and open it for writing
  result = default(RodFile)
  if not open(result.f, filename, fmWrite):
    setError result, cannotOpen

proc close*(f: var RodFile) = close(f.f)

proc open*(filename: string): RodFile =
  ## open the file for reading
  result = default(RodFile)
  if not open(result.f, filename, fmRead):
    setError result, cannotOpen
