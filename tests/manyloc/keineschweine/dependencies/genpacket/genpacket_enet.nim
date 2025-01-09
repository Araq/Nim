import macros, macro_dsl, estreams
from strutils import format

template newLenName() =
  let lenName {.inject.} = ^("len" & $lenNames)
  inc(lenNames)

template defPacketImports*() {.dirty.} =
  import macros, macro_dsl, estreams
  from strutils import format

macro defPacket*(typeNameN: untyped, typeFields: untyped): untyped =
  result = newNimNode(nnkStmtList)
  let
    typeName = quoted2ident(typeNameN)
    packetID = ^"p"
    streamID = ^"s"
  var
    constructorParams = newNimNode(nnkFormalParams).und(typeName)
    constructor = newNimNode(nnkProcDef).und(
      postfix(^("new" & $typeName.strVal), "*"),
      emptyNode(),
      emptyNode(),
      constructorParams,
      emptyNode(),
      emptyNode())
    pack = newNimNode(nnkProcDef).und(
      postfix(^"pack", "*"),
      emptyNode(),
      emptyNode(),
      newNimNode(nnkFormalParams).und(
        emptyNode(),   # : void
        newNimNode(nnkIdentDefs).und(
          streamID,    # s: PBuffer
          ^"PBuffer",
          newNimNode(nnkNilLit)),
        newNimNode(nnkIdentDefs).und(
          packetID,    # p: var typeName
          newNimNode(nnkVarTy).und(typeName),
          emptyNode())),
      emptyNode(),
      emptyNode())
    read = newNimNode(nnkProcDef).und(
      newIdentNode("read" & $typeName.strVal).postfix("*"),
      emptyNode(),
      emptyNode(),
      newNimNode(nnkFormalParams).und(
        typeName,   #result type
        newNimNode(nnkIdentDefs).und(
          streamID, # s: PBuffer = nil
          ^"PBuffer",
          newNimNode(nnkNilLit))),
      emptyNode(),
      emptyNode())
    constructorBody = newNimNode(nnkStmtList)
    packBody = newNimNode(nnkStmtList)
    readBody = newNimNode(nnkStmtList)
    lenNames = 0
  for i in 0.. typeFields.len - 1:
    let
      name = typeFields[i][0]
      dotName = packetID.dot(name)
      resName = newIdentNode("result").dot(name)
    case typeFields[i][1].kind
    of nnkBracketExpr: #ex: paddedstring[32, '\0'], array[range, type]
      case $typeFields[i][1][0].strVal
      of "seq":
        ## let lenX = readInt16(s)
        newLenName()
        let
          item = ^"item"  ## item name in our iterators
          seqType = typeFields[i][1][1] ## type of seq
          readName = newIdentNode("read" & $seqType.strVal)
        readBody.add(newNimNode(nnkLetSection).und(
          newNimNode(nnkIdentDefs).und(
            lenName,
            newNimNode(nnkEmpty),
            newCall("readInt16", streamID))))
        readBody.add(      ## result.name = @[]
          resName := ("@".prefix(newNimNode(nnkBracket))),
          newNimNode(nnkForStmt).und(  ## for item in 1..len:
            item,
            infix(1.lit, "..", lenName),
            newNimNode(nnkStmtList).und(
              newCall(  ## add(result.name, unpack[seqType](stream))
                "add", resName, newNimNode(nnkCall).und(readName, streamID)
        ) ) ) )
        packbody.add(
          newNimNode(nnkVarSection).und(newNimNode(nnkIdentDefs).und(
            lenName,  ## var lenName = int16(len(p.name))
            newIdentNode("int16"),
            newCall("int16", newCall("len", dotName)))),
          newCall("writeBE", streamID, lenName),
          newNimNode(nnkForStmt).und(  ## for item in 0..length - 1: pack(p.name[item], stream)
            item,
            infix(0.lit, "..", infix(lenName, "-", 1.lit)),
            newNimNode(nnkStmtList).und(
              newCall("echo", item, ": ".lit),
              newCall("pack", streamID, dotName[item]))))
        #set the default value to @[] (new sequence)
        typeFields[i][2] = "@".prefix(newNimNode(nnkBracket))
      else:
        error("Unknown type: " & treeRepr(typeFields[i]))
    of nnkIdent: ##normal type
      case $typeFields[i][1].strVal
      of "string": # length encoded string
        packBody.add(newCall("write", streamID, dotName))
        readBody.add(resName := newCall("readStr", streamID))
      of "int8", "int16", "int32", "float32", "float64", "char", "bool":
        packBody.add(newCall(
          "writeBE", streamID, dotName))
        readBody.add(resName := newCall("read" & $typeFields[i][1].strVal, streamID))
      else:  ## hopefully the type you specified was another defpacket() type
        packBody.add(newCall("pack", streamID, dotName))
        readBody.add(resName := newCall("read" & $typeFields[i][1].strVal, streamID))
    else:
      error("I don't know what to do with: " & treerepr(typeFields[i]))

  var
    toStringFunc = newNimNode(nnkProcDef).und(
      newNimNode(nnkPostfix).und(
        ^"*",
        newNimNode(nnkAccQuoted).und(^"$")),
      emptyNode(),
      emptyNode(),
      newNimNode(nnkFormalParams).und(
        ^"string",
        newNimNode(nnkIdentDefs).und(
          packetID, # p: typeName
          typeName,
          emptyNode())),
      emptyNode(),
      emptyNode(),
      newNimNode(nnkStmtList).und(# [6]
        newNimNode(nnkAsgn).und(
          ^"result",                  ## result =
          newNimNode(nnkCall).und(# [6][0][1]
            ^"format",  ## format
            emptyNode()))))  ## "[TypeName   $1   $2]"
    formatStr = "[" & $typeName.strVal

  const emptyFields = {nnkEmpty, nnkNilLit}
  var objFields = newNimNode(nnkRecList)
  for i in 0 ..< len(typeFields):
    let fname = typeFields[i][0]
    constructorParams.add(newNimNode(nnkIdentDefs).und(
      fname,
      typeFields[i][1],
      typeFields[i][2]))
    constructorBody.add((^"result").dot(fname) := fname)
    #export the name
    typeFields[i][0] = fname.postfix("*")
    if not(typeFields[i][2].kind in emptyFields):
      ## empty the type default for the type def
      typeFields[i][2] = newNimNode(nnkEmpty)
    objFields.add(typeFields[i])
    toStringFunc[6][0][1].add(
      prefix("$", packetID.dot(fname)))
    formatStr.add "   $"
    formatStr.add($(i + 1))

  formatStr.add ']'
  toStringFunc[6][0][1][1] = formatStr.lit()

  result.add(
    newNimNode(nnkTypeSection).und(
      newNimNode(nnkTypeDef).und(
        typeName.postfix("*"),
        newNimNode(nnkEmpty),
        newNimNode(nnkObjectTy).und(
          newNimNode(nnkEmpty), #not sure what this is
          newNimNode(nnkEmpty), #parent: OfInherit(Ident(!"SomeObj"))
          objFields))))
  result.add(constructor.und(constructorBody))
  result.add(pack.und(packBody))
  result.add(read.und(readBody))
  result.add(toStringFunc)
  when defined(GenPacketShowOutput):
    echo(repr(result))

proc newProc*(name: NimNode; params: varargs[NimNode]; resultType: NimNode): NimNode {.compileTime.} =
  result = newNimNode(nnkProcDef).und(
    name,
    emptyNode(),
    emptyNode(),
    newNimNode(nnkFormalParams).und(resultType),
    emptyNode(),
    emptyNode(),
    newNimNode(nnkStmtList))
  result[3].add(params)

proc body*(procNode: NimNode): NimNode {.compileTime.} =
  assert procNode.kind == nnkProcDef and procNode[6].kind == nnkStmtList
  result = procNode[6]

proc iddefs*(a, b: string; c: NimNode): NimNode {.compileTime.} =
  result = newNimNode(nnkIdentDefs).und(^a, ^b, c)
proc iddefs*(a: string; b: NimNode): NimNode {.compileTime.} =
  result = newNimNode(nnkIdentDefs).und(^a, b, emptyNode())
proc varTy*(a: NimNode): NimNode {.compileTime.} =
  result = newNimNode(nnkVarTy).und(a)

macro forwardPacket*(typeName: untyped, underlyingType: untyped): untyped =
  var
    packetID = ^"p"
    streamID = ^"s"
  result = newNimNode(nnkStmtList).und(
    newProc(
      (^("read" & $typeName.strVal)).postfix("*"),
      [ iddefs("s", "PBuffer", newNimNode(nnkNilLit)) ],
      typeName),
    newProc(
      (^"pack").postfix("*"),
      [ iddefs("s", "PBuffer", newNimNode(nnkNilLit)),
        iddefs("p", varTy(typeName)) ],
      emptyNode()))
  var
    readBody = result[0][6]
    packBody = result[1][6]
    resName = ^"result"

  case underlyingType.kind
  of nnkBracketExpr:
    case $underlyingType[0].strVal
    of "array":
      for i in underlyingType[1][1].intval.int .. underlyingType[1][2].intval.int:
        readBody.add(
          newCall("read", ^"s", resName[lit(i)]))
        packBody.add(
          newCall("writeBE", ^"s", packetID[lit(i)]))
    else:
      echo "Unknown type: ", repr(underlyingtype)
  else:
    echo "unknown type:", repr(underlyingtype)
  echo(repr(result))

template forwardPacketT*(typeName: untyped; underlyingType: untyped) {.dirty.} =
  proc `read typeName`*(buffer: PBuffer): typeName =
    #discard readData(s, addr result, sizeof(result))
    var res: underlyingType
    buffer.read(res)
    result = typeName(res)
  proc `pack`*(buffer: PBuffer; ord: var typeName) =
    #writeData(s, addr p, sizeof(p))
    buffer.write(underlyingType(ord))

when false:
  type
    SomeEnum = enum
      A = 0'i8,
      B, C
  forwardPacket(SomeEnum, int8)


  defPacket(Foo, tuple[x: array[0..4, int8]])
  var f = newFoo([4'i8, 3'i8, 2'i8, 1'i8, 0'i8])
  var s2 = newStringStream("")
  f.pack(s2)
  assert s2.data == "\4\3\2\1\0"

  var s = newStringStream()
  s.flushImpl = proc(s: PStream) =
    var z = PStringStream(s)
    z.setPosition(0)
    z.data.setLen(0)


  s.setPosition(0)
  s.data.setLen(0)
  var o = B
  o.pack(s)
  o = A
  o.pack(s)
  o = C
  o.pack(s)
  assert s.data == "\1\0\2"
  s.flush

  defPacket(Y, tuple[z: int8])
  proc `$`(z: Y): string = result = "Y(" & $z.z & ")"
  defPacket(TestPkt, tuple[x: seq[Y]])
  var test = newTestPkt()
  test.x.add([newY(5), newY(4), newY(3), newY(2), newY(1)])
  for itm in test.x:
    echo(itm)
  test.pack(s)
  echo(repr(s.data))
