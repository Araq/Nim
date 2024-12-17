#
#
#           The Nim Compiler
#        (c) Copyright 2022 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Package related procs.
##
## See Also:
## * `packagehandling` for package path handling
## * `modulegraphs.getPackage`
## * `modulegraphs.belongsToStdlib`

import "." / [options, ast, lineinfos, idents, pathutils, msgs]

when defined(nimPreviewSlimSystem):
  import std/assertions


proc getPackage*(conf: ConfigRef; cache: IdentCache; fileIdx: FileIndex): PSym =
  ## Return a new package symbol.
  ##
  ## See Also:
  ## * `modulegraphs.getPackage`
  let
    filename = AbsoluteFile toFullPath(conf, fileIdx)
    name = getIdent(cache, splitFile(filename).name)
    info = newLineInfo(fileIdx, 1, 1)
    pkgName = getPackageName(conf, filename.string)
    pkgIdent = getIdent(cache, pkgName)
  newSym(skPackage, pkgIdent, idGeneratorForPackage(int32(fileIdx)), nil, info)

func getPackageSymbol*(sym: PSym): PSym =
  ## Return the owning package symbol.
  assert sym != nil
  result = sym
  while result.kind != skPackage:
    result = result.owner
    assert result != nil, repr(sym.info)

func getPackageId*(sym: PSym): int =
  ## Return the owning package ID.
  sym.getPackageSymbol.id

func belongsToProjectPackage*(conf: ConfigRef, sym: PSym): bool =
  ## Return whether the symbol belongs to the project's package.
  ##
  ## See Also:
  ## * `modulegraphs.belongsToStdlib`
  conf.mainPackageId == sym.getPackageId

func belongsToProjectPackageMaybeNil*(conf: ConfigRef, sym: PSym): bool =
  ## Return whether the symbol belongs to the project's package.
  ## Returns `false` if `sym` is nil.
  ##
  ## See Also:
  ## * `modulegraphs.belongsToStdlib`
  sym != nil and conf.mainPackageId == sym.getPackageId
