#
#
#           The Nim Compiler
#        (c) Copyright 2017 Contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import ast, renderer, msgs, options, idents, lineinfos,
  pathutils

import std/[strutils, os]

proc getModuleName*(conf: ConfigRef; n: PNode): string =
  # This returns a short relative module name without the nim extension
  # e.g. like "system", "importer" or "somepath/module"
  # The proc won't perform any checks that the path is actually valid
  case n.kind
  of nkStrLit, nkRStrLit, nkTripleStrLit:
    try:
      result = pathSubs(conf, n.strVal, toFullPath(conf, n.info).splitFile().dir)
    except ValueError:
      localError(conf, n.info, "invalid path: " & n.strVal)
      result = n.strVal
  of nkIdent:
    result = n.ident.s
  of nkSym:
    result = n.sym.name.s
  of nkInfix:
    let n0 = n[0]
    let n1 = n[1]
    when false:
      if n1.kind == nkPrefix and n1[0].kind == nkIdent and n1[0].ident.s == "$":
        if n0.kind == nkIdent and n0.ident.s == "/":
          result = lookupPackage(n1[1], n[2])
        else:
          localError(n.info, "only '/' supported with $package notation")
          result = ""
    else:
      if n0.kind in nkIdentKinds:
        let ident = n0.getPIdent
        if ident != nil and ident.s[0] == '/':
          let modname = getModuleName(conf, n[2])
          # hacky way to implement 'x / y /../ z':
          result = getModuleName(conf, n1)
          result.add renderTree(n0, {renderNoComments}).replace(" ")
          result.add modname
        else:
          result = ""
      else:
        result = ""
  of nkPrefix:
    when false:
      if n[0].kind == nkIdent and n[0].ident.s == "$":
        result = lookupPackage(n[1], nil)
      else:
        discard
    # hacky way to implement 'x / y /../ z':
    result = renderTree(n, {renderNoComments}).replace(" ")
  of nkDotExpr:
    localError(conf, n.info, warnDeprecated, "using '.' instead of '/' in import paths is deprecated")
    result = renderTree(n, {renderNoComments}).replace(".", "/")
  of nkImportAs:
    result = getModuleName(conf, n[0])
  else:
    localError(conf, n.info, "invalid module name: '$1'" % n.renderTree)
    result = ""

proc checkModuleName*(conf: ConfigRef; n: PNode; doLocalError=true): FileIndex =
  # This returns the full canonical path for a given module import
  let modulename = getModuleName(conf, n)
  let fullPath = findModule(conf, modulename, toFullPath(conf, n.info))
  if fullPath.isEmpty:
    if doLocalError:
      let m = if modulename.len > 0: modulename else: $n
      localError(conf, n.info, "cannot open file: " & m)
    result = InvalidFileIdx
  else:
    result = fileInfoIdx(conf, fullPath)

proc mangleModuleName*(conf: ConfigRef; path: AbsoluteFile): string =
  ## Mangle a relative module path to avoid path and symbol collisions.
  ##
  ## Used by backends that need to generate intermediary files from Nim modules.
  ## This is needed because the compiler uses a flat cache file hierarchy.
  ##
  ## Example:
  ## `foo-#head/../bar` becomes `@foo-@hhead@s..@sbar`
  "@m" & relativeTo(path, conf.projectPath).string.multiReplace(
    {$os.DirSep: "@s", $os.AltSep: "@s", "#": "@h", "@": "@@", ":": "@c"})

proc demangleModuleName*(path: string): string =
  ## Demangle a relative module path.
  result = path.multiReplace({"@@": "@", "@h": "#", "@s": "/", "@m": "", "@c": ":"})
