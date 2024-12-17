#
#
#            Nim's Runtime Library
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# Implementation of some runtime checks.
include system/indexerrors
when defined(nimPreviewSlimSystem):
  import std/formatfloat

proc raiseRangeError(val: BiggestInt) {.compilerproc, noinline.} =
  when hostOS == "standalone":
    sysFatal(RangeDefect, "value out of range")
  else:
    sysFatal(RangeDefect, "value out of range: ", $val)

proc raiseIndexError4(l1, h1, h2: int) {.compilerproc, noinline.} =
  sysFatal(IndexDefect, "index out of bounds: " & $l1 & ".." & $h1 & " notin 0.." & $(h2 - 1))

proc raiseIndexError3(i, a, b: int) {.compilerproc, noinline.} =
  sysFatal(IndexDefect, formatErrorIndexBound(i, a, b))

proc raiseIndexError2(i, n: int) {.compilerproc, noinline.} =
  sysFatal(IndexDefect, formatErrorIndexBound(i, n))

proc raiseIndexError() {.compilerproc, noinline.} =
  sysFatal(IndexDefect, "index out of bounds")

proc raiseFieldError(f: string) {.compilerproc, noinline.} =
  ## remove after bootstrap > 1.5.1
  sysFatal(FieldDefect, f)

when defined(nimV2):
  proc raiseFieldError2(f: string, discVal: int) {.compilerproc, noinline.} =
    ## raised when field is inaccessible given runtime value of discriminant
    sysFatal(FieldDefect, f & $discVal & "'")

  proc raiseFieldErrorStr(f: string, discVal: string) {.compilerproc, noinline.} =
    ## raised when field is inaccessible given runtime value of discriminant
    sysFatal(FieldDefect, formatFieldDefect(f, discVal))
else:
  proc raiseFieldError2(f: string, discVal: string) {.compilerproc, noinline.} =
    ## raised when field is inaccessible given runtime value of discriminant
    sysFatal(FieldDefect, formatFieldDefect(f, discVal))

proc raiseRangeErrorI(i, a, b: BiggestInt) {.compilerproc, noinline.} =
  when defined(standalone):
    sysFatal(RangeDefect, "value out of range")
  else:
    sysFatal(RangeDefect, "value out of range: " & $i & " notin " & $a & " .. " & $b)

proc raiseRangeErrorF(i, a, b: float) {.compilerproc, noinline.} =
  when defined(standalone):
    sysFatal(RangeDefect, "value out of range")
  else:
    sysFatal(RangeDefect, "value out of range: " & $i & " notin " & $a & " .. " & $b)

proc raiseRangeErrorU(i, a, b: uint64) {.compilerproc, noinline.} =
  # todo: better error reporting
  sysFatal(RangeDefect, "value out of range")

proc raiseRangeErrorNoArgs() {.compilerproc, noinline.} =
  sysFatal(RangeDefect, "value out of range")

proc raiseObjectConversionError() {.compilerproc, noinline.} =
  sysFatal(ObjectConversionDefect, "invalid object conversion")

proc chckIndx(i, a, b: int): int =
  if i >= a and i <= b:
    return i
  else:
    result = 0
    raiseIndexError3(i, a, b)

proc chckRange(i, a, b: int): int =
  if i >= a and i <= b:
    return i
  else:
    result = 0
    raiseRangeError(i)

proc chckRange64(i, a, b: int64): int64 {.compilerproc.} =
  if i >= a and i <= b:
    return i
  else:
    result = 0
    raiseRangeError(i)

proc chckRangeU(i, a, b: uint64): uint64 {.compilerproc.} =
  if i >= a and i <= b:
    return i
  else:
    result = 0
    sysFatal(RangeDefect, "value out of range")

proc chckRangeF(x, a, b: float): float =
  if x >= a and x <= b:
    return x
  else:
    result = 0.0
    when hostOS == "standalone":
      sysFatal(RangeDefect, "value out of range")
    else:
      sysFatal(RangeDefect, "value out of range: ", $x)

proc chckNil(p: pointer) =
  if p == nil:
    sysFatal(NilAccessDefect, "attempt to write to a nil address")

proc chckNilDisp(p: pointer) {.compilerproc.} =
  if p == nil:
    sysFatal(NilAccessDefect, "cannot dispatch; dispatcher is nil")

when not defined(nimV2):

  proc chckObj(obj, subclass: PNimType) {.compilerproc.} =
    # checks if obj is of type subclass:
    var x = obj
    if x == subclass: return # optimized fast path
    while x != subclass:
      if x == nil:
        sysFatal(ObjectConversionDefect, "invalid object conversion")
      x = x.base

  proc chckObjAsgn(a, b: PNimType) {.compilerproc, inline.} =
    if a != b:
      sysFatal(ObjectAssignmentDefect, "invalid object assignment")

  type ObjCheckCache = array[0..1, PNimType]

  proc isObjSlowPath(obj, subclass: PNimType;
                    cache: var ObjCheckCache): bool {.noinline.} =
    # checks if obj is of type subclass:
    var x = obj.base
    while x != subclass:
      if x == nil:
        cache[0] = obj
        return false
      x = x.base
    cache[1] = obj
    return true

  proc isObjWithCache(obj, subclass: PNimType;
                      cache: var ObjCheckCache): bool {.compilerproc, inline.} =
    if obj == subclass: return true
    if obj.base == subclass: return true
    if cache[0] == obj: return false
    if cache[1] == obj: return true
    return isObjSlowPath(obj, subclass, cache)

  proc isObj(obj, subclass: PNimType): bool {.compilerproc.} =
    # checks if obj is of type subclass:
    var x = obj
    if x == subclass: return true # optimized fast path
    while x != subclass:
      if x == nil: return false
      x = x.base
    return true

when defined(nimV2):
  proc raiseObjectCaseTransition() {.compilerproc.} =
    sysFatal(FieldDefect, "assignment to discriminant changes object branch")
