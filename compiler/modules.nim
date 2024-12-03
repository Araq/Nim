#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Implements the module handling, including the caching of modules.

import
  ast, magicsys, msgs, options,
  idents, lexer, syntaxes, modulegraphs,
  lineinfos, pathutils

import ../dist/checksums/src/checksums/sha1
import std/strtabs

proc resetSystemArtifacts*(g: ModuleGraph) =
  magicsys.resetSysTypes(g)

template getModuleIdent(graph: ModuleGraph, filename: AbsoluteFile): PIdent =
  getIdent(graph.cache, splitFile(filename).name)

proc partialInitModule*(result: PSym; graph: ModuleGraph; fileIdx: FileIndex; filename: AbsoluteFile) =
  let packSym = getPackage(graph, fileIdx)
  setOwner(result, packSym)
  result.position = int fileIdx

proc newModule*(graph: ModuleGraph; fileIdx: FileIndex): PSym =
  let filename = AbsoluteFile toFullPath(graph.config, fileIdx)
  # We cannot call ``newSym`` here, because we have to circumvent the ID
  # mechanism, which we do in order to assign each module a persistent ID.
  result = PSym(kind: skModule, itemId: ItemId(module: int32(fileIdx), item: 0'i32),
                name: getModuleIdent(graph, filename),
                info: newLineInfo(fileIdx, 1, 1))
  if not isNimIdentifier(result.name.s):
    rawMessage(graph.config, errGenerated, "invalid module name: '" & result.name.s &
              "'; a module name must be a valid Nim identifier.")
  partialInitModule(result, graph, fileIdx, filename)
  graph.registerModule(result)

proc includeModule*(graph: ModuleGraph; s: PSym, fileIdx: FileIndex): PNode =
  result = syntaxes.parseFile(fileIdx, graph.cache, graph.config)
  graph.addDep(s, fileIdx)
  graph.addIncludeDep(s.position.FileIndex, fileIdx)
  let path = toFullPath(graph.config, fileIdx)
  graph.cachedFiles[path] = $secureHashFile(path)

proc wantMainModule*(conf: ConfigRef) =
  if conf.projectFull.isEmpty:
    fatal(conf, gCmdLineInfo, "command expects a filename")
  conf.projectMainIdx = fileInfoIdx(conf, addFileExt(conf.projectFull, NimExt))

proc makeModule*(graph: ModuleGraph; filename: AbsoluteFile): PSym =
  result = graph.newModule(fileInfoIdx(graph.config, filename))
  registerModule(graph, result)

proc makeModule*(graph: ModuleGraph; filename: string): PSym =
  result = makeModule(graph, AbsoluteFile filename)

proc makeStdinModule*(graph: ModuleGraph): PSym = graph.makeModule(AbsoluteFile"stdin")
