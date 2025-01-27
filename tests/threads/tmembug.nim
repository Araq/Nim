
import std / [atomics, strutils, sequtils]

type
  BackendMessage* = object
    field*: seq[int]

var
  chan1: Channel[BackendMessage]
  chan2: Channel[BackendMessage]

chan1.open()
chan2.open()

proc routeMessage*(msg: BackendMessage) =
  discard chan2.trySend(msg)

var
  recv: Thread[void]
  stopToken: Atomic[bool]

proc recvMsg() =
  while not stopToken.load(moRelaxed):
    let resp = chan1.tryRecv()
    if resp.dataAvailable:
      routeMessage(resp.msg)
      echo "child consumes ", formatSize getOccupiedMem()

createThread[void](recv, recvMsg)

const MESSAGE_COUNT = 100

proc main() =
  let msg: BackendMessage = BackendMessage(field: (0..500).toSeq())
  for j in 0..0: #100:
    echo "New iteration"

    for _ in 1..MESSAGE_COUNT:
      chan1.send(msg)
    echo "After sending"

    var counter = 0
    while counter < MESSAGE_COUNT:
      let resp = recv(chan2)
      counter.inc
    echo "After receiving ", formatSize getOccupiedMem()

  stopToken.store true, moRelaxed
  joinThreads(recv)

main()
