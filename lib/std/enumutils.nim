#
#
#            Nim's Runtime Library
#        (c) Copyright 2020 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import std/macros
from std/typetraits import OrdinalEnum, HoleyEnum

when defined(nimPreviewSlimSystem):
  import std/assertions


# xxx `genEnumCaseStmt` needs tests and runnableExamples

macro genEnumCaseStmt*(typ: typedesc, argSym: typed, default: typed,
            userMin, userMax: static[int], normalizer: static[proc(s :string): string]): untyped =
  # Generates a case stmt, which assigns the correct enum field given
  # a normalized string comparison to the `argSym` input.
  # string normalization is done using passed normalizer.
  let typ = typ.getTypeInst[1]
  let typSym = typ.getTypeImpl.getTypeInst # skip aliases etc to get type sym
  let impl = typSym.getImpl[2]
  expectKind impl, nnkEnumTy
  let normalizerNode = quote: `normalizer`
  expectKind normalizerNode, nnkSym
  result = nnkCaseStmt.newTree(newCall(normalizerNode, argSym))
  # stores all processed field strings to give error msg for ambiguous enums
  var foundFields: seq[string] = @[]
  var fVal = ""
  var fStr = "" # string of current field
  var fNum = BiggestInt(0) # int value of current field
  for f in impl:
    case f.kind
    of nnkEmpty: continue # skip first node of `enumTy`
    of nnkSym, nnkIdent:
      fVal = f.strVal
      fStr = fVal
    of nnkAccQuoted:
      fVal = ""
      for ch in f:
        fVal.add ch.strVal
      fStr = fVal
    of nnkEnumFieldDef:
      fVal = f[0].strVal
      case f[1].kind
      of nnkStrLit:
        fStr = f[1].strVal
      of nnkTupleConstr:
        fStr = f[1][1].strVal
        fNum = f[1][0].intVal
      of nnkIntLit:
        fStr = f[0].strVal
        fNum = f[1].intVal
      else:
        let fAst = f[0].getImpl
        if fAst.kind == nnkStrLit:
          fStr = fAst.strVal
        else:
          error("Invalid tuple syntax!", f[1])
    else: error("Invalid node for enum type `" & $f.kind & "`!", f)
    # add field if string not already added
    if fNum >= userMin and fNum <= userMax:
      fStr = normalizer(fStr)
      if fStr notin foundFields:
        result.add nnkOfBranch.newTree(newLit fStr, newDotExpr(typ, ident fVal))
        foundFields.add fStr
      else:
        error("Ambiguous enums cannot be parsed, field " & $fStr &
          " appears multiple times!", f)
    inc fNum
  # finally add else branch to raise or use default
  if default == nil:
    let raiseStmt = quote do:
      raise newException(ValueError, "Invalid enum value: " & $`argSym`)
    result.add nnkElse.newTree(raiseStmt)
  else:
    expectKind(default, nnkSym)
    result.add nnkElse.newTree(default)

macro enumFullRange(a: typed): untyped =
  newNimNode(nnkBracket).add(a.getType[1][1..^1])

macro enumNames(a: typed): untyped =
  # this could be exported too; in particular this could be useful for enum with holes.
  result = newNimNode(nnkBracket)
  for ai in a.getType[1][1..^1]:
    assert ai.kind == nnkSym
    result.add newLit ai.strVal

iterator items*[T: HoleyEnum](E: typedesc[T]): T =
  ## Iterates over an enum with holes.
  runnableExamples:
    type
      A = enum
        a0 = 2
        a1 = 4
        a2
      B[T] = enum
        b0 = 2
        b1 = 4
    from std/sequtils import toSeq
    assert A.toSeq == [a0, a1, a2]
    assert B[float].toSeq == [B[float].b0, B[float].b1]
  for a in enumFullRange(E): yield a

func span(T: typedesc[HoleyEnum]): int =
  (T.high.ord - T.low.ord) + 1

const invalidSlot = uint8.high

proc genLookup[T: typedesc[HoleyEnum]](_: T): auto =
  const n = span(T)
  var i = 0
  assert n <= invalidSlot.int
  var ret {.noinit.}: array[n, uint8]
  for ai in mitems(ret): ai = invalidSlot
  for ai in items(T):
    ret[ai.ord - T.low.ord] = uint8(i)
    inc(i)
  return ret

func symbolRankImpl[T](a: T): int {.inline.} =
  const n = T.span
  const thres = 255 # must be <= `invalidSlot`, but this should be tuned.
  when n <= thres:
    const lookup = genLookup(T)
    let lookup2 {.global.} = lookup # xxx improve pending https://github.com/timotheecour/Nim/issues/553
    #[
    This could be optimized using a hash adapted to `T` (possible since it's known at CT)
    to get better key distribution before indexing into the lookup table table.
    ]#
    {.noSideEffect.}: # because it's immutable
      let ret = lookup2[ord(a) - T.low.ord]
    if ret != invalidSlot: return ret.int
  else:
    var i = 0
    # we could also generate a case statement as optimization
    for ai in items(T):
      if ai == a: return i
      inc(i)
  raise newException(IndexDefect, $ord(a) & " invalid for " & $T)

template symbolRank*[T: enum](a: T): int =
  ## Returns the index in which `a` is listed in `T`.
  ##
  ## The cost for a `HoleyEnum` is implementation defined, currently optimized
  ## for small enums, otherwise is `O(T.enumLen)`.
  runnableExamples:
    type
      A = enum # HoleyEnum
        a0 = -3
        a1 = 10
        a2
        a3 = (20, "f3Alt")
      B = enum # OrdinalEnum
        b0
        b1
        b2
      C = enum # OrdinalEnum
        c0 = 10
        c1
        c2
    assert a2.symbolRank == 2
    assert b2.symbolRank == 2
    assert c2.symbolRank == 2
    assert c2.ord == 12
    assert a2.ord == 11
    var invalid = 7.A
    doAssertRaises(IndexDefect): discard invalid.symbolRank
  when T is Ordinal: ord(a) - T.low.ord.static
  else: symbolRankImpl(a)

proc rangeBase(T: typedesc): typedesc {.magic: "TypeTrait".}
  # skip one level of range; return the base type of a range type

func symbolName*[T: enum](a: T): string =
  ## Returns the symbol name of an enum.
  ##
  ## This uses `symbolRank`.
  runnableExamples:
    type B = enum
      b0 = (10, "kb0")
      b1 = "kb1"
      b2
    let b = B.low
    assert b.symbolName == "b0"
    assert $b == "kb0"
    static: assert B.high.symbolName == "b2"
    type C = enum # HoleyEnum
      c0 = -3
      c1 = 4
      c2 = 20
    assert c1.symbolName == "c1"
  when T is range:
    const names = enumNames(rangeBase T)
  else:
    const names = enumNames(T)
  names[a.symbolRank]
