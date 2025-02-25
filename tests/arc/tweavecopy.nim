discard """
  outputsub: '''Success'''
  cmd: '''nim c --gc:arc --threads:on $file'''
  disabled: "bsd"
"""

# bug #13936

import std/atomics

const MemBlockSize = 256

type
  ChannelSPSCSingle* = object
    full{.align: 128.}: Atomic[bool]
    itemSize*: uint8
    buffer*{.align: 8.}: UncheckedArray[byte]

proc `=copy`(
    dest: var ChannelSPSCSingle,
    source: ChannelSPSCSingle
  ) {.error: "A channel cannot be copied".}

proc initialize*(chan: var ChannelSPSCSingle, itemsize: SomeInteger) {.inline.} =
  ## If ChannelSPSCSingle is used intrusive another data structure
  ## be aware that it should be the last part due to ending by UncheckedArray
  ## Also due to 128 bytes padding, it automatically takes half
  ## of the default MemBlockSize
  assert itemsize.int in 0 .. int high(uint8)
  assert itemSize.int +
          sizeof(chan.itemsize) +
          sizeof(chan.full) < MemBlockSize

  chan.itemSize = uint8 itemsize
  chan.full.store(false, moRelaxed)

func isEmpty*(chan: var ChannelSPSCSingle): bool {.inline.} =
  not chan.full.load(moAcquire)

func tryRecv*[T](chan: var ChannelSPSCSingle, dst: var T): bool {.inline.} =
  ## Try receiving the item buffered in the channel
  ## Returns true if successful (channel was not empty)
  ##
  ## ⚠ Use only in the consumer thread that reads from the channel.
  assert (sizeof(T) == chan.itemsize.int) or
          # Support dummy object
          (sizeof(T) == 0 and chan.itemsize == 1)

  let full = chan.full.load(moAcquire)
  if not full:
    return false
  dst = cast[ptr T](chan.buffer.addr)[]
  chan.full.store(false, moRelease)
  return true

func trySend*[T](chan: var ChannelSPSCSingle, src: sink T): bool {.inline.} =
  ## Try sending an item into the channel
  ## Reurns true if successful (channel was empty)
  ##
  ## ⚠ Use only in the producer thread that writes from the channel.
  assert (sizeof(T) == chan.itemsize.int) or
          # Support dummy object
          (sizeof(T) == 0 and chan.itemsize == 1)

  let full = chan.full.load(moAcquire)
  if full:
    return false
  cast[ptr T](chan.buffer.addr)[] = src
  chan.full.store(true, moRelease)
  return true

# Sanity checks
# ------------------------------------------------------------------------------
when isMainModule:

  when not compileOption("threads"):
    {.error: "This requires --threads:on compilation flag".}

  template sendLoop[T](chan: var ChannelSPSCSingle,
                       data: sink T,
                       body: untyped): untyped =
    while not chan.trySend(data):
      body

  template recvLoop[T](chan: var ChannelSPSCSingle,
                       data: var T,
                       body: untyped): untyped =
    while not chan.tryRecv(data):
      body

  type
    ThreadArgs = object
      ID: WorkerKind
      chan: ptr ChannelSPSCSingle

    WorkerKind = enum
      Sender
      Receiver

  template Worker(id: WorkerKind, body: untyped): untyped {.dirty.} =
    if args.ID == id:
      body

  proc thread_func(args: ThreadArgs) =

    # Worker RECEIVER:
    # ---------
    # <- chan
    # <- chan
    # <- chan
    #
    # Worker SENDER:
    # ---------
    # chan <- 42
    # chan <- 53
    # chan <- 64
    Worker(Receiver):
      var val: int = 0
      for j in 0 ..< 10:
        args.chan[].recvLoop(val):
          # Busy loop, in prod we might want to yield the core/thread timeslice
          discard
        echo "                  Receiver got: ", val
        doAssert val == 42 + j*11

    Worker(Sender):
      doAssert args.chan.full.load(moRelaxed) == false
      for j in 0 ..< 10:
        let val = 42 + j*11
        args.chan[].sendLoop(val):
          # Busy loop, in prod we might want to yield the core/thread timeslice
          discard
        echo "Sender sent: ", val

  proc main() =
    echo "Testing if 2 threads can send data"
    echo "-----------------------------------"
    var threads: array[2, Thread[ThreadArgs]] = default(array[2, Thread[ThreadArgs]])

    var chan = cast[ptr ChannelSPSCSingle](allocShared(MemBlockSize))
    chan[].initialize(itemSize = sizeof(int))

    createThread(threads[0], thread_func, ThreadArgs(ID: Receiver, chan: chan))
    createThread(threads[1], thread_func, ThreadArgs(ID: Sender, chan: chan))

    joinThread(threads[0])
    joinThread(threads[1])

    freeShared(chan)

    echo "-----------------------------------"
    echo "Success"

  main()
