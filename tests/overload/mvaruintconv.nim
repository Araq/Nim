import
  std/[macros, tables, hashes]

export
  macros

type
  FieldDescription* = object
    name*: NimNode
    isPublic*: bool
    isDiscriminator*: bool
    typ*: NimNode
    pragmas*: NimNode
    caseField*: NimNode
    caseBranch*: NimNode

{.push raises: [].}

func isTuple*(t: NimNode): bool =
  t.kind == nnkBracketExpr and t[0].kind == nnkSym and eqIdent(t[0], "tuple")

macro isTuple*(T: type): untyped =
  newLit(isTuple(getType(T)[1]))

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
  of nnkRecWhen:
    for branch in n:
      case branch.kind:
      of nnkElifBranch:
        collectFieldsFromRecList result, branch[1],
                                 parentCaseField, parentCaseBranch
      of nnkElse:
        collectFieldsFromRecList result, branch[0],
                                 parentCaseField, parentCaseBranch
      else:
        doAssert false

  of nnkRecCase:
    collectFieldsFromRecList result, n[0],
                             parentCaseField,
                             parentCaseBranch,
                             isDiscriminator = true

    for i in 1 ..< n.len:
      let branch = n[i]
      case branch.kind
      of nnkOfBranch:
        collectFieldsFromRecList result, branch[^1], n[0], branch
      of nnkElse:
        collectFieldsFromRecList result, branch[0], n[0], branch
      else:
        doAssert false

  of nnkIdentDefs:
    let fieldType = n[^2]
    for i in 0 ..< n.len - 2:
      var field: FieldDescription
      field.name = n[i]
      field.typ = fieldType
      field.caseField = parentCaseField
      field.caseBranch = parentCaseBranch
      field.isDiscriminator = isDiscriminator

      if field.name.kind == nnkPragmaExpr:
        field.pragmas = field.name[1]
        field.name = field.name[0]

      if field.name.kind == nnkPostfix:
        field.isPublic = true
        field.name = field.name[1]

      result.add field

  of nnkSym:
    result.add FieldDescription(
      name: n,
      typ: getType(n),
      caseField: parentCaseField,
      caseBranch: parentCaseBranch,
      isDiscriminator: isDiscriminator)

  of nnkNilLit, nnkDiscardStmt, nnkCommentStmt, nnkEmpty:
    discard

  else:
    doAssert false, "Unexpected nodes in recordFields:\n" & n.treeRepr

proc collectFieldsInHierarchy(result: var seq[FieldDescription],
                              objectType: NimNode) =
  var objectType = objectType

  objectType.expectKind {nnkObjectTy, nnkRefTy}

  if objectType.kind == nnkRefTy:
    objectType = objectType[0]

  objectType.expectKind nnkObjectTy

  var baseType = objectType[1]
  if baseType.kind != nnkEmpty:
    baseType.expectKind nnkOfInherit
    baseType = baseType[0]
    baseType.expectKind nnkSym
    baseType = getImpl(baseType)
    baseType.expectKind nnkTypeDef
    baseType = baseType[2]
    baseType.expectKind {nnkObjectTy, nnkRefTy}
    collectFieldsInHierarchy result, baseType

  let recList = objectType[2]
  collectFieldsFromRecList result, recList

proc recordFields*(typeImpl: NimNode): seq[FieldDescription] =
  if typeImpl.isTuple:
    for i in 1 ..< typeImpl.len:
      result.add FieldDescription(typ: typeImpl[i], name: ident("Field" & $(i - 1)))
    return

  let objectType = case typeImpl.kind
    of nnkObjectTy: typeImpl
    of nnkTypeDef: typeImpl[2]
    else:
      macros.error("object type expected", typeImpl)
      return

  collectFieldsInHierarchy(result, objectType)

macro field*(obj: typed, fieldName: static string): untyped =
  newDotExpr(obj, ident fieldName)

proc skipPragma*(n: NimNode): NimNode =
  if n.kind == nnkPragmaExpr: n[0]
  else: n


{.pop.}
