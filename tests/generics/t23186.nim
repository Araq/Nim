# issue #23186

block: # simplified
  template typedTempl(x: int, body): untyped =
    body
  proc generic1[T]() =
    discard
  proc generic2[T]() =
    typedTempl(1):
      let x = generic1[T]
  generic2[int]()

import std/macros

when not compiles(len((1, 2))):
  import std/typetraits

  func len(x: tuple): int =
    arity(type(x))

block: # full issue example
  type FieldDescription = object
    name: NimNode
  func isTuple(t: NimNode): bool =
    t.kind == nnkBracketExpr and t[0].kind == nnkSym and eqIdent(t[0], "tuple")
  proc collectFieldsFromRecList(result: var seq[FieldDescription],
                                n: NimNode,
                                parentCaseField: NimNode = nil,
                                parentCaseBranch: NimNode = nil,
                                isDiscriminator = false) =
    case n.kind
    of nnkRecList:
      for entry in n:
        collectFieldsFromRecList result, entry,
                                parentCaseField, parentCaseBranch
    of nnkIdentDefs:
      for i in 0 ..< n.len - 2:
        var field: FieldDescription
        field.name = n[i]
        if field.name.kind == nnkPragmaExpr:
          field.name = field.name[0]
        if field.name.kind == nnkPostfix:
          field.name = field.name[1]
        result.add field
    of nnkNilLit, nnkDiscardStmt, nnkCommentStmt, nnkEmpty:
      discard
    else:
      doAssert false, "Unexpected nodes in recordFields:\n" & n.treeRepr
  proc collectFieldsInHierarchy(result: var seq[FieldDescription],
                                objectType: NimNode) =
    var objectType = objectType
    if objectType.kind == nnkRefTy:
      objectType = objectType[0]
    let recList = objectType[2]
    collectFieldsFromRecList result, recList
  proc recordFields(typeImpl: NimNode): seq[FieldDescription] =
    let objectType = case typeImpl.kind
      of nnkObjectTy: typeImpl
      of nnkTypeDef: typeImpl[2]
      else:
        macros.error("object type expected", typeImpl)
        return
    collectFieldsInHierarchy(result, objectType)
  proc skipPragma(n: NimNode): NimNode =
    if n.kind == nnkPragmaExpr: n[0]
    else: n
  func declval(T: type): T =
    doAssert false,
      "declval should be used only in `typeof` expressions and concepts"
    default(ptr T)[]
  macro enumAllSerializedFieldsImpl(T: type, body: untyped): untyped =
    var typeAst = getType(T)[1]
    var typeImpl: NimNode
    let isSymbol = not typeAst.isTuple
    if not isSymbol:
      typeImpl = typeAst
    else:
      typeImpl = getImpl(typeAst)
    result = newStmtList()
    var i = 0
    for field in recordFields(typeImpl):
      let
        fieldIdent = field.name
        realFieldName = newLit($fieldIdent.skipPragma)
        fieldName = realFieldName
        fieldIndex = newLit(i)
      let fieldNameDefs =
        if isSymbol:
          quote:
            const fieldName {.inject, used.} = `fieldName`
            const realFieldName {.inject, used.} = `realFieldName`
        else:
          quote:
            const fieldName {.inject, used.} = $`fieldIndex`
            const realFieldName {.inject, used.} = $`fieldIndex`
            # we can't access .Fieldn, so our helper knows
            # to parseInt this
      let field =
        if isSymbol:
          quote do: declval(`T`).`fieldIdent`
        else:
          quote do: declval(`T`)[`fieldIndex`]
      result.add quote do:
        block:
          `fieldNameDefs`
          type FieldType {.inject, used.} = type(`field`)
          `body`
      i += 1
  template enumAllSerializedFields(T: type, body): untyped =
    when T is ref|ptr:
      type TT = type(default(T)[])
      enumAllSerializedFieldsImpl(TT, body)
    else:
      enumAllSerializedFieldsImpl(T, body)
  type
    MemRange = object
      startAddr: ptr byte
      length: int
    SszNavigator[T] = object
      m: MemRange
  func sszMount(data: openArray[byte], T: type): SszNavigator[T] =
    let startAddr = unsafeAddr data[0]
    SszNavigator[T](m: MemRange(startAddr: startAddr, length: data.len))
  func sszMount(data: openArray[char], T: type): SszNavigator[T] =
    let startAddr = cast[ptr byte](unsafeAddr data[0])
    SszNavigator[T](m: MemRange(startAddr: startAddr, length: data.len))
  template sszMount(data: MemRange, T: type): SszNavigator[T] =
    SszNavigator[T](m: data)
  func navigateToField[T](
      n: SszNavigator[T],
      FieldType: type): SszNavigator[FieldType] =
    default(SszNavigator[FieldType])
  type
    FieldInfo = ref object
      navigator: proc (m: MemRange): MemRange {.
        gcsafe, noSideEffect, raises: [IOError] .}
  func fieldNavigatorImpl[RecordType; FieldType; fieldName: static string](
      m: MemRange): MemRange =
    var typedNavigator = sszMount(m, RecordType)
    discard navigateToField(typedNavigator, FieldType)
    default(MemRange)
  func genTypeInfo(T: type) =
    when T is object:
      enumAllSerializedFields(T):
        discard FieldInfo(navigator: fieldNavigatorImpl[T, FieldType, fieldName])
  type
    Foo = object
      bar: Bar
    BarList = seq[uint64]
    Bar = object
      b: BarList
      baz: Baz
    Baz = object
      i: uint64
  genTypeInfo(Foo)
