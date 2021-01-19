#
#
#           The Nim Compiler
#        (c) Copyright 2021 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## New entry point into our C/C++ code generator. Ideally
## somebody would rewrite the old backend (which is 8000 lines of crufty Nim code)
## to work on packed trees directly and produce the C code as an AST which can
## then be rendered to text in a very simple manner. Unfortunately nobody wrote
## this code. So instead we wrap the existing cgen.nim and its friends so that
## we call directly into the existing code generation logic but avoiding the
## naive, outdated `passes` design. Thus you will see some
## `useAliveDataFromDce in flags` checks in the old code -- the old code is
## also doing cross-module dependency tracking and DCE that we don't need
## anymore. DCE is now done as prepass over the entire packed module graph.

import std / intsets
import ".." / [ast, options, lineinfos, modulegraphs, cgendata, cgen,
  pathutils, extccomp, msgs]

import packed_ast, to_packed_ast, bitabs, dce

proc unpackTree(g: ModuleGraph; thisModule: int;
                tree: PackedTree; n: NodePos): PNode =
  var decoder = initPackedDecoder(g.config, g.cache)
  result = loadNodes(decoder, g.packed, thisModule, tree, n)

proc generateCodeForModule(g: ModuleGraph; m: var LoadedModule; alive: var AliveSyms) =
  if g.backend == nil:
    g.backend = cgendata.newModuleList(g)

  var bmod = cgen.newModule(BModuleList(g.backend), m.module, g.config)
  bmod.idgen = idgenFromLoadedModule(m)
  bmod.flags.incl useAliveDataFromDce
  bmod.alive = move alive[m.module.position]

  for p in allNodes(m.fromDisk.topLevel):
    let n = unpackTree(g, m.module.position, m.fromDisk.topLevel, p)
    cgen.genTopLevelStmt(bmod, n)

  finalCodegenActions(g, bmod, newNodeI(nkStmtList, m.module.info))

proc addFileToLink(config: ConfigRef; m: PSym) =
  let filename = AbsoluteFile toFullPath(config, m.position.FileIndex)
  let ext =
      if config.backend == backendCpp: ".nim.cpp"
      elif config.backend == backendObjc: ".nim.m"
      else: ".nim.c"
  let cfile = changeFileExt(completeCfilePath(config, withPackageName(config, filename)), ext)
  var cf = Cfile(nimname: m.name.s, cname: cfile,
                 obj: completeCfilePath(config, toObjFile(config, cfile)),
                 flags: {CfileFlag.Cached})
  addFileToCompile(config, cf)

proc aliveSymsChanged(m: LoadedModule; alive: AliveSyms): bool =
  # XXX Todo.
  result = true

proc generateCode*(g: ModuleGraph) =
  ## The single entry point, generate C(++) code for the entire
  ## Nim program aka `ModuleGraph`.
  var alive = computeAliveSyms(g.packed, g.config)

  for i in 0..high(g.packed):
    # case statement here to enforce exhaustive checks.
    case g.packed[i].status
    of undefined:
      discard "nothing to do"
    of loading:
      assert false
    of storing, outdated:
      generateCodeForModule(g, g.packed[i], alive)
    of loaded:
      # Even though this module didn't change, DCE might trigger a change.
      # Consider this case: Module A uses symbol S from B and B does not use
      # S itself. A is then edited not to use S either. Thus we have to
      # recompile B in order to remove S from the final result.
      if aliveSymsChanged(g.packed[i], alive):
        generateCodeForModule(g, g.packed[i], alive)
      else:
        addFileToLink(g.config, g.packed[i].module)

