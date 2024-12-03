import ast, modulegraphs, magicsys, lineinfos, options, cgmeth, types
import std/[algorithm, tables, intsets, assertions]



proc genVTableDispatcher(g: ModuleGraph; methods: seq[PSym]; index: int): PSym =
#[
proc dispatch(x: Base, params: ...) =
  cast[proc bar(x: Base, params: ...)](x.vTable[index])(x, params)
]#
  var base = methods[0].ast[dispatcherPos].sym
  result = base
  var paramLen = base.typ.signatureLen
  var body = newNodeI(nkStmtList, base.info)

  var disp = newNodeI(nkIfStmt, base.info)

  let nimGetVTableSym = getCompilerProc(g, "nimGetVTable")
  let ptrPNimType = nimGetVTableSym.typ.n[1].sym.typ

  var nTyp = base.typ.n[1].sym.typ
  var dispatchObject = newSymNode(base.typ.n[1].sym)
  if nTyp.kind == tyObject:
    dispatchObject = newTree(nkAddr, dispatchObject)
  else:
    if g.config.backend != backendCpp: # TODO: maybe handle ptr?
      if nTyp.kind == tyVar and nTyp.skipTypes({tyVar}).kind != tyObject:
        dispatchObject = newTree(nkDerefExpr, dispatchObject)

  var getVTableCall = newTree(nkCall,
    newSymNode(nimGetVTableSym),
    dispatchObject,
    newIntNode(nkIntLit, index)
  )
  getVTableCall.typ() = getSysType(g, unknownLineInfo, tyPointer)
  var vTableCall = newNodeIT(nkCall, base.info, base.typ.returnType)
  var castNode = newTree(nkCast,
        newNodeIT(nkType, base.info, base.typ),
        getVTableCall)

  castNode.typ() = base.typ
  vTableCall.add castNode
  for col in 1..<paramLen:
    let param = base.typ.n[col].sym
    vTableCall.add newSymNode(param)

  var ret: PNode
  if base.typ.returnType != nil:
    var a = newNodeI(nkFastAsgn, base.info)
    a.add newSymNode(base.ast[resultPos].sym)
    a.add vTableCall
    ret = newNodeI(nkReturnStmt, base.info)
    ret.add a
  else:
    ret = vTableCall

  if base.typ.n[1].sym.typ.skipTypes(abstractInst).kind in {tyRef, tyPtr}:
    let ifBranch = newNodeI(nkElifBranch, base.info)
    let boolType = getSysType(g, unknownLineInfo, tyBool)
    var isNil = getSysMagic(g, unknownLineInfo, "isNil", mIsNil)
    let checkSelf = newNodeIT(nkCall, base.info, boolType)
    checkSelf.add newSymNode(isNil)
    checkSelf.add newSymNode(base.typ.n[1].sym)
    ifBranch.add checkSelf
    ifBranch.add newTree(nkCall,
        newSymNode(getCompilerProc(g, "chckNilDisp")), newSymNode(base.typ.n[1].sym))
    let elseBranch = newTree(nkElifBranch, ret)
    disp.add ifBranch
    disp.add elseBranch
  else:
    disp = ret

  body.add disp
  body.flags.incl nfTransf # should not be further transformed
  result.ast[bodyPos] = body

proc containGenerics(base: PType, s: seq[tuple[depth: int, value: PType]]): bool =
  result = tfHasMeta in base.flags
  for i in s:
    if tfHasMeta in i.value.flags:
      result = true
      break

proc collectVTableDispatchers*(g: ModuleGraph) =
  var itemTable = initTable[ItemId, seq[LazySym]]()
  var rootTypeSeq = newSeq[PType]()
  var rootItemIdCount = initCountTable[ItemId]()
  for bucket in 0..<g.methods.len:
    var relevantCols = initIntSet()
    if relevantCol(g.methods[bucket].methods, 1): incl(relevantCols, 1)
    sortBucket(g.methods[bucket].methods, relevantCols)
    let base = g.methods[bucket].methods[^1]
    let baseType = base.typ.firstParamType.skipTypes(skipPtrs-{tyTypeDesc})
    if baseType.itemId in g.objectTree and not containGenerics(baseType, g.objectTree[baseType.itemId]):
      let methodIndexLen = g.bucketTable[baseType.itemId]
      if baseType.itemId notin itemTable: # once is enough
        rootTypeSeq.add baseType
        itemTable[baseType.itemId] = newSeq[LazySym](methodIndexLen)

        sort(g.objectTree[baseType.itemId], cmp = proc (x, y: tuple[depth: int, value: PType]): int =
          if x.depth >= y.depth: 1
          else: -1
          )

        for item in g.objectTree[baseType.itemId]:
          if item.value.itemId notin itemTable:
            itemTable[item.value.itemId] = newSeq[LazySym](methodIndexLen)

      var mIndex = 0 # here is the correpsonding index
      if baseType.itemId notin rootItemIdCount:
        rootItemIdCount[baseType.itemId] = 1
      else:
        mIndex = rootItemIdCount[baseType.itemId]
        rootItemIdCount.inc(baseType.itemId)
      for idx in 0..<g.methods[bucket].methods.len:
        let obj = g.methods[bucket].methods[idx].typ.firstParamType.skipTypes(skipPtrs)
        itemTable[obj.itemId][mIndex] = LazySym(sym: g.methods[bucket].methods[idx])
      g.addDispatchers genVTableDispatcher(g, g.methods[bucket].methods, mIndex)
    else: # if the base object doesn't have this method
      g.addDispatchers genIfDispatcher(g, g.methods[bucket].methods, relevantCols, g.idgen)

proc sortVTableDispatchers*(g: ModuleGraph) =
  var itemTable = initTable[ItemId, seq[LazySym]]()
  var rootTypeSeq = newSeq[ItemId]()
  var rootItemIdCount = initCountTable[ItemId]()
  for bucket in 0..<g.methods.len:
    var relevantCols = initIntSet()
    if relevantCol(g.methods[bucket].methods, 1): incl(relevantCols, 1)
    sortBucket(g.methods[bucket].methods, relevantCols)
    let base = g.methods[bucket].methods[^1]
    let baseType = base.typ.firstParamType.skipTypes(skipPtrs-{tyTypeDesc})
    if baseType.itemId in g.objectTree and not containGenerics(baseType, g.objectTree[baseType.itemId]):
      let methodIndexLen = g.bucketTable[baseType.itemId]
      if baseType.itemId notin itemTable: # once is enough
        rootTypeSeq.add baseType.itemId
        itemTable[baseType.itemId] = newSeq[LazySym](methodIndexLen)

        sort(g.objectTree[baseType.itemId], cmp = proc (x, y: tuple[depth: int, value: PType]): int =
          if x.depth >= y.depth: 1
          else: -1
          )

        for item in g.objectTree[baseType.itemId]:
          if item.value.itemId notin itemTable:
            itemTable[item.value.itemId] = newSeq[LazySym](methodIndexLen)

      var mIndex = 0 # here is the correpsonding index
      if baseType.itemId notin rootItemIdCount:
        rootItemIdCount[baseType.itemId] = 1
      else:
        mIndex = rootItemIdCount[baseType.itemId]
        rootItemIdCount.inc(baseType.itemId)
      for idx in 0..<g.methods[bucket].methods.len:
        let obj = g.methods[bucket].methods[idx].typ.firstParamType.skipTypes(skipPtrs)
        itemTable[obj.itemId][mIndex] = LazySym(sym: g.methods[bucket].methods[idx])

  for baseType in rootTypeSeq:
    g.setMethodsPerType(baseType, itemTable[baseType])
    for item in g.objectTree[baseType]:
      let typ = item.value.skipTypes(skipPtrs)
      let idx = typ.itemId
      for mIndex in 0..<itemTable[idx].len:
        if itemTable[idx][mIndex].sym == nil:
          let parentIndex = typ.baseClass.skipTypes(skipPtrs).itemId
          itemTable[idx][mIndex] = itemTable[parentIndex][mIndex]
      g.setMethodsPerType(idx, itemTable[idx])
