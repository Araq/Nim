#
#
#            Nim's Runtime Library
#        (c) Copyright 2021 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module provides basic primitives for creating parallel programs.
## A `Task` should be only owned by a single Thread, it cannot be shared by threads.

import std/[macros, isolation, typetraits]

when defined(nimPreviewSlimSystem):
  import std/assertions

export isolation


when compileOption("threads"):
  from std/effecttraits import isGcSafe


#
# proc hello(a: int, b: string) =
#   echo $a & b
#
# let literal = "Nim"
# let t = toTask(hello(521, literal))
#
#
# is roughly converted to
#
# type
#   ScratchObj_369098780 = object
#     a: int
#     b: string
#
# let scratch_369098762 = cast[ptr ScratchObj_369098780](c_calloc(csize_t 1,
#     csize_t sizeof(ScratchObj_369098780)))
# if scratch_369098762.isNil:
#   raise newException(OutOfMemDefect, "Could not allocate memory")
# block:
#   var isolate_369098776 = isolate(521)
#   scratch_369098762.a = extract(isolate_369098776)
#   var isolate_369098778 = isolate(literal)
#   scratch_369098762.b = extract(isolate_369098778)
# proc hello_369098781(args`gensym3: pointer) {.nimcall.} =
#   let objTemp_369098775 = cast[ptr ScratchObj_369098780](args`gensym3)
#   let :tmp_369098777 = objTemp_369098775.a
#   let :tmp_369098779 = objTemp_369098775.b
#   hello(a = :tmp_369098777, b = :tmp_369098779)
#
# proc destroyScratch_369098782(args`gensym3: pointer) {.nimcall.} =
#   let obj_369098783 = cast[ptr ScratchObj_369098780](args`gensym3)
#   =destroy(obj_369098783[])
# let t = Task(callback: hello_369098781, args: scratch_369098762, destroy: destroyScratch_369098782)
#


type
  Task* = object ## `Task` contains the callback and its arguments.
    callback: proc (args, res: pointer) {.nimcall, gcsafe.}
    args: pointer
    destroy: proc (args: pointer) {.nimcall, gcsafe.}


proc `=copy`*(x: var Task, y: Task) {.error.}

const arcLike = defined(gcArc) or defined(gcAtomicArc) or defined(gcOrc)
when defined(nimAllowNonVarDestructor) and arcLike:
  proc `=destroy`*(t: Task) {.inline, gcsafe.} =
    ## Frees the resources allocated for a `Task`.
    if t.args != nil:
      if t.destroy != nil:
        t.destroy(t.args)
      deallocShared(t.args)
else:
  proc `=destroy`*(t: var Task) {.inline, gcsafe.} =
    ## Frees the resources allocated for a `Task`.
    if t.args != nil:
      if t.destroy != nil:
        t.destroy(t.args)
      deallocShared(t.args)

proc invoke*(task: Task; res: pointer = nil) {.inline, gcsafe.} =
  ## Invokes the `task`.
  assert task.callback != nil
  task.callback(task.args, res)

template checkIsolate(scratchAssignList: seq[NimNode], procParam, scratchDotExpr: NimNode) =
  # block:
  #   var isoTempA = isolate(521)
  #   scratch.a = extract(isolateA)
  #   var isoTempB = isolate(literal)
  #   scratch.b = extract(isolateB)
  let isolatedTemp = genSym(nskTemp, "isoTemp")
  scratchAssignList.add newVarStmt(isolatedTemp, newCall(newIdentNode("isolate"), procParam))
  scratchAssignList.add newAssignment(scratchDotExpr,
      newCall(newIdentNode("extract"), isolatedTemp))

template addAllNode(assignParam: NimNode, procParam: NimNode) =
  let scratchDotExpr = newDotExpr(scratchIdent, formalParams[i][0])

  checkIsolate(scratchAssignList, procParam, scratchDotExpr)

  let tempNode = genSym(kind = nskTemp, ident = formalParams[i][0].strVal)
  callNode.add nnkExprEqExpr.newTree(formalParams[i][0], tempNode)
  tempAssignList.add newLetStmt(tempNode, newDotExpr(objTemp, formalParams[i][0]))
  scratchRecList.add newIdentDefs(newIdentNode(formalParams[i][0].strVal), assignParam)

proc analyseRootSym(s: NimNode): NimNode =
  result = s
  while true:
    case result.kind
    of nnkBracketExpr, nnkDerefExpr, nnkHiddenDeref,
        nnkAddr, nnkHiddenAddr,
        nnkObjDownConv, nnkObjUpConv:
      result = result[0]
    of nnkDotExpr, nnkCheckedFieldExpr, nnkHiddenStdConv, nnkHiddenSubConv:
      result = result[1]
    else:
      break

macro toTask*(e: typed{nkCall | nkInfix | nkPrefix | nkPostfix | nkCommand | nkCallStrLit}): Task =
  ## Converts the call and its arguments to `Task`.
  runnableExamples:
    proc hello(a: int) = echo a

    let b = toTask hello(13)
    assert b is Task

  let retType = getTypeInst(e)
  let returnsVoid = retType.typeKind == ntyVoid

  let rootSym = analyseRootSym(e[0])
  expectKind rootSym, nnkSym

  when compileOption("threads"):
    if not isGcSafe(rootSym):
      error("'toTask' takes a GC safe call expression", e)

  if hasClosure(rootSym):
    error("closure call is not allowed", e)

  if e.len > 1:
    let scratchIdent = genSym(kind = nskTemp, ident = "scratch")
    let impl = e[0].getTypeInst

    when defined(nimTasksDebug):
      echo impl.treeRepr
      echo e.treeRepr
    let formalParams = impl[0]

    var
      scratchRecList = newNimNode(nnkRecList)
      scratchAssignList: seq[NimNode]
      tempAssignList: seq[NimNode]
      callNode: seq[NimNode]

    let
      objTemp = genSym(nskTemp, ident = "objTemp")

    for i in 1 ..< formalParams.len:
      var param = formalParams[i][1]

      if param.kind == nnkBracketExpr and param[0].eqIdent("sink"):
        param = param[0]

      if param.typeKind in {ntyExpr, ntyStmt}:
        error("'toTask'ed function cannot have a 'typed' or 'untyped' parameter", e)

      case param.kind
      of nnkVarTy:
        error("'toTask'ed function cannot have a 'var' parameter", e)
      of nnkBracketExpr:
        if param[0].typeKind == ntyTypeDesc:
          callNode.add nnkExprEqExpr.newTree(formalParams[i][0], e[i])
        elif param[0].typeKind in {ntyVarargs, ntyOpenArray}:
          if param[1].typeKind in {ntyExpr, ntyStmt}:
            error("'toTask'ed function cannot have a 'typed' or 'untyped' parameter", e)
          let
            seqType = nnkBracketExpr.newTree(newIdentNode("seq"), param[1])
            seqCallNode = newCall("@", e[i])
          addAllNode(seqType, seqCallNode)
        else:
          addAllNode(param, e[i])
      of nnkBracket, nnkObjConstr:
        # passing by static parameters
        # so we pass them directly instead of passing by scratchObj
        callNode.add nnkExprEqExpr.newTree(formalParams[i][0], e[i])
      of nnkSym, nnkPtrTy, nnkProcTy, nnkTupleTy, nnkTupleConstr:
        addAllNode(param, e[i])
      of nnkCharLit..nnkNilLit:
        callNode.add nnkExprEqExpr.newTree(formalParams[i][0], e[i])
      else:
        error("'toTask'ed function cannot have a parameter of " & $param.kind & " kind", e)

    let scratchObjType = genSym(kind = nskType, ident = "ScratchObj")
    let scratchObj = nnkTypeSection.newTree(
                      nnkTypeDef.newTree(
                        scratchObjType,
                        newEmptyNode(),
                        nnkObjectTy.newTree(
                          newEmptyNode(),
                          newEmptyNode(),
                          scratchRecList
                        )
                      )
                    )


    let scratchObjPtrType = quote do:
      cast[ptr `scratchObjType`](allocShared0(sizeof(`scratchObjType`)))

    let scratchLetSection = newLetStmt(scratchIdent, scratchObjPtrType)

    var stmtList = newStmtList()
    stmtList.add(scratchObj)
    stmtList.add(scratchLetSection)
    stmtList.add(nnkBlockStmt.newTree(newEmptyNode(), newStmtList(scratchAssignList)))

    var functionStmtList = newStmtList()
    let funcCall = newCall(e[0], callNode)
    functionStmtList.add tempAssignList

    let funcName = genSym(nskProc, rootSym.strVal)
    let destroyName = genSym(nskProc, "destroyScratch")
    let objTemp2 = genSym(ident = "obj")
    let tempNode = quote("@") do:
        `=destroy`(@objTemp2[])

    var funcDecl: NimNode
    if returnsVoid:
      funcDecl = quote do:
        proc `funcName`(args, res: pointer) {.gcsafe, nimcall.} =
          let `objTemp` = cast[ptr `scratchObjType`](args)
          `functionStmtList`
          `funcCall`
    else:
      funcDecl = quote do:
        proc `funcName`(args, res: pointer) {.gcsafe, nimcall.} =
          let `objTemp` = cast[ptr `scratchObjType`](args)
          `functionStmtList`
          cast[ptr `retType`](res)[] = `funcCall`

    result = quote do:
      `stmtList`

      `funcDecl`

      proc `destroyName`(args: pointer) {.gcsafe, nimcall.} =
        let `objTemp2` = cast[ptr `scratchObjType`](args)
        `tempNode`

      Task(callback: `funcName`, args: `scratchIdent`, destroy: `destroyName`)
  else:
    let funcCall = newCall(e[0])
    let funcName = genSym(nskProc, rootSym.strVal)

    if returnsVoid:
      result = quote do:
        proc `funcName`(args, res: pointer) {.gcsafe, nimcall.} =
          `funcCall`

        Task(callback: `funcName`, args: nil)
    else:
      result = quote do:
        proc `funcName`(args, res: pointer) {.gcsafe, nimcall.} =
          cast[ptr `retType`](res)[] = `funcCall`

        Task(callback: `funcName`, args: nil)


  when defined(nimTasksDebug):
    echo result.repr

runnableExamples:
  block:
    var num = 0
    proc hello(a: int) = inc num, a

    let b = toTask hello(13)
    b.invoke()
    assert num == 13
    # A task can be invoked multiple times
    b.invoke()
    assert num == 26

  block:
    type
      Runnable = ref object
        data: int

    var data: int
    proc hello(a: Runnable) {.nimcall.} =
      a.data += 2
      data = a.data


    when false:
      # the parameters of call must be isolated.
      let x = Runnable(data: 12)
      let b = toTask hello(x) # error ----> expression cannot be isolated: x
      b.invoke()

    let b = toTask(hello(Runnable(data: 12)))
    b.invoke()
    assert data == 14
    b.invoke()
    assert data == 16
