discard """
  action: compile
"""

# https://github.com/status-im/nimbus-eth2/pull/6554#issuecomment-2354977102
# failed with "for a 'var' type a variable needs to be passed; but 'uint64(result)' is immutable"

import
  std/[typetraits, macros]

type
  DefaultFlavor = object

template serializationFormatImpl(Name: untyped) {.dirty.} =
  type Name = object

template serializationFormat(Name: untyped) =
  serializationFormatImpl(Name)

template setReader(Format, FormatReader: distinct type) =
  when arity(FormatReader) > 1:
    template Reader(T: type Format, F: distinct type = DefaultFlavor): type = FormatReader[F]
  else:
    template ReaderType(T: type Format): type = FormatReader
    template Reader(T: type Format): type = FormatReader

template useDefaultReaderIn(T: untyped, Flavor: type) =
  mixin Reader

  template readValue(r: var Reader(Flavor), value: var T) =
    mixin readRecordValue
    readRecordValue(r, value)

import mvaruintconv

type
  FieldTag[RecordType: object; fieldName: static string] = distinct void

func declval*(T: type): T {.compileTime.} =
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

    let field =
      if isSymbol:
        quote do: declval(`T`).`fieldIdent`
      else:
        quote do: declval(`T`)[`fieldIndex`]

    result.add quote do:
      block:
        `fieldNameDefs`

        template FieldType: untyped {.inject, used.} = typeof(`field`)

        `body`

  # echo repr(result)

template enumAllSerializedFields(T: type, body): untyped =
  enumAllSerializedFieldsImpl(T, body)

type
  FieldReader[RecordType, Reader] = tuple[
    fieldName: string,
    reader: proc (rec: var RecordType, reader: var Reader)
                 {.gcsafe, nimcall.}
  ]

proc totalSerializedFieldsImpl(T: type): int =
  mixin enumAllSerializedFields
  enumAllSerializedFields(T): inc result

template totalSerializedFields(T: type): int =
  (static(totalSerializedFieldsImpl(T)))

template GetFieldType(FT: type FieldTag): type =
  typeof field(declval(FT.RecordType), FT.fieldName)

proc makeFieldReadersTable(RecordType, ReaderType: distinct type,
                           numFields: static[int]):
                           array[numFields, FieldReader[RecordType, ReaderType]] =
  mixin enumAllSerializedFields, handleReadException
  var idx = 0

  enumAllSerializedFields(RecordType):
    proc readField(obj: var RecordType, reader: var ReaderType)
                  {.gcsafe, nimcall.} =

      mixin readValue

      type F = FieldTag[RecordType, realFieldName]
      field(obj, realFieldName) = reader.readValue(GetFieldType(F))

    result[idx] = (fieldName, readField)
    inc idx

proc fieldReadersTable(RecordType, ReaderType: distinct type): auto =
  mixin readValue
  type T = RecordType
  const numFields = totalSerializedFields(T)
  var tbl {.threadvar.}: ref array[numFields, FieldReader[RecordType, ReaderType]]
  if tbl == nil:
    tbl = new typeof(tbl)
    tbl[] = makeFieldReadersTable(RecordType, ReaderType, numFields)
  return addr(tbl[])

proc readValue(reader: var auto, T: type): T =
  mixin readValue
  reader.readValue(result)

template decode(Format: distinct type,
                 input: string,
                 RecordType: distinct type): auto =
  mixin Reader
  block:  # https://github.com/nim-lang/Nim/issues/22874
    var reader: Reader(Format)
    reader.readValue(RecordType)

template readValue(Format: type,
                    ValueType: type): untyped =
  mixin Reader, init, readValue
  var reader: Reader(Format)
  readValue reader, ValueType

template parseArrayImpl(numElem: untyped,
                        actionValue: untyped) =
  actionValue

serializationFormat Json
template createJsonFlavor(FlavorName: untyped,
                           skipNullFields = false) {.dirty.} =
  type FlavorName = object

  template Reader(T: type FlavorName): type = Reader(Json, FlavorName)
type
  JsonReader[Flavor = DefaultFlavor] = object

Json.setReader JsonReader

template parseArray(r: var JsonReader; body: untyped) =
  parseArrayImpl(idx): body

template parseArray(r: var JsonReader; idx: untyped; body: untyped) =
  parseArrayImpl(idx): body

proc readRecordValue[T](r: var JsonReader, value: var T) =
  type
    ReaderType {.used.} = type r
    T = type value

  discard T.fieldReadersTable(ReaderType)

proc readValue[T](r: var JsonReader, value: var T) =
  mixin readValue

  when value is seq:
    r.parseArray:
      readValue(r, value[0])

  elif value is object:
    readRecordValue(r, value)

type
  RemoteSignerInfo = object
    id: uint32
  RemoteKeystore = object

proc readValue(reader: var JsonReader, value: var RemoteKeystore) =
  discard reader.readValue(seq[RemoteSignerInfo])

createJsonFlavor RestJson
useDefaultReaderIn(RemoteSignerInfo, RestJson)
proc readValue(reader: var JsonReader[RestJson], value: var uint64) =
  discard reader.readValue(string)

discard Json.decode("", RemoteKeystore)
block:  # https://github.com/nim-lang/Nim/issues/22874
  var reader: Reader(RestJson)
  discard reader.readValue(RemoteSignerInfo)
