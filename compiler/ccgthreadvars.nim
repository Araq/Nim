#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Thread var support for architectures that lack native support for
## thread local storage.

# included from cgen.nim

proc emulatedThreadVars(conf: ConfigRef): bool =
  result = {optThreads, optTlsEmulation} <= conf.globalOptions

proc accessThreadLocalVar(p: BProc, s: PSym) =
  if emulatedThreadVars(p.config) and threadVarAccessed notin p.flags:
    p.flags.incl threadVarAccessed
    incl p.module.flags, usesThreadVars
    p.procSec(cpsLocals).addVar(kind = Local,
      name = "NimTV_",
      typ = ptrType("NimThreadVars"))
    p.procSec(cpsInit).addAssignment("NimTV_",
      cCast(ptrType("NimThreadVars"),
        cCall(cgsymValue(p.module, "GetThreadLocalVars"))))

proc declareThreadVar(m: BModule, s: PSym, isExtern: bool) =
  if emulatedThreadVars(m.config):
    # we gather all thread locals var into a struct; we need to allocate
    # storage for that somehow, can't use the thread local storage
    # allocator for it :-(
    if not containsOrIncl(m.g.nimtvDeclared, s.id):
      m.g.nimtvDeps.add(s.loc.t)
      m.g.nimtv.addField(name = s.loc.snippet, typ = getTypeDesc(m, s.loc.t))
  else:
    let vis =
      if isExtern: Extern
      elif lfExportLib in s.loc.flags: ExportLibVar
      else: Private
    m.s[cfsVars].addVar(m, s,
      name = s.loc.snippet,
      typ = getTypeDesc(m, s.loc.t),
      kind = Threadvar,
      visibility = vis)

proc generateThreadLocalStorage(m: BModule) =
  if m.g.nimtv.buf.len != 0 and (usesThreadVars in m.flags or sfMainModule in m.module.flags):
    for t in items(m.g.nimtvDeps): discard getTypeDesc(m, t)
    finishTypeDescriptions(m)
    m.s[cfsSeqTypes].addTypedef(name = "NimThreadVars"):
      m.s[cfsSeqTypes].addSimpleStruct(m, name = "", baseType = ""):
        m.s[cfsSeqTypes].add(extract(m.g.nimtv))

proc generateThreadVarsSize(m: BModule) =
  if m.g.nimtv.buf.len != 0:
    let externc = if m.config.backend == backendCpp or
                       sfCompileToCpp in m.module.flags: ExternC
                  else: None
    m.s[cfsProcs].addDeclWithVisibility(externc):
      m.s[cfsProcs].addProcHeaderWithParams(ccNoConvention, "NimThreadVarsSize", "NI"):
        var params: ProcParamBuilder
        m.s[cfsProcs].addProcParams(params):
          discard
      m.s[cfsProcs].finishProcHeaderWithBody():
        m.s[cfsProcs].addReturn(cCast("NI", cSizeof("NimThreadVars")))
