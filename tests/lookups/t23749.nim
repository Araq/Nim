discard """
  action: compile
"""

{.pragma: callback, gcsafe, raises: [].}

type
  DataProc* = proc(val: openArray[byte]) {.callback.}
  GetProc = proc (db: RootRef, key: openArray[byte], onData: DataProc): bool {.nimcall, callback.}
  KvStoreRef* = ref object
    obj: RootRef
    getProc: GetProc

template get(dbParam: KvStoreRef, key: openArray[byte], onData: untyped): bool =
  let db = dbParam
  db.getProc(db.obj, key, onData)

func decode(input: openArray[byte], maxSize = 128): seq[byte] =
  @[]

proc getSnappySSZ(db: KvStoreRef, key: openArray[byte]): string =
  var status = "not found"
  proc decode(data: openArray[byte]) =
    status =
      if true: "found"
      else: "corrupted"
  discard db.get(key, decode)
  status


var ksr: KvStoreRef
var k = [byte(1), 2, 3, 4, 5]

proc foo(): string =
  getSnappySSZ(ksr, toOpenArray(k, 1, 3))

echo foo()
