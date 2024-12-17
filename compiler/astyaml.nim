#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# AST YAML printing

import "."/[ast, lineinfos, msgs, options, rodutils]
import std/[intsets, strutils]

proc addYamlString*(res: var string; s: string) =
  res.add "\""
  for c in s:
    case c
    of '\0' .. '\x1F', '\x7F' .. '\xFF':
      res.add("\\u" & strutils.toHex(ord(c), 4))
    of '\"', '\\':
      res.add '\\' & c
    else:
      res.add c

  res.add('\"')

proc makeYamlString(s: string): string =
  result = ""
  result.addYamlString(s)

proc flagsToStr[T](flags: set[T]): string =
  if flags == {}:
    result = "[]"
  else:
    result = ""
    for x in items(flags):
      if result != "":
        result.add(", ")
      result.addYamlString($x)
    result = "[" & result & "]"

proc lineInfoToStr*(conf: ConfigRef; info: TLineInfo): string =
  result = "["
  result.addYamlString(toFilename(conf, info))
  result.addf ", $1, $2]", [toLinenumber(info), toColumn(info)]

proc treeToYamlAux(res: var string; conf: ConfigRef; n: PNode; marker: var IntSet; indent, maxRecDepth: int)
proc symToYamlAux(res: var string; conf: ConfigRef; n: PSym; marker: var IntSet; indent, maxRecDepth: int)
proc typeToYamlAux(res: var string; conf: ConfigRef; n: PType; marker: var IntSet; indent, maxRecDepth: int)

proc symToYamlAux(res: var string; conf: ConfigRef; n: PSym; marker: var IntSet; indent: int; maxRecDepth: int) =
  if n == nil:
    res.add("null")
  elif containsOrIncl(marker, n.id):
    res.addYamlString(n.name.s)
  else:
    let istr = spaces(indent * 4)

    res.addf("kind: $1", [makeYamlString($n.kind)])
    res.addf("\n$1name: $2", [istr, makeYamlString(n.name.s)])
    res.addf("\n$1typ: ", [istr])
    res.typeToYamlAux(conf, n.typ, marker, indent + 1, maxRecDepth - 1)
    if conf != nil:
      # if we don't pass the config, we probably don't care about the line info
      res.addf("\n$1info: $2", [istr, lineInfoToStr(conf, n.info)])
    if card(n.flags) > 0:
      res.addf("\n$1flags: $2", [istr, flagsToStr(n.flags)])
    res.addf("\n$1magic: $2", [istr, makeYamlString($n.magic)])
    res.addf("\n$1ast: ", [istr])
    res.treeToYamlAux(conf, n.ast, marker, indent + 1, maxRecDepth - 1)
    res.addf("\n$1options: $2", [istr, flagsToStr(n.options)])
    res.addf("\n$1position: $2", [istr, $n.position])
    res.addf("\n$1k: $2", [istr, makeYamlString($n.loc.k)])
    res.addf("\n$1storage: $2", [istr, makeYamlString($n.loc.storage)])
    if card(n.loc.flags) > 0:
      res.addf("\n$1flags: $2", [istr, makeYamlString($n.loc.flags)])
    res.addf("\n$1snippet: $2", [istr, n.loc.snippet])
    res.addf("\n$1lode: $2", [istr])
    res.treeToYamlAux(conf, n.loc.lode, marker, indent + 1, maxRecDepth - 1)

proc typeToYamlAux(res: var string; conf: ConfigRef; n: PType; marker: var IntSet; indent: int; maxRecDepth: int) =
  if n == nil:
    res.add("null")
  elif containsOrIncl(marker, n.id):
    res.addf "\"$1 @$2\"" % [$n.kind, strutils.toHex(cast[uint](n), sizeof(n) * 2)]
  else:
    let istr = spaces(indent * 4)
    res.addf("kind: $2", [istr, makeYamlString($n.kind)])
    res.addf("\n$1sym: ")
    res.symToYamlAux(conf, n.sym, marker, indent + 1, maxRecDepth - 1)
    res.addf("\n$1n: ")
    res.treeToYamlAux(conf, n.n, marker, indent + 1, maxRecDepth - 1)
    if card(n.flags) > 0:
      res.addf("\n$1flags: $2", [istr, flagsToStr(n.flags)])
    res.addf("\n$1callconv: $2", [istr, makeYamlString($n.callConv)])
    res.addf("\n$1size: $2", [istr, $(n.size)])
    res.addf("\n$1align: $2", [istr, $(n.align)])
    if n.hasElementType:
      res.addf("\n$1sons:")
      for a in n.kids:
        res.addf("\n  - ")
        res.typeToYamlAux(conf, a, marker, indent + 1, maxRecDepth - 1)

proc treeToYamlAux(res: var string; conf: ConfigRef; n: PNode; marker: var IntSet; indent: int;
                   maxRecDepth: int) =
  if n == nil:
    res.add("null")
  else:
    var istr = spaces(indent * 4)
    res.addf("kind: $1" % [makeYamlString($n.kind)])

    if maxRecDepth != 0:
      if conf != nil:
        res.addf("\n$1info: $2", [istr, lineInfoToStr(conf, n.info)])
      case n.kind
      of nkCharLit .. nkInt64Lit:
        res.addf("\n$1intVal: $2", [istr, $(n.intVal)])
      of nkFloatLit, nkFloat32Lit, nkFloat64Lit:
        res.addf("\n$1floatVal: $2", [istr, n.floatVal.toStrMaxPrecision])
      of nkStrLit .. nkTripleStrLit:
        res.addf("\n$1strVal: $2", [istr, makeYamlString(n.strVal)])
      of nkSym:
        res.addf("\n$1sym: ", [istr])
        res.symToYamlAux(conf, n.sym, marker, indent + 1, maxRecDepth)
      of nkIdent:
        if n.ident != nil:
          res.addf("\n$1ident: $2", [istr, makeYamlString(n.ident.s)])
        else:
          res.addf("\n$1ident: null", [istr])
      else:
        if n.len > 0:
          res.addf("\n$1sons: ", [istr])
          for i in 0 ..< n.len:
            res.addf("\n$1  - ", [istr])
            res.treeToYamlAux(conf, n[i], marker, indent + 1, maxRecDepth - 1)
      if n.typ != nil:
        res.addf("\n$1typ: ", [istr])
        res.typeToYamlAux(conf, n.typ, marker, indent + 1, maxRecDepth)

proc treeToYaml*(conf: ConfigRef; n: PNode; indent: int = 0; maxRecDepth: int = -1): string =
  var marker = initIntSet()
  result = newStringOfCap(1024)
  result.treeToYamlAux(conf, n, marker, indent, maxRecDepth)

proc typeToYaml*(conf: ConfigRef; n: PType; indent: int = 0; maxRecDepth: int = -1): string =
  var marker = initIntSet()
  result = newStringOfCap(1024)
  result.typeToYamlAux(conf, n, marker, indent, maxRecDepth)

proc symToYaml*(conf: ConfigRef; n: PSym; indent: int = 0; maxRecDepth: int = -1): string =
  var marker = initIntSet()
  result = newStringOfCap(1024)
  result.symToYamlAux(conf, n, marker, indent, maxRecDepth)
