type VarKind = enum
  Local
  Global
  Threadvar
  Const
  AlwaysConst ## const even on C++

proc addVarHeader(builder: var Builder, kind: VarKind) =
  ## adds modifiers for given var kind:
  ## Local has no modifier
  ## Global has `static` modifier
  ## Const has `static NIM_CONST` modifier
  ## AlwaysConst has `static const` modifier (NIM_CONST is no-op on C++)
  ## Threadvar is unimplemented
  case kind
  of Local:
    when buildNifc:
      builder.add("var ")
  of Global:
    when buildNifc:
      builder.add("gvar ")
    else:
      builder.add("static ")
  of Const:
    when buildNifc:
      builder.add("const ")
    else:
      builder.add("static NIM_CONST ")
  of AlwaysConst:
    when buildNifc:
      builder.add("const ")
    else:
      builder.add("static const ")
  of Threadvar:
    when buildNifc:
      builder.add("tvar ")
    else:
      raiseAssert "unimplemented"

proc addVar(builder: var Builder, kind: VarKind = Local, name: string, typ: Snippet, initializer: Snippet = "") =
  ## adds a variable declaration to the builder
  when buildNifc:
    builder.add("(")
    builder.addVarHeader(kind)
    builder.add(":")
    builder.add(name)
    builder.add(" . ") # pragmas
    builder.add(typ)
    builder.add(" ")
    if initializer.len != 0:
      builder.add(initializer)
    else:
      builder.add(".")
    builder.addLineEnd(")")
  else:
    builder.addVarHeader(kind)
    builder.add(typ)
    builder.add(" ")
    builder.add(name)
    if initializer.len != 0:
      builder.add(" = ")
      builder.add(initializer)
    builder.addLineEnd(";")

template addVarWithInitializer(builder: var Builder, kind: VarKind = Local, name: string,
                               typ: Snippet, initializerBody: typed) =
  ## adds a variable declaration to the builder, with
  ## `initializerBody` building the initializer. initializer must be provided
  when buildNifc:
    builder.add("(")
    builder.addVarHeader(kind)
    builder.add(":")
    builder.add(name)
    builder.add(" . ") # pragmas
    builder.add(typ)
    builder.add(" ")
    initializerBody
    builder.addLineEnd(")")
  else:
    builder.addVarHeader(kind)
    builder.add(typ)
    builder.add(" ")
    builder.add(name)
    builder.add(" = ")
    initializerBody
    builder.addLineEnd(";")

when buildNifc:
  proc getArrayType(m: BModule, elementType: Snippet, len: int): Snippet =
    let key = (elementType, len)
    if key in m.arrayTypes:
      result = m.arrayTypes[key]
    else:
      let tmp = getTempName(m)
      result = tmp & (when buildNifc: ".arr." else: "_Arr_") & $len
      m.s[cfsTypes].add("(type :")
      m.s[cfsTypes].add(result)
      m.s[cfsTypes].add(" . (array ")
      m.s[cfsTypes].add(elementType)
      m.s[cfsTypes].add(" ")
      m.s[cfsTypes].add(cIntValue(len))
      m.s[cfsTypes].addLineEnd("))")
      m.arrayTypes[key] = result

proc addArrayVar(builder: var Builder, m: BModule, kind: VarKind = Local, name: string, elementType: Snippet, len: int, initializer: Snippet = "") =
  ## adds an array variable declaration to the builder
  when buildNifc:
    builder.add("(")
    builder.addVarHeader(kind)
    builder.add(":")
    builder.add(name)
    builder.add(" . ") # pragmas
    builder.add(getArrayType(m, elementType, len))
    builder.add(" ")
    if initializer.len != 0:
      builder.add(initializer)
    else:
      builder.add(".")
    builder.addLineEnd(")")
  else:
    builder.addVarHeader(kind)
    builder.add(elementType)
    builder.add(" ")
    builder.add(name)
    builder.add("[")
    builder.addIntValue(len)
    builder.add("]")
    if initializer.len != 0:
      builder.add(" = ")
      builder.add(initializer)
    builder.addLineEnd(";")

template addArrayVarWithInitializer(builder: var Builder, m: BModule, kind: VarKind = Local, name: string, elementType: Snippet, len: int, body: typed) =
  ## adds an array variable declaration to the builder with the initializer built according to `body`
  when buildNifc:
    builder.add("(")
    builder.addVarHeader(kind)
    builder.add(":")
    builder.add(name)
    builder.add(" . ") # pragmas
    builder.add(getArrayType(m, elementType, len))
    builder.add(" ")
    body
    builder.addLineEnd(")")
  else:
    builder.addVarHeader(kind)
    builder.add(elementType)
    builder.add(" ")
    builder.add(name)
    builder.add("[")
    builder.addIntValue(len)
    builder.add("] = ")
    body
    builder.addLineEnd(";")

template addTypedef(builder: var Builder, name: string, typeBody: typed) =
  ## adds a typedef declaration to the builder with name `name` and type as
  ## built in `typeBody`
  when buildNifc:
    builder.add("(type :")
    builder.add(name)
    builder.add(" . ")
    typeBody
    builder.addLineEnd(")")
  else:
    builder.add("typedef ")
    typeBody
    builder.add(" ")
    builder.add(name)
    builder.addLineEnd(";")

proc addProcTypedef(builder: var Builder, callConv: TCallingConvention, name: string, rettype, params: Snippet, isVarargs = false) =
  when buildNifc:
    builder.add("(type :")
    builder.add(name)
    builder.add(" . (proctype . ")
    builder.add(params)
    builder.add(" ")
    builder.add(rettype)
    builder.add(" (pragmas ")
    builder.add(CallingConvToStr[callConv])
    if isVarargs:
      builder.add(" (varargs)")
    builder.addLineEnd(")))")
  else:
    builder.add("typedef ")
    builder.add(CallingConvToStr[callConv])
    builder.add("_PTR(")
    builder.add(rettype)
    builder.add(", ")
    builder.add(name)
    builder.add(")")
    builder.add(params)
    builder.addLineEnd(";")

template addArrayTypedef(builder: var Builder, name: string, len: BiggestInt, typeBody: typed) =
  ## adds an array typedef declaration to the builder with name `name`,
  ## length `len`, and element type as built in `typeBody`
  when buildNifc:
    builder.add("(type :")
    builder.add(name)
    builder.add(" . (array ")
    typeBody
    builder.add(" ")
    builder.addIntValue(len)
    builder.addLineEnd("))")
  else:
    builder.add("typedef ")
    typeBody
    builder.add(" ")
    builder.add(name)
    builder.add("[")
    builder.addIntValue(len)
    builder.addLineEnd("];")

type
  StructInitializerKind = enum
    siOrderedStruct ## struct constructor, but without named fields on C
    siNamedStruct ## struct constructor, with named fields i.e. C99 designated initializer
    siArray ## array constructor
    siWrapper ## wrapper for a single field, generates it verbatim

  StructInitializer = object
    ## context for building struct initializers, i.e. `{ field1, field2 }`
    kind: StructInitializerKind
      ## if true, fields will not be named, instead values are placed in order
    needsComma: bool

proc initStructInitializer(builder: var Builder, kind: StructInitializerKind, typ: Snippet): StructInitializer =
  ## starts building a struct initializer, i.e. braced initializer list
  result = StructInitializer(kind: kind, needsComma: false)
  when buildNifc:
    case kind
    of siOrderedStruct, siNamedStruct:
      builder.add("(oconstr ")
      builder.add(typ)
    of siArray:
      builder.add("(aconstr ")
      builder.add(typ)
    of siWrapper: discard
  else:
    if kind != siWrapper:
      builder.add("{")

template addField(builder: var Builder, constr: var StructInitializer, name: string, valueBody: typed) =
  ## adds a field to a struct initializer, with the value built in `valueBody`
  if constr.needsComma:
    assert constr.kind != siWrapper, "wrapper constructor cannot have multiple fields"
    when not buildNifc:
      builder.add(", ")
  else:
    constr.needsComma = true
  case constr.kind
  of siArray, siWrapper:
    # no name, can just add value
    when buildNifc:
      if constr.kind == siArray:
        builder.add(" ")
    valueBody
  of siOrderedStruct:
    # no name, can just add value on C
    assert name.len != 0, "name has to be given for struct initializer field"
    when buildNifc:
      builder.add(" (kv ")
      builder.add(rawFieldName(name))
      builder.add(" ")
    valueBody
    when buildNifc:
      builder.add(")")
  of siNamedStruct:
    assert name.len != 0, "name has to be given for struct initializer field"
    when buildNifc:
      builder.add(" (kv ")
      builder.add(rawFieldName(name))
      builder.add(" ")
    else:
      builder.add(".")
      builder.add(name)
      builder.add(" = ")
    valueBody
    when buildNifc:
      builder.add(")")

proc finishStructInitializer(builder: var Builder, constr: StructInitializer) =
  ## finishes building a struct initializer
  if constr.kind != siWrapper:
    when buildNifc:
      builder.add(")")
    else:
      builder.add("}")

template addStructInitializer(builder: var Builder, constr: out StructInitializer, kind: StructInitializerKind, typ: Snippet, body: typed) =
  ## builds a struct initializer, i.e. `{ field1, field2 }`
  ## a `var StructInitializer` must be declared and passed as a parameter so
  ## that it can be used with `addField`
  constr = builder.initStructInitializer(kind, typ)
  body
  builder.finishStructInitializer(constr)

proc addField(obj: var Builder; name, typ: Snippet; isFlexArray: bool = false) =
  ## adds a field inside a struct/union type
  when buildNifc:
    obj.add("\n\t(fld :")
    obj.add(rawFieldName(name))
    obj.add(" . ") # pragmas
    if isFlexArray:
      obj.add("(flexarray ")
      obj.add(typ)
      obj.add(")")
    else:
      obj.add(typ)
    obj.add(")")
  else:
    obj.add('\t')
    obj.add(typ)
    obj.add(" ")
    obj.add(name)
    if isFlexArray:
      obj.add("[SEQ_DECL_SIZE]")
    obj.add(";\n")

proc addArrayField(obj: var Builder; m: BModule, name, elementType: Snippet; len: int) =
  ## adds an array field inside a struct/union type
  when buildNifc:
    obj.add("\n\t(fld :")
    obj.add(rawFieldName(name))
    obj.add(" . ") # pragmas
    obj.add(getArrayType(m, elementType, len))
    obj.add(")")
  else:
    obj.add('\t')
    obj.add(elementType)
    obj.add(" ")
    obj.add(name)
    obj.add("[")
    obj.addIntValue(len)
    obj.add("];\n")

proc addField(obj: var Builder; field: PSym; name, typ: Snippet; isFlexArray: bool = false; cppInitializer: Snippet = "") =
  ## adds an field inside a struct/union type, based on an `skField` symbol
  when buildNifc:
    obj.add("\n\t(fld :")
    obj.add(rawFieldName(name))
    var pragmasInner = ""
    if field.alignment > 0:
      pragmasInner.add("(align ")
      pragmasInner.add(cIntValue(field.alignment))
      pragmasInner.add(")")
    if field.bitsize != 0:
      if pragmasInner.len != 0: pragmasInner.add(" ")
      pragmasInner.add("(bits ")
      pragmasInner.add(cIntValue(field.bitsize))
      pragmasInner.add(")")
    if sfNoalias in field.flags:
      when false: # XXX not implemented in NIFC
        if pragmasInner.len != 0: pragmasInner.add(" ")
        pragmasInner.add("(restrict)")
    if pragmasInner.len != 0:
      obj.add(" (pragmas ")
      obj.add(pragmasInner)
      obj.add(") ")
    else:
      obj.add(" . ")
    if isFlexArray:
      obj.add("(flexarray ")
      obj.add(typ)
      obj.add("))")
    else:
      obj.add(typ)
      obj.add(")")
    doAssert cppInitializer.len == 0, "cpp initializer unsupported in nifc"
  else:
    obj.add('\t')
    if field.alignment > 0:
      obj.add("NIM_ALIGN(")
      obj.addIntValue(field.alignment)
      obj.add(") ")
    obj.add(typ)
    if sfNoalias in field.flags:
      obj.add(" NIM_NOALIAS")
    obj.add(" ")
    obj.add(name)
    if isFlexArray:
      obj.add("[SEQ_DECL_SIZE]")
    if field.bitsize != 0:
      obj.add(":")
      obj.addIntValue(field.bitsize)
    if cppInitializer.len != 0:
      obj.add(cppInitializer)
    obj.add(";\n")

proc addProcField(obj: var Builder, callConv: TCallingConvention, name: string, rettype, params: Snippet, isVarargs = false) =
  when buildNifc:
    obj.add("(fld :")
    obj.add(rawFieldName(name))
    obj.add(" . (proctype . ")
    obj.add(params)
    obj.add(" ")
    obj.add(rettype)
    obj.add(" (pragmas ")
    obj.add(CallingConvToStr[callConv])
    if isVarargs:
      obj.add(" (varargs)")
    obj.addLineEnd(")))")
  else:
    obj.add(CallingConvToStr[callConv])
    obj.add("_PTR(")
    obj.add(rettype)
    obj.add(", ")
    obj.add(name)
    obj.add(")")
    obj.add(params)
    obj.add(";\n")

type
  BaseClassKind = enum
    ## denotes how and whether or not the base class/RTTI should be stored
    bcNone, bcCppInherit, bcSupField, bcNoneRtti, bcNoneTinyRtti
  StructBuilderInfo = object
    ## context for building `struct` types
    baseKind: BaseClassKind
    named: bool
    preFieldsLen: int

proc structOrUnion(t: PType): Snippet =
  let t = t.skipTypes({tyAlias, tySink})
  if tfUnion in t.flags: "union"
  else:
    when buildNifc:
      "object"
    else:
      "struct"

proc startSimpleStruct(obj: var Builder; m: BModule; name: string; baseType: Snippet): StructBuilderInfo =
  result = StructBuilderInfo(baseKind: bcNone, named: name.len != 0)
  when buildNifc:
    if result.named:
      obj.add("(type :")
      obj.add(name)
      obj.add(" . ")
    obj.add("(object ")
    if baseType.len != 0:
      if m.compileToCpp:
        result.baseKind = bcCppInherit
      else:
        result.baseKind = bcSupField
      obj.add(baseType)
      obj.add(" ")
    else:
      obj.add(". ")
  else:
    obj.add("struct")
    if result.named:
      obj.add(" ")
      obj.add(name)
    if baseType.len != 0:
      if m.compileToCpp:
        result.baseKind = bcCppInherit
      else:
        result.baseKind = bcSupField
    if result.baseKind == bcCppInherit:
      obj.add(" : public ")
      obj.add(baseType)
    obj.add(" ")
    obj.add("{\n")
  result.preFieldsLen = obj.buf.len
  if result.baseKind == bcSupField:
    obj.addField(name = "Sup", typ = baseType)

proc finishSimpleStruct(obj: var Builder; m: BModule; info: StructBuilderInfo) =
  if info.baseKind == bcNone and info.preFieldsLen == obj.buf.len:
    # no fields were added, add dummy field
    obj.addField(name = "dummy", typ = CChar)
  if info.named:
    when buildNifc:
      obj.add("))\n")
    else:
      obj.add("};\n")
  else:
    when buildNifc:
      obj.add(")")
    else:
      obj.add("}")

template addSimpleStruct(obj: var Builder; m: BModule; name: string; baseType: Snippet; body: typed) =
  ## builds a struct type not based on a Nim type with fields according to `body`,
  ## `name` can be empty to build as a type expression and not a statement
  let info = startSimpleStruct(obj, m, name, baseType)
  body
  finishSimpleStruct(obj, m, info)

proc startStruct(obj: var Builder; m: BModule; t: PType; name: string; baseType: Snippet): StructBuilderInfo =
  result = StructBuilderInfo(baseKind: bcNone, named: name.len != 0)
  when buildNifc:
    # XXX no attributes for object types in NIFC
    if result.named:
      obj.add("(type :")
      obj.add(name)
      obj.add(" . (")
      obj.add(structOrUnion(t))
      obj.add(" ")
    else:
      obj.add("(")
      obj.add(structOrUnion(t))
      obj.add(" ")
  else:
    if tfPacked in t.flags:
      if hasAttribute in CC[m.config.cCompiler].props:
        obj.add(structOrUnion(t))
        obj.add(" __attribute__((__packed__))")
      else:
        obj.add("#pragma pack(push, 1)\n")
        obj.add(structOrUnion(t))
    else:
      obj.add(structOrUnion(t))
    if result.named:
      obj.add(" ")
      obj.add(name)
  if t.kind == tyObject:
    if t.baseClass == nil:
      if lacksMTypeField(t):
        result.baseKind = bcNone
      elif optTinyRtti in m.config.globalOptions:
        result.baseKind = bcNoneTinyRtti
      else:
        result.baseKind = bcNoneRtti
    elif m.compileToCpp:
      result.baseKind = bcCppInherit
    else:
      result.baseKind = bcSupField
  elif baseType.len != 0:
    if m.compileToCpp:
      result.baseKind = bcCppInherit
    else:
      result.baseKind = bcSupField
  when buildNifc:
    if baseType.len != 0:
      obj.add(baseType)
      obj.add(" ")
    else:
      obj.add(". ")
  else:
    if result.baseKind == bcCppInherit:
      obj.add(" : public ")
      obj.add(baseType)
    obj.add(" ")
    obj.add("{\n")
  result.preFieldsLen = obj.buf.len
  case result.baseKind
  of bcNone:
    # rest of the options add a field or don't need it due to inheritance,
    # we need to add the dummy field for uncheckedarray ahead of time
    # so that it remains trailing
    if t.itemId notin m.g.graph.memberProcsPerType and
        t.n != nil and t.n.len == 1 and t.n[0].kind == nkSym and
        t.n[0].sym.typ.skipTypes(abstractInst).kind == tyUncheckedArray:
      # only consists of flexible array field, add *initial* dummy field
      obj.addField(name = "dummy", typ = CChar)
  of bcCppInherit: discard
  of bcNoneRtti:
    obj.addField(name = "m_type", typ = ptrType(cgsymValue(m, "TNimType")))
  of bcNoneTinyRtti:
    obj.addField(name = "m_type", typ = ptrType(cgsymValue(m, "TNimTypeV2")))
  of bcSupField:
    obj.addField(name = "Sup", typ = baseType)

proc finishStruct(obj: var Builder; m: BModule; t: PType; info: StructBuilderInfo) =
  if info.baseKind == bcNone and info.preFieldsLen == obj.buf.len and
      t.itemId notin m.g.graph.memberProcsPerType:
    # no fields were added, add dummy field
    obj.addField(name = "dummy", typ = CChar)
  if info.named:
    when buildNifc:
      obj.add("))\n")
    else:
      obj.add("};\n")
  else:
    when buildNifc:
      obj.add(")")
    else:
      obj.add("}")
  when not buildNifc:
    if tfPacked in t.flags and hasAttribute notin CC[m.config.cCompiler].props:
      obj.add("#pragma pack(pop)\n")

template addStruct(obj: var Builder; m: BModule; typ: PType; name: string; baseType: Snippet; body: typed) =
  ## builds a struct type directly based on `typ` with fields according to `body`,
  ## `name` can be empty to build as a type expression and not a statement
  let info = startStruct(obj, m, typ, name, baseType)
  body
  finishStruct(obj, m, typ, info)

proc addFieldStruct(obj: var Builder; m: BModule; parentTyp: PType; name: string, fields: Snippet) =
  ## see `genRecordFieldsAux` for use
  when buildNifc:
    # XXX packed not implemented in nifc
    obj.addTypedef(name):
      obj.addSimpleStruct(m, "", ""):
        obj.add(fields)
  else:
    obj.add('\t')
    if tfPacked in parentTyp.flags:
      if hasAttribute in CC[m.config.cCompiler].props:
        obj.add("typedef struct __attribute__((__packed__)) ")
      else:
        obj.add("#pragma pack(push, 1)\ntypedef struct ")
    else:
      obj.add("typedef struct ")
    obj.add(name)
    obj.add(" {\n")
    obj.add(fields)
    obj.add("} ")
    obj.add(name)
    obj.add(";\n")
    if tfPacked in parentTyp.flags and hasAttribute notin CC[m.config.cCompiler].props:
      obj.add("#pragma pack(pop)\n")

template addUnion(obj: var Builder; name: string; body: typed) =
  let named = name.len != 0
  when buildNifc:
    if named:
      obj.add("(type :")
      obj.add(name)
      obj.add(" . (union . ")
    else:
      obj.add("(union . ")
  else:
    if named:
      obj.add("typedef union ")
      obj.add(name)
      obj.add(" {\n")
    else:
      obj.add("union {\n")
  body
  when buildNifc:
    if named:
      obj.add("))\n")
    else:
      obj.add(")\n")
  else:
    if named:
      obj.add("} ")
      obj.add(name)
      obj.add(";\n")
    else:
      obj.add("}")

type DeclVisibility = enum
  None
  Extern
  ExternC
  ImportLib
  ExportLib
  ExportLibVar
  Private
  StaticProc

proc addVisibilityPrefix(builder: var Builder, visibility: DeclVisibility) =
  # internal proc
  when buildNifc:
    case visibility
    of None: discard
    of Extern:
      builder.add("(imp ")
    of ExternC, ImportLib, ExportLib, ExportLibVar:
      raiseAssert "visibility " & $visibility & " not supported in NIFC"
    of Private, StaticProc:
      # also not supported but can just be ignored
      discard
  else:
    case visibility
    of None: discard
    of Extern:
      builder.add("extern ")
    of ExternC:
      builder.add("NIM_EXTERNC ")
    of ImportLib:
      builder.add("N_LIB_IMPORT ")
    of ExportLib:
      builder.add("N_LIB_EXPORT ")
    of ExportLibVar:
      builder.add("N_LIB_EXPORT_VAR ")
    of Private:
      builder.add("N_LIB_PRIVATE ")
    of StaticProc:
      builder.add("static ")

proc addVisibilitySuffix(builder: var Builder, visibility: DeclVisibility) =
  when buildNifc:
    case visibility
    of None: discard
    of Extern:
      builder.addLineEnd(")")
    of ExternC, ImportLib, ExportLib, ExportLibVar:
      raiseAssert "visibility " & $visibility & " not supported in NIFC"
    of Private, StaticProc:
      # also not supported but can just be ignored
      discard

template addDeclWithVisibility(builder: var Builder, visibility: DeclVisibility, declBody: typed) =
  ## adds a declaration as in `declBody` with the given visibility
  builder.addVisibilityPrefix(visibility)
  declBody
  builder.addVisibilitySuffix(visibility)

type ProcParamBuilder = object
  needsComma: bool

proc initProcParamBuilder(builder: var Builder): ProcParamBuilder =
  result = ProcParamBuilder(needsComma: false)
  when buildNifc:
    builder.add("(params ")
  else:
    builder.add("(")

proc finishProcParamBuilder(builder: var Builder, params: ProcParamBuilder) =
  when buildNifc:
    builder.add(")")
  else:
    if params.needsComma:
      builder.add(")")
    else:
      builder.add("void)")

template cgDeclFrmt*(s: PSym): string =
  s.constraint.strVal

proc addParam(builder: var Builder, params: var ProcParamBuilder, name: string, typ: Snippet) =
  if params.needsComma:
    when buildNifc:
      builder.add(" ")
    else:
      builder.add(", ")
  else:
    params.needsComma = true
  when buildNifc:
    builder.add("(param :")
    builder.add(name)
    builder.add(" . ")
    builder.add(typ)
    builder.add(")")
  else:
    builder.add(typ)
    builder.add(" ")
    builder.add(name)

proc addParam(builder: var Builder, params: var ProcParamBuilder, param: PSym, typ: Snippet) =
  if params.needsComma:
    when buildNifc:
      builder.add(" ")
    else:
      builder.add(", ")
  else:
    params.needsComma = true
  when buildNifc:
    # XXX noalias not implemented in nifc
    if sfCodegenDecl notin param.flags:
      builder.add("(param :")
      builder.add(param.loc.snippet)
      builder.add(" . ")
      builder.add(typ)
      builder.add(")")
    else:
      raiseAssert "codegendecl not supported on NIFC"
  else:
    var modifiedTyp = typ
    if sfNoalias in param.flags:
      modifiedTyp.add(" NIM_NOALIAS")
    if sfCodegenDecl notin param.flags:
      builder.add(modifiedTyp)
      builder.add(" ")
      builder.add(param.loc.snippet)
    else:
      builder.add runtimeFormat(param.cgDeclFrmt, [modifiedTyp, param.loc.snippet])

proc addUnnamedParam(builder: var Builder, params: var ProcParamBuilder, typ: Snippet) =
  if params.needsComma:
    when buildNifc:
      builder.add(" ")
    else:
      builder.add(", ")
  else:
    params.needsComma = true
  when buildNifc:
    builder.add("(param . . ")
    builder.add(typ)
    builder.add(")")
  else:
    builder.add(typ)

proc addProcTypedParam(builder: var Builder, paramBuilder: var ProcParamBuilder, callConv: TCallingConvention, name: string, rettype, params: Snippet, isVarargs = false) =
  if paramBuilder.needsComma:
    when buildNifc:
      builder.add(" ")
    else:
      builder.add(", ")
  else:
    paramBuilder.needsComma = true
  when buildNifc:
    builder.add("(param :")
    builder.add(name)
    builder.add(" . (proctype . ")
    builder.add(params)
    builder.add(" ")
    builder.add(rettype)
    builder.add(" (pragmas ")
    builder.add(CallingConvToStr[callConv])
    if isVarargs:
      builder.add(" (varargs)")
    builder.add(")))")
  else:
    builder.add(CallingConvToStr[callConv])
    builder.add("_PTR(")
    builder.add(rettype)
    builder.add(", ")
    builder.add(name)
    builder.add(")")
    builder.add(params)

proc addVarargsParam(builder: var Builder, params: var ProcParamBuilder) =
  when buildNifc:
    # information needs to be provided to proc type generators
    discard
  else:
    if params.needsComma:
      builder.add(", ")
    else:
      params.needsComma = true
    builder.add("...")

template addProcParams(builder: var Builder, params: out ProcParamBuilder, body: typed) =
  params = initProcParamBuilder(builder)
  body
  finishProcParamBuilder(builder, params)

type SimpleProcParam = tuple
  name, typ: string

proc cProcParams(params: varargs[SimpleProcParam]): Snippet =
  when buildNifc:
    result = "(params"
    for i in 0 ..< params.len:
      result.add(" (param ")
      if params[i].name.len != 0:
        result.add(":")
        result.add(params[i].name)
      else:
        result.add(".")
      result.add(" . ")
      result.add(params[i].typ)
      result.add(")")
    result.add(")")
  else:
    if params.len == 0: return "(void)"
    result = "("
    for i in 0 ..< params.len:
      if i != 0: result.add(", ")
      result.add(params[i].typ)
      if params[i].name.len != 0:
        result.add(" ")
        result.add(params[i].name)
    result.add(")")

template addProcHeaderWithParams(builder: var Builder, callConv: TCallingConvention,
                                 name: string, rettype: Snippet, isVarargs: bool, paramBuilder: typed) =
  when buildNifc:
    builder.add("(proc :")
    builder.add(name)
    builder.add(" ")
  else:
    builder.add(CallingConvToStr[callConv])
    builder.add("(")
    builder.add(rettype)
    builder.add(", ")
    builder.add(name)
    builder.add(")")
  paramBuilder
  when buildNifc:
    builder.add(" ")
    builder.add(rettype)
    builder.add(" (pragmas ")
    builder.add(CallingConvToStr[callConv])
    if isVarargs:
      builder.add(" (varargs)")
    builder.add(") ")

template addProcHeaderWithParams(builder: var Builder, callConv: TCallingConvention,
                                 name: string, rettype: Snippet, paramBuilder: typed) =
  # overload without isVarargs
  addProcHeaderWithParams(builder, callConv, name, rettype, isVarargs = false, paramBuilder)

proc addProcHeader(builder: var Builder, callConv: TCallingConvention,
                   name: string, rettype, params: Snippet, isVarargs = false) =
  addProcHeaderWithParams(builder, callConv, name, rettype, isVarargs):
    builder.add(params)

proc addProcHeader(builder: var Builder, name: string, rettype, params: Snippet, isConstructor = false) =
  # no callconv
  when buildNifc:
    builder.add("(proc :")
    builder.add(name)
    builder.add(" ")
    builder.add(params)
    builder.add(" ")
    builder.add(rettype)
    if isConstructor:
      builder.add(" (pragmas (attr \"constructor\")) ")
    else:
      builder.add(" . ")
  else:
    builder.add(rettype)
    builder.add(" ")
    if isConstructor:
      builder.add("__attribute__((constructor)) ")
    builder.add(name)
    builder.add(params)

proc addProcHeader(builder: var Builder, m: BModule, prc: PSym, name: string, params, rettype: Snippet, addAttributes: bool, isVarargs = false) =
  let noreturn = isNoReturn(m, prc)
  when buildNifc:
    # XXX no declspec on nifc
    builder.add("(proc :")
    builder.add(name)
    builder.add(" ")
    builder.add(params)
    builder.add(" ")
    builder.add(rettype)
    builder.add(" (pragmas ")
    builder.add(CallingConvToStr[prc.typ.callConv])
    if isVarargs:
      builder.add(" (varargs)")
    if addAttributes:
      if sfPure in prc.flags and hasAttribute in extccomp.CC[m.config.cCompiler].props:
        builder.add(" (attr \"naked\")")
      if noreturn and hasAttribute in extccomp.CC[m.config.cCompiler].props:
        builder.add(" (attr \"noreturn\")")
    builder.add(") ")
  else:
    if sfPure in prc.flags and hasDeclspec in extccomp.CC[m.config.cCompiler].props:
      builder.add("__declspec(naked) ")
    if noreturn and hasDeclspec in extccomp.CC[m.config.cCompiler].props:
      builder.add("__declspec(noreturn) ")
    builder.add(CallingConvToStr[prc.typ.callConv])
    builder.add("(")
    builder.add(rettype)
    builder.add(", ")
    builder.add(name)
    builder.add(")")
    builder.add(params)
    if addAttributes:
      if sfPure in prc.flags and hasAttribute in extccomp.CC[m.config.cCompiler].props:
        builder.add(" __attribute__((naked))")
      if noreturn and hasAttribute in extccomp.CC[m.config.cCompiler].props:
        builder.add(" __attribute__((noreturn))")

proc finishProcHeaderAsProto(builder: var Builder) =
  when buildNifc:
    builder.addLineEnd(".)")
  else:
    builder.addLineEnd(";")

template finishProcHeaderWithBody(builder: var Builder, body: typed) =
  when buildNifc:
    builder.addLineEndIndent(" (stmts")
    body
    builder.addLineEndDedent("))")
  else:
    builder.addLineEndIndent(" {")
    body
    builder.addLineEndDedent("}")
  builder.addNewline()

proc addProcVar(builder: var Builder, m: BModule, prc: PSym, name: string, params, rettype: Snippet,
                isStatic = false, ignoreAttributes = false, isVarargs = false) =
  let noreturn = isNoReturn(m, prc)
  when buildNifc:
    # XXX declspec not supported in NIFC
    builder.add("(")
    builder.addVarHeader(if isStatic: Global else: Local)
    builder.add(" :")
    builder.add(name)
    builder.add(" . (proctype . ")
    builder.add(params)
    builder.add(" ")
    builder.add(rettype)
    builder.add(" (pragmas ")
    builder.add(CallingConvToStr[prc.typ.callConv])
    if isVarargs:
      builder.add(" (varargs)")
    if not ignoreAttributes:
      if sfPure in prc.flags and hasAttribute in extccomp.CC[m.config.cCompiler].props:
        builder.add(" (attr \"naked\")")
      if noreturn and hasAttribute in extccomp.CC[m.config.cCompiler].props:
        builder.add(" (attr \"noreturn\")")
    # ensure we are just adding a variable:
    builder.addLineEnd(")) .)")
  else:
    if isStatic:
      builder.add("static ")
    if not ignoreAttributes:
      if sfPure in prc.flags and hasDeclspec in extccomp.CC[m.config.cCompiler].props:
        builder.add("__declspec(naked) ")
      if noreturn and hasDeclspec in extccomp.CC[m.config.cCompiler].props:
        builder.add("__declspec(noreturn) ")
    builder.add(CallingConvToStr[prc.typ.callConv])
    builder.add("_PTR(")
    builder.add(rettype)
    builder.add(", ")
    builder.add(name)
    builder.add(")")
    builder.add(params)
    if not ignoreAttributes:
      if sfPure in prc.flags and hasAttribute in extccomp.CC[m.config.cCompiler].props:
        builder.add(" __attribute__((naked))")
      if noreturn and hasAttribute in extccomp.CC[m.config.cCompiler].props:
        builder.add(" __attribute__((noreturn))")
    # ensure we are just adding a variable:
    builder.addLineEnd(";")

proc addProcVar(builder: var Builder, callConv: TCallingConvention,
                name: string, params, rettype: Snippet,
                isStatic = false, isVolatile = false, isVarargs = false) =
  when buildNifc:
    # XXX volatile not supported in nifc
    builder.add("(")
    builder.addVarHeader(if isStatic: Global else: Local)
    builder.add(" :")
    builder.add(name)
    builder.add(" . (proctype . ")
    builder.add(params)
    builder.add(" ")
    builder.add(rettype)
    builder.add(" (pragmas ")
    builder.add(CallingConvToStr[callConv])
    if isVarargs:
      builder.add(" (varargs)")
    # ensure we are just adding a variable:
    builder.addLineEnd(")) .)")
  else:
    if isStatic:
      builder.add("static ")
    builder.add(CallingConvToStr[callConv])
    builder.add("_PTR(")
    builder.add(rettype)
    builder.add(", ")
    if isVolatile:
      builder.add("volatile ")
    builder.add(name)
    builder.add(")")
    builder.add(params)
    # ensure we are just adding a variable:
    builder.addLineEnd(";")

proc addProcVar(builder: var Builder,
                name: string, params, rettype: Snippet,
                isStatic = false, isVolatile = false, isVarargs = false) =
  # no callconv
  when buildNifc:
    # XXX volatile not supported in nifc
    builder.add("(")
    builder.addVarHeader(if isStatic: Global else: Local)
    builder.add(" :")
    builder.add(name)
    builder.add(" . (proctype . ")
    builder.add(params)
    builder.add(" ")
    builder.add(rettype)
    if isVarargs:
      builder.add(" (pragmas (varargs))")
    else:
      builder.add(" .")
    builder.add(") .)")
  else:
    if isStatic:
      builder.add("static ")
    builder.add(rettype)
    builder.add(" (*")
    if isVolatile:
      builder.add("volatile ")
    builder.add(name)
    builder.add(")")
    builder.add(params)
    # ensure we are just adding a variable:
    builder.addLineEnd(";")

type VarInitializerKind = enum
  Assignment, CppConstructor

proc addVar(builder: var Builder, m: BModule, s: PSym, name: string, typ: Snippet, kind = Local, visibility: DeclVisibility = None, initializer: Snippet = "", initializerKind: VarInitializerKind = Assignment) =
  if sfCodegenDecl in s.flags:
    when buildNifc:
      raiseAssert "codegendecl not supported in nifc"
    else:
      builder.add(runtimeFormat(s.cgDeclFrmt, [typ, name]))
      if initializer.len != 0:
        if initializerKind == Assignment:
          builder.add(" = ")
        builder.add(initializer)
      builder.addLineEnd(";")
    return
  when buildNifc:
    builder.addDeclWithVisibility(visibility):
      builder.add("(")
      builder.addVarHeader(kind)
      builder.add(" :")
      builder.add(name)
      # XXX register, volatile, noalias not implemented in nifc
      if s.kind in {skLet, skVar, skField, skForVar} and s.alignment > 0:
        builder.add(" (pragmas (align ")
        builder.addIntValue(s.alignment)
        builder.add(")) ")
      else:
        builder.add(" . ")
      builder.add(typ)
      if initializer.len != 0:
        # XXX c++ initializers not supported?
        builder.add(" ")
        builder.add(initializer)
        builder.addLineEnd(")")
      else:
        builder.addLineEnd(" .)")
  else:
    if s.kind in {skLet, skVar, skField, skForVar} and s.alignment > 0:
      builder.add("NIM_ALIGN(" & $s.alignment & ") ")
    builder.addVisibilityPrefix(visibility)
    if kind == Threadvar:
      if optThreads in m.config.globalOptions:
        let sym = s.typ.sym
        if sym != nil and sfCppNonPod in sym.flags:
          builder.add("NIM_THREAD_LOCAL ")
        else: builder.add("NIM_THREADVAR ")
    else:
      builder.addVarHeader(kind)
    builder.add(typ)
    if sfRegister in s.flags: builder.add(" register")
    if sfVolatile in s.flags: builder.add(" volatile")
    if sfNoalias in s.flags: builder.add(" NIM_NOALIAS")
    builder.add(" ")
    builder.add(name)
    if initializer.len != 0:
      if initializerKind == Assignment:
        builder.add(" = ")
      builder.add(initializer)
    builder.addLineEnd(";")

proc addInclude(builder: var Builder, value: Snippet) =
  when buildNifc:
    builder.add("(incl ")
    builder.add(makeCString(value))
    builder.addLineEnd(")")
  else:
    builder.addLineEnd("#include " & value)
