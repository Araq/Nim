discard """
  disabled: "true"
"""

import std / [atomics, strutils, sequtils, isolation]

import threading / channels

type
  BackendMessage* = object
    field*: seq[int]

const MESSAGE_COUNT = 100

var
  chan1 = newChan[BackendMessage](MESSAGE_COUNT*2)
  chan2 = newChan[BackendMessage](MESSAGE_COUNT*2)

#chan1.open()
#chan2.open()

proc routeMessage*(msg: BackendMessage) =
  var m = isolate(msg)
  discard chan2.trySend(m)

var
  thr: Thread[void]
  stopToken: Atomic[bool]

proc recvMsg() =
  while not stopToken.load(moRelaxed):
    var resp: BackendMessage
    if chan1.tryRecv(resp):
      #if resp.dataAvailable:
      routeMessage(resp)
      echo "child consumes ", formatSize getOccupiedMem()

createThread[void](thr, recvMsg)

proc main() =
  let msg: BackendMessage = BackendMessage(field: (0..5).toSeq())
  for j in 0..100:
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
  joinThreads(thr)

main()
