discard """
  targets: "c js"
"""

# bug #21306
type
  FutureState {.pure.} = enum
    Pending, Finished, Cancelled, Failed

  FutureBase = ref object of RootObj
    state: FutureState
    error: ref CatchableError
    id: uint

  Future[T] = ref object of FutureBase
    closure: iterator(f: Future[T]): FutureBase {.raises: [Defect, CatchableError, Exception], gcsafe.}
    value: T

template setupFutureBase() =
  new(result)
  result.state = FutureState.Pending

proc newFutureImpl[T](): Future[T] =
  setupFutureBase()

template newFuture[T](fromProc: static[string] = ""): Future[T] =
  newFutureImpl[T]()

proc internalRead[T](fut: Future[T]): T =
  when T isnot void:
    return fut.value

template await[T](f: Future[T]): untyped =
  when declared(chronosInternalRetFuture):
    when not declaredInScope(chronosInternalTmpFuture):
      var chronosInternalTmpFuture {.inject.}: FutureBase = f
    else:
      chronosInternalTmpFuture = f

    yield chronosInternalTmpFuture

    when T isnot void:
      cast[type(f)](chronosInternalTmpFuture).internalRead()

type
  VerifierError {.pure.} = enum
    Invalid
    MissingParent
    UnviableFork
    Duplicate
  ProcessingCallback = proc() {.gcsafe, raises: [Defect].}
  BlockVerifier =
    proc(signedBlock: int):
      Future[VerifierError] {.gcsafe, raises: [Defect].}

  SyncQueueKind {.pure.} = enum
    Forward, Backward

  SyncRequest[T] = object
    kind: SyncQueueKind
    index: uint64
    slot: uint64
    count: uint64
    item: T

  SyncResult[T] = object
    request: SyncRequest[T]
    data: seq[ref int]

  SyncQueue[T] = ref object
    kind: SyncQueueKind
    readyQueue: seq[SyncResult[T]]
    blockVerifier: BlockVerifier

iterator blocks[T](sq: SyncQueue[T],
                    sr: SyncResult[T]): ref int =
  case sq.kind
  of SyncQueueKind.Forward:
    for i in countup(0, len(sr.data) - 1):
      yield sr.data[i]
  of SyncQueueKind.Backward:
    for i in countdown(len(sr.data) - 1, 0):
      yield sr.data[i]

proc push[T](sq: SyncQueue[T]; sr: SyncRequest[T]; data: seq[ref int];
             processingCb: ProcessingCallback = nil): Future[void] {.
    stackTrace: off, gcsafe.} =
  iterator push_436208182(chronosInternalRetFuture: Future[void]): FutureBase {.
      closure, gcsafe, raises: [Defect, CatchableError, Exception].} =
    block:
      template result(): auto {.used.} =
        {.fatal: "You should not reference the `result` variable inside" &
            " a void async proc".}

      let item = default(SyncResult[T])
      for blk in sq.blocks(item):
        let res = await sq.blockVerifier(blk[])

  var resultFuture = newFuture[void]("push")
  resultFuture.closure = push_436208182
  return resultFuture

type
  SomeTPeer = ref object
    score: int

proc getSlice(): seq[ref int] =
  discard

template smokeTest(kkind: SyncQueueKind, start, finish: uint64,
                   chunkSize: uint64) =
  var queue: SyncQueue[SomeTPeer]
  var request: SyncRequest[SomeTPeer]
  discard queue.push(request, getSlice())

for k in {SyncQueueKind.Forward}:
  for item in [(uint64(1181), uint64(1399), 41'u64)]:
    smokeTest(k, item[0], item[1], item[2])