import std/tables
import ast

type
  LayeredIdTableObj* {.acyclic.} = object
    ## stack of type binding contexts implemented as a linked list
    topLayer*: TypeMapping
      ## the mappings on the current layer
    nextLayer*: ref LayeredIdTableObj
      ## the parent type binding context, possibly `nil`
    previousLen*: int
      ## total length of the bindings up to the parent layer,
      ## used to track if new bindings were added

const useRef = not defined(gcDestructors)
  # implementation detail, only arc/orc doesn't cause issues when
  # using LayeredIdTable as an object and not a ref

when useRef:
  type LayeredIdTable* = ref LayeredIdTableObj
else:
  type LayeredIdTable* = LayeredIdTableObj

proc initLayeredTypeMap*(pt: sink TypeMapping = initTypeMapping()): LayeredIdTable =
  result = LayeredIdTable(topLayer: pt, nextLayer: nil)

proc shallowCopy*(pt: LayeredIdTable): LayeredIdTable {.inline.} =
  ## copies only the type bindings of the current layer, but not any parent layers,
  ## useful for write-only bindings
  result = LayeredIdTable(topLayer: pt.topLayer, nextLayer: pt.nextLayer, previousLen: pt.previousLen)

proc currentLen*(pt: LayeredIdTable): int =
  ## the sum of the cached total binding count of the parents and
  ## the current binding count, just used to track if bindings were added
  pt.previousLen + pt.topLayer.len

proc newTypeMapLayer*(pt: LayeredIdTable): LayeredIdTable =
  result = LayeredIdTable(topLayer: initTable[ItemId, PType](), previousLen: pt.currentLen)
  when useRef:
    result.nextLayer = pt
  else:
    new(result.nextLayer)
    result.nextLayer[] = pt

proc setToPreviousLayer*(pt: var LayeredIdTable) {.inline.} =
  when useRef:
    pt = pt.nextLayer
  else:
    when defined(gcDestructors):
      pt = pt.nextLayer[]
    else:
      # workaround refc
      let tmp = pt.nextLayer[]
      pt = tmp

proc lookup(typeMap: ref LayeredIdTableObj, key: ItemId): PType =
  result = nil
  var tm = typeMap
  while tm != nil:
    result = getOrDefault(tm.topLayer, key)
    if result != nil: return
    tm = tm.nextLayer

template lookup*(typeMap: ref LayeredIdTableObj, key: PType): PType =
  ## recursively looks up binding of `key` in all parent layers
  lookup(typeMap, key.itemId)

when not useRef:
  proc lookup(typeMap: LayeredIdTableObj, key: ItemId): PType {.inline.} =
    result = getOrDefault(typeMap.topLayer, key)
    if result == nil and typeMap.nextLayer != nil:
      result = lookup(typeMap.nextLayer, key)

  template lookup*(typeMap: LayeredIdTableObj, key: PType): PType =
    lookup(typeMap, key.itemId)

proc put(typeMap: var LayeredIdTable, key: ItemId, value: PType) {.inline.} =
  typeMap.topLayer[key] = value

template put*(typeMap: var LayeredIdTable, key, value: PType) =
  ## binds `key` to `value` only in current layer
  put(typeMap, key.itemId, value)
