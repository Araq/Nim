type
  MinKind* = enum
    minDictionary
    minBool
  MinValue* = object
    case kind*: MinKind
    of minDictionary:
      symbols: seq[MinOperator]
    else: discard
  MinOperator = object

# remove this inline pragma to make it compile
proc `$`*(a: MinValue): string {.inline.} =
  case a.kind
  of minDictionary:
    result = "hello"
    for i in a.symbols:
      result = "hello"
  else: result = ""

proc parseMinValue*(): MinValue =
  # or this echo
  result = MinValue()
  echo result
