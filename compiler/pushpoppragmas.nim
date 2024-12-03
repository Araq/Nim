import pragmas, options, ast, trees, lineinfos, idents, wordrecg
import std/assertions

import renderer


proc processNote(config: ConfigRef, n: PNode) =
  template handleNote(enumVals, notes) =
    let x = findStr(enumVals.a, enumVals.b, n[0][1].ident.s, errUnknown)
    assert x != errUnknown
    assert n[1].kind == nkIntLit

    nk = TNoteKind(x)
    if n[1].intVal != 0: incl(notes, nk)
    else: excl(notes, nk)

  var nk: TNoteKind
  case whichKeyword(n[0][0].ident)
  of wHint: handleNote(hintMin .. hintMax, config.notes)
  of wWarning: handleNote(warnMin .. warnMax, config.notes)
  of wWarningAsError: handleNote(warnMin .. warnMax, config.warningAsErrors)
  of wHintAsError: handleNote(hintMin .. hintMax, config.warningAsErrors)
  else: discard

proc pushBackendOption(optionsStack: var seq[(TOptions, TNoteKinds)], options: TOptions, notes: TNoteKinds) =
  optionsStack.add (options, notes)

proc popBackendOption(config: ConfigRef, optionsStack: var seq[(TOptions, TNoteKinds)], options: var TOptions) =
  let entry = optionsStack[^1]
  options = entry[0]
  config.notes = entry[1]
  optionsStack.setLen(optionsStack.len-1)

proc processPushBackendOption*(config: ConfigRef, optionsStack: var seq[(TOptions, TNoteKinds)], options: var TOptions,
                           n: PNode, start: int) =
  pushBackendOption(optionsStack, options, config.notes)
  for i in start..<n.len:
    let it = n[i]
    if it.kind in nkPragmaCallKinds and it.len == 2:
      if it[0].kind == nkBracketExpr and
          it[0].len == 2 and
          it[0][1].kind == nkIdent and it[0][0].kind == nkIdent:
        processNote(config, it)
      elif it[1].kind == nkIntLit:
        let sw = whichPragma(it[0])
        let opts = pragmaToOptions(sw)
        if opts != {}:
          if it[1].intVal != 0:
            options.incl opts
          else:
            options.excl opts

template processPopBackendOption*(config: ConfigRef, optionsStack: var seq[(TOptions, TNoteKinds)], options: var TOptions) =
  popBackendOption(config, optionsStack, options)
