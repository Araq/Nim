#
#
#           The Nim Compiler
#        (c) Copyright 2020 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

proc checkForSink*(config: ConfigRef; idgen: IdGenerator; owner: PSym; arg: PNode) =
  #[ Patterns we seek to detect:

    someLocation = p # ---> p: sink T
    passToSink(p)    # p: sink
    ObjConstr(fieldName: p)
    [p, q] # array construction

    # Open question:
    var local = p # sink parameter?
    passToSink(local)
  ]#
  case arg.kind
  of nkSym:
    if arg.sym.kind == skParam and
        arg.sym.owner == owner and
        owner.typ != nil and owner.typ.kind == tyProc and
        arg.sym.typ.hasDestructor and
        arg.sym.typ.kind notin {tyVar, tySink, tyOwned}:
      # Watch out: cannot do this inference for procs with forward
      # declarations.
      if sfWasForwarded notin owner.flags:
        let argType = arg.sym.typ

        let sinkType = newType(tySink, idgen, owner)
        sinkType.size = argType.size
        sinkType.align = argType.align
        sinkType.paddingAtEnd = argType.paddingAtEnd
        sinkType.add argType

        arg.sym.typ = sinkType
        owner.typ[arg.sym.position+1] = sinkType

        #message(config, arg.info, warnUser,
        #  ("turned '$1' to a sink parameter") % [$arg])
        #echo config $ arg.info, " turned into a sink parameter ", arg.sym.name.s
      elif sfWasForwarded notin arg.sym.flags:
        # we only report every potential 'sink' parameter only once:
        incl arg.sym.flags, sfWasForwarded
        message(config, arg.info, hintPerformance,
          "could not turn '$1' to a sink parameter" % [arg.sym.name.s])
      #echo config $ arg.info, " candidate for a sink parameter here"
  of nkStmtList, nkStmtListExpr, nkBlockStmt, nkBlockExpr:
    if not isEmptyType(arg.typ):
      checkForSink(config, idgen, owner, arg.lastSon)
  of nkIfStmt, nkIfExpr, nkWhen:
    for branch in arg:
      let value = branch.lastSon
      if not isEmptyType(value.typ):
        checkForSink(config, idgen, owner, value)
  of nkCaseStmt:
    for i in 1..<arg.len:
      let value = arg[i].lastSon
      if not isEmptyType(value.typ):
        checkForSink(config, idgen, owner, value)
  of nkTryStmt:
    checkForSink(config, idgen, owner, arg[0])
  else:
    discard "nothing to do"
