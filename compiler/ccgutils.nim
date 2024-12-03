#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This module declares some helpers for the C code generator.

import
  ast, types, msgs, wordrecg,
  platform, trees, options, cgendata, mangleutils

import std/[hashes, strutils, formatfloat]

when defined(nimPreviewSlimSystem):
  import std/assertions

proc getPragmaStmt*(n: PNode, w: TSpecialWord): PNode =
  case n.kind
  of nkStmtList:
    result = nil
    for i in 0..<n.len:
      result = getPragmaStmt(n[i], w)
      if result != nil: break
  of nkPragma:
    result = nil
    for i in 0..<n.len:
      if whichPragma(n[i]) == w: return n[i]
  else:
    result = nil

proc stmtsContainPragma*(n: PNode, w: TSpecialWord): bool =
  result = getPragmaStmt(n, w) != nil

proc hashString*(conf: ConfigRef; s: string): BiggestInt =
  # has to be the same algorithm as strmantle.hashString!
  if CPU[conf.target.targetCPU].bit == 64:
    # we have to use the same bitwidth
    # as the target CPU
    var b = 0'u64
    for i in 0..<s.len:
      b = b + uint(s[i])
      b = b + (b shl 10)
      b = b xor (b shr 6)
    b = b + (b shl 3)
    b = b xor (b shr 11)
    b = b + (b shl 15)
    result = cast[Hash](b)
  else:
    var a = 0'u32
    for i in 0..<s.len:
      a = a + uint32(s[i])
      a = a + (a shl 10)
      a = a xor (a shr 6)
    a = a + (a shl 3)
    a = a xor (a shr 11)
    a = a + (a shl 15)
    result = cast[Hash](uint(a))

template getUniqueType*(key: PType): PType = key

proc makeSingleLineCString*(s: string): string =
  result = "\""
  for c in items(s):
    c.toCChar(result)
  result.add('\"')

proc mapSetType(conf: ConfigRef; typ: PType): TCTypeKind =
  case int(getSize(conf, typ))
  of 1: result = ctInt8
  of 2: result = ctInt16
  of 4: result = ctInt32
  of 8: result = ctInt64
  else: result = ctArray

proc ccgIntroducedPtr*(conf: ConfigRef; s: PSym, retType: PType): bool =
  var pt = skipTypes(s.typ, typedescInst)
  assert skResult != s.kind

  #note precedence: params override types
  if optByRef in s.options: return true
  elif sfByCopy in s.flags: return false
  elif tfByRef in pt.flags: return true
  elif tfByCopy in pt.flags: return false
  case pt.kind
  of tyObject:
    if s.typ.sym != nil and sfForward in s.typ.sym.flags:
      # forwarded objects are *always* passed by pointers for consistency!
      result = true
    elif s.typ.kind == tySink and conf.selectedGC notin {gcArc, gcAtomicArc, gcOrc, gcHooks}:
      # bug #23354:
      result = false
    elif (optByRef in s.options) or (getSize(conf, pt) > conf.target.floatSize * 3):
      result = true           # requested anyway
    elif (tfFinal in pt.flags) and (pt[0] == nil):
      result = false          # no need, because no subtyping possible
    else:
      result = true           # ordinary objects are always passed by reference,
                              # otherwise casting doesn't work
  of tyTuple:
    result = (getSize(conf, pt) > conf.target.floatSize*3) or (optByRef in s.options)
  else:
    result = false
  # first parameter and return type is 'lent T'? --> use pass by pointer
  if s.position == 0 and retType != nil and retType.kind == tyLent:
    result = not (pt.kind in {tyVar, tyArray, tyOpenArray, tyVarargs, tyRef, tyPtr, tyPointer} or
      pt.kind == tySet and mapSetType(conf, pt) == ctArray)

proc encodeName*(name: string): string =
  result = mangle(name)
  result = $result.len & result

proc makeUnique(m: BModule; s: PSym, name: string = ""): string =
  result = if name == "": s.name.s else: name
  result.add "__"
  result.add m.g.graph.ifaces[s.itemId.module].uniqueName
  result.add "_u"
  result.add $s.itemId.item

proc encodeSym*(m: BModule; s: PSym; makeUnique: bool = false): string =
  #Module::Type
  var name = s.name.s
  if makeUnique:
    name = makeUnique(m, s, name)
  "N" & encodeName(s.skipGenericOwner.name.s) & encodeName(name) & "E"

proc encodeType*(m: BModule; t: PType): string =
  result = ""
  var kindName = ($t.kind)[2..^1]
  kindName[0] = toLower($kindName[0])[0]
  case t.kind
  of tyObject, tyEnum, tyDistinct, tyUserTypeClass, tyGenericParam:
    result = encodeSym(m, t.sym)
  of tyGenericInst, tyUserTypeClassInst, tyGenericBody:
    result = encodeName(t[0].sym.name.s)
    result.add "I"
    for i in 1..<t.len - 1:
      result.add encodeType(m, t[i])
    result.add "E"
  of tySequence, tyOpenArray, tyArray, tyVarargs, tyTuple, tyProc, tySet, tyTypeDesc,
    tyPtr, tyRef, tyVar, tyLent, tySink, tyStatic, tyUncheckedArray, tyOr, tyAnd, tyBuiltInTypeClass:
    result =
      case t.kind:
      of tySequence: encodeName("seq")
      else: encodeName(kindName)
    result.add "I"
    for i in 0..<t.len:
      let s = t[i]
      if s.isNil: continue
      result.add encodeType(m, s)
    result.add "E"
  of tyRange:
    var val = "range_"
    if t.n[0].typ.kind in {tyFloat..tyFloat128}:
      val.addFloat t.n[0].floatVal
      val.add "_"
      val.addFloat t.n[1].floatVal
    else:
      val.add $t.n[0].intVal & "_" & $t.n[1].intVal
    result = encodeName(val)
  of tyString..tyUInt64, tyPointer, tyBool, tyChar, tyVoid, tyAnything, tyNil, tyEmpty:
    result = encodeName(kindName)
  of tyAlias, tyInferred, tyOwned:
    result = encodeType(m, t.elementType)
  else:
    assert false, "encodeType " & $t.kind

