import std/strutils
import ast, modulegraphs

proc mangle*(name: string): string =
  result = newStringOfCap(name.len)
  var start = 0
  if name[0] in Digits:
    result.add("X" & name[0])
    start = 1
  var requiresUnderscore = false
  template special(x) =
    result.add x
    requiresUnderscore = true
  for i in start..<name.len:
    let c = name[i]
    case c
    of 'a'..'z', '0'..'9', 'A'..'Z':
      result.add(c)
    of '_':
      # we generate names like 'foo_9' for scope disambiguations and so
      # disallow this here:
      if i > 0 and i < name.len-1 and name[i+1] in Digits:
        discard
      else:
        result.add(c)
    of '$': special "dollar"
    of '%': special "percent"
    of '&': special "amp"
    of '^': special "roof"
    of '!': special "emark"
    of '?': special "qmark"
    of '*': special "star"
    of '+': special "plus"
    of '-': special "minus"
    of '/': special "slash"
    of '\\': special "backslash"
    of '=': special "eq"
    of '<': special "lt"
    of '>': special "gt"
    of '~': special "tilde"
    of ':': special "colon"
    of '.': special "dot"
    of '@': special "at"
    of '|': special "bar"
    else:
      result.add("X" & toHex(ord(c), 2))
      requiresUnderscore = true
  if requiresUnderscore:
    result.add "_"

proc mangleParamExt*(s: PSym): string =
  result = "_p"
  result.addInt s.position

proc mangleProcNameExt*(graph: ModuleGraph, s: PSym): string =
  result = "__"
  result.add graph.ifaces[s.itemId.module].uniqueName
  result.add "_u"
  result.addInt s.itemId.item # s.disamb #
