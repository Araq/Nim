# this module avoids ast depending on msgs or vice versa
import std/strutils
import options, ast, msgs

proc typSym*(t: PType): PSym =
  result = t.sym
  if result == nil and t.kind == tyGenericInst: # this might need to be refined
    result = t.genericHead.sym

proc addDeclaredLoc*(result: var string, conf: ConfigRef; sym: PSym) =
  result.add " [$1 declared in $2]" % [sym.kind.toHumanStr, toFileLineCol(conf, sym.info)]

proc addDeclaredLocMaybe*(result: var string, conf: ConfigRef; sym: PSym) =
  if optDeclaredLocs in conf.globalOptions and sym != nil:
    addDeclaredLoc(result, conf, sym)

proc addDeclaredLoc*(result: var string, conf: ConfigRef; typ: PType) =
  # xxx figure out how to resolve `tyGenericParam`, e.g. for
  # proc fn[T](a: T, b: T) = discard
  # fn(1.1, "a")
  let typ = typ.skipTypes(abstractInst + {tyStatic, tySequence, tyArray, tySet, tyUserTypeClassInst, tyVar, tyRef, tyPtr} - {tyRange})
  result.add " [$1" % typ.kind.toHumanStr
  if typ.sym != nil:
    result.add " declared in " & toFileLineCol(conf, typ.sym.info)
  result.add "]"

proc addTypeNodeDeclaredLoc*(result: var string, conf: ConfigRef; typ: PType) =
  result.add " [$1" % typ.kind.toHumanStr
  if typ.sym != nil:
    result.add " declared in " & toFileLineCol(conf, typ.sym.info)
  result.add "]"

proc addDeclaredLocMaybe*(result: var string, conf: ConfigRef; typ: PType) =
  if optDeclaredLocs in conf.globalOptions: addDeclaredLoc(result, conf, typ)

template quoteExpr*(a: string): untyped =
  ## can be used for quoting expressions in error msgs.
  "'" & a & "'"

proc genFieldDefect*(conf: ConfigRef, field: string, disc: PSym): string =
  let obj = disc.owner.name.s # `types.typeToString` might be better, eg for generics
  result = "field '$#' is not accessible for type '$#'" % [field, obj]
  if optDeclaredLocs in conf.globalOptions:
    result.add " [discriminant declared in $#]" % toFileLineCol(conf, disc.info)
  result.add " using '$# = " % disc.name.s
