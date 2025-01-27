#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# Unfortunately this cannot be a module yet:
#import vmdeps, vm
from std/math import sqrt, ln, log10, log2, exp, round, arccos, arcsin,
  arctan, arctan2, cos, cosh, hypot, sinh, sin, tan, tanh, pow, trunc,
  floor, ceil, `mod`, cbrt, arcsinh, arccosh, arctanh, erf, erfc, gamma,
  lgamma, divmod
from std/sequtils import toSeq
when declared(math.copySign):
  # pending bug #18762, avoid renaming math
  from std/math as math2 import copySign

when declared(math.signbit):
  # ditto
  from std/math as math3 import signbit


from std/envvars import getEnv, existsEnv, delEnv, putEnv, envPairs
from std/os import getAppFilename
from std/private/oscommon import dirExists, fileExists
from std/private/osdirs import walkDir, createDir
from std/private/ospaths2 import getCurrentDir

from std/times import cpuTime
from std/hashes import hash
from std/osproc import nil


when defined(nimPreviewSlimSystem):
  import std/syncio
else:
  from std/formatfloat import addFloatRoundtrip, addFloatSprintf


# There are some useful procs in vmconv.
import vmconv, vmmarshal

template mathop(op) {.dirty.} =
  registerCallback(c, "stdlib.math." & astToStr(op), `op Wrapper`)

template osop(op) {.dirty.} =
  registerCallback(c, "stdlib.os." & astToStr(op), `op Wrapper`)

template oscommonop(op) {.dirty.} =
  registerCallback(c, "stdlib.oscommon." & astToStr(op), `op Wrapper`)

template osdirsop(op) {.dirty.} =
  registerCallback(c, "stdlib.osdirs." & astToStr(op), `op Wrapper`)

template envvarsop(op) {.dirty.} =
  registerCallback(c, "stdlib.envvars." & astToStr(op), `op Wrapper`)

template timesop(op) {.dirty.} =
  registerCallback(c, "stdlib.times." & astToStr(op), `op Wrapper`)

template systemop(op) {.dirty.} =
  registerCallback(c, "stdlib.system." & astToStr(op), `op Wrapper`)

template ioop(op) {.dirty.} =
  registerCallback(c, "stdlib.syncio." & astToStr(op), `op Wrapper`)

template macrosop(op) {.dirty.} =
  registerCallback(c, "stdlib.macros." & astToStr(op), `op Wrapper`)

template wrap1fMath(op) {.dirty.} =
  proc `op Wrapper`(a: VmArgs) {.nimcall.} =
    doAssert a.numArgs == 1
    setResult(a, op(getFloat(a, 0)))
  mathop op

template wrap2fMath(op) {.dirty.} =
  proc `op Wrapper`(a: VmArgs) {.nimcall.} =
    setResult(a, op(getFloat(a, 0), getFloat(a, 1)))
  mathop op

template wrap2iMath(op) {.dirty.} =
  proc `op Wrapper`(a: VmArgs) {.nimcall.} =
    setResult(a, op(getInt(a, 0), getInt(a, 1)))
  mathop op

template wrap0(op, modop) {.dirty.} =
  proc `op Wrapper`(a: VmArgs) {.nimcall.} =
    setResult(a, op())
  modop op

template wrap1s(op, modop) {.dirty.} =
  proc `op Wrapper`(a: VmArgs) {.nimcall.} =
    setResult(a, op(getString(a, 0)))
  modop op

template wrap2s(op, modop) {.dirty.} =
  proc `op Wrapper`(a: VmArgs) {.nimcall.} =
    setResult(a, op(getString(a, 0), getString(a, 1)))
  modop op

template wrap2si(op, modop) {.dirty.} =
  proc `op Wrapper`(a: VmArgs) {.nimcall.} =
    setResult(a, op(getString(a, 0), getInt(a, 1)))
  modop op

template wrap1svoid(op, modop) {.dirty.} =
  proc `op Wrapper`(a: VmArgs) {.nimcall.} =
    op(getString(a, 0))
  modop op

template wrap2svoid(op, modop) {.dirty.} =
  proc `op Wrapper`(a: VmArgs) {.nimcall.} =
    op(getString(a, 0), getString(a, 1))
  modop op

template wrapDangerous1svoid(op, modop) {.dirty.} =
  if vmopsDanger notin c.config.features and (defined(nimsuggest) or c.config.cmd == cmdCheck):
    proc `op Wrapper`(a: VmArgs) {.nimcall.} =
      discard
    modop op
  else:
    proc `op Wrapper`(a: VmArgs) {.nimcall.} =
      op(getString(a, 0))
    modop op

template wrapDangerous2svoid(op, modop) {.dirty.} =
  if vmopsDanger notin c.config.features and (defined(nimsuggest) or c.config.cmd == cmdCheck):
    proc `op Wrapper`(a: VmArgs) {.nimcall.} =
      discard
    modop op
  else:
    proc `op Wrapper`(a: VmArgs) {.nimcall.} =
      op(getString(a, 0), getString(a, 1))
    modop op

proc getCurrentExceptionMsgWrapper(a: VmArgs) {.nimcall.} =
  setResult(a, if a.currentException.isNil: ""
               else: a.currentException[3].skipColon.strVal)

proc getCurrentExceptionWrapper(a: VmArgs) {.nimcall.} =
  setResult(a, a.currentException)

proc staticWalkDirImpl(path: string, relative: bool): PNode =
  result = newNode(nkBracket)
  for k, f in walkDir(path, relative):
    result.add toLit((k, f))

from std / compilesettings import SingleValueSetting, MultipleValueSetting

proc querySettingImpl(conf: ConfigRef, switch: BiggestInt): string =
  {.push warning[Deprecated]:off.}
  case SingleValueSetting(switch)
  of arguments: result = conf.arguments
  of outFile: result = conf.outFile.string
  of outDir: result = conf.outDir.string
  of nimcacheDir: result = conf.getNimcacheDir().string
  of projectName: result = conf.projectName
  of projectPath: result = conf.projectPath.string
  of projectFull: result = conf.projectFull.string
  of command: result = conf.command
  of commandLine: result = conf.commandLine
  of linkOptions: result = conf.linkOptions
  of compileOptions: result = conf.compileOptions
  of ccompilerPath: result = conf.cCompilerPath
  of backend: result = $conf.backend
  of libPath: result = conf.libpath.string
  of gc: result = $conf.selectedGC
  of mm: result = $conf.selectedGC
  {.pop.}

proc querySettingSeqImpl(conf: ConfigRef, switch: BiggestInt): seq[string] =
  template copySeq(field: untyped): untyped =
    result = @[]
    for i in field: result.add i.string

  case MultipleValueSetting(switch)
  of nimblePaths: copySeq(conf.nimblePaths)
  of searchPaths: copySeq(conf.searchPaths)
  of lazyPaths: copySeq(conf.lazyPaths)
  of commandArgs: result = conf.commandArgs
  of cincludes: copySeq(conf.cIncludes)
  of clibs: copySeq(conf.cLibs)

proc stackTrace2(c: PCtx, msg: string, n: PNode) =
  stackTrace(c, PStackFrame(prc: c.prc.sym, comesFrom: 0, next: nil), c.exceptionInstr, msg, n.info)


proc registerAdditionalOps*(c: PCtx) =

  template wrapIterator(fqname: string, iter: untyped) =
    registerCallback c, fqname, proc(a: VmArgs) =
      setResult(a, toLit(toSeq(iter)))


  proc gorgeExWrapper(a: VmArgs) =
    let ret = opGorge(getString(a, 0), getString(a, 1), getString(a, 2),
                         a.currentLineInfo, c.config)
    setResult a, ret.toLit

  proc getProjectPathWrapper(a: VmArgs) =
    setResult a, c.config.projectPath.string

  wrap1fMath(sqrt)
  wrap1fMath(cbrt)
  wrap1fMath(ln)
  wrap1fMath(log10)
  wrap1fMath(log2)
  wrap1fMath(exp)
  wrap1fMath(arccos)
  wrap1fMath(arcsin)
  wrap1fMath(arctan)
  wrap1fMath(arcsinh)
  wrap1fMath(arccosh)
  wrap1fMath(arctanh)
  wrap2fMath(arctan2)
  wrap1fMath(cos)
  wrap1fMath(cosh)
  wrap2fMath(hypot)
  wrap1fMath(sinh)
  wrap1fMath(sin)
  wrap1fMath(tan)
  wrap1fMath(tanh)
  wrap2fMath(pow)
  wrap1fMath(trunc)
  wrap1fMath(floor)
  wrap1fMath(ceil)
  wrap1fMath(erf)
  wrap1fMath(erfc)
  wrap1fMath(gamma)
  wrap1fMath(lgamma)
  wrap2iMath(divmod)

  when declared(copySign):
    wrap2fMath(copySign)

  when declared(signbit):
    wrap1fMath(signbit)

  registerCallback c, "stdlib.math.round", proc (a: VmArgs) {.nimcall.} =
    let n = a.numArgs
    case n
    of 1: setResult(a, round(getFloat(a, 0)))
    of 2: setResult(a, round(getFloat(a, 0), getInt(a, 1).int))
    else: raiseAssert $n

  proc `mod Wrapper`(a: VmArgs) {.nimcall.} =
    setResult(a, `mod`(getFloat(a, 0), getFloat(a, 1)))
  registerCallback(c, "stdlib.math.mod", `mod Wrapper`)

  when defined(nimcore):
    wrap2s(getEnv, envvarsop)
    wrap1s(existsEnv, envvarsop)
    wrap2svoid(putEnv, envvarsop)
    wrap1svoid(delEnv, envvarsop)
    wrap1s(dirExists, oscommonop)
    wrap1s(fileExists, oscommonop)
    wrapDangerous2svoid(writeFile, ioop)
    wrapDangerous1svoid(createDir, osdirsop)
    wrap1s(readFile, ioop)
    wrap2si(readLines, ioop)
    systemop getCurrentExceptionMsg
    systemop getCurrentException
    registerCallback c, "stdlib.staticos.staticWalkDir", proc (a: VmArgs) {.nimcall.} =
      setResult(a, staticWalkDirImpl(getString(a, 0), getBool(a, 1)))
    registerCallback c, "stdlib.staticos.staticDirExists", proc (a: VmArgs) {.nimcall.} =
      setResult(a, dirExists(getString(a, 0)))
    registerCallback c, "stdlib.staticos.staticFileExists", proc (a: VmArgs) {.nimcall.} =
      setResult(a, fileExists(getString(a, 0)))
    registerCallback c, "stdlib.compilesettings.querySetting", proc (a: VmArgs) =
      setResult(a, querySettingImpl(c.config, getInt(a, 0)))
    registerCallback c, "stdlib.compilesettings.querySettingSeq", proc (a: VmArgs) =
      setResult(a, querySettingSeqImpl(c.config, getInt(a, 0)))

    if defined(nimsuggest) or c.config.cmd == cmdCheck:
      discard "don't run staticExec for 'nim suggest'"
    else:
      systemop gorgeEx
  macrosop getProjectPath

  registerCallback c, "stdlib.os.getCurrentCompilerExe", proc (a: VmArgs) {.nimcall.} =
    setResult(a, getAppFilename())

  registerCallback c, "stdlib.macros.symBodyHash", proc (a: VmArgs) =
    let n = getNode(a, 0)
    if n.kind != nkSym:
      stackTrace2(c, "symBodyHash() requires a symbol. '$#' is of kind '$#'" % [$n, $n.kind], n)
    setResult(a, $symBodyDigest(c.graph, n.sym))

  registerCallback c, "stdlib.macros.isExported", proc(a: VmArgs) =
    let n = getNode(a, 0)
    if n.kind != nkSym:
      stackTrace2(c, "isExported() requires a symbol. '$#' is of kind '$#'" % [$n, $n.kind], n)
    setResult(a, sfExported in n.sym.flags)

  registerCallback c, "stdlib.macrocache.hasKey", proc (a: VmArgs) =
    let
      table = getString(a, 0)
      key = getString(a, 1)
    setResult(a, table in c.graph.cacheTables and key in c.graph.cacheTables[table])

  registerCallback c, "stdlib.vmutils.vmTrace", proc (a: VmArgs) =
    c.config.isVmTrace = getBool(a, 0)

  proc hashVmImpl(a: VmArgs) =
    var res = hashes.hash(a.getString(0), a.getInt(1).int, a.getInt(2).int)
    if c.config.backend == backendJs:
      # emulate JS's terrible integers:
      res = cast[int32](res)
    setResult(a, res)

  registerCallback c, "stdlib.hashes.hashVmImpl", hashVmImpl

  proc hashVmImplByte(a: VmArgs) =
    # nkBracket[...]
    let sPos = a.getInt(1).int
    let ePos = a.getInt(2).int
    let arr = a.getNode(0)
    var bytes = newSeq[byte](arr.len)
    for i in 0..<arr.len:
      bytes[i] = byte(arr[i].intVal and 0xff)

    var res = hashes.hash(bytes, sPos, ePos)
    if c.config.backend == backendJs:
      # emulate JS's terrible integers:
      res = cast[int32](res)
    setResult(a, res)

  registerCallback c, "stdlib.hashes.hashVmImplByte", hashVmImplByte
  registerCallback c, "stdlib.hashes.hashVmImplChar", hashVmImplByte

  if optBenchmarkVM in c.config.globalOptions or vmopsDanger in c.config.features:
    wrap0(cpuTime, timesop)
  else:
    proc cpuTime(): float = 5.391245e-44  # Randomly chosen
    wrap0(cpuTime, timesop)

  if vmopsDanger in c.config.features:
    ## useful procs but these should be opt-in because they may impact
    ## reproducible builds and users need to understand that this runs at CT.
    ## Note that `staticExec` can already do equal amount of damage so it's more
    ## of a semantic issue than a security issue.
    registerCallback c, "stdlib.ospaths2.getCurrentDir", proc (a: VmArgs) {.nimcall.} =
      setResult(a, getCurrentDir())
    registerCallback c, "stdlib.osproc.execCmdEx", proc (a: VmArgs) {.nimcall.} =
      let options = getNode(a, 1).fromLit(set[osproc.ProcessOption])
      a.setResult osproc.execCmdEx(getString(a, 0), options).toLit
    registerCallback c, "stdlib.times.getTimeImpl", proc (a: VmArgs) =
      let obj = a.getNode(0).typ.n
      setResult(a, times.getTime().toTimeLit(c, obj, a.currentLineInfo))

  proc getEffectList(c: PCtx; a: VmArgs; effectIndex: int) =
    let fn = getNode(a, 0)
    var list = newNodeI(nkBracket, fn.info)
    if fn.typ != nil and fn.typ.n != nil and fn.typ.n[0].len >= effectListLen and
        fn.typ.n[0][effectIndex] != nil:
      for e in fn.typ.n[0][effectIndex]:
        list.add opMapTypeInstToAst(c.cache, e.typ.skipTypes({tyRef}), e.info, c.idgen)
    else:
      list.add newIdentNode(getIdent(c.cache, "UncomputedEffects"), fn.info)

    setResult(a, list)

  registerCallback c, "stdlib.effecttraits.getRaisesListImpl", proc (a: VmArgs) =
    getEffectList(c, a, exceptionEffects)
  registerCallback c, "stdlib.effecttraits.getTagsListImpl", proc (a: VmArgs) =
    getEffectList(c, a, tagEffects)
  registerCallback c, "stdlib.effecttraits.getForbidsListImpl", proc (a: VmArgs) =
    getEffectList(c, a, forbiddenEffects)

  registerCallback c, "stdlib.effecttraits.isGcSafeImpl", proc (a: VmArgs) =
    let fn = getNode(a, 0)
    setResult(a, fn.typ != nil and tfGcSafe in fn.typ.flags)

  registerCallback c, "stdlib.effecttraits.hasNoSideEffectsImpl", proc (a: VmArgs) =
    let fn = getNode(a, 0)
    setResult(a, (fn.typ != nil and tfNoSideEffect in fn.typ.flags) or
                 (fn.kind == nkSym and fn.sym.kind == skFunc))

  registerCallback c, "stdlib.typetraits.hasClosureImpl", proc (a: VmArgs) =
    let fn = getNode(a, 0)
    setResult(a, fn.kind == nkClosure or (fn.typ != nil and fn.typ.callConv == ccClosure))

  registerCallback c, "stdlib.formatfloat.addFloatRoundtrip", proc(a: VmArgs) =
    let p = a.getVar(0)
    let x = a.getFloat(1)
    addFloatRoundtrip(p.strVal, x)

  registerCallback c, "stdlib.formatfloat.addFloatSprintf", proc(a: VmArgs) =
    let p = a.getVar(0)
    let x = a.getFloat(1)
    addFloatSprintf(p.strVal, x)

  registerCallback c, "stdlib.strutils.formatBiggestFloat", proc(a: VmArgs) =
    setResult(a, formatBiggestFloat(a.getFloat(0), FloatFormatMode(a.getInt(1)),
                                    a.getInt(2), chr(a.getInt(3))))

  wrapIterator("stdlib.envvars.envPairsImplSeq"): envPairs()

  registerCallback c, "stdlib.marshal.toVM", proc(a: VmArgs) =
    let typ = a.getNode(0).typ
    case typ.kind
    of tyInt..tyInt64, tyUInt..tyUInt64:
      setResult(a, loadAny(a.getString(1), typ, c.cache, c.config, c.idgen).intVal)
    of tyFloat..tyFloat128:
      setResult(a, loadAny(a.getString(1), typ, c.cache, c.config, c.idgen).floatVal)
    else:
      setResult(a, loadAny(a.getString(1), typ, c.cache, c.config, c.idgen))

  registerCallback c, "stdlib.marshal.loadVM", proc(a: VmArgs) =
    let typ = a.getNode(0).typ
    let p = a.getReg(1)
    var res: string = ""
    storeAny(res, typ, regToNode(p[]), c.config)
    setResult(a, res)
