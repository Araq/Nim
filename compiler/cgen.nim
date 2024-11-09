#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements the C code generator.

import
  ast, astalgo, trees, platform, magicsys, extccomp, options,
  nversion, nimsets, msgs, bitsets, idents, types,
  ccgutils, ropes, wordrecg, treetab, cgmeth,
  rodutils, renderer, cgendata, aliases,
  lowerings, lineinfos, pathutils, transf,
  injectdestructors, astmsgs, modulepaths, pushpoppragmas,
  mangleutils, cbuilderbase

from expanddefaults import caseObjDefaultBranch

import pipelineutils

when defined(nimPreviewSlimSystem):
  import std/assertions

when not defined(leanCompiler):
  import spawn, semparallel

import std/strutils except `%`, addf # collides with ropes.`%`

from ic / ic import ModuleBackendFlag
import std/[dynlib, math, tables, sets, os, intsets, hashes]

const
  # we use some ASCII control characters to insert directives that will be converted to real code in a postprocessing pass
  postprocessDirStart = '\1'
  postprocessDirSep = '\31'
  postprocessDirEnd = '\23'

when not declared(dynlib.libCandidates):
  proc libCandidates(s: string, dest: var seq[string]) =
    ## given a library name pattern `s` write possible library names to `dest`.
    var le = strutils.find(s, '(')
    var ri = strutils.find(s, ')', le+1)
    if le >= 0 and ri > le:
      var prefix = substr(s, 0, le - 1)
      var suffix = substr(s, ri + 1)
      for middle in split(substr(s, le + 1, ri - 1), '|'):
        libCandidates(prefix & middle & suffix, dest)
    else:
      dest.add(s)

when options.hasTinyCBackend:
  import tccgen

proc hcrOn(m: BModule): bool = m.config.hcrOn
proc hcrOn(p: BProc): bool = p.module.config.hcrOn

proc addForwardedProc(m: BModule, prc: PSym) =
  m.g.forwardedProcs.add(prc)

proc findPendingModule(m: BModule, s: PSym): BModule =
  # TODO fixme
  if m.config.symbolFiles == v2Sf:
    let ms = s.itemId.module  #getModule(s)
    result = m.g.modules[ms]
  else:
    var ms = getModule(s)
    result = m.g.modules[ms.position]

proc initLoc(k: TLocKind, lode: PNode, s: TStorageLoc, flags: TLocFlags = {}): TLoc =
  result = TLoc(k: k, storage: s, lode: lode,
                snippet: "", flags: flags)

proc fillLoc(a: var TLoc, k: TLocKind, lode: PNode, r: Rope, s: TStorageLoc) {.inline.} =
  # fills the loc if it is not already initialized
  if a.k == locNone:
    a.k = k
    a.lode = lode
    a.storage = s
    if a.snippet == "": a.snippet = r

proc fillLoc(a: var TLoc, k: TLocKind, lode: PNode, s: TStorageLoc) {.inline.} =
  # fills the loc if it is not already initialized
  if a.k == locNone:
    a.k = k
    a.lode = lode
    a.storage = s

proc t(a: TLoc): PType {.inline.} =
  if a.lode.kind == nkSym:
    result = a.lode.sym.typ
  else:
    result = a.lode.typ

proc lodeTyp(t: PType): PNode =
  result = newNode(nkEmpty)
  result.typ() = t

proc isSimpleConst(typ: PType): bool =
  let t = skipTypes(typ, abstractVar)
  result = t.kind notin
      {tyTuple, tyObject, tyArray, tySet, tySequence} and not
      (t.kind == tyProc and t.callConv == ccClosure)

proc useHeader(m: BModule, sym: PSym) =
  if lfHeader in sym.loc.flags:
    assert(sym.annex != nil)
    let str = getStr(sym.annex.path)
    m.includeHeader(str)

proc cgsym(m: BModule, name: string)
proc cgsymValue(m: BModule, name: string): Rope

proc getCFile(m: BModule): AbsoluteFile

proc getModuleDllPath(m: BModule): Rope =
  let (dir, name, ext) = splitFile(getCFile(m))
  let filename = strutils.`%`(platform.OS[m.g.config.target.targetOS].dllFrmt, [name & ext])
  result = makeCString(dir.string & "/" & filename)

proc getModuleDllPath(m: BModule, module: int): Rope =
  result = getModuleDllPath(m.g.modules[module])

proc getModuleDllPath(m: BModule, s: PSym): Rope =
  result = getModuleDllPath(m.g.modules[s.itemId.module])

import std/macros

proc cgFormatValue(result: var string; value: string) =
  result.add value

proc cgFormatValue(result: var string; value: BiggestInt) =
  result.addInt value

proc cgFormatValue(result: var string; value: Int128) =
  result.addInt128 value

template addf(result: var Builder, args: varargs[untyped]) =
  result.buf.addf(args)

# TODO: please document
macro ropecg(m: BModule, frmt: static[FormatStr], args: untyped): Rope =
  args.expectKind nnkBracket
  # echo "ropecg ", newLit(frmt).repr, ", ", args.repr
  var i = 0
  result = nnkStmtListExpr.newTree()

  result.add quote do:
    assert `m` != nil

  let resVar = genSym(nskVar, "res")
  # during `koch boot` the median of all generates strings from this
  # macro is around 40 bytes in length.
  result.add newVarStmt(resVar, newCall(bindSym"newStringOfCap", newLit(80)))
  let formatValue = bindSym"cgFormatValue"

  var num = 0
  var strLit = ""

  template flushStrLit() =
    if strLit != "":
      result.add newCall(ident "add", resVar, newLit(strLit))
      strLit.setLen 0

  while i < frmt.len:
    if frmt[i] == '$':
      inc(i)                  # skip '$'
      case frmt[i]
      of '$':
        strLit.add '$'
        inc(i)
      of '#':
        flushStrLit()
        inc(i)
        result.add newCall(formatValue, resVar, args[num])
        inc(num)
      of '^':
        flushStrLit()
        inc(i)
        result.add newCall(formatValue, resVar, args[^1])
        inc(num)
      of '0'..'9':
        var j = 0
        while true:
          j = (j * 10) + ord(frmt[i]) - ord('0')
          inc(i)
          if i >= frmt.len or not (frmt[i] in {'0'..'9'}): break
        num = j
        if j > args.len:
          error("ropes: invalid format string " & newLit(frmt).repr & " args.len: " & $args.len)

        flushStrLit()
        result.add newCall(formatValue, resVar, args[j-1])
      of 'n':
        flushStrLit()
        result.add quote do:
          if optLineDir notin `m`.config.options:
            `resVar`.add("\L")
        inc(i)
      of 'N':
        strLit.add "\L"
        inc(i)
      else:
        error("ropes: invalid format string $" & frmt[i])
    elif frmt[i] == '#' and frmt[i+1] in IdentStartChars:
      inc(i)
      var j = i
      while frmt[j] in IdentChars: inc(j)
      var ident = newLit(substr(frmt, i, j-1))
      i = j
      flushStrLit()
      result.add newCall(formatValue, resVar, newCall(ident"cgsymValue", m, ident))
    elif frmt[i] == '#' and frmt[i+1] == '$':
      inc(i, 2)
      var j = 0
      while frmt[i] in Digits:
        j = (j * 10) + ord(frmt[i]) - ord('0')
        inc(i)
      let ident = args[j-1]
      flushStrLit()
      result.add newCall(formatValue, resVar, newCall(ident"cgsymValue", m, ident))
    elif frmt[i] == '#' and frmt[i+1] == '#':
      inc(i, 2)
      strLit.add("#")
    else:
      strLit.add(frmt[i])
      inc(i)

  flushStrLit()
  result.add newCall(ident"rope", resVar)

proc addIndent(p: BProc; result: var Rope) =
  var i = result.len
  let newLen = i + p.blocks.len
  result.setLen newLen
  while i < newLen:
    result[i] = '\t'
    inc i

proc addIndent(p: BProc; result: var Builder) =
  var i = result.buf.len
  let newLen = i + p.blocks.len
  result.buf.setLen newLen
  while i < newLen:
    result.buf[i] = '\t'
    inc i

template appcg(m: BModule, c: var (Rope | Builder), frmt: FormatStr,
           args: untyped) =
  c.add(ropecg(m, frmt, args))

template appcg(m: BModule, sec: TCFileSection, frmt: FormatStr,
           args: untyped) =
  m.s[sec].add(ropecg(m, frmt, args))

template appcg(p: BProc, sec: TCProcSection, frmt: FormatStr,
           args: untyped) =
  p.s(sec).add(ropecg(p.module, frmt, args))

template line(p: BProc, sec: TCProcSection, r: string) =
  addIndent p, p.s(sec)
  p.s(sec).add(r)

template lineF(p: BProc, sec: TCProcSection, frmt: FormatStr,
              args: untyped) =
  addIndent p, p.s(sec)
  p.s(sec).add(frmt % args)

template lineCg(p: BProc, sec: TCProcSection, frmt: FormatStr,
               args: untyped) =
  addIndent p, p.s(sec)
  p.s(sec).add(ropecg(p.module, frmt, args))

template linefmt(p: BProc, sec: TCProcSection, frmt: FormatStr,
             args: untyped) =
  addIndent p, p.s(sec)
  p.s(sec).add(ropecg(p.module, frmt, args))

proc safeLineNm(info: TLineInfo): int =
  result = toLinenumber(info)
  if result < 0: result = 0 # negative numbers are not allowed in #line

proc genPostprocessDir(field1, field2, field3: string): string =
  result = postprocessDirStart & field1 & postprocessDirSep & field2 & postprocessDirSep & field3 & postprocessDirEnd

proc genCLineDir(r: var Builder, fileIdx: FileIndex, line: int; conf: ConfigRef) =
  assert line >= 0
  if optLineDir in conf.options and line > 0:
    if fileIdx == InvalidFileIdx:
      r.add(rope("\n#line " & $line & " \"generated_not_to_break_here\"\n"))
    else:
      r.add(rope("\n#line " & $line & " FX_" & $fileIdx.int32 & "\n"))

proc genCLineDir(r: var Builder, fileIdx: FileIndex, line: int; p: BProc; info: TLineInfo; lastFileIndex: FileIndex) =
  assert line >= 0
  if optLineDir in p.config.options and line > 0:
    if fileIdx == InvalidFileIdx:
      r.add(rope("\n#line " & $line & " \"generated_not_to_break_here\"\n"))
    else:
      r.add(rope("\n#line " & $line & " FX_" & $fileIdx.int32 & "\n"))

proc genCLineDir(r: var Builder, info: TLineInfo; conf: ConfigRef) =
  if optLineDir in conf.options:
    genCLineDir(r, info.fileIndex, info.safeLineNm, conf)

proc freshLineInfo(p: BProc; info: TLineInfo): bool =
  if p.lastLineInfo.line != info.line or
     p.lastLineInfo.fileIndex != info.fileIndex:
    p.lastLineInfo.line = info.line
    p.lastLineInfo.fileIndex = info.fileIndex
    result = true
  else:
    result = false

proc genCLineDir(r: var Builder, p: BProc, info: TLineInfo; conf: ConfigRef) =
  if optLineDir in conf.options:
    let lastFileIndex = p.lastLineInfo.fileIndex
    if freshLineInfo(p, info):
      genCLineDir(r, info.fileIndex, info.safeLineNm, p, info, lastFileIndex)

proc genLineDir(p: BProc, t: PNode) =
  if p == p.module.preInitProc: return
  let line = t.info.safeLineNm

  if optEmbedOrigSrc in p.config.globalOptions:
    p.s(cpsStmts).add("//" & sourceLine(p.config, t.info) & "\L")
  let lastFileIndex = p.lastLineInfo.fileIndex
  let freshLine = freshLineInfo(p, t.info)
  if freshLine:
    genCLineDir(p.s(cpsStmts), t.info.fileIndex, line, p, t.info, lastFileIndex)
  if ({optLineTrace, optStackTrace} * p.options == {optLineTrace, optStackTrace}) and
      (p.prc == nil or sfPure notin p.prc.flags) and t.info.fileIndex != InvalidFileIdx:
      if freshLine:
        line(p, cpsStmts, genPostprocessDir("nimln", $line, $t.info.fileIndex.int32))

proc accessThreadLocalVar(p: BProc, s: PSym)
proc emulatedThreadVars(conf: ConfigRef): bool {.inline.}
proc genProc(m: BModule, prc: PSym)
proc raiseInstr(p: BProc; result: var Builder)

template compileToCpp(m: BModule): untyped =
  m.config.backend == backendCpp or sfCompileToCpp in m.module.flags

proc getTempName(m: BModule): Rope =
  result = m.tmpBase & rope(m.labels)
  inc m.labels

proc isNoReturn(m: BModule; s: PSym): bool {.inline.} =
  sfNoReturn in s.flags and m.config.exc != excGoto

include cbuilderexprs
include cbuilderdecls
include cbuilderstmts

proc rdLoc(a: TLoc): Rope =
  # 'read' location (deref if indirect)
  if lfIndirect in a.flags:
    result = cDeref(a.snippet)
  else:
    result = a.snippet

proc addRdLoc(a: TLoc; result: var Builder) =
  if lfIndirect in a.flags:
    result.add cDeref(a.snippet)
  else:
    result.add a.snippet

proc lenField(p: BProc): Rope {.inline.} =
  result = rope(if p.module.compileToCpp: "len" else: "Sup.len")

proc lenField(p: BProc, val: Rope): Rope {.inline.} =
  if p.module.compileToCpp:
    result = derefField(val, "len")
  else:
    result = dotField(derefField(val, "Sup"), "len")

proc lenExpr(p: BProc; a: TLoc): Rope =
  if optSeqDestructors in p.config.globalOptions:
    result = dotField(rdLoc(a), "len")
  else:
    let ra = rdLoc(a)
    result = cIfExpr(ra, lenField(p, ra), cIntValue(0))

proc dataFieldAccessor(p: BProc, sym: Rope): Rope =
  if optSeqDestructors in p.config.globalOptions:
    result = dotField(wrapPar(sym), "p")
  else:
    result = sym

proc dataField(p: BProc): Rope =
  if optSeqDestructors in p.config.globalOptions:
    result = rope".p->data"
  else:
    result = rope"->data"

proc dataField(p: BProc, val: Rope): Rope {.inline.} =
  result = derefField(dataFieldAccessor(p, val), "data")

proc genProcPrototype(m: BModule, sym: PSym)

include ccgliterals
include ccgtypes

# ------------------------------ Manager of temporaries ------------------

template mapTypeChooser(n: PNode): TSymKind =
  (if n.kind == nkSym: n.sym.kind else: skVar)

template mapTypeChooser(a: TLoc): TSymKind = mapTypeChooser(a.lode)

proc addAddrLoc(conf: ConfigRef; a: TLoc; result: var Builder) =
  if lfIndirect notin a.flags and mapType(conf, a.t, mapTypeChooser(a) == skParam) != ctArray:
    result.add wrapPar(cAddr(a.snippet))
  else:
    result.add a.snippet

proc addrLoc(conf: ConfigRef; a: TLoc): Rope =
  if lfIndirect notin a.flags and mapType(conf, a.t, mapTypeChooser(a) == skParam) != ctArray:
    result = wrapPar(cAddr(a.snippet))
  else:
    result = a.snippet

proc byRefLoc(p: BProc; a: TLoc): Rope =
  if lfIndirect notin a.flags and mapType(p.config, a.t, mapTypeChooser(a) == skParam) != ctArray and not
      p.module.compileToCpp:
    result = wrapPar(cAddr(a.snippet))
  else:
    result = a.snippet

proc rdCharLoc(a: TLoc): Rope =
  # read a location that may need a char-cast:
  result = rdLoc(a)
  if skipTypes(a.t, abstractRange).kind == tyChar:
    result = cCast("NU8", result)

type
  TAssignmentFlag = enum
    needToCopy
    needToCopySinkParam
    needTempForOpenArray
    needAssignCall
  TAssignmentFlags = set[TAssignmentFlag]

proc genObjConstr(p: BProc, e: PNode, d: var TLoc)
proc rawConstExpr(p: BProc, n: PNode; d: var TLoc)
proc genAssignment(p: BProc, dest, src: TLoc, flags: TAssignmentFlags)

type
  ObjConstrMode = enum
    constructObj,
    constructRefObj

proc genObjectInit(p: BProc, section: TCProcSection, t: PType, a: var TLoc,
                   mode: ObjConstrMode) =
  #if optNimV2 in p.config.globalOptions: return
  case analyseObjectWithTypeField(t)
  of frNone:
    discard
  of frHeader:
    var r = rdLoc(a)
    if mode == constructRefObj: r = "(*$1)" % [r]
    var s = skipTypes(t, abstractInst)
    if not p.module.compileToCpp:
      while s.kind == tyObject and s[0] != nil:
        r.add(".Sup")
        s = skipTypes(s[0], skipPtrs)
    if optTinyRtti in p.config.globalOptions:
      linefmt(p, section, "$1.m_type = $2;$n", [r, genTypeInfoV2(p.module, t, a.lode.info)])
    else:
      linefmt(p, section, "$1.m_type = $2;$n", [r, genTypeInfoV1(p.module, t, a.lode.info)])
  of frEmbedded:
    if optTinyRtti in p.config.globalOptions:
      var tmp: TLoc = default(TLoc)
      if mode == constructRefObj:
        let objType = t.skipTypes(abstractInst+{tyRef})
        rawConstExpr(p, newNodeIT(nkType, a.lode.info, objType), tmp)
        linefmt(p, cpsStmts,
            "#nimCopyMem((void*)$1, (NIM_CONST void*)&$2, sizeof($3));$n",
            [rdLoc(a), rdLoc(tmp), getTypeDesc(p.module, objType, descKindFromSymKind mapTypeChooser(a))])
      else:
        rawConstExpr(p, newNodeIT(nkType, a.lode.info, t), tmp)
        genAssignment(p, a, tmp, {})
    else:
      # worst case for performance:
      var r = if mode == constructObj: addrLoc(p.config, a) else: rdLoc(a)
      linefmt(p, section, "#objectInit($1, $2);$n", [r, genTypeInfoV1(p.module, t, a.lode.info)])

  if isException(t):
    var r = rdLoc(a)
    if mode == constructRefObj: r = "(*$1)" % [r]
    var s = skipTypes(t, abstractInst)
    if not p.module.compileToCpp:
      while s.kind == tyObject and s[0] != nil and s.sym.magic != mException:
        r.add(".Sup")
        s = skipTypes(s[0], skipPtrs)
    linefmt(p, section, "$1.name = $2;$n", [r, makeCString(t.skipTypes(abstractInst).sym.name.s)])

proc genRefAssign(p: BProc, dest, src: TLoc)

proc isComplexValueType(t: PType): bool {.inline.} =
  let t = t.skipTypes(abstractInst + tyUserTypeClasses)
  result = t.kind in {tyArray, tySet, tyTuple, tyObject, tyOpenArray} or
    (t.kind == tyProc and t.callConv == ccClosure)

include ccgreset

proc resetLoc(p: BProc, loc: var TLoc) =
  let containsGcRef = optSeqDestructors notin p.config.globalOptions and containsGarbageCollectedRef(loc.t)
  let typ = skipTypes(loc.t, abstractVarRange)
  if isImportedCppType(typ): 
    var didGenTemp = false
    linefmt(p, cpsStmts, "$1 = $2;$n", [rdLoc(loc), genCppInitializer(p.module, p, typ, didGenTemp)])
    return
  if optSeqDestructors in p.config.globalOptions and typ.kind in {tyString, tySequence}:
    assert loc.snippet != ""

    let atyp = skipTypes(loc.t, abstractInst)
    if atyp.kind in {tyVar, tyLent}:
      linefmt(p, cpsStmts, "$1->len = 0; $1->p = NIM_NIL;$n", [rdLoc(loc)])
    else:
      linefmt(p, cpsStmts, "$1.len = 0; $1.p = NIM_NIL;$n", [rdLoc(loc)])
  elif not isComplexValueType(typ):
    if containsGcRef:
      var nilLoc: TLoc = initLoc(locTemp, loc.lode, OnStack)
      nilLoc.snippet = rope("NIM_NIL")
      genRefAssign(p, loc, nilLoc)
    else:
      linefmt(p, cpsStmts, "$1 = 0;$n", [rdLoc(loc)])
  else:
    if loc.storage != OnStack and containsGcRef:
      specializeReset(p, loc)
      when false:
        linefmt(p, cpsStmts, "#genericReset((void*)$1, $2);$n",
                [addrLoc(p.config, loc), genTypeInfoV1(p.module, loc.t, loc.lode.info)])
      # XXX: generated reset procs should not touch the m_type
      # field, so disabling this should be safe:
      genObjectInit(p, cpsStmts, loc.t, loc, constructObj)
    else:
      # array passed as argument decayed into pointer, bug #7332
      # so we use getTypeDesc here rather than rdLoc(loc)
      let tyDesc = getTypeDesc(p.module, loc.t, descKindFromSymKind mapTypeChooser(loc))
      if p.module.compileToCpp and isOrHasImportedCppType(typ):
        if lfIndirect in loc.flags:
          #C++ cant be just zeroed. We need to call the ctors
          var tmp = getTemp(p, loc.t)
          linefmt(p, cpsStmts,"#nimCopyMem((void*)$1, (NIM_CONST void*)$2, sizeof($3));$n",
                  [addrLoc(p.config, loc), addrLoc(p.config, tmp), tyDesc])
      else:
        linefmt(p, cpsStmts, "#nimZeroMem((void*)$1, sizeof($2));$n",
                [addrLoc(p.config, loc), tyDesc])

      # XXX: We can be extra clever here and call memset only
      # on the bytes following the m_type field?
      genObjectInit(p, cpsStmts, loc.t, loc, constructObj)

proc constructLoc(p: BProc, loc: var TLoc, isTemp = false) =
  let typ = loc.t
  if optSeqDestructors in p.config.globalOptions and skipTypes(typ, abstractInst + {tyStatic}).kind in {tyString, tySequence}:
    linefmt(p, cpsStmts, "$1.len = 0; $1.p = NIM_NIL;$n", [rdLoc(loc)])
  elif not isComplexValueType(typ):
    if containsGarbageCollectedRef(loc.t):
      var nilLoc: TLoc = initLoc(locTemp, loc.lode, OnStack)
      nilLoc.snippet = rope("NIM_NIL")
      genRefAssign(p, loc, nilLoc)
    else:
      linefmt(p, cpsStmts, "$1 = ($2)0;$n", [rdLoc(loc),
        getTypeDesc(p.module, typ, descKindFromSymKind mapTypeChooser(loc))])
  else:
    if (not isTemp or containsGarbageCollectedRef(loc.t)) and not hasNoInit(loc.t):
      # don't use nimZeroMem for temporary values for performance if we can
      # avoid it:
      if not isOrHasImportedCppType(typ):
        linefmt(p, cpsStmts, "#nimZeroMem((void*)$1, sizeof($2));$n",
                [addrLoc(p.config, loc), getTypeDesc(p.module, typ, descKindFromSymKind mapTypeChooser(loc))])
    genObjectInit(p, cpsStmts, loc.t, loc, constructObj)

proc initLocalVar(p: BProc, v: PSym, immediateAsgn: bool) =
  if sfNoInit notin v.flags:
    # we know it is a local variable and thus on the stack!
    # If ``not immediateAsgn`` it is not initialized in a binding like
    # ``var v = X`` and thus we need to init it.
    # If ``v`` contains a GC-ref we may pass it to ``unsureAsgnRef`` somehow
    # which requires initialization. However this can really only happen if
    # ``var v = X()`` gets transformed into ``X(&v)``.
    # Nowadays the logic in ccgcalls deals with this case however.
    if not immediateAsgn:
      constructLoc(p, v.loc)

proc getTemp(p: BProc, t: PType, needsInit=false): TLoc =
  inc(p.labels)
  result = TLoc(snippet: "T" & rope(p.labels) & "_", k: locTemp, lode: lodeTyp t,
                storage: OnStack, flags: {})
  if p.module.compileToCpp and isOrHasImportedCppType(t):
    var didGenTemp = false
    linefmt(p, cpsLocals, "$1 $2$3;$n", [getTypeDesc(p.module, t, dkVar), result.snippet,
      genCppInitializer(p.module, p, t, didGenTemp)])
  else:
    linefmt(p, cpsLocals, "$1 $2;$n", [getTypeDesc(p.module, t, dkVar), result.snippet])
  constructLoc(p, result, not needsInit)
  when false:
    # XXX Introduce a compiler switch in order to detect these easily.
    if getSize(p.config, t) > 1024 * 1024:
      if p.prc != nil:
        echo "ENORMOUS TEMPORARY! ", p.config $ p.prc.info
      else:
        echo "ENORMOUS TEMPORARY! ", p.config $ p.lastLineInfo
      writeStackTrace()

proc getTempCpp(p: BProc, t: PType, value: Rope): TLoc =
  inc(p.labels)
  result = TLoc(snippet: "T" & rope(p.labels) & "_", k: locTemp, lode: lodeTyp t,
                storage: OnStack, flags: {})
  linefmt(p, cpsStmts, "auto $1 = $2;$n", [result.snippet, value])

proc getIntTemp(p: BProc): TLoc =
  inc(p.labels)
  result = TLoc(snippet: "T" & rope(p.labels) & "_", k: locTemp,
                storage: OnStack, lode: lodeTyp getSysType(p.module.g.graph, unknownLineInfo, tyInt),
                flags: {})
  linefmt(p, cpsLocals, "NI $1;$n", [result.snippet])

proc localVarDecl(p: BProc; n: PNode): Rope =
  var res = newBuilder("")
  let s = n.sym
  if s.loc.k == locNone:
    fillLocalName(p, s)
    fillLoc(s.loc, locLocalVar, n, OnStack)
    if s.kind == skLet: incl(s.loc.flags, lfNoDeepCopy)
  if s.kind in {skLet, skVar, skField, skForVar} and s.alignment > 0:
    res.addf("NIM_ALIGN($1) ", [rope(s.alignment)])

  genCLineDir(res, p, n.info, p.config)

  res.add getTypeDesc(p.module, s.typ, dkVar)
  if sfCodegenDecl notin s.flags:
    if sfRegister in s.flags: res.add(" register")
    #elif skipTypes(s.typ, abstractInst).kind in GcTypeKinds:
    #  decl.add(" GC_GUARD")
    if sfVolatile in s.flags: res.add(" volatile")
    if sfNoalias in s.flags: res.add(" NIM_NOALIAS")
    res.add(" ")
    res.add(s.loc.snippet)
    result = extract(res)
  else:
    result = runtimeFormat(s.cgDeclFrmt, [extract(res), s.loc.snippet])

proc assignLocalVar(p: BProc, n: PNode) =
  #assert(s.loc.k == locNone) # not yet assigned
  # this need not be fulfilled for inline procs; they are regenerated
  # for each module that uses them!
  let nl = if optLineDir in p.config.options: "" else: "\n"
  var decl = localVarDecl(p, n)
  if p.module.compileToCpp and isOrHasImportedCppType(n.typ):
    var didGenTemp = false
    decl.add genCppInitializer(p.module, p, n.typ, didGenTemp)
  decl.add ";" & nl
  line(p, cpsLocals, decl)

include ccgthreadvars

proc varInDynamicLib(m: BModule, sym: PSym)

proc treatGlobalDifferentlyForHCR(m: BModule, s: PSym): bool =
  return m.hcrOn and {sfThread, sfGlobal} * s.flags == {sfGlobal} and
      ({lfNoDecl, lfHeader} * s.loc.flags == {})
      # and s.owner.kind == skModule # owner isn't always a module (global pragma on local var)
      # and s.loc.k == locGlobalVar  # loc isn't always initialized when this proc is used

proc genGlobalVarDecl(p: BProc, n: PNode; td, value: Rope; decl: var Rope) =
  let s = n.sym
  if sfCodegenDecl notin s.flags:
    if s.kind in {skLet, skVar, skField, skForVar} and s.alignment > 0:
      decl.addf "NIM_ALIGN($1) ", [rope(s.alignment)]
    if p.hcrOn: decl.add("static ")
    elif sfImportc in s.flags: decl.add("extern ")
    elif lfExportLib in s.loc.flags: decl.add("N_LIB_EXPORT_VAR ")
    else: decl.add("N_LIB_PRIVATE ")
    if s.kind == skLet and value != "": decl.add("NIM_CONST ")
    decl.add(td)
    if p.hcrOn: decl.add("*")
    if sfRegister in s.flags: decl.add(" register")
    if sfVolatile in s.flags: decl.add(" volatile")
    if sfNoalias in s.flags: decl.add(" NIM_NOALIAS")
  else:
    if value != "":
      decl = runtimeFormat(s.cgDeclFrmt & " = $#;$n", [td, s.loc.snippet, value])
    else:
      decl = runtimeFormat(s.cgDeclFrmt & ";$n", [td, s.loc.snippet])

proc genCppVarForCtor(p: BProc; call: PNode; decl: var Rope; didGenTemp: var bool)

proc assignGlobalVar(p: BProc, n: PNode; value: Rope) =
  let s = n.sym
  if s.loc.k == locNone:
    fillBackendName(p.module, s)
    fillLoc(s.loc, locGlobalVar, n, OnHeap)
    if treatGlobalDifferentlyForHCR(p.module, s): incl(s.loc.flags, lfIndirect)

  if lfDynamicLib in s.loc.flags:
    var q = findPendingModule(p.module, s)
    if q != nil and not containsOrIncl(q.declaredThings, s.id):
      varInDynamicLib(q, s)
    else:
      s.loc.snippet = mangleDynLibProc(s)
    if value != "":
      internalError(p.config, n.info, ".dynlib variables cannot have a value")
    return
  useHeader(p.module, s)
  if lfNoDecl in s.loc.flags: return
  if not containsOrIncl(p.module.declaredThings, s.id):
    if sfThread in s.flags:
      declareThreadVar(p.module, s, sfImportc in s.flags)
      if value != "":
        internalError(p.config, n.info, ".threadvar variables cannot have a value")
    else:
      var decl: Rope = ""
      let td = getTypeDesc(p.module, s.loc.t, dkVar)
      genGlobalVarDecl(p, n, td, value, decl)
      if s.constraint.isNil:
        if value != "":
          if p.module.compileToCpp and value.startsWith "{{}":
            # TODO: taking this branch, re"\{\{\}(,\s\{\})*\}" might be emitted, resulting in
            # either warnings (GCC 12.2+) or errors (Clang 15, MSVC 19.3+) of C++11+ compilers **when
            # explicit constructors are around** due to overload resolution rules in place [^0][^1][^2]
            # *Workaround* here: have C++'s static initialization mechanism do the default init work,
            # for us lacking a deeper knowledge of an imported object's constructors' ex-/implicitness
            # (so far) *and yet* trying to achieve default initialization.
            # Still, generating {}s in genConstObjConstr() just to omit them here is faaaar from ideal;
            # need to figure out a better way, possibly by keeping around more data about the
            # imported objects' contructors?
            #
            # [^0]: https://en.cppreference.com/w/cpp/language/aggregate_initialization
            # [^1]: https://cplusplus.github.io/CWG/issues/1518.html
            # [^2]: https://eel.is/c++draft/over.match.ctor
            decl.addf(" $1;$n", [s.loc.snippet])
          else:
            decl.addf(" $1 = $2;$n", [s.loc.snippet, value])
        else:
          decl.addf(" $1;$n", [s.loc.snippet])

      p.module.s[cfsVars].add(decl)
  if p.withinLoop > 0 and value == "":
    # fixes tests/run/tzeroarray:
    resetLoc(p, s.loc)

proc callGlobalVarCppCtor(p: BProc; v: PSym; vn, value: PNode; didGenTemp: var bool) =
  let s = vn.sym
  fillBackendName(p.module, s)
  fillLoc(s.loc, locGlobalVar, vn, OnHeap)
  var decl: Rope = ""
  let td = getTypeDesc(p.module, vn.sym.typ, dkVar)
  genGlobalVarDecl(p, vn, td, "", decl)
  decl.add " " & $s.loc.snippet
  genCppVarForCtor(p, value, decl, didGenTemp)
  if didGenTemp:  return # generated in the caller
  p.module.s[cfsVars].add decl

proc assignParam(p: BProc, s: PSym, retType: PType) =
  assert(s.loc.snippet != "")
  scopeMangledParam(p, s)

proc fillProcLoc(m: BModule; n: PNode) =
  let sym = n.sym
  if sym.loc.k == locNone:
    fillBackendName(m, sym)
    fillLoc(sym.loc, locProc, n, OnStack)

proc getLabel(p: BProc): TLabel =
  inc(p.labels)
  result = "LA" & rope(p.labels) & "_"

proc fixLabel(p: BProc, labl: TLabel) =
  p.s(cpsStmts).addLabel(labl)

proc genVarPrototype(m: BModule, n: PNode)
proc requestConstImpl(p: BProc, sym: PSym)
proc genStmts(p: BProc, t: PNode)
proc expr(p: BProc, n: PNode, d: var TLoc)

proc putLocIntoDest(p: BProc, d: var TLoc, s: TLoc)
proc genLiteral(p: BProc, n: PNode; result: var Builder)
proc genOtherArg(p: BProc; ri: PNode; i: int; typ: PType; result: var Builder; argBuilder: var CallBuilder)
proc raiseExit(p: BProc)
proc raiseExitCleanup(p: BProc, destroy: string)

proc initLocExpr(p: BProc, e: PNode, flags: TLocFlags = {}): TLoc =
  result = initLoc(locNone, e, OnUnknown, flags)
  expr(p, e, result)

proc initLocExprSingleUse(p: BProc, e: PNode): TLoc =
  result = initLoc(locNone, e, OnUnknown)
  if e.kind in nkCallKinds and (e[0].kind != nkSym or e[0].sym.magic == mNone):
    # We cannot check for tfNoSideEffect here because of mutable parameters.
    discard "bug #8202; enforce evaluation order for nested calls for C++ too"
    # We may need to consider that 'f(g())' cannot be rewritten to 'tmp = g(); f(tmp)'
    # if 'tmp' lacks a move/assignment operator.
    if e[0].kind == nkSym and sfCompileToCpp in e[0].sym.flags:
      result.flags.incl lfSingleUse
  else:
    result.flags.incl lfSingleUse
  expr(p, e, result)

include ccgcalls, "ccgstmts.nim"

proc initFrame(p: BProc, procname, filename: Rope): Rope =
  const frameDefines = """
$1define nimfr_(proc, file) \
  TFrame FR_; \
  FR_.procname = proc; FR_.filename = file; FR_.line = 0; FR_.len = 0; #nimFrame(&FR_);

$1define nimln_(n) \
  FR_.line = n;

$1define nimlf_(n, file) \
  FR_.line = n; FR_.filename = file;

"""
  if p.module.s[cfsFrameDefines].buf.len == 0:
    appcg(p.module, p.module.s[cfsFrameDefines], frameDefines, ["#"])

  cgsym(p.module, "nimFrame")
  result = ropecg(p.module, "\tnimfr_($1, $2);$n", [procname, filename])

proc initFrameNoDebug(p: BProc; frame, procname, filename: Rope; line: int): Rope =
  cgsym(p.module, "nimFrame")
  p.blocks[0].sections[cpsLocals].addf("TFrame $1;$n", [frame])
  result = ropecg(p.module, "\t$1.procname = $2; $1.filename = $3; " &
                      " $1.line = $4; $1.len = -1; nimFrame(&$1);$n",
                      [frame, procname, filename, line])

proc deinitFrameNoDebug(p: BProc; frame: Rope): Rope =
  result = ropecg(p.module, "\t#popFrameOfAddr(&$1);$n", [frame])

proc deinitFrame(p: BProc): Rope =
  result = ropecg(p.module, "\t#popFrame();$n", [])

include ccgexprs

# ----------------------------- dynamic library handling -----------------
# We don't finalize dynamic libs as the OS does this for us.

proc isGetProcAddr(lib: PLib): bool =
  let n = lib.path
  result = n.kind in nkCallKinds and n.typ != nil and
    n.typ.kind in {tyPointer, tyProc}

proc loadDynamicLib(m: BModule, lib: PLib) =
  assert(lib != nil)
  if not lib.generated:
    lib.generated = true
    var tmp = getTempName(m)
    assert(lib.name == "")
    lib.name = tmp # BUGFIX: cgsym has awful side-effects
    m.s[cfsVars].addf("static void* $1;$n", [tmp])
    if lib.path.kind in {nkStrLit..nkTripleStrLit}:
      var s: TStringSeq = @[]
      libCandidates(lib.path.strVal, s)
      rawMessage(m.config, hintDependency, lib.path.strVal)
      var loadlib = newBuilder("")
      for i in 0..high(s):
        inc(m.labels)
        if i > 0: loadlib.add("||")
        let n = newStrNode(nkStrLit, s[i])
        n.info = lib.path.info
        appcg(m, loadlib, "($1 = #nimLoadLibrary(", [tmp])
        genStringLiteral(m, n, loadlib)
        loadlib.addf "))$n", []
      appcg(m, m.s[cfsDynLibInit],
            "if (!($1)) #nimLoadLibraryError(",
            [extract(loadlib)])
      genStringLiteral(m, lib.path, m.s[cfsDynLibInit])
      m.s[cfsDynLibInit].addf ");$n", []

    else:
      var p = newProc(nil, m)
      p.options.excl optStackTrace
      p.flags.incl nimErrorFlagDisabled
      var dest: TLoc = initLoc(locTemp, lib.path, OnStack)
      dest.snippet = getTempName(m)
      appcg(m, m.s[cfsDynLibInit],"$1 $2;$n",
           [getTypeDesc(m, lib.path.typ, dkVar), rdLoc(dest)])
      expr(p, lib.path, dest)

      m.s[cfsVars].add(extract(p.s(cpsLocals)))
      m.s[cfsDynLibInit].add(extract(p.s(cpsInit)))
      m.s[cfsDynLibInit].add(extract(p.s(cpsStmts)))
      appcg(m, m.s[cfsDynLibInit],
           "if (!($1 = #nimLoadLibrary($2))) #nimLoadLibraryError($2);$n",
           [tmp, rdLoc(dest)])

  if lib.name == "": internalError(m.config, "loadDynamicLib")

proc mangleDynLibProc(sym: PSym): Rope =
  # we have to build this as a single rope in order not to trip the
  # optimization in genInfixCall, see test tests/cpp/t8241.nim
  if sfCompilerProc in sym.flags:
    # NOTE: sym.loc.snippet is the external name!
    result = rope(sym.name.s)
  else:
    result = rope(strutils.`%`("Dl_$1_", $sym.id))

proc symInDynamicLib(m: BModule, sym: PSym) =
  var lib = sym.annex
  let isCall = isGetProcAddr(lib)
  var extname = sym.loc.snippet
  if not isCall: loadDynamicLib(m, lib)
  var tmp = mangleDynLibProc(sym)
  sym.loc.snippet = tmp             # from now on we only need the internal name
  sym.typ.sym = nil           # generate a new name
  inc(m.labels, 2)
  if isCall:
    let n = lib.path
    var a: TLoc = initLocExpr(m.initProc, n[0])
    var params = rdLoc(a) & "("
    for i in 1..<n.len-1:
      a = initLocExpr(m.initProc, n[i])
      params.add(rdLoc(a))
      params.add(", ")
    let load = "\t$1 = ($2) ($3$4));$n" %
        [tmp, getTypeDesc(m, sym.typ, dkVar), params, makeCString($extname)]
    var last = lastSon(n)
    if last.kind == nkHiddenStdConv: last = last[1]
    internalAssert(m.config, last.kind == nkStrLit)
    let idx = last.strVal
    if idx.len == 0:
      m.initProc.s(cpsStmts).add(load)
    elif idx.len == 1 and idx[0] in {'0'..'9'}:
      m.extensionLoaders[idx[0]].add(load)
    else:
      internalError(m.config, sym.info, "wrong index: " & idx)
  else:
    appcg(m, m.s[cfsDynLibInit],
        "\t$1 = ($2) #nimGetProcAddr($3, $4);$n",
        [tmp, getTypeDesc(m, sym.typ, dkVar), lib.name, makeCString($extname)])
  m.s[cfsVars].addf("$2 $1;$n", [sym.loc.snippet, getTypeDesc(m, sym.loc.t, dkVar)])

proc varInDynamicLib(m: BModule, sym: PSym) =
  var lib = sym.annex
  var extname = sym.loc.snippet
  loadDynamicLib(m, lib)
  incl(sym.loc.flags, lfIndirect)
  var tmp = mangleDynLibProc(sym)
  sym.loc.snippet = tmp             # from now on we only need the internal name
  inc(m.labels, 2)
  appcg(m, m.s[cfsDynLibInit],
      "$1 = ($2*) #nimGetProcAddr($3, $4);$n",
      [tmp, getTypeDesc(m, sym.typ, dkVar), lib.name, makeCString($extname)])
  m.s[cfsVars].addf("$2* $1;$n",
      [sym.loc.snippet, getTypeDesc(m, sym.loc.t, dkVar)])

proc symInDynamicLibPartial(m: BModule, sym: PSym) =
  sym.loc.snippet = mangleDynLibProc(sym)
  sym.typ.sym = nil           # generate a new name

proc cgsymImpl(m: BModule; sym: PSym) {.inline.} =
  case sym.kind
  of skProc, skFunc, skMethod, skConverter, skIterator: genProc(m, sym)
  of skVar, skResult, skLet: genVarPrototype(m, newSymNode sym)
  of skType: discard getTypeDesc(m, sym.typ)
  else: internalError(m.config, "cgsym: " & $sym.kind)

proc cgsym(m: BModule, name: string) =
  let sym = magicsys.getCompilerProc(m.g.graph, name)
  if sym != nil:
    cgsymImpl m, sym
  else:
    rawMessage(m.config, errGenerated, "system module needs: " & name)

proc cgsymValue(m: BModule, name: string): Rope =
  let sym = magicsys.getCompilerProc(m.g.graph, name)
  if sym != nil:
    cgsymImpl m, sym
  else:
    rawMessage(m.config, errGenerated, "system module needs: " & name)
  result = sym.loc.snippet
  if m.hcrOn and sym != nil and sym.kind in {skProc..skIterator}:
    result.addActualSuffixForHCR(m.module, sym)

proc generateHeaders(m: BModule) =
  var nimbase = m.config.nimbasePattern
  if nimbase == "": nimbase = "nimbase.h"
  m.s[cfsHeaders].addf("\L#include \"$1\"\L", [nimbase])

  for it in m.headerFiles:
    if it[0] == '#':
      m.s[cfsHeaders].add(rope(it.replace('`', '"') & "\L"))
    elif it[0] notin {'"', '<'}:
      m.s[cfsHeaders].addf("#include \"$1\"$N", [rope(it)])
    else:
      m.s[cfsHeaders].addf("#include $1$N", [rope(it)])
  m.s[cfsHeaders].add("""#undef LANGUAGE_C
#undef MIPSEB
#undef MIPSEL
#undef PPC
#undef R3000
#undef R4000
#undef i386
#undef linux
#undef mips
#undef near
#undef far
#undef powerpc
#undef unix
""")

proc openNamespaceNim(namespace: string; result: var Builder) =
  result.add("namespace ")
  result.add(namespace)
  result.add(" {\L")

proc closeNamespaceNim(result: var Builder) =
  result.add("}\L")

proc closureSetup(p: BProc, prc: PSym) =
  if tfCapturesEnv notin prc.typ.flags: return
  # prc.ast[paramsPos].last contains the type we're after:
  var ls = lastSon(prc.ast[paramsPos])
  if ls.kind != nkSym:
    internalError(p.config, prc.info, "closure generation failed")
  var env = ls.sym
  #echo "created environment: ", env.id, " for ", prc.name.s
  assignLocalVar(p, ls)
  # generate cast assignment:
  if p.config.selectedGC == gcGo:
    linefmt(p, cpsStmts, "#unsureAsgnRef((void**) $1, ($2) ClE_0);$n",
            [addrLoc(p.config, env.loc), getTypeDesc(p.module, env.typ)])
  else:
    linefmt(p, cpsStmts, "$1 = ($2) ClE_0;$n",
            [rdLoc(env.loc), getTypeDesc(p.module, env.typ)])

const harmless = {nkConstSection, nkTypeSection, nkEmpty, nkCommentStmt, nkTemplateDef,
                  nkMacroDef, nkMixinStmt, nkBindStmt, nkFormalParams} +
                  declarativeDefs

proc containsResult(n: PNode): bool =
  result = false
  case n.kind
  of succ(nkEmpty)..pred(nkSym), succ(nkSym)..nkNilLit, harmless:
    discard
  of nkReturnStmt:
    for i in 0..<n.len:
      if containsResult(n[i]): return true
    result = n.len > 0 and n[0].kind == nkEmpty
  of nkSym:
    if n.sym.kind == skResult:
      result = true
  else:
    for i in 0..<n.len:
      if containsResult(n[i]): return true

proc easyResultAsgn(n: PNode): PNode =
  result = nil
  case n.kind
  of nkStmtList, nkStmtListExpr:
    var i = 0
    while i < n.len and n[i].kind in harmless: inc i
    if i < n.len: result = easyResultAsgn(n[i])
  of nkAsgn, nkFastAsgn, nkSinkAsgn:
    if n[0].kind == nkSym and n[0].sym.kind == skResult and not containsResult(n[1]):
      incl n.flags, nfPreventCg
      return n[1]
  of nkReturnStmt:
    if n.len > 0:
      result = easyResultAsgn(n[0])
      if result != nil: incl n.flags, nfPreventCg
  else: discard

type
  InitResultEnum = enum Unknown, InitSkippable, InitRequired

proc allPathsAsgnResult(p: BProc; n: PNode): InitResultEnum =
  # Exceptions coming from calls don't have not be considered here:
  #
  # proc bar(): string = raise newException(...)
  #
  # proc foo(): string =
  #   # optimized out: 'reset(result)'
  #   result = bar()
  #
  # try:
  #   a = foo()
  # except:
  #   echo "a was not written to"
  #
  template allPathsInBranch(it) =
    let a = allPathsAsgnResult(p, it)
    case a
    of InitRequired: return InitRequired
    of InitSkippable: discard
    of Unknown:
      # sticky, but can be overwritten by InitRequired:
      result = Unknown

  result = Unknown
  case n.kind
  of nkStmtList, nkStmtListExpr:
    for it in n:
      result = allPathsAsgnResult(p, it)
      if result != Unknown: return result
  of nkAsgn, nkFastAsgn, nkSinkAsgn:
    if n[0].kind == nkSym and n[0].sym.kind == skResult:
      if not containsResult(n[1]):
        if allPathsAsgnResult(p, n[1]) == InitRequired:
          result = InitRequired
        else:
          result = InitSkippable
      else: result = InitRequired
    elif containsResult(n):
      result = InitRequired
    else:
      result = allPathsAsgnResult(p, n[1])
  of nkReturnStmt:
    if n.len > 0:
      if n[0].kind == nkEmpty and result != InitSkippable:
        # This is a bare `return` statement, if `result` was not initialized
        # anywhere else (or if we're not sure about this) let's require it to be
        # initialized. This avoids cases like #9286 where this heuristic lead to
        # wrong code being generated.
        result = InitRequired
      else: result = allPathsAsgnResult(p, n[0])
  of nkIfStmt, nkIfExpr:
    var exhaustive = false
    result = InitSkippable
    for it in n:
      # Every condition must not use 'result':
      if it.len == 2 and containsResult(it[0]):
        return InitRequired
      if it.len == 1: exhaustive = true
      allPathsInBranch(it.lastSon)
    # if the 'if' statement is not exhaustive and yet it touched 'result'
    # in some way, say Unknown.
    if not exhaustive: result = Unknown
  of nkCaseStmt:
    if containsResult(n[0]): return InitRequired
    result = InitSkippable
    var exhaustive = skipTypes(n[0].typ,
        abstractVarRange-{tyTypeDesc}).kind notin {tyFloat..tyFloat128, tyString, tyCstring}
    for i in 1..<n.len:
      let it = n[i]
      allPathsInBranch(it.lastSon)
      if it.kind == nkElse: exhaustive = true
    if not exhaustive: result = Unknown
  of nkWhileStmt:
    # some dubious code can assign the result in the 'while'
    # condition and that would be fine. Everything else isn't:
    result = allPathsAsgnResult(p, n[0])
    if result == Unknown:
      result = allPathsAsgnResult(p, n[1])
      # we cannot assume that the 'while' loop is really executed at least once:
      if result == InitSkippable: result = Unknown
  of harmless:
    result = Unknown
  of nkGotoState, nkBreakState:
    # give up for now.
    result = InitRequired
  of nkSym:
    # some path reads from 'result' before it was written to!
    if n.sym.kind == skResult: result = InitRequired
  of nkTryStmt, nkHiddenTryStmt:
    # We need to watch out for the following problem:
    # try:
    #   result = stuffThatRaises()
    # except:
    #   discard "result was not set"
    #
    # So ... even if the assignment to 'result' is the very first
    # assignment this is not good enough! The only pattern we allow for
    # is 'finally: result = x'
    result = InitSkippable
    allPathsInBranch(n[0])
    for i in 1..<n.len:
      if n[i].kind == nkFinally:
        result = allPathsAsgnResult(p, n[i].lastSon)
      else:
        allPathsInBranch(n[i].lastSon)
  of nkCallKinds:
    if canRaiseDisp(p, n[0]):
      result = InitRequired
    else:
      for i in 0..<n.safeLen:
        allPathsInBranch(n[i])
  of nkRaiseStmt:
    result = InitRequired
  of nkChckRangeF, nkChckRange64, nkChckRange:
    # TODO: more checks might need to be covered like overflow, indexDefect etc.
    # bug #22852
    result = InitRequired
  else:
    for i in 0..<n.safeLen:
      allPathsInBranch(n[i])

proc getProcTypeCast(m: BModule, prc: PSym): Rope =
  result = getTypeDesc(m, prc.loc.t)
  if prc.typ.callConv == ccClosure:
    var rettype: Snippet = ""
    var desc = newBuilder("")
    var check = initIntSet()
    genProcParams(m, prc.typ, rettype, desc, check)
    let params = extract(desc)
    result = procPtrTypeUnnamed(rettype = rettype, params = params)

proc genProcBody(p: BProc; procBody: PNode) =
  genStmts(p, procBody) # modifies p.locals, p.init, etc.
  if {nimErrorFlagAccessed, nimErrorFlagDeclared, nimErrorFlagDisabled} * p.flags == {nimErrorFlagAccessed}:
    p.flags.incl nimErrorFlagDeclared
    p.blocks[0].sections[cpsLocals].addVar(kind = Local,
      name = "nimErr_", typ = ptrType("NIM_BOOL"))
    p.blocks[0].sections[cpsInit].addAssignmentWithValue("nimErr_"):
      p.blocks[0].sections[cpsInit].addCall(cgsymValue(p.module, "nimErrorFlag"))

proc genProcAux*(m: BModule, prc: PSym) =
  var p = newProc(prc, m)
  var header = newBuilder("")
  let isCppMember = m.config.backend == backendCpp and sfCppMember * prc.flags != {}
  var visibility: DeclVisibility = None
  if isCppMember:
    genMemberProcHeader(m, prc, header)
  else:
    genProcHeader(m, prc, header, visibility, asPtr = false, addAttributes = false)
  var returnStmt: Snippet = ""
  assert(prc.ast != nil)

  var procBody = transformBody(m.g.graph, m.idgen, prc, {})
  if sfInjectDestructors in prc.flags:
    procBody = injectDestructorCalls(m.g.graph, m.idgen, prc, procBody)

  let tmpInfo = prc.info
  discard freshLineInfo(p, prc.info)

  if sfPure notin prc.flags and prc.typ.returnType != nil:
    if resultPos >= prc.ast.len:
      internalError(m.config, prc.info, "proc has no result symbol")
    let resNode = prc.ast[resultPos]
    let res = resNode.sym # get result symbol
    if not isInvalidReturnType(m.config, prc.typ) and sfConstructor notin prc.flags:
      if sfNoInit in prc.flags: incl(res.flags, sfNoInit)
      if sfNoInit in prc.flags and p.module.compileToCpp and (let val = easyResultAsgn(procBody); val != nil):
        var decl = localVarDecl(p, resNode)
        var a: TLoc = initLocExprSingleUse(p, val)
        let ra = rdLoc(a)
        p.s(cpsStmts).addAssignment(decl, ra)
      else:
        # declare the result symbol:
        assignLocalVar(p, resNode)
        assert(res.loc.snippet != "")
        if p.config.selectedGC in {gcArc, gcAtomicArc, gcOrc} and
            allPathsAsgnResult(p, procBody) == InitSkippable:
          # In an ideal world the codegen could rely on injectdestructors doing its job properly
          # and then the analysis step would not be required.
          discard "result init optimized out"
        else:
          initLocalVar(p, res, immediateAsgn=false)
      var returnBuilder = newBuilder("\t")
      let rres = rdLoc(res.loc)
      returnBuilder.addReturn(rres)
      returnStmt = extract(returnBuilder)
    elif sfConstructor in prc.flags:
      resNode.sym.loc.flags.incl lfIndirect
      fillLoc(resNode.sym.loc, locParam, resNode, "this", OnHeap)
      prc.loc.snippet = getTypeDesc(m, resNode.sym.loc.t, dkVar)
    else:
      fillResult(p.config, resNode, prc.typ)
      assignParam(p, res, prc.typ.returnType)
      # We simplify 'unsureAsgn(result, nil); unsureAsgn(result, x)'
      # to 'unsureAsgn(result, x)'
      # Sketch why this is correct: If 'result' points to a stack location
      # the 'unsureAsgn' is a nop. If it points to a global variable the
      # global is either 'nil' or points to valid memory and so the RC operation
      # succeeds without touching not-initialized memory.
      if sfNoInit in prc.flags: discard
      elif allPathsAsgnResult(p, procBody) == InitSkippable: discard
      else:
        resetLoc(p, res.loc)
      if skipTypes(res.typ, abstractInst).kind == tyArray:
        #incl(res.loc.flags, lfIndirect)
        res.loc.storage = OnUnknown

  for i in 1..<prc.typ.n.len:
    let param = prc.typ.n[i].sym
    if param.typ.isCompileTimeOnly: continue
    assignParam(p, param, prc.typ.returnType)
  closureSetup(p, prc)
  genProcBody(p, procBody)

  prc.info = tmpInfo

  var generatedProc = newBuilder("")
  generatedProc.genCLineDir prc.info, m.config
  generatedProc.addDeclWithVisibility(visibility):
    if sfPure in prc.flags:
      generatedProc.add(extract(header))
      generatedProc.finishProcHeaderWithBody():
        generatedProc.add(extract(p.s(cpsLocals)))
        generatedProc.add(extract(p.s(cpsInit)))
        generatedProc.add(extract(p.s(cpsStmts)))
    else:
      if m.hcrOn and isReloadable(m, prc):
        m.s[cfsProcHeaders].addDeclWithVisibility(visibility):
          # Add forward declaration for "_actual"-suffixed functions defined in the same module (or inline).
          # This fixes the use of methods and also the case when 2 functions within the same module
          # call each other using directly the "_actual" versions (an optimization) - see issue #11608
          m.s[cfsProcHeaders].add(extract(header))
          m.s[cfsProcHeaders].finishProcHeaderAsProto()
      generatedProc.add(extract(header))
      generatedProc.finishProcHeaderWithBody():
        if optStackTrace in prc.options:
          generatedProc.add(extract(p.s(cpsLocals)))
          var procname = makeCString(prc.name.s)
          generatedProc.add(initFrame(p, procname, quotedFilename(p.config, prc.info)))
        else:
          generatedProc.add(extract(p.s(cpsLocals)))
        if optProfiler in prc.options:
          # invoke at proc entry for recursion:
          p.s(cpsInit).add('\t')
          p.s(cpsInit).addCallStmt(cgsymValue(m, "nimProfile"))
        if beforeRetNeeded in p.flags:
          # this pair of {} is required for C++ (C++ is weird with its
          # control flow integrity checks):
          generatedProc.addScope():
            generatedProc.add(extract(p.s(cpsInit)))
            generatedProc.add(extract(p.s(cpsStmts)))
          generatedProc.addLabel("BeforeRet_")
        else:
          generatedProc.add(extract(p.s(cpsInit)))
          generatedProc.add(extract(p.s(cpsStmts)))
        if optStackTrace in prc.options: generatedProc.add(deinitFrame(p))
        generatedProc.add(returnStmt)
  m.s[cfsProcs].add(extract(generatedProc))
  if isReloadable(m, prc):
    m.s[cfsDynLibInit].add('\t')
    m.s[cfsDynLibInit].addAssignmentWithValue(prc.loc.snippet):
      m.s[cfsDynLibInit].addCast(getProcTypeCast(m, prc)):
        m.s[cfsDynLibInit].addCall("hcrRegisterProc",
          getModuleDllPath(m, prc),
          '"' & prc.loc.snippet & '"',
          cCast("void*", prc.loc.snippet & "_actual"))

proc requiresExternC(m: BModule; sym: PSym): bool {.inline.} =
  result = (sfCompileToCpp in m.module.flags and
           sfCompileToCpp notin sym.getModule().flags and
           m.config.backend != backendCpp) or (
           sym.flags * {sfInfixCall, sfCompilerProc, sfMangleCpp} == {} and
           sym.flags * {sfImportc, sfExportc} != {} and
           sym.magic == mNone and
           m.config.backend == backendCpp)

proc genProcPrototype(m: BModule, sym: PSym) =
  useHeader(m, sym)
  if lfNoDecl in sym.loc.flags or sfCppMember * sym.flags != {}: return
  if lfDynamicLib in sym.loc.flags:
    if sym.itemId.module != m.module.position and
        not containsOrIncl(m.declaredThings, sym.id):
      let vis = if isReloadable(m, sym): StaticProc else: Extern
      let name = mangleDynLibProc(sym)
      let t = getTypeDesc(m, sym.loc.t)
      m.s[cfsVars].addDeclWithVisibility(vis):
        m.s[cfsVars].addVar(kind = Local,
          name = name,
          typ = t)
      if isReloadable(m, sym):
        m.s[cfsDynLibInit].add('\t')
        m.s[cfsDynLibInit].addAssignmentWithValue(name):
          m.s[cfsDynLibInit].addCast(t):
            m.s[cfsDynLibInit].addCall("hcrGetProc",
              getModuleDllPath(m, sym),
              '"' & name & '"')
  elif not containsOrIncl(m.declaredProtos, sym.id):
    let asPtr = isReloadable(m, sym)
    var header = newBuilder("")
    var visibility: DeclVisibility = None
    genProcHeader(m, sym, header, visibility, asPtr = asPtr, addAttributes = true)
    if asPtr:
      m.s[cfsProcHeaders].addDeclWithVisibility(visibility):
        # genProcHeader would give variable declaration, add it directly
        m.s[cfsProcHeaders].add(extract(header))
    else:
      let extraVis =
        if sym.typ.callConv != ccInline and requiresExternC(m, sym):
          ExternC
        else:
          None
      m.s[cfsProcHeaders].addDeclWithVisibility(extraVis):
        m.s[cfsProcHeaders].addDeclWithVisibility(visibility):
          m.s[cfsProcHeaders].add(extract(header))
          m.s[cfsProcHeaders].finishProcHeaderAsProto()

# TODO: figure out how to rename this - it DOES generate a forward declaration
proc genProcNoForward(m: BModule, prc: PSym) =
  if lfImportCompilerProc in prc.loc.flags:
    fillProcLoc(m, prc.ast[namePos])
    useHeader(m, prc)
    # dependency to a compilerproc:
    cgsym(m, prc.name.s)
    return
  if lfNoDecl in prc.loc.flags:
    fillProcLoc(m, prc.ast[namePos])
    genProcPrototype(m, prc)
  elif lfDynamicLib in prc.loc.flags:
    var q = findPendingModule(m, prc)
    fillProcLoc(q, prc.ast[namePos])
    genProcPrototype(m, prc)
    if q != nil and not containsOrIncl(q.declaredThings, prc.id):
      symInDynamicLib(q, prc)
      # register the procedure even though it is in a different dynamic library and will not be
      # reloadable (and has no _actual suffix) - other modules will need to be able to get it through
      # the hcr dynlib (also put it in the DynLibInit section - right after it gets loaded)
      if isReloadable(q, prc):
        q.s[cfsDynLibInit].addf("\t$1 = ($2) hcrRegisterProc($3, \"$1\", (void*)$1);$n",
            [prc.loc.snippet, getTypeDesc(q, prc.loc.t), getModuleDllPath(m, q.module)])
    else:
      symInDynamicLibPartial(m, prc)
  elif prc.typ.callConv == ccInline:
    # We add inline procs to the calling module to enable C based inlining.
    # This also means that a check with ``q.declaredThings`` is wrong, we need
    # a check for ``m.declaredThings``.
    if not containsOrIncl(m.declaredThings, prc.id):
      #if prc.loc.k == locNone:
      # mangle the inline proc based on the module where it is defined -
      # not on the first module that uses it
      let m2 = if m.config.symbolFiles != disabledSf: m
               else: findPendingModule(m, prc)
      fillProcLoc(m2, prc.ast[namePos])
      #elif {sfExportc, sfImportc} * prc.flags == {}:
      #  # reset name to restore consistency in case of hashing collisions:
      #  echo "resetting ", prc.id, " by ", m.module.name.s
      #  prc.loc.snippet = nil
      #  prc.loc.snippet = mangleName(m, prc)
      genProcPrototype(m, prc)
      genProcAux(m, prc)
  elif sfImportc notin prc.flags:
    var q = findPendingModule(m, prc)
    fillProcLoc(q, prc.ast[namePos])
    # generate a getProc call to initialize the pointer for this
    # externally-to-the-current-module defined proc, also important
    # to do the declaredProtos check before the call to genProcPrototype
    if isReloadable(m, prc) and prc.id notin m.declaredProtos and
      q != nil and q.module.id != m.module.id:
      m.s[cfsDynLibInit].addf("\t$1 = ($2) hcrGetProc($3, \"$1\");$n",
           [prc.loc.snippet, getProcTypeCast(m, prc), getModuleDllPath(m, prc)])
    genProcPrototype(m, prc)
    if q != nil and not containsOrIncl(q.declaredThings, prc.id):
      # make sure there is a "prototype" in the external module
      # which will actually become a function pointer
      if isReloadable(m, prc):
        genProcPrototype(q, prc)
      genProcAux(q, prc)
  else:
    fillProcLoc(m, prc.ast[namePos])
    useHeader(m, prc)
    if sfInfixCall notin prc.flags: genProcPrototype(m, prc)

proc requestConstImpl(p: BProc, sym: PSym) =
  if genConstSetup(p, sym):
    let m = p.module
    # declare implementation:
    var q = findPendingModule(m, sym)
    if q != nil and not containsOrIncl(q.declaredThings, sym.id):
      assert q.initProc.module == q
      genConstDefinition(q, p, sym)
    # declare header:
    if q != m and not containsOrIncl(m.declaredThings, sym.id):
      genConstHeader(m, q, p, sym)

proc isActivated(prc: PSym): bool = prc.typ != nil

proc genProc(m: BModule, prc: PSym) =
  if sfBorrow in prc.flags or not isActivated(prc): return
  if sfForward in prc.flags:
    addForwardedProc(m, prc)
    fillProcLoc(m, prc.ast[namePos])
  else:
    genProcNoForward(m, prc)
    if {sfExportc, sfCompilerProc} * prc.flags == {sfExportc} and
        m.g.generatedHeader != nil and lfNoDecl notin prc.loc.flags:
      genProcPrototype(m.g.generatedHeader, prc)
      if prc.typ.callConv == ccInline:
        if not containsOrIncl(m.g.generatedHeader.declaredThings, prc.id):
          genProcAux(m.g.generatedHeader, prc)

proc genVarPrototype(m: BModule, n: PNode) =
  #assert(sfGlobal in sym.flags)
  let sym = n.sym
  useHeader(m, sym)
  fillBackendName(m, sym)
  fillLoc(sym.loc, locGlobalVar, n, OnHeap)
  if treatGlobalDifferentlyForHCR(m, sym): incl(sym.loc.flags, lfIndirect)

  if (lfNoDecl in sym.loc.flags) or contains(m.declaredThings, sym.id):
    return
  if sym.owner.id != m.module.id:
    # else we already have the symbol generated!
    assert(sym.loc.snippet != "")
    incl(m.declaredThings, sym.id)
    if sfThread in sym.flags:
      declareThreadVar(m, sym, true)
    else:
      if sym.kind in {skLet, skVar, skField, skForVar} and sym.alignment > 0:
        m.s[cfsVars].addf "NIM_ALIGN($1) ", [rope(sym.alignment)]
      m.s[cfsVars].add(if m.hcrOn: "static " else: "extern ")
      m.s[cfsVars].add(getTypeDesc(m, sym.loc.t, dkVar))
      if m.hcrOn: m.s[cfsVars].add("*")
      if lfDynamicLib in sym.loc.flags: m.s[cfsVars].add("*")
      if sfRegister in sym.flags: m.s[cfsVars].add(" register")
      if sfVolatile in sym.flags: m.s[cfsVars].add(" volatile")
      if sfNoalias in sym.flags: m.s[cfsVars].add(" NIM_NOALIAS")
      m.s[cfsVars].addf(" $1;$n", [sym.loc.snippet])
      if m.hcrOn: m.initProc.procSec(cpsLocals).addf(
        "\t$1 = ($2*)hcrGetGlobal($3, \"$1\");$n", [sym.loc.snippet,
        getTypeDesc(m, sym.loc.t, dkVar), getModuleDllPath(m, sym)])

proc addNimDefines(result: var Builder; conf: ConfigRef) {.inline.} =
  result.addf("#define NIM_INTBITS $1\L", [
    platform.CPU[conf.target.targetCPU].intSize.rope])
  if conf.cppCustomNamespace.len > 0:
    result.add("#define USE_NIM_NAMESPACE ")
    result.add(conf.cppCustomNamespace)
    result.add("\L")
  if conf.isDefined("nimEmulateOverflowChecks"):
    result.add("#define NIM_EmulateOverflowChecks\L")

proc headerTop(): Rope =
  result = "/* Generated by Nim Compiler v$1 */$N" % [rope(VersionAsString)]

proc getCopyright(conf: ConfigRef; cfile: Cfile): Rope =
  result = headerTop()
  if optCompileOnly notin conf.globalOptions:
    result.add ("/* Compiled for: $1, $2, $3 */$N" &
        "/* Command for C compiler:$n   $4 */$N") %
        [rope(platform.OS[conf.target.targetOS].name),
        rope(platform.CPU[conf.target.targetCPU].name),
        rope(extccomp.CC[conf.cCompiler].name),
        rope(getCompileCFileCmd(conf, cfile))]

proc getFileHeader(conf: ConfigRef; cfile: Cfile): Rope =
  var res = newBuilder(getCopyright(conf, cfile))
  if conf.hcrOn: res.add("#define NIM_HOT_CODE_RELOADING\L")
  addNimDefines(res, conf)
  result = extract(res)

proc getSomeNameForModule(conf: ConfigRef, filename: AbsoluteFile): Rope =
  ## Returns a mangled module name.
  result = mangleModuleName(conf, filename).mangle

proc getSomeNameForModule(m: BModule): Rope =
  ## Returns a mangled module name.
  assert m.module.kind == skModule
  assert m.module.owner.kind == skPackage
  result = mangleModuleName(m.g.config, m.filename).mangle

proc getSomeInitName(m: BModule, suffix: string): Rope =
  if not m.hcrOn:
    result = getSomeNameForModule(m)
  else:
    result = ""
  result.add suffix

proc getInitName(m: BModule): Rope =
  if sfMainModule in m.module.flags:
    # generate constant name for main module, for "easy" debugging.
    result = rope(m.config.nimMainPrefix) & rope"NimMainModule"
  else:
    result = getSomeInitName(m, "Init000")

proc getDatInitName(m: BModule): Rope = getSomeInitName(m, "DatInit000")
proc getHcrInitName(m: BModule): Rope = getSomeInitName(m, "HcrInit000")

proc hcrGetProcLoadCode(m: BModule, sym, prefix, handle, getProcFunc: string): Rope

proc genMainProc(m: BModule) =
  ## this function is called in cgenWriteModules after all modules are closed,
  ## it means raising dependency on the symbols is too late as it will not propagate
  ## into other modules, only simple rope manipulations are allowed
  var preMainCode: Rope = ""
  if m.hcrOn:
    proc loadLib(handle: string, name: string): Rope =
      result = ""
      let prc = magicsys.getCompilerProc(m.g.graph, name)
      assert prc != nil
      let n = newStrNode(nkStrLit, prc.annex.path.strVal)
      n.info = prc.annex.path.info
      var strLitBuilder = newBuilder("")
      genStringLiteral(m, n, strLitBuilder)
      let strLit = extract(strLitBuilder)
      appcg(m, result, "\tif (!($1 = #nimLoadLibrary($2)))$N" &
                       "\t\t#nimLoadLibraryError($2);$N",
                       [handle, strLit])

    preMainCode.add(loadLib("hcr_handle", "hcrGetProc"))
    if m.config.selectedGC in {gcArc, gcAtomicArc, gcOrc}:
      preMainCode.add("\t$1PreMain();\L" % [rope m.config.nimMainPrefix])
    else:
      preMainCode.add("\tvoid* rtl_handle;\L")
      preMainCode.add(loadLib("rtl_handle", "nimGC_setStackBottom"))
      preMainCode.add(hcrGetProcLoadCode(m, "nimGC_setStackBottom", "nimrtl_", "rtl_handle", "nimGetProcAddr"))
      preMainCode.add("\tinner = $1PreMain;\L" % [rope m.config.nimMainPrefix])
      preMainCode.add("\tinitStackBottomWith_actual((void *)&inner);\L")
      preMainCode.add("\t(*inner)();\L")
  else:
    preMainCode.add("\t$1PreMain();\L" % [rope m.config.nimMainPrefix])

  var posixCmdLine: Rope = ""
  if optNoMain notin m.config.globalOptions:
    posixCmdLine.add "N_LIB_PRIVATE int cmdCount;\L"
    posixCmdLine.add "N_LIB_PRIVATE char** cmdLine;\L"
    posixCmdLine.add "N_LIB_PRIVATE char** gEnv;\L"

  const
    # The use of a volatile function pointer to call Pre/NimMainInner
    # prevents inlining of the NimMainInner function and dependent
    # functions, which might otherwise merge their stack frames.

    PreMainBody = "$N" &
      "N_LIB_PRIVATE void $3PreMainInner(void) {$N" &
      "$2" &
      "}$N$N" &
      "$4" &
      "N_LIB_PRIVATE void $3PreMain(void) {$N" &
      "##if $5$N" & # 1 for volatile call, 0 for non-volatile
      "\tvoid (*volatile inner)(void);$N" &
      "\tinner = $3PreMainInner;$N" &
      "$1" &
      "\t(*inner)();$N" &
      "##else$N" &
      "$1" &
      "\t$3PreMainInner();$N" &
      "##endif$N" &
      "}$N$N"

    MainProcs =
      "\t$^NimMain();$N"

    MainProcsWithResult =
      MainProcs & ("\treturn $1nim_program_result;$N")

    NimMainInner = "N_LIB_PRIVATE N_CDECL(void, $5NimMainInner)(void) {$N" &
        "$1" &
      "}$N$N"

    NimMainProc =
      "N_CDECL(void, $5NimMain)(void) {$N" &
      "##if $6$N" & # 1 for volatile call, 0 for non-volatile
      "\tvoid (*volatile inner)(void);$N" &
      "$4" &
      "\tinner = $5NimMainInner;$N" &
      "$2" &
      "\t(*inner)();$N" &
      "##else$N" &
      "$4" &
      "$2" &
      "\t$5NimMainInner();$N" &
      "##endif$N" &
      "}$N$N"

    NimMainBody = NimMainInner & NimMainProc

    PosixCMain =
      "int main(int argc, char** args, char** env) {$N" &
        "\tcmdLine = args;$N" &
        "\tcmdCount = argc;$N" &
        "\tgEnv = env;$N" &
        MainProcsWithResult &
      "}$N$N"

    StandaloneCMain =
      "int main(void) {$N" &
        MainProcs &
        "\treturn 0;$N" &
      "}$N$N"

    WinNimMain = NimMainBody

    WinCMain = "N_STDCALL(int, WinMain)(HINSTANCE hCurInstance, $N" &
      "                        HINSTANCE hPrevInstance, $N" &
      "                        LPSTR lpCmdLine, int nCmdShow) {$N" &
      MainProcsWithResult & "}$N$N"

    WinNimDllMain = NimMainInner & "N_LIB_EXPORT " & NimMainProc

    WinCDllMain =
      "BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fwdreason, $N" &
      "                    LPVOID lpvReserved) {$N" &
      "\tif (fwdreason == DLL_PROCESS_ATTACH) {$N" & MainProcs & "\t}$N" &
      "\treturn 1;$N}$N$N"

    PosixNimDllMain = WinNimDllMain

    PosixCDllMain =
      "N_LIB_PRIVATE void NIM_POSIX_INIT NimMainInit(void) {$N" &
        MainProcs &
      "}$N$N"

    GenodeNimMain =
      "extern Genode::Env *nim_runtime_env;$N" &
      "extern \"C\" void nim_component_construct(Genode::Env*);$N$N" &
      NimMainBody

    ComponentConstruct =
      "void Libc::Component::construct(Libc::Env &env) {$N" &
      "\t// Set Env used during runtime initialization$N" &
      "\tnim_runtime_env = &env;$N" &
      "\tLibc::with_libc([&] () {$N\t" &
      "\t// Initialize runtime and globals$N" &
      MainProcs &
      "\t// Call application construct$N" &
      "\t\tnim_component_construct(&env);$N" &
      "\t});$N" &
      "}$N$N"

  if m.config.target.targetOS == osWindows and
      m.config.globalOptions * {optGenGuiApp, optGenDynLib} != {}:
    m.includeHeader("<windows.h>")
  elif m.config.target.targetOS == osGenode:
    m.includeHeader("<libc/component.h>")

  let initStackBottomCall =
    if m.config.target.targetOS == osStandalone or m.config.selectedGC in {gcNone, gcArc, gcAtomicArc, gcOrc}: "".rope
    else: ropecg(m, "\t#initStackBottomWith((void *)&inner);$N", [])
  inc(m.labels)

  let isVolatile = if m.config.selectedGC notin {gcNone, gcArc, gcAtomicArc, gcOrc}: "1" else: "0"
  appcg(m, m.s[cfsProcs], PreMainBody, [m.g.mainDatInit, m.g.otherModsInit, m.config.nimMainPrefix, posixCmdLine, isVolatile])

  if m.config.target.targetOS == osWindows and
      m.config.globalOptions * {optGenGuiApp, optGenDynLib} != {}:
    if optGenGuiApp in m.config.globalOptions:
      const nimMain = WinNimMain
      appcg(m, m.s[cfsProcs], nimMain,
        [m.g.mainModInit, initStackBottomCall, m.labels, preMainCode, m.config.nimMainPrefix, isVolatile])
    else:
      const nimMain = WinNimDllMain
      appcg(m, m.s[cfsProcs], nimMain,
        [m.g.mainModInit, initStackBottomCall, m.labels, preMainCode, m.config.nimMainPrefix, isVolatile])
  elif m.config.target.targetOS == osGenode:
    const nimMain = GenodeNimMain
    appcg(m, m.s[cfsProcs], nimMain,
        [m.g.mainModInit, initStackBottomCall, m.labels, preMainCode, m.config.nimMainPrefix, isVolatile])
  elif optGenDynLib in m.config.globalOptions:
    const nimMain = PosixNimDllMain
    appcg(m, m.s[cfsProcs], nimMain,
        [m.g.mainModInit, initStackBottomCall, m.labels, preMainCode, m.config.nimMainPrefix, isVolatile])
  else:
    const nimMain = NimMainBody
    appcg(m, m.s[cfsProcs], nimMain,
        [m.g.mainModInit, initStackBottomCall, m.labels, preMainCode, m.config.nimMainPrefix, isVolatile])

  if optNoMain notin m.config.globalOptions:
    if m.config.cppCustomNamespace.len > 0:
      closeNamespaceNim(m.s[cfsProcs])
      m.s[cfsProcs].add "using namespace " & m.config.cppCustomNamespace & ";\L"

    if m.config.target.targetOS == osWindows and
        m.config.globalOptions * {optGenGuiApp, optGenDynLib} != {}:
      if optGenGuiApp in m.config.globalOptions:
        const otherMain = WinCMain
        appcg(m, m.s[cfsProcs], otherMain, [if m.hcrOn: "*" else: "", m.config.nimMainPrefix])
      else:
        const otherMain = WinCDllMain
        appcg(m, m.s[cfsProcs], otherMain, [m.config.nimMainPrefix])
    elif m.config.target.targetOS == osGenode:
      const otherMain = ComponentConstruct
      appcg(m, m.s[cfsProcs], otherMain, [m.config.nimMainPrefix])
    elif optGenDynLib in m.config.globalOptions:
      const otherMain = PosixCDllMain
      appcg(m, m.s[cfsProcs], otherMain, [m.config.nimMainPrefix])
    elif m.config.target.targetOS == osStandalone:
      const otherMain = StandaloneCMain
      appcg(m, m.s[cfsProcs], otherMain, [m.config.nimMainPrefix])
    else:
      const otherMain = PosixCMain
      appcg(m, m.s[cfsProcs], otherMain, [if m.hcrOn: "*" else: "", m.config.nimMainPrefix])

    if m.config.cppCustomNamespace.len > 0:
      openNamespaceNim(m.config.cppCustomNamespace, m.s[cfsProcs])

proc registerInitProcs*(g: BModuleList; m: PSym; flags: set[ModuleBackendFlag]) =
  ## Called from the IC backend.
  if HasDatInitProc in flags:
    let datInit = getSomeNameForModule(g.config, g.config.toFullPath(m.info.fileIndex).AbsoluteFile) & "DatInit000"
    g.mainModProcs.addf("N_LIB_PRIVATE N_NIMCALL(void, $1)(void);$N", [datInit])
    g.mainDatInit.addf("\t$1();$N", [datInit])
  if HasModuleInitProc in flags:
    let init = getSomeNameForModule(g.config, g.config.toFullPath(m.info.fileIndex).AbsoluteFile) & "Init000"
    g.mainModProcs.addf("N_LIB_PRIVATE N_NIMCALL(void, $1)(void);$N", [init])
    let initCall = "\t$1();$N" % [init]
    if sfMainModule in m.flags:
      g.mainModInit.add(initCall)
    elif sfSystemModule in m.flags:
      g.mainDatInit.add(initCall) # systemInit must called right after systemDatInit if any
    else:
      g.otherModsInit.add(initCall)

proc whichInitProcs*(m: BModule): set[ModuleBackendFlag] =
  # called from IC.
  result = {}
  if m.hcrOn or m.preInitProc.s(cpsInit).buf.len > 0 or m.preInitProc.s(cpsStmts).buf.len > 0:
    result.incl HasModuleInitProc
  for i in cfsTypeInit1..cfsDynLibInit:
    if m.s[i].buf.len != 0:
      result.incl HasDatInitProc
      break

proc registerModuleToMain(g: BModuleList; m: BModule) =
  let
    init = m.getInitName
    datInit = m.getDatInitName

  if m.hcrOn:
    var hcrModuleMeta = "$nN_LIB_PRIVATE const char* hcr_module_list[] = {$n" % []
    let systemModulePath = getModuleDllPath(m, g.modules[g.graph.config.m.systemFileIdx.int].module)
    let mainModulePath = getModuleDllPath(m, m.module)
    if sfMainModule in m.module.flags:
      hcrModuleMeta.addf("\t$1,$n", [systemModulePath])
    g.graph.importDeps.withValue(FileIndex(m.module.position), deps):
      for curr in deps[]:
        hcrModuleMeta.addf("\t$1,$n", [getModuleDllPath(m, g.modules[curr.int].module)])
    hcrModuleMeta.addf("\t\"\"};$n", [])
    hcrModuleMeta.addf("$nN_LIB_EXPORT N_NIMCALL(void**, HcrGetImportedModules)() { return (void**)hcr_module_list; }$n", [])
    hcrModuleMeta.addf("$nN_LIB_EXPORT N_NIMCALL(char*, HcrGetSigHash)() { return \"$1\"; }$n$n",
                          [($sigHash(m.module, m.config)).rope])
    if sfMainModule in m.module.flags:
      g.mainModProcs.add(hcrModuleMeta)
      g.mainModProcs.addf("static void* hcr_handle;$N", [])
      g.mainModProcs.addf("N_LIB_EXPORT N_NIMCALL(void, $1)(void);$N", [init])
      g.mainModProcs.addf("N_LIB_EXPORT N_NIMCALL(void, $1)(void);$N", [datInit])
      g.mainModProcs.addf("N_LIB_EXPORT N_NIMCALL(void, $1)(void*, N_NIMCALL_PTR(void*, getProcAddr)(void*, char*));$N", [m.getHcrInitName])
      g.mainModProcs.addf("N_LIB_EXPORT N_NIMCALL(void, HcrCreateTypeInfos)(void);$N", [])
      g.mainModInit.addf("\t$1();$N", [init])
      g.otherModsInit.addf("\thcrInit((void**)hcr_module_list, $1, $2, $3, hcr_handle, nimGetProcAddr);$n",
                            [mainModulePath, systemModulePath, datInit])
      g.mainDatInit.addf("\t$1(hcr_handle, nimGetProcAddr);$N", [m.getHcrInitName])
      g.mainDatInit.addf("\thcrAddModule($1);\n", [mainModulePath])
      g.mainDatInit.addf("\tHcrCreateTypeInfos();$N", [])
      # nasty nasty hack to get the command line functionality working with HCR
      # register the 2 variables on behalf of the os module which might not even
      # be loaded (in which case it will get collected but that is not a problem)
      # EDIT: indeed, this hack, in combination with another un-necessary one
      # (`makeCString` was doing line wrap of string litterals) was root cause for
      # bug #16265.
      let osModulePath = ($systemModulePath).replace("stdlib_system", "stdlib_os").rope
      g.mainDatInit.addf("\thcrAddModule($1);\n", [osModulePath])
      g.mainDatInit.add("\tint* cmd_count;\n")
      g.mainDatInit.add("\tchar*** cmd_line;\n")
      g.mainDatInit.addf("\thcrRegisterGlobal($1, \"cmdCount\", sizeof(cmd_count), NULL, (void**)&cmd_count);$N", [osModulePath])
      g.mainDatInit.addf("\thcrRegisterGlobal($1, \"cmdLine\", sizeof(cmd_line), NULL, (void**)&cmd_line);$N", [osModulePath])
      g.mainDatInit.add("\t*cmd_count = cmdCount;\n")
      g.mainDatInit.add("\t*cmd_line = cmdLine;\n")
    else:
      m.s[cfsInitProc].add(hcrModuleMeta)
    return

  if m.s[cfsDatInitProc].buf.len > 0:
    g.mainModProcs.addf("N_LIB_PRIVATE N_NIMCALL(void, $1)(void);$N", [datInit])
    g.mainDatInit.addf("\t$1();$N", [datInit])

  # Initialization of TLS and GC should be done in between
  # systemDatInit and systemInit calls if any
  if sfSystemModule in m.module.flags:
    if emulatedThreadVars(m.config) and m.config.target.targetOS != osStandalone:
      g.mainDatInit.add(ropecg(m, "\t#initThreadVarsEmulation();$N", []))
    if m.config.target.targetOS != osStandalone and m.config.selectedGC notin {gcNone, gcArc, gcAtomicArc, gcOrc}:
      g.mainDatInit.add(ropecg(m, "\t#initStackBottomWith((void *)&inner);$N", []))

  if m.s[cfsInitProc].buf.len > 0:
    g.mainModProcs.addf("N_LIB_PRIVATE N_NIMCALL(void, $1)(void);$N", [init])
    let initCall = "\t$1();$N" % [init]
    if sfMainModule in m.module.flags:
      g.mainModInit.add(initCall)
    elif sfSystemModule in m.module.flags:
      g.mainDatInit.add(initCall) # systemInit must called right after systemDatInit if any
    else:
      g.otherModsInit.add(initCall)

proc genDatInitCode(m: BModule) =
  ## this function is called in cgenWriteModules after all modules are closed,
  ## it means raising dependency on the symbols is too late as it will not propagate
  ## into other modules, only simple rope manipulations are allowed

  var moduleDatInitRequired = m.hcrOn

  var prc = newBuilder("$1 N_NIMCALL(void, $2)(void) {$N" %
    [rope(if m.hcrOn: "N_LIB_EXPORT" else: "N_LIB_PRIVATE"), getDatInitName(m)])

  # we don't want to break into such init code - could happen if a line
  # directive from a function written by the user spills after itself
  genCLineDir(prc, InvalidFileIdx, 999999, m.config)

  for i in cfsTypeInit1..cfsDynLibInit:
    if m.s[i].buf.len != 0:
      moduleDatInitRequired = true
      prc.add(extract(m.s[i]))

  prc.addf("}$N$N", [])

  if moduleDatInitRequired:
    m.s[cfsDatInitProc].add(extract(prc))
    #rememberFlag(m.g.graph, m.module, HasDatInitProc)

# Very similar to the contents of symInDynamicLib - basically only the
# things needed for the hot code reloading runtime procs to be loaded
proc hcrGetProcLoadCode(m: BModule, sym, prefix, handle, getProcFunc: string): Rope =
  let prc = magicsys.getCompilerProc(m.g.graph, sym)
  assert prc != nil
  fillProcLoc(m, prc.ast[namePos])

  var extname = prefix & sym
  var tmp = mangleDynLibProc(prc)
  prc.loc.snippet = tmp
  prc.typ.sym = nil

  if not containsOrIncl(m.declaredThings, prc.id):
    m.s[cfsVars].addf("static $2 $1;$n", [prc.loc.snippet, getTypeDesc(m, prc.loc.t, dkVar)])

  result = "\t$1 = ($2) $3($4, $5);$n" %
      [tmp, getTypeDesc(m, prc.typ, dkVar), getProcFunc.rope, handle.rope, makeCString(prefix & sym)]

proc genInitCode(m: BModule) =
  ## this function is called in cgenWriteModules after all modules are closed,
  ## it means raising dependency on the symbols is too late as it will not propagate
  ## into other modules, only simple rope manipulations are allowed
  var moduleInitRequired = m.hcrOn
  let initname = getInitName(m)
  var prc = newBuilder("$1 N_NIMCALL(void, $2)(void) {$N" %
    [rope(if m.hcrOn: "N_LIB_EXPORT" else: "N_LIB_PRIVATE"), initname])
  # we don't want to break into such init code - could happen if a line
  # directive from a function written by the user spills after itself
  genCLineDir(prc, InvalidFileIdx, 999999, m.config)
  if m.typeNodes > 0:
    if m.hcrOn:
      appcg(m, m.s[cfsTypeInit1], "\t#TNimNode* $1;$N", [m.typeNodesName])
      appcg(m, m.s[cfsTypeInit1], "\thcrRegisterGlobal($3, \"$1_$2\", sizeof(TNimNode) * $2, NULL, (void**)&$1);$N",
            [m.typeNodesName, m.typeNodes, getModuleDllPath(m, m.module)])
    else:
      appcg(m, m.s[cfsTypeInit1], "static #TNimNode $1[$2];$n",
            [m.typeNodesName, m.typeNodes])
  if m.nimTypes > 0:
    appcg(m, m.s[cfsTypeInit1], "static #TNimType $1[$2];$n",
          [m.nimTypesName, m.nimTypes])

  if m.hcrOn:
    prc.addf("\tint* nim_hcr_dummy_ = 0;$n" &
              "\tNIM_BOOL nim_hcr_do_init_ = " &
                  "hcrRegisterGlobal($1, \"module_initialized_\", 1, NULL, (void**)&nim_hcr_dummy_);$n",
      [getModuleDllPath(m, m.module)])

  template writeSection(thing: untyped, section: TCProcSection, addHcrGuards = false) =
    if m.thing.s(section).buf.len > 0:
      moduleInitRequired = true
      if addHcrGuards: prc.add("\tif (nim_hcr_do_init_) {\n\n")
      prc.add(extract(m.thing.s(section)))
      if addHcrGuards: prc.add("\n\t} // nim_hcr_do_init_\n")

  if m.preInitProc.s(cpsInit).buf.len > 0 or m.preInitProc.s(cpsStmts).buf.len > 0:
    # Give this small function its own scope
    prc.addf("{$N", [])
    # Keep a bogus frame in case the code needs one
    prc.add("\tTFrame FR_; FR_.len = 0;\n")

    writeSection(preInitProc, cpsLocals)
    writeSection(preInitProc, cpsInit, m.hcrOn)
    writeSection(preInitProc, cpsStmts)
    prc.addf("}/* preInitProc end */$N", [])
    when false:
      m.initProc.blocks[0].sections[cpsLocals].add m.preInitProc.s(cpsLocals)
      m.initProc.blocks[0].sections[cpsInit].prepend m.preInitProc.s(cpsInit)
      m.initProc.blocks[0].sections[cpsStmts].prepend m.preInitProc.s(cpsStmts)

  # add new scope for following code, because old vcc compiler need variable
  # be defined at the top of the block
  prc.addf("{$N", [])
  writeSection(initProc, cpsLocals)

  if m.initProc.s(cpsInit).buf.len > 0 or m.initProc.s(cpsStmts).buf.len > 0:
    moduleInitRequired = true
    if optStackTrace in m.initProc.options and frameDeclared notin m.flags:
      # BUT: the generated init code might depend on a current frame, so
      # declare it nevertheless:
      incl m.flags, frameDeclared
      if preventStackTrace notin m.flags:
        var procname = makeCString(m.module.name.s)
        prc.add(initFrame(m.initProc, procname, quotedFilename(m.config, m.module.info)))
      else:
        prc.add("\tTFrame FR_; FR_.len = 0;\n")

    writeSection(initProc, cpsInit, m.hcrOn)
    writeSection(initProc, cpsStmts)

    if beforeRetNeeded in m.initProc.flags:
      prc.add("\tBeforeRet_: ;\n")

    if m.config.exc == excGoto:
      if getCompilerProc(m.g.graph, "nimTestErrorFlag") != nil:
        m.appcg(prc, "\t#nimTestErrorFlag();$n", [])

    if optStackTrace in m.initProc.options and preventStackTrace notin m.flags:
      prc.add(deinitFrame(m.initProc))

  prc.addf("}$N", [])

  prc.addf("}$N$N", [])

  # we cannot simply add the init proc to ``m.s[cfsProcs]`` anymore because
  # that would lead to a *nesting* of merge sections which the merger does
  # not support. So we add it to another special section: ``cfsInitProc``

  if m.hcrOn:
    var procsToLoad = @["hcrRegisterProc", "hcrGetProc", "hcrRegisterGlobal", "hcrGetGlobal"]

    m.s[cfsInitProc].addf("N_LIB_EXPORT N_NIMCALL(void, $1)(void* handle, N_NIMCALL_PTR(void*, getProcAddr)(void*, char*)) {$N", [getHcrInitName(m)])
    if sfMainModule in m.module.flags:
      # additional procs to load
      procsToLoad.add("hcrInit")
      procsToLoad.add("hcrAddModule")
    # load procs
    for curr in procsToLoad:
      m.s[cfsInitProc].add(hcrGetProcLoadCode(m, curr, "", "handle", "getProcAddr"))
    m.s[cfsInitProc].addf("}$N$N", [])

  for i, el in pairs(m.extensionLoaders):
    if el != "":
      let ex = "NIM_EXTERNC N_NIMCALL(void, nimLoadProcs$1)(void) {$2}$N$N" %
        [(i.ord - '0'.ord).rope, el]
      moduleInitRequired = true
      prc.add(ex)

  if moduleInitRequired or sfMainModule in m.module.flags:
    m.s[cfsInitProc].add(extract(prc))
    #rememberFlag(m.g.graph, m.module, HasModuleInitProc)

  genDatInitCode(m)

  if m.hcrOn:
    m.s[cfsInitProc].addf("N_LIB_EXPORT N_NIMCALL(void, HcrCreateTypeInfos)(void) {$N", [])
    m.s[cfsInitProc].add(extract(m.hcrCreateTypeInfosProc))
    m.s[cfsInitProc].addf("}$N$N", [])

  registerModuleToMain(m.g, m)

proc postprocessCode(conf: ConfigRef, r: var Rope) =
  # find the first directive
  var f = r.find(postprocessDirStart)
  if f == -1:
    return

  var
    nimlnDirLastF = ""

  var res: Rope = r.substr(0, f - 1)
  while f != -1:
    var
      e = r.find(postprocessDirEnd, f + 1)
      dir = r.substr(f + 1, e - 1).split(postprocessDirSep)
    case dir[0]
    of "nimln":
      if dir[2] == nimlnDirLastF:
        res.add("nimln_(" & dir[1] & ");")
      else:
        res.add("nimlf_(" & dir[1] & ", " & quotedFilename(conf, dir[2].parseInt.FileIndex) & ");")
        nimlnDirLastF = dir[2]
    else:
      raiseAssert "unexpected postprocess directive"

    # find the next directive
    f = r.find(postprocessDirStart, e + 1)
    # copy the code until the next directive
    if f != -1:
      res.add(r.substr(e + 1, f - 1))
    else:
      res.add(r.substr(e + 1))

  r = res

proc genModule(m: BModule, cfile: Cfile): Rope =
  var moduleIsEmpty = true

  var res = newBuilder(getFileHeader(m.config, cfile))

  generateThreadLocalStorage(m)
  generateHeaders(m)
  res.add(extract(m.s[cfsHeaders]))
  if m.config.cppCustomNamespace.len > 0:
    openNamespaceNim(m.config.cppCustomNamespace, res)
  if m.s[cfsFrameDefines].buf.len > 0:
    res.add(extract(m.s[cfsFrameDefines]))

  for i in cfsForwardTypes..cfsProcs:
    if m.s[i].buf.len > 0:
      moduleIsEmpty = false
      res.add(extract(m.s[i]))

  if m.s[cfsInitProc].buf.len > 0:
    moduleIsEmpty = false
    res.add(extract(m.s[cfsInitProc]))
  if m.s[cfsDatInitProc].buf.len > 0 or m.hcrOn:
    moduleIsEmpty = false
    res.add(extract(m.s[cfsDatInitProc]))

  if m.config.cppCustomNamespace.len > 0:
    closeNamespaceNim(res)

  result = extract(res)
  if optLineDir in m.config.options:
    var srcFileDefs = ""
    for fi in 0..m.config.m.fileInfos.high:
      srcFileDefs.add("#define FX_" & $fi & " " & makeSingleLineCString(toFullPath(m.config, fi.FileIndex)) & "\n")
    result = srcFileDefs & result

  if moduleIsEmpty:
    result = ""

  postprocessCode(m.config, result)

proc initProcOptions(m: BModule): TOptions =
  let opts = m.config.options
  if sfSystemModule in m.module.flags: opts-{optStackTrace} else: opts

proc rawNewModule(g: BModuleList; module: PSym, filename: AbsoluteFile): BModule =
  new(result)
  result.g = g
  result.tmpBase = rope("TM" & $hashOwner(module) & "_")
  result.headerFiles = @[]
  result.declaredThings = initIntSet()
  result.declaredProtos = initIntSet()
  result.cfilename = filename
  result.filename = filename
  result.typeCache = initTable[SigHash, Rope]()
  result.forwTypeCache = initTable[SigHash, Rope]()
  result.module = module
  result.typeInfoMarker = initTable[SigHash, Rope]()
  result.sigConflicts = initCountTable[SigHash]()
  result.initProc = newProc(nil, result)
  for i in low(result.s)..high(result.s): result.s[i] = newBuilder("")
  result.initProc.options = initProcOptions(result)
  result.preInitProc = newProc(nil, result)
  result.preInitProc.flags.incl nimErrorFlagDisabled
  result.preInitProc.labels = 100_000 # little hack so that unique temporaries are generated
  result.hcrCreateTypeInfosProc = newBuilder("")
  result.dataCache = initNodeTable()
  result.typeStack = @[]
  result.typeNodesName = getTempName(result)
  result.nimTypesName = getTempName(result)
  # no line tracing for the init sections of the system module so that we
  # don't generate a TFrame which can confuse the stack bottom initialization:
  if sfSystemModule in module.flags:
    incl result.flags, preventStackTrace
    excl(result.preInitProc.options, optStackTrace)

proc rawNewModule(g: BModuleList; module: PSym; conf: ConfigRef): BModule =
  result = rawNewModule(g, module, AbsoluteFile toFullPath(conf, module.position.FileIndex))

proc newModule*(g: BModuleList; module: PSym; conf: ConfigRef): BModule =
  # we should create only one cgen module for each module sym
  result = rawNewModule(g, module, conf)
  if module.position >= g.modules.len:
    setLen(g.modules, module.position + 1)
  #growCache g.modules, module.position
  g.modules[module.position] = result

template injectG() {.dirty.} =
  if graph.backend == nil:
    graph.backend = newModuleList(graph)
  let g = BModuleList(graph.backend)

proc setupCgen*(graph: ModuleGraph; module: PSym; idgen: IdGenerator): PPassContext =
  injectG()
  result = newModule(g, module, graph.config)
  result.idgen = idgen
  if optGenIndex in graph.config.globalOptions and g.generatedHeader == nil:
    let f = if graph.config.headerFile.len > 0: AbsoluteFile graph.config.headerFile
            else: graph.config.projectFull
    g.generatedHeader = rawNewModule(g, module,
      changeFileExt(completeCfilePath(graph.config, f), hExt))
    incl g.generatedHeader.flags, isHeaderFile

proc writeHeader(m: BModule) =
  var result = newBuilder(headerTop())
  var guard = "__$1__" % [m.filename.splitFile.name.rope]
  result.addf("#ifndef $1$n#define $1$n", [guard])
  addNimDefines(result, m.config)
  generateHeaders(m)

  generateThreadLocalStorage(m)
  for i in cfsHeaders..cfsProcs:
    result.add(extract(m.s[i]))
    if m.config.cppCustomNamespace.len > 0 and i == cfsHeaders:
      openNamespaceNim(m.config.cppCustomNamespace, result)
  result.add(extract(m.s[cfsInitProc]))

  if optGenDynLib in m.config.globalOptions:
    result.add("N_LIB_IMPORT ")
  result.addf("N_CDECL(void, $1NimMain)(void);$n", [rope m.config.nimMainPrefix])
  if m.config.cppCustomNamespace.len > 0: closeNamespaceNim(result)
  result.addf("#endif /* $1 */$n", [guard])
  if not writeRope(extract(result), m.filename):
    rawMessage(m.config, errCannotOpenFile, m.filename.string)

proc getCFile(m: BModule): AbsoluteFile =
  let ext =
      if m.compileToCpp: ".nim.cpp"
      elif m.config.backend == backendObjc or sfCompileToObjc in m.module.flags: ".nim.m"
      else: ".nim.c"
  result = changeFileExt(completeCfilePath(m.config, mangleModuleName(m.config, m.cfilename).AbsoluteFile), ext)

when false:
  proc myOpenCached(graph: ModuleGraph; module: PSym, rd: PRodReader): PPassContext =
    injectG()
    var m = newModule(g, module, graph.config)
    readMergeInfo(getCFile(m), m)
    result = m

proc addHcrInitGuards(p: BProc, n: PNode, inInitGuard: var bool, init: var IfBuilder) =
  if n.kind == nkStmtList:
    for child in n:
      addHcrInitGuards(p, child, inInitGuard, init)
  else:
    let stmtShouldExecute = n.kind in {nkVarSection, nkLetSection} or
                            nfExecuteOnReload in n.flags
    if inInitGuard:
      if stmtShouldExecute:
        endBlockWith(p):
          finishBranch(p.s(cpsStmts), init)
          finishIfStmt(p.s(cpsStmts), init)
        inInitGuard = false
    else:
      if not stmtShouldExecute:
        startBlockWith(p):
          init = initIfStmt(p.s(cpsStmts))
          initElifBranch(p.s(cpsStmts), init, "nim_hcr_do_init_")
        inInitGuard = true

    genStmts(p, n)

proc genTopLevelStmt*(m: BModule; n: PNode) =
  ## Also called from `ic/cbackend.nim`.
  if pipelineutils.skipCodegen(m.config, n): return
  m.initProc.options = initProcOptions(m)
  #softRnl = if optLineDir in m.config.options: noRnl else: rnl
  # XXX replicate this logic!
  var transformedN = transformStmt(m.g.graph, m.idgen, m.module, n)
  if sfInjectDestructors in m.module.flags:
    transformedN = injectDestructorCalls(m.g.graph, m.idgen, m.module, transformedN)

  if m.hcrOn:
    addHcrInitGuards(m.initProc, transformedN, m.inHcrInitGuard, m.hcrInitGuard)
  else:
    genProcBody(m.initProc, transformedN)

proc shouldRecompile(m: BModule; code: Rope, cfile: Cfile): bool =
  if optForceFullMake notin m.config.globalOptions:
    if not moduleHasChanged(m.g.graph, m.module):
      result = false
    elif not equalsFile(code, cfile.cname):
      when false:
        #m.config.symbolFiles == readOnlySf: #isDefined(m.config, "nimdiff"):
        if fileExists(cfile.cname):
          copyFile(cfile.cname.string, cfile.cname.string & ".backup")
          echo "diff ", cfile.cname.string, ".backup ", cfile.cname.string
        else:
          echo "new file ", cfile.cname.string
      if not writeRope(code, cfile.cname):
        rawMessage(m.config, errCannotOpenFile, cfile.cname.string)
      result = true
    elif fileExists(cfile.obj) and os.fileNewer(cfile.obj.string, cfile.cname.string):
      result = false
    else:
      result = true
  else:
    if not writeRope(code, cfile.cname):
      rawMessage(m.config, errCannotOpenFile, cfile.cname.string)
    result = true

# We need 2 different logics here: pending modules (including
# 'nim__dat') may require file merging for the combination of dead code
# elimination and incremental compilation! Non pending modules need no
# such logic and in fact the logic hurts for the main module at least;
# it would generate multiple 'main' procs, for instance.

proc writeModule(m: BModule, pending: bool) =
  let cfile = getCFile(m)
  if moduleHasChanged(m.g.graph, m.module):
    genInitCode(m)
    finishTypeDescriptions(m)
    if sfMainModule in m.module.flags:
      # generate main file:
      genMainProc(m)
      m.s[cfsProcHeaders].add(m.g.mainModProcs)
      generateThreadVarsSize(m)

  var cf = Cfile(nimname: m.module.name.s, cname: cfile,
                  obj: completeCfilePath(m.config, toObjFile(m.config, cfile)), flags: {})
  var code = genModule(m, cf)
  if code != "" or m.config.symbolFiles != disabledSf:
    when hasTinyCBackend:
      if m.config.cmd == cmdTcc:
        tccgen.compileCCode($code, m.config)
        return

    if not shouldRecompile(m, code, cf): cf.flags = {CfileFlag.Cached}
    addFileToCompile(m.config, cf)

proc updateCachedModule(m: BModule) =
  let cfile = getCFile(m)
  var cf = Cfile(nimname: m.module.name.s, cname: cfile,
                 obj: completeCfilePath(m.config, toObjFile(m.config, cfile)), flags: {})
  if sfMainModule notin m.module.flags:
    genMainProc(m)
  cf.flags = {CfileFlag.Cached}
  addFileToCompile(m.config, cf)

proc generateLibraryDestroyGlobals(graph: ModuleGraph; m: BModule; body: PNode; isDynlib: bool): PSym =
  let procname = getIdent(graph.cache, "NimDestroyGlobals")
  result = newSym(skProc, procname, m.idgen, m.module.owner, m.module.info)
  result.typ = newProcType(m.module.info, m.idgen, m.module.owner)
  result.typ.callConv = ccCDecl
  incl result.flags, sfExportc
  result.loc.snippet = "NimDestroyGlobals"
  if isDynlib:
    incl(result.loc.flags, lfExportLib)

  let theProc = newNodeI(nkProcDef, m.module.info, bodyPos+1)
  for i in 0..<theProc.len: theProc[i] = newNodeI(nkEmpty, m.module.info)
  theProc[namePos] = newSymNode(result)
  theProc[bodyPos] = body
  result.ast = theProc

proc finalCodegenActions*(graph: ModuleGraph; m: BModule; n: PNode) =
  ## Also called from IC.
  if sfMainModule in m.module.flags:
    # phase ordering problem here: We need to announce this
    # dependency to 'nimTestErrorFlag' before system.c has been written to disk.
    if m.config.exc == excGoto and getCompilerProc(graph, "nimTestErrorFlag") != nil:
      cgsym(m, "nimTestErrorFlag")

    if {optGenStaticLib, optGenDynLib, optNoMain} * m.config.globalOptions == {}:
      for i in countdown(high(graph.globalDestructors), 0):
        n.add graph.globalDestructors[i]
    else:
      var body = newNodeI(nkStmtList, m.module.info)
      for i in countdown(high(graph.globalDestructors), 0):
        body.add graph.globalDestructors[i]
      body.flags.incl nfTransf # should not be further transformed
      let dtor = generateLibraryDestroyGlobals(graph, m, body, optGenDynLib in m.config.globalOptions)
      genProcAux(m, dtor)
  if pipelineutils.skipCodegen(m.config, n): return
  if moduleHasChanged(graph, m.module):
    # if the module is cached, we don't regenerate the main proc
    # nor the dispatchers? But if the dispatchers changed?
    # XXX emit the dispatchers into its own .c file?
    if n != nil:
      m.initProc.options = initProcOptions(m)
      genProcBody(m.initProc, n)

    if m.hcrOn:
      # make sure this is pulled in (meaning hcrGetGlobal() is called for it during init)
      let sym = magicsys.getCompilerProc(m.g.graph, "programResult")
      # ignore when not available, could be a module imported early in `system`
      if sym != nil:
        cgsymImpl m, sym
      if m.inHcrInitGuard:
        endBlockWith(m.initProc):
          finishBranch(m.initProc.s(cpsStmts), m.hcrInitGuard)
          finishIfStmt(m.initProc.s(cpsStmts), m.hcrInitGuard)

    if sfMainModule in m.module.flags:
      if m.hcrOn:
        # pull ("define" since they are inline when HCR is on) these functions in the main file
        # so it can load the HCR runtime and later pass the library handle to the HCR runtime which
        # will in turn pass it to the other modules it initializes so they can initialize the
        # register/get procs so they don't have to have the definitions of these functions as well
        cgsym(m, "nimLoadLibrary")
        cgsym(m, "nimLoadLibraryError")
        cgsym(m, "nimGetProcAddr")
        cgsym(m, "procAddrError")
        cgsym(m, "rawWrite")

      # raise dependencies on behalf of genMainProc
      if m.config.target.targetOS != osStandalone and m.config.selectedGC notin {gcNone, gcArc, gcAtomicArc, gcOrc}:
        cgsym(m, "initStackBottomWith")
      if emulatedThreadVars(m.config) and m.config.target.targetOS != osStandalone:
        cgsym(m, "initThreadVarsEmulation")

      if m.g.forwardedProcs.len == 0:
        incl m.flags, objHasKidsValid
      if optMultiMethods in m.g.config.globalOptions or
          m.g.config.selectedGC notin {gcArc, gcOrc, gcAtomicArc} or
          vtables notin m.g.config.features:
        generateIfMethodDispatchers(graph, m.idgen)


  let mm = m
  m.g.modulesClosed.add mm

proc genForwardedProcs(g: BModuleList) =
  # Forward declared proc:s lack bodies when first encountered, so they're given
  # a second pass here
  # Note: ``genProcNoForward`` may add to ``forwardedProcs``
  while g.forwardedProcs.len > 0:
    let
      prc = g.forwardedProcs.pop()
      m = g.modules[prc.itemId.module]
    if sfForward in prc.flags:
      internalError(m.config, prc.info, "still forwarded: " & prc.name.s)

    genProcNoForward(m, prc)

proc cgenWriteModules*(backend: RootRef, config: ConfigRef) =
  let g = BModuleList(backend)
  g.config = config

  # we need to process the transitive closure because recursive module
  # deps are allowed (and the system module is processed in the wrong
  # order anyway)
  genForwardedProcs(g)

  for m in cgenModules(g):
    m.writeModule(pending=true)
  writeMapping(config, g.mapping)
  if g.generatedHeader != nil: writeHeader(g.generatedHeader)
