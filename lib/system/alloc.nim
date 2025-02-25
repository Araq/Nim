#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# Low level allocator for Nim. Has been designed to support the GC.
{.push profiler:off.}

include osalloc
import std/private/syslocks
import std/sysatomics

template track(op, address, size) =
  when defined(memTracker):
    memTrackerOp(op, address, size)

# We manage *chunks* of memory. Each chunk is a multiple of the page size.
# Each chunk starts at an address that is divisible by the page size.
# Small chunks may be divided into smaller cells of reusable pointers to reduce the number of page allocations.

# An allocation of a small pointer looks approximately like this
#[

  alloc -> rawAlloc -> No free chunk available > Request a new page from tslf -> result = chunk.data -------------+
              |                                                                                                   |
              v                                                                                                   |
    Free chunk available                                                                                          |
              |                                                                                                   |
              v                                                                                                   v
      Fetch shared cells -> No free cells available -> Advance acc -> result = chunk.data + chunk.acc -------> return
    (may not add new cells)                                                                                       ^
              |                                                                                                   |
              v                                                                                                   |
     Free cells available -> result = chunk.freeList -> Advance chunk.freeList -----------------------------------+
]#
# so it is split into 3 paths, where the last path is preferred to prevent unnecessary allocations.
#
#
# A deallocation of a small pointer then looks like this
#[
  dealloc -> rawDealloc -> chunk.owner == addr(a) --------------> This thread owns the chunk ------> The current chunk is active    -> Chunk is completely unused -----> Chunk references no foreign cells
                                      |                                       |                   (Add cell into the current chunk)                 |                  Return the current chunk back to tlsf
                                      |                                       |                                   |                                 |
                                      v                                       v                                   v                                 v
                      A different thread owns this chunk.     The current chunk is not active.          chunk.free was < size      Chunk references foreign cells, noop
                      Add the cell to a.sharedFreeLists      Add the cell into the active chunk          Activate the chunk                       (end)
                                    (end)                                    (end)                              (end)
]#
# So "true" deallocation is delayed for as long as possible in favor of reusing cells.

const
  nimMinHeapPages {.intdefine.} = 128 # 0.5 MB
  SmallChunkSize = PageSize
  MaxFli = when sizeof(int) > 2: 30 else: 14
  MaxLog2Sli = 5 # 32, this cannot be increased without changing 'uint32'
                 # everywhere!
  MaxSli = 1 shl MaxLog2Sli
  FliOffset = 6
  RealFli = MaxFli - FliOffset

  # size of chunks in last matrix bin
  MaxBigChunkSize = int(1'i32 shl MaxFli - 1'i32 shl (MaxFli-MaxLog2Sli-1))
  HugeChunkSize = MaxBigChunkSize + 1

type
  PTrunk = ptr Trunk
  Trunk = object
    next: PTrunk         # all nodes are connected with this pointer
    key: int             # start address at bit 0
    bits: array[0..IntsPerTrunk-1, uint] # a bit vector

  TrunkBuckets = array[0..255, PTrunk]
  IntSet = object
    data: TrunkBuckets

# ------------- chunk table ---------------------------------------------------
# We use a PtrSet of chunk starts and a table[Page, chunksize] for chunk
# endings of big chunks. This is needed by the merging operation. The only
# remaining operation is best-fit for big chunks. Since there is a size-limit
# for big chunks (because greater than the limit means they are returned back
# to the OS), a fixed size array can be used.

type
  PLLChunk = ptr LLChunk
  LLChunk = object ## *low-level* chunk
    size: int                # remaining size
    acc: int                 # accumulator
    next: PLLChunk           # next low-level chunk; only needed for dealloc

  PAvlNode = ptr AvlNode
  AvlNode = object
    link: array[0..1, PAvlNode] # Left (0) and right (1) links
    key, upperBound: int
    level: int

const
  RegionHasLock = false # hasThreadSupport and defined(gcDestructors)

type
  FreeCell {.final, pure.} = object
    # A free cell is a pointer that has been freed, meaning it became available for reuse.
    # It may become foreign if it is lent to a chunk that did not create it, doing so reduces the amount of needed pages.
    next: ptr FreeCell  # next free cell in chunk (overlaid with refcount)
    when not defined(gcDestructors):
      zeroField: int       # 0 means cell is not used (overlaid with typ field)
                          # 1 means cell is manually managed pointer
                          # otherwise a PNimType is stored in there
    else:
      alignment: int

  PChunk = ptr BaseChunk
  PBigChunk = ptr BigChunk
  PSmallChunk = ptr SmallChunk
  BaseChunk {.pure, inheritable.} = object
    prevSize: int        # size of previous chunk; for coalescing
                         # 0th bit == 1 if 'used
    size: int            # if < PageSize it is a small chunk
    owner: ptr MemRegion

  SmallChunk = object of BaseChunk
    next, prev: PSmallChunk  # chunks of the same size
    freeList: ptr FreeCell   # Singly linked list of cells. They may be from foreign chunks or from the current chunk.
                             #  Should be `nil` when the chunk isn't active in `a.freeSmallChunks`.
    free: int32              # Bytes this chunk is able to provide using both the accumulator and free cells.
                             # When a cell is considered foreign, its source chunk's free field is NOT adjusted until it
                             #  reaches dealloc while the source chunk is active.
                             # Instead, the receiving chunk gains the capacity and thus reserves space in the foreign chunk.
    acc: uint32              # Offset from data, used when there are no free cells available but the chunk is considered free.
    foreignCells: int        # When a free cell is given to a chunk that is not its origin,
                             #  both the cell and the source chunk are considered foreign.
                             # Receiving a foreign cell can happen both when deallocating from another thread or when
                             #  the active chunk in `a.freeSmallChunks` is not the current chunk.
                             # Freeing a chunk while `foreignCells > 0` leaks memory as all references to it become lost.
    data {.align: MemAlign.}: UncheckedArray[byte]      # start of usable memory

  BigChunk = object of BaseChunk # not necessarily > PageSize!
    next, prev: PBigChunk    # chunks of the same (or bigger) size
    data {.align: MemAlign.}: UncheckedArray[byte]      # start of usable memory

  HeapLinks = object
    len: int
    chunks: array[30, (PBigChunk, int)]
    next: ptr HeapLinks

  MemRegion = object
    when not defined(gcDestructors):
      minLargeObj, maxLargeObj: int
    freeSmallChunks: array[0..max(1, SmallChunkSize div MemAlign-1), PSmallChunk]
      # List of available chunks per size class. Only one is expected to be active per class.
    when defined(gcDestructors):
      sharedFreeLists: array[0..max(1, SmallChunkSize div MemAlign-1), ptr FreeCell]
        # When a thread frees a pointer it did not create, it must not adjust the counters.
        # Instead, the cell is placed here and deferred until the next allocation.
    flBitmap: uint32
    slBitmap: array[RealFli, uint32]
    matrix: array[RealFli, array[MaxSli, PBigChunk]]
    llmem: PLLChunk
    currMem, maxMem, freeMem, occ: int # memory sizes (allocated from OS)
    lastSize: int # needed for the case that OS gives us pages linearly
    when RegionHasLock:
      lock: SysLock
    when defined(gcDestructors):
      sharedFreeListBigChunks: PBigChunk # make no attempt at avoiding false sharing for now for this object field

    chunkStarts: IntSet
    when not defined(gcDestructors):
      root, deleted, last, freeAvlNodes: PAvlNode
    lockActive, locked, blockChunkSizeIncrease: bool # if locked, we cannot free pages.
    nextChunkSize: int
    when not defined(gcDestructors):
      bottomData: AvlNode
    heapLinks: HeapLinks
    when defined(nimTypeNames):
      allocCounter, deallocCounter: int

template smallChunkOverhead(): untyped = sizeof(SmallChunk)
template bigChunkOverhead(): untyped = sizeof(BigChunk)

when hasThreadSupport:
  template loada(x: untyped): untyped = atomicLoadN(unsafeAddr x, ATOMIC_RELAXED)
  template storea(x, y: untyped) = atomicStoreN(unsafeAddr x, y, ATOMIC_RELAXED)

  when false:
    # not yet required
    template atomicStatDec(x, diff: untyped) = discard atomicSubFetch(unsafeAddr x, diff, ATOMIC_RELAXED)
    template atomicStatInc(x, diff: untyped) = discard atomicAddFetch(unsafeAddr x, diff, ATOMIC_RELAXED)
else:
  template loada(x: untyped): untyped = x
  template storea(x, y: untyped) = x = y

template atomicStatDec(x, diff: untyped) = dec x, diff
template atomicStatInc(x, diff: untyped) = inc x, diff

const
  fsLookupTable: array[byte, int8] = [
    -1'i8, 0, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3,
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
    5, 5, 5, 5, 5, 5, 5, 5,
    6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7
  ]

proc msbit(x: uint32): int {.inline.} =
  let a = if x <= 0xff_ff'u32:
            (if x <= 0xff: 0 else: 8)
          else:
            (if x <= 0xff_ff_ff'u32: 16 else: 24)
  result = int(fsLookupTable[byte(x shr a)]) + a

proc lsbit(x: uint32): int {.inline.} =
  msbit(x and ((not x) + 1))

proc setBit(nr: int; dest: var uint32) {.inline.} =
  dest = dest or (1u32 shl (nr and 0x1f))

proc clearBit(nr: int; dest: var uint32) {.inline.} =
  dest = dest and not (1u32 shl (nr and 0x1f))

proc mappingSearch(r, fl, sl: var int) {.inline.} =
  #let t = (1 shl (msbit(uint32 r) - MaxLog2Sli)) - 1
  # This diverges from the standard TLSF algorithm because we need to ensure
  # PageSize alignment:
  let t = roundup((1 shl (msbit(uint32 r) - MaxLog2Sli)), PageSize) - 1
  r = r + t
  r = r and not t
  r = min(r, MaxBigChunkSize).int
  fl = msbit(uint32 r)
  sl = (r shr (fl - MaxLog2Sli)) - MaxSli
  dec fl, FliOffset
  sysAssert((r and PageMask) == 0, "mappingSearch: still not aligned")

# See http://www.gii.upv.es/tlsf/files/papers/tlsf_desc.pdf for details of
# this algorithm.

proc mappingInsert(r: int): tuple[fl, sl: int] {.inline.} =
  sysAssert((r and PageMask) == 0, "mappingInsert: still not aligned")
  result.fl = msbit(uint32 r)
  result.sl = (r shr (result.fl - MaxLog2Sli)) - MaxSli
  dec result.fl, FliOffset

template mat(): untyped = a.matrix[fl][sl]

proc findSuitableBlock(a: MemRegion; fl, sl: var int): PBigChunk {.inline.} =
  let tmp = a.slBitmap[fl] and (not 0u32 shl sl)
  result = nil
  if tmp != 0:
    sl = lsbit(tmp)
    result = mat()
  else:
    fl = lsbit(a.flBitmap and (not 0u32 shl (fl + 1)))
    if fl > 0:
      sl = lsbit(a.slBitmap[fl])
      result = mat()

template clearBits(sl, fl) =
  clearBit(sl, a.slBitmap[fl])
  if a.slBitmap[fl] == 0u32:
    # do not forget to cascade:
    clearBit(fl, a.flBitmap)

proc removeChunkFromMatrix(a: var MemRegion; b: PBigChunk) =
  let (fl, sl) = mappingInsert(b.size)
  if b.next != nil: b.next.prev = b.prev
  if b.prev != nil: b.prev.next = b.next
  if mat() == b:
    mat() = b.next
    if mat() == nil:
      clearBits(sl, fl)
  b.prev = nil
  b.next = nil

proc removeChunkFromMatrix2(a: var MemRegion; b: PBigChunk; fl, sl: int) =
  mat() = b.next
  if mat() != nil:
    mat().prev = nil
  else:
    clearBits(sl, fl)
  b.prev = nil
  b.next = nil

proc addChunkToMatrix(a: var MemRegion; b: PBigChunk) =
  let (fl, sl) = mappingInsert(b.size)
  b.prev = nil
  b.next = mat()
  if mat() != nil:
    mat().prev = b
  mat() = b
  setBit(sl, a.slBitmap[fl])
  setBit(fl, a.flBitmap)

proc incCurrMem(a: var MemRegion, bytes: int) {.inline.} =
  atomicStatInc(a.currMem, bytes)

proc decCurrMem(a: var MemRegion, bytes: int) {.inline.} =
  a.maxMem = max(a.maxMem, a.currMem)
  atomicStatDec(a.currMem, bytes)

proc getMaxMem(a: var MemRegion): int =
  # Since we update maxPagesCount only when freeing pages,
  # maxPagesCount may not be up to date. Thus we use the
  # maximum of these both values here:
  result = max(a.currMem, a.maxMem)

const nimMaxHeap {.intdefine.} = 0

proc allocPages(a: var MemRegion, size: int): pointer =
  when nimMaxHeap != 0:
    if a.occ + size > nimMaxHeap * 1024 * 1024:
      raiseOutOfMem()
  osAllocPages(size)

proc tryAllocPages(a: var MemRegion, size: int): pointer =
  when nimMaxHeap != 0:
    if a.occ + size > nimMaxHeap * 1024 * 1024:
      raiseOutOfMem()
  osTryAllocPages(size)

proc llAlloc(a: var MemRegion, size: int): pointer =
  # *low-level* alloc for the memory managers data structures. Deallocation
  # is done at the end of the allocator's life time.
  if a.llmem == nil or size > a.llmem.size:
    # the requested size is ``roundup(size+sizeof(LLChunk), PageSize)``, but
    # since we know ``size`` is a (small) constant, we know the requested size
    # is one page:
    sysAssert roundup(size+sizeof(LLChunk), PageSize) == PageSize, "roundup 6"
    var old = a.llmem # can be nil and is correct with nil
    a.llmem = cast[PLLChunk](allocPages(a, PageSize))
    when defined(nimAvlcorruption):
      trackLocation(a.llmem, PageSize)
    incCurrMem(a, PageSize)
    a.llmem.size = PageSize - sizeof(LLChunk)
    a.llmem.acc = sizeof(LLChunk)
    a.llmem.next = old
  result = cast[pointer](cast[int](a.llmem) + a.llmem.acc)
  dec(a.llmem.size, size)
  inc(a.llmem.acc, size)
  zeroMem(result, size)

when not defined(gcDestructors):
  proc getBottom(a: var MemRegion): PAvlNode =
    result = addr(a.bottomData)
    if result.link[0] == nil:
      result.link[0] = result
      result.link[1] = result

  proc allocAvlNode(a: var MemRegion, key, upperBound: int): PAvlNode =
    if a.freeAvlNodes != nil:
      result = a.freeAvlNodes
      a.freeAvlNodes = a.freeAvlNodes.link[0]
    else:
      result = cast[PAvlNode](llAlloc(a, sizeof(AvlNode)))
      when defined(nimAvlcorruption):
        cprintf("tracking location: %p\n", result)
    result.key = key
    result.upperBound = upperBound
    let bottom = getBottom(a)
    result.link[0] = bottom
    result.link[1] = bottom
    result.level = 1
    #when defined(nimAvlcorruption):
    #  track("allocAvlNode", result, sizeof(AvlNode))
    sysAssert(bottom == addr(a.bottomData), "bottom data")
    sysAssert(bottom.link[0] == bottom, "bottom link[0]")
    sysAssert(bottom.link[1] == bottom, "bottom link[1]")

  proc deallocAvlNode(a: var MemRegion, n: PAvlNode) {.inline.} =
    n.link[0] = a.freeAvlNodes
    a.freeAvlNodes = n

proc addHeapLink(a: var MemRegion; p: PBigChunk, size: int): ptr HeapLinks =
  var it = addr(a.heapLinks)
  while it != nil and it.len >= it.chunks.len: it = it.next
  if it == nil:
    var n = cast[ptr HeapLinks](llAlloc(a, sizeof(HeapLinks)))
    n.next = a.heapLinks.next
    a.heapLinks.next = n
    n.chunks[0] = (p, size)
    n.len = 1
    result = n
  else:
    let L = it.len
    it.chunks[L] = (p, size)
    inc it.len
    result = it

when not defined(gcDestructors):
  include "system/avltree"

proc llDeallocAll(a: var MemRegion) =
  var it = a.llmem
  while it != nil:
    # we know each block in the list has the size of 1 page:
    var next = it.next
    osDeallocPages(it, PageSize)
    it = next
  a.llmem = nil

proc intSetGet(t: IntSet, key: int): PTrunk =
  var it = t.data[key and high(t.data)]
  while it != nil:
    if it.key == key: return it
    it = it.next
  result = nil

proc intSetPut(a: var MemRegion, t: var IntSet, key: int): PTrunk =
  result = intSetGet(t, key)
  if result == nil:
    result = cast[PTrunk](llAlloc(a, sizeof(result[])))
    result.next = t.data[key and high(t.data)]
    t.data[key and high(t.data)] = result
    result.key = key

proc contains(s: IntSet, key: int): bool =
  var t = intSetGet(s, key shr TrunkShift)
  if t != nil:
    var u = key and TrunkMask
    result = (t.bits[u shr IntShift] and (uint(1) shl (u and IntMask))) != 0
  else:
    result = false

proc incl(a: var MemRegion, s: var IntSet, key: int) =
  var t = intSetPut(a, s, key shr TrunkShift)
  var u = key and TrunkMask
  t.bits[u shr IntShift] = t.bits[u shr IntShift] or (uint(1) shl (u and IntMask))

proc excl(s: var IntSet, key: int) =
  var t = intSetGet(s, key shr TrunkShift)
  if t != nil:
    var u = key and TrunkMask
    t.bits[u shr IntShift] = t.bits[u shr IntShift] and not
        (uint(1) shl (u and IntMask))

iterator elements(t: IntSet): int {.inline.} =
  # while traversing it is forbidden to change the set!
  for h in 0..high(t.data):
    var r = t.data[h]
    while r != nil:
      var i = 0
      while i <= high(r.bits):
        var w = r.bits[i] # taking a copy of r.bits[i] here is correct, because
        # modifying operations are not allowed during traversation
        var j = 0
        while w != 0:         # test all remaining bits for zero
          if (w and 1) != 0:  # the bit is set!
            yield (r.key shl TrunkShift) or (i shl IntShift +% j)
          inc(j)
          w = w shr 1
        inc(i)
      r = r.next

proc isSmallChunk(c: PChunk): bool {.inline.} =
  result = c.size <= SmallChunkSize-smallChunkOverhead()

proc chunkUnused(c: PChunk): bool {.inline.} =
  result = (c.prevSize and 1) == 0

iterator allObjects(m: var MemRegion): pointer {.inline.} =
  m.locked = true
  for s in elements(m.chunkStarts):
    # we need to check here again as it could have been modified:
    if s in m.chunkStarts:
      let c = cast[PChunk](s shl PageShift)
      if not chunkUnused(c):
        if isSmallChunk(c):
          var c = cast[PSmallChunk](c)

          let size = c.size
          var a = cast[int](addr(c.data))
          let limit = a + c.acc.int
          while a <% limit:
            yield cast[pointer](a)
            a = a +% size
        else:
          let c = cast[PBigChunk](c)
          yield addr(c.data)
  m.locked = false

proc iterToProc*(iter: typed, envType: typedesc; procName: untyped) {.
                      magic: "Plugin", compileTime.}

when not defined(gcDestructors):
  proc isCell(p: pointer): bool {.inline.} =
    result = cast[ptr FreeCell](p).zeroField >% 1

# ------------- chunk management ----------------------------------------------
proc pageIndex(c: PChunk): int {.inline.} =
  result = cast[int](c) shr PageShift

proc pageIndex(p: pointer): int {.inline.} =
  result = cast[int](p) shr PageShift

proc pageAddr(p: pointer): PChunk {.inline.} =
  result = cast[PChunk](cast[int](p) and not PageMask)
  #sysAssert(Contains(allocator.chunkStarts, pageIndex(result)))

when false:
  proc writeFreeList(a: MemRegion) =
    var it = a.freeChunksList
    c_fprintf(stdout, "freeChunksList: %p\n", it)
    while it != nil:
      c_fprintf(stdout, "it: %p, next: %p, prev: %p, size: %ld\n",
                it, it.next, it.prev, it.size)
      it = it.next

proc requestOsChunks(a: var MemRegion, size: int): PBigChunk =
  when not defined(emscripten):
    if not a.blockChunkSizeIncrease:
      let usedMem = a.occ #a.currMem # - a.freeMem
      if usedMem < 64 * 1024:
        a.nextChunkSize = PageSize*4
      else:
        a.nextChunkSize = min(roundup(usedMem shr 2, PageSize), a.nextChunkSize * 2)
        a.nextChunkSize = min(a.nextChunkSize, MaxBigChunkSize).int

  var size = size
  if size > a.nextChunkSize:
    result = cast[PBigChunk](allocPages(a, size))
  else:
    result = cast[PBigChunk](tryAllocPages(a, a.nextChunkSize))
    if result == nil:
      result = cast[PBigChunk](allocPages(a, size))
      a.blockChunkSizeIncrease = true
    else:
      size = a.nextChunkSize

  incCurrMem(a, size)
  inc(a.freeMem, size)
  let heapLink = a.addHeapLink(result, size)
  when defined(debugHeapLinks):
    cprintf("owner: %p; result: %p; next pointer %p; size: %ld\n", addr(a),
      result, heapLink, size)

  when defined(memtracker):
    trackLocation(addr result.size, sizeof(int))

  sysAssert((cast[int](result) and PageMask) == 0, "requestOsChunks 1")
  #zeroMem(result, size)
  result.next = nil
  result.prev = nil
  result.size = size
  # update next.prevSize:
  var nxt = cast[int](result) +% size
  sysAssert((nxt and PageMask) == 0, "requestOsChunks 2")
  var next = cast[PChunk](nxt)
  if pageIndex(next) in a.chunkStarts:
    #echo("Next already allocated!")
    next.prevSize = size or (next.prevSize and 1)
  # set result.prevSize:
  var lastSize = if a.lastSize != 0: a.lastSize else: PageSize
  var prv = cast[int](result) -% lastSize
  sysAssert((nxt and PageMask) == 0, "requestOsChunks 3")
  var prev = cast[PChunk](prv)
  if pageIndex(prev) in a.chunkStarts and prev.size == lastSize:
    #echo("Prev already allocated!")
    result.prevSize = lastSize or (result.prevSize and 1)
  else:
    result.prevSize = 0 or (result.prevSize and 1) # unknown
    # but do not overwrite 'used' field
  a.lastSize = size # for next request
  sysAssert((cast[int](result) and PageMask) == 0, "requestOschunks: unaligned chunk")

proc isAccessible(a: MemRegion, p: pointer): bool {.inline.} =
  result = contains(a.chunkStarts, pageIndex(p))

proc contains[T](list, x: T): bool =
  result = false
  var it = list
  while it != nil:
    if it == x: return true
    it = it.next

proc listAdd[T](head: var T, c: T) {.inline.} =
  sysAssert(c notin head, "listAdd 1")
  sysAssert c.prev == nil, "listAdd 2"
  sysAssert c.next == nil, "listAdd 3"
  c.next = head
  if head != nil:
    sysAssert head.prev == nil, "listAdd 4"
    head.prev = c
  head = c

proc listRemove[T](head: var T, c: T) {.inline.} =
  sysAssert(c in head, "listRemove")
  if c == head:
    head = c.next
    sysAssert c.prev == nil, "listRemove 2"
    if head != nil: head.prev = nil
  else:
    sysAssert c.prev != nil, "listRemove 3"
    c.prev.next = c.next
    if c.next != nil: c.next.prev = c.prev
  c.next = nil
  c.prev = nil

proc updatePrevSize(a: var MemRegion, c: PBigChunk,
                    prevSize: int) {.inline.} =
  var ri = cast[PChunk](cast[int](c) +% c.size)
  sysAssert((cast[int](ri) and PageMask) == 0, "updatePrevSize")
  if isAccessible(a, ri):
    ri.prevSize = prevSize or (ri.prevSize and 1)

proc splitChunk2(a: var MemRegion, c: PBigChunk, size: int): PBigChunk =
  result = cast[PBigChunk](cast[int](c) +% size)
  result.size = c.size - size
  track("result.size", addr result.size, sizeof(int))
  when not defined(nimOptimizedSplitChunk):
    # still active because of weird codegen issue on some of our CIs:
    result.next = nil
    result.prev = nil
  # size and not used:
  result.prevSize = size
  result.owner = addr a
  sysAssert((size and 1) == 0, "splitChunk 2")
  sysAssert((size and PageMask) == 0,
      "splitChunk: size is not a multiple of the PageSize")
  updatePrevSize(a, c, result.size)
  c.size = size
  incl(a, a.chunkStarts, pageIndex(result))

proc splitChunk(a: var MemRegion, c: PBigChunk, size: int) =
  let rest = splitChunk2(a, c, size)
  addChunkToMatrix(a, rest)

proc freeBigChunk(a: var MemRegion, c: PBigChunk) =
  var c = c
  sysAssert(c.size >= PageSize, "freeBigChunk")
  inc(a.freeMem, c.size)
  c.prevSize = c.prevSize and not 1  # set 'used' to false
  when coalescLeft:
    let prevSize = c.prevSize
    if prevSize != 0:
      var le = cast[PChunk](cast[int](c) -% prevSize)
      sysAssert((cast[int](le) and PageMask) == 0, "freeBigChunk 4")
      if isAccessible(a, le) and chunkUnused(le):
        sysAssert(not isSmallChunk(le), "freeBigChunk 5")
        if not isSmallChunk(le) and le.size < MaxBigChunkSize:
          removeChunkFromMatrix(a, cast[PBigChunk](le))
          inc(le.size, c.size)
          excl(a.chunkStarts, pageIndex(c))
          c = cast[PBigChunk](le)
          if c.size > MaxBigChunkSize:
            let rest = splitChunk2(a, c, MaxBigChunkSize)
            when defined(nimOptimizedSplitChunk):
              rest.next = nil
              rest.prev = nil
            addChunkToMatrix(a, c)
            c = rest
  when coalescRight:
    var ri = cast[PChunk](cast[int](c) +% c.size)
    sysAssert((cast[int](ri) and PageMask) == 0, "freeBigChunk 2")
    if isAccessible(a, ri) and chunkUnused(ri):
      sysAssert(not isSmallChunk(ri), "freeBigChunk 3")
      if not isSmallChunk(ri) and c.size < MaxBigChunkSize:
        removeChunkFromMatrix(a, cast[PBigChunk](ri))
        inc(c.size, ri.size)
        excl(a.chunkStarts, pageIndex(ri))
        if c.size > MaxBigChunkSize:
          let rest = splitChunk2(a, c, MaxBigChunkSize)
          addChunkToMatrix(a, rest)
  addChunkToMatrix(a, c)

proc getBigChunk(a: var MemRegion, size: int): PBigChunk =
  sysAssert(size > 0, "getBigChunk 2")
  var size = size # roundup(size, PageSize)
  var fl = 0
  var sl = 0
  mappingSearch(size, fl, sl)
  sysAssert((size and PageMask) == 0, "getBigChunk: unaligned chunk")
  result = findSuitableBlock(a, fl, sl)

  when RegionHasLock:
    if not a.lockActive:
      a.lockActive = true
      initSysLock(a.lock)
    acquireSys a.lock

  if result == nil:
    if size < nimMinHeapPages * PageSize:
      result = requestOsChunks(a, nimMinHeapPages * PageSize)
      splitChunk(a, result, size)
    else:
      result = requestOsChunks(a, size)
      # if we over allocated split the chunk:
      if result.size > size:
        splitChunk(a, result, size)
    result.owner = addr a
  else:
    removeChunkFromMatrix2(a, result, fl, sl)
    if result.size >= size + PageSize:
      splitChunk(a, result, size)
  # set 'used' to to true:
  result.prevSize = 1
  track("setUsedToFalse", addr result.size, sizeof(int))
  sysAssert result.owner == addr a, "getBigChunk: No owner set!"

  incl(a, a.chunkStarts, pageIndex(result))
  dec(a.freeMem, size)
  when RegionHasLock:
    releaseSys a.lock

proc getHugeChunk(a: var MemRegion; size: int): PBigChunk =
  result = cast[PBigChunk](allocPages(a, size))
  when RegionHasLock:
    if not a.lockActive:
      a.lockActive = true
      initSysLock(a.lock)
    acquireSys a.lock
  incCurrMem(a, size)
  # XXX add this to the heap links. But also remove it from it later.
  when false: a.addHeapLink(result, size)
  sysAssert((cast[int](result) and PageMask) == 0, "getHugeChunk")
  result.next = nil
  result.prev = nil
  result.size = size
  # set 'used' to to true:
  result.prevSize = 1
  result.owner = addr a
  incl(a, a.chunkStarts, pageIndex(result))
  when RegionHasLock:
    releaseSys a.lock

proc freeHugeChunk(a: var MemRegion; c: PBigChunk) =
  let size = c.size
  sysAssert(size >= HugeChunkSize, "freeHugeChunk: invalid size")
  excl(a.chunkStarts, pageIndex(c))
  decCurrMem(a, size)
  osDeallocPages(c, size)

proc getSmallChunk(a: var MemRegion): PSmallChunk =
  var res = getBigChunk(a, PageSize)
  sysAssert res.prev == nil, "getSmallChunk 1"
  sysAssert res.next == nil, "getSmallChunk 2"
  result = cast[PSmallChunk](res)

# -----------------------------------------------------------------------------
when not defined(gcDestructors):
  proc isAllocatedPtr(a: MemRegion, p: pointer): bool {.benign.}

when true:
  template allocInv(a: MemRegion): bool = true
else:
  proc allocInv(a: MemRegion): bool =
    ## checks some (not all yet) invariants of the allocator's data structures.
    for s in low(a.freeSmallChunks)..high(a.freeSmallChunks):
      var c = a.freeSmallChunks[s]
      while not (c == nil):
        if c.next == c:
          echo "[SYSASSERT] c.next == c"
          return false
        if not (c.size == s * MemAlign):
          echo "[SYSASSERT] c.size != s * MemAlign"
          return false
        var it = c.freeList
        while not (it == nil):
          if not (it.zeroField == 0):
            echo "[SYSASSERT] it.zeroField != 0"
            c_printf("%ld %p\n", it.zeroField, it)
            return false
          it = it.next
        c = c.next
    result = true

when false:
  var
    rsizes: array[50_000, int]
    rsizesLen: int

  proc trackSize(size: int) =
    rsizes[rsizesLen] = size
    inc rsizesLen

  proc untrackSize(size: int) =
    for i in 0 .. rsizesLen-1:
      if rsizes[i] == size:
        rsizes[i] = rsizes[rsizesLen-1]
        dec rsizesLen
        return
    c_fprintf(stdout, "%ld\n", size)
    sysAssert(false, "untracked size!")
else:
  template trackSize(x) = discard
  template untrackSize(x) = discard

proc deallocBigChunk(a: var MemRegion, c: PBigChunk) =
  when RegionHasLock:
    acquireSys a.lock
  dec a.occ, c.size
  untrackSize(c.size)
  sysAssert a.occ >= 0, "rawDealloc: negative occupied memory (case B)"
  when not defined(gcDestructors):
    a.deleted = getBottom(a)
    del(a, a.root, cast[int](addr(c.data)))
  if c.size >= HugeChunkSize: freeHugeChunk(a, c)
  else: freeBigChunk(a, c)
  when RegionHasLock:
    releaseSys a.lock

when defined(gcDestructors):
  template atomicPrepend(head, elem: untyped) =
    # see also https://en.cppreference.com/w/cpp/atomic/atomic_compare_exchange
    when hasThreadSupport:
      while true:
        elem.next.storea head.loada
        if atomicCompareExchangeN(addr head, addr elem.next, elem, weak = true, ATOMIC_RELEASE, ATOMIC_RELAXED):
          break
    else:
      elem.next.storea head.loada
      head.storea elem

  proc addToSharedFreeListBigChunks(a: var MemRegion; c: PBigChunk) {.inline.} =
    sysAssert c.next == nil, "c.next pointer must be nil"
    atomicPrepend a.sharedFreeListBigChunks, c

  proc addToSharedFreeList(c: PSmallChunk; f: ptr FreeCell; size: int) {.inline.} =
    atomicPrepend c.owner.sharedFreeLists[size], f

  const MaxSteps = 20

  proc compensateCounters(a: var MemRegion; c: PSmallChunk; size: int) =
    # rawDealloc did NOT do the usual:
    # `inc(c.free, size); dec(a.occ, size)` because it wasn't the owner of these
    # memory locations. We have to compensate here for these for the entire list.
    var it = c.freeList
    var total = 0
    while it != nil:
      inc total, size
      let chunk = cast[PSmallChunk](pageAddr(it))
      if c != chunk:
        # The cell is foreign, potentially even from a foreign thread.
        # It must block the current chunk from being freed, as doing so would leak memory.
        inc c.foreignCells
      it = it.next
    # By not adjusting the foreign chunk we reserve space in it to prevent deallocation
    inc(c.free, total)
    dec(a.occ, total)

  proc freeDeferredObjects(a: var MemRegion; root: PBigChunk) =
    var it = root
    var maxIters = MaxSteps # make it time-bounded
    while true:
      let rest = it.next.loada
      it.next.storea nil
      deallocBigChunk(a, cast[PBigChunk](it))
      if maxIters == 0:
        if rest != nil:
          addToSharedFreeListBigChunks(a, rest)
          sysAssert a.sharedFreeListBigChunks != nil, "re-enqueing failed"
        break
      it = rest
      dec maxIters
      if it == nil: break

proc rawAlloc(a: var MemRegion, requestedSize: int): pointer =
  when defined(nimTypeNames):
    inc(a.allocCounter)
  sysAssert(allocInv(a), "rawAlloc: begin")
  sysAssert(roundup(65, 8) == 72, "rawAlloc: roundup broken")
  var size = roundup(requestedSize, MemAlign)
  sysAssert(size >= sizeof(FreeCell), "rawAlloc: requested size too small")
  sysAssert(size >= requestedSize, "insufficient allocated size!")
  #c_fprintf(stdout, "alloc; size: %ld; %ld\n", requestedSize, size)

  if size <= SmallChunkSize-smallChunkOverhead():
    template fetchSharedCells(tc: PSmallChunk) =
      # Consumes cells from (potentially) foreign threads from `a.sharedFreeLists[s]`
      when defined(gcDestructors):
        if tc.freeList == nil:
          when hasThreadSupport:
            # Steal the entire list from `sharedFreeList`:
            tc.freeList = atomicExchangeN(addr a.sharedFreeLists[s], nil, ATOMIC_RELAXED)
          else:
            tc.freeList = a.sharedFreeLists[s]
            a.sharedFreeLists[s] = nil
          # if `tc.freeList` isn't nil, `tc` will gain capacity.
          # We must calculate how much it gained and how many foreign cells are included.
          compensateCounters(a, tc, size)

    # allocate a small block: for small chunks, we use only its next pointer
    let s = size div MemAlign
    var c = a.freeSmallChunks[s]
    if c == nil:
      # There is no free chunk of the requested size available, we need a new one.
      c = getSmallChunk(a)
      # init all fields in case memory didn't get zeroed
      c.freeList = nil
      c.foreignCells = 0
      sysAssert c.size == PageSize, "rawAlloc 3"
      c.size = size
      c.acc = size.uint32
      c.free = SmallChunkSize - smallChunkOverhead() - size.int32
      sysAssert c.owner == addr(a), "rawAlloc: No owner set!"
      c.next = nil
      c.prev = nil
      # Shared cells are fetched here in case `c.size * 2 >= SmallChunkSize - smallChunkOverhead()`.
      # For those single cell chunks, we would otherwise have to allocate a new one almost every time.
      fetchSharedCells(c)
      if c.free >= size:
        # Because removals from `a.freeSmallChunks[s]` only happen in the other alloc branch and during dealloc,
        #  we must not add it to the list if it cannot be used the next time a pointer of `size` bytes is needed.
        listAdd(a.freeSmallChunks[s], c)
      result = addr(c.data)
      sysAssert((cast[int](result) and (MemAlign-1)) == 0, "rawAlloc 4")
    else:
      # There is a free chunk of the requested size available, use it.
      sysAssert(allocInv(a), "rawAlloc: begin c != nil")
      sysAssert c.next != c, "rawAlloc 5"
      #if c.size != size:
      #  c_fprintf(stdout, "csize: %lld; size %lld\n", c.size, size)
      sysAssert c.size == size, "rawAlloc 6"
      if c.freeList == nil:
        sysAssert(c.acc.int + smallChunkOverhead() + size <= SmallChunkSize,
                  "rawAlloc 7")
        result = cast[pointer](cast[int](addr(c.data)) +% c.acc.int)
        inc(c.acc, size)
      else:
        # There are free cells available, prefer them over the accumulator
        result = c.freeList
        when not defined(gcDestructors):
          sysAssert(c.freeList.zeroField == 0, "rawAlloc 8")
        c.freeList = c.freeList.next
        if cast[PSmallChunk](pageAddr(result)) != c:
          # This cell isn't a blocker for the current chunk's deallocation anymore
          dec(c.foreignCells)
        else:
          sysAssert(c == cast[PSmallChunk](pageAddr(result)), "rawAlloc: Bad cell")
      # Even if the cell we return is foreign, the local chunk's capacity decreases.
      # The capacity was previously reserved in the source chunk (when it first got allocated),
      #  then added into the current chunk during dealloc,
      #  so the source chunk will not be freed or leak memory because of this.
      dec(c.free, size)
      sysAssert((cast[int](result) and (MemAlign-1)) == 0, "rawAlloc 9")
      sysAssert(allocInv(a), "rawAlloc: end c != nil")
      # We fetch deferred cells *after* advancing `c.freeList`/`acc` to adjust `c.free`.
      # If after the adjustment it turns out there's free cells available,
      #  the chunk stays in `a.freeSmallChunks[s]` and the need for a new chunk is delayed.
      fetchSharedCells(c)
      sysAssert(allocInv(a), "rawAlloc: before c.free < size")
      if c.free < size:
        # Even after fetching shared cells the chunk has no usable memory left. It is no longer the active chunk
        sysAssert(allocInv(a), "rawAlloc: before listRemove test")
        listRemove(a.freeSmallChunks[s], c)
        sysAssert(allocInv(a), "rawAlloc: end listRemove test")
    sysAssert(((cast[int](result) and PageMask) - smallChunkOverhead()) %%
               size == 0, "rawAlloc 21")
    sysAssert(allocInv(a), "rawAlloc: end small size")
    inc a.occ, size
    trackSize(c.size)
  else:
    when defined(gcDestructors):
      when hasThreadSupport:
        let deferredFrees = atomicExchangeN(addr a.sharedFreeListBigChunks, nil, ATOMIC_RELAXED)
      else:
        let deferredFrees = a.sharedFreeListBigChunks
        a.sharedFreeListBigChunks = nil
      if deferredFrees != nil:
        freeDeferredObjects(a, deferredFrees)

    size = requestedSize + bigChunkOverhead() #  roundup(requestedSize+bigChunkOverhead(), PageSize)
    # allocate a large block
    var c = if size >= HugeChunkSize: getHugeChunk(a, size)
            else: getBigChunk(a, size)
    sysAssert c.prev == nil, "rawAlloc 10"
    sysAssert c.next == nil, "rawAlloc 11"
    result = addr(c.data)
    sysAssert((cast[int](c) and (MemAlign-1)) == 0, "rawAlloc 13")
    sysAssert((cast[int](c) and PageMask) == 0, "rawAlloc: Not aligned on a page boundary")
    when not defined(gcDestructors):
      if a.root == nil: a.root = getBottom(a)
      add(a, a.root, cast[int](result), cast[int](result)+%size)
    inc a.occ, c.size
    trackSize(c.size)
  sysAssert(isAccessible(a, result), "rawAlloc 14")
  sysAssert(allocInv(a), "rawAlloc: end")
  when logAlloc: cprintf("var pointer_%p = alloc(%ld) # %p\n", result, requestedSize, addr a)

proc rawAlloc0(a: var MemRegion, requestedSize: int): pointer =
  result = rawAlloc(a, requestedSize)
  zeroMem(result, requestedSize)

proc rawDealloc(a: var MemRegion, p: pointer) =
  when defined(nimTypeNames):
    inc(a.deallocCounter)
  #sysAssert(isAllocatedPtr(a, p), "rawDealloc: no allocated pointer")
  sysAssert(allocInv(a), "rawDealloc: begin")
  var c = pageAddr(p)
  sysAssert(c != nil, "rawDealloc: begin")
  if isSmallChunk(c):
    # `p` is within a small chunk:
    var c = cast[PSmallChunk](c)
    let s = c.size
    #       ^ We might access thread foreign storage here.
    # The other thread cannot possibly free this block as it's still alive.
    var f = cast[ptr FreeCell](p)
    if c.owner == addr(a):
      # We own the block, there is no foreign thread involved.
      dec a.occ, s
      untrackSize(s)
      sysAssert a.occ >= 0, "rawDealloc: negative occupied memory (case A)"
      sysAssert(((cast[int](p) and PageMask) - smallChunkOverhead()) %%
                s == 0, "rawDealloc 3")
      when not defined(gcDestructors):
        #echo("setting to nil: ", $cast[int](addr(f.zeroField)))
        sysAssert(f.zeroField != 0, "rawDealloc 1")
        f.zeroField = 0
      when overwriteFree:
        # set to 0xff to check for usage after free bugs:
        nimSetMem(cast[pointer](cast[int](p) +% sizeof(FreeCell)), -1'i32,
                s -% sizeof(FreeCell))
      let activeChunk = a.freeSmallChunks[s div MemAlign]
      if activeChunk != nil and c != activeChunk:
        # This pointer is not part of the active chunk, lend it out
        #  and do not adjust the current chunk (same logic as compensateCounters.)
        # Put the cell into the active chunk,
        #  may prevent a queue of available chunks from forming in a.freeSmallChunks[s div MemAlign].
        #  This queue would otherwise waste memory in the form of free cells until we return to those chunks.
        f.next = activeChunk.freeList
        activeChunk.freeList = f # lend the cell
        inc(activeChunk.free, s) # By not adjusting the current chunk's capacity it is prevented from being freed
        inc(activeChunk.foreignCells) # The cell is now considered foreign from the perspective of the active chunk
      else:
        f.next = c.freeList
        c.freeList = f
        if c.free < s:
          # The chunk could not have been active as it didn't have enough space to give
          listAdd(a.freeSmallChunks[s div MemAlign], c)
          inc(c.free, s)
        else:
          inc(c.free, s)
          # Free only if the entire chunk is unused and there are no borrowed cells.
          # If the chunk were to be freed while it references foreign cells,
          #  the foreign chunks will leak memory and can never be freed.
          if c.free == SmallChunkSize-smallChunkOverhead() and c.foreignCells == 0:
            listRemove(a.freeSmallChunks[s div MemAlign], c)
            c.size = SmallChunkSize
            freeBigChunk(a, cast[PBigChunk](c))
    else:
      when logAlloc: cprintf("dealloc(pointer_%p) # SMALL FROM %p CALLER %p\n", p, c.owner, addr(a))

      when defined(gcDestructors):
        addToSharedFreeList(c, f, s div MemAlign)
    sysAssert(((cast[int](p) and PageMask) - smallChunkOverhead()) %%
               s == 0, "rawDealloc 2")
  else:
    # set to 0xff to check for usage after free bugs:
    when overwriteFree: nimSetMem(p, -1'i32, c.size -% bigChunkOverhead())
    when logAlloc: cprintf("dealloc(pointer_%p) # BIG %p\n", p, c.owner)
    when defined(gcDestructors):
      if c.owner == addr(a):
        deallocBigChunk(a, cast[PBigChunk](c))
      else:
        addToSharedFreeListBigChunks(c.owner[], cast[PBigChunk](c))
    else:
      deallocBigChunk(a, cast[PBigChunk](c))

  sysAssert(allocInv(a), "rawDealloc: end")
  #when logAlloc: cprintf("dealloc(pointer_%p)\n", p)

when not defined(gcDestructors):
  proc isAllocatedPtr(a: MemRegion, p: pointer): bool =
    if isAccessible(a, p):
      var c = pageAddr(p)
      if not chunkUnused(c):
        if isSmallChunk(c):
          var c = cast[PSmallChunk](c)
          var offset = (cast[int](p) and (PageSize-1)) -%
                      smallChunkOverhead()
          result = (c.acc.int >% offset) and (offset %% c.size == 0) and
            (cast[ptr FreeCell](p).zeroField >% 1)
        else:
          var c = cast[PBigChunk](c)
          result = p == addr(c.data) and cast[ptr FreeCell](p).zeroField >% 1

  proc prepareForInteriorPointerChecking(a: var MemRegion) {.inline.} =
    a.minLargeObj = lowGauge(a.root)
    a.maxLargeObj = highGauge(a.root)

  proc interiorAllocatedPtr(a: MemRegion, p: pointer): pointer =
    if isAccessible(a, p):
      var c = pageAddr(p)
      if not chunkUnused(c):
        if isSmallChunk(c):
          var c = cast[PSmallChunk](c)
          var offset = (cast[int](p) and (PageSize-1)) -%
                      smallChunkOverhead()
          if c.acc.int >% offset:
            sysAssert(cast[int](addr(c.data)) +% offset ==
                      cast[int](p), "offset is not what you think it is")
            var d = cast[ptr FreeCell](cast[int](addr(c.data)) +%
                      offset -% (offset %% c.size))
            if d.zeroField >% 1:
              result = d
              sysAssert isAllocatedPtr(a, result), " result wrong pointer!"
        else:
          var c = cast[PBigChunk](c)
          var d = addr(c.data)
          if p >= d and cast[ptr FreeCell](d).zeroField >% 1:
            result = d
            sysAssert isAllocatedPtr(a, result), " result wrong pointer!"
    else:
      var q = cast[int](p)
      if q >=% a.minLargeObj and q <=% a.maxLargeObj:
        # this check is highly effective! Test fails for 99,96% of all checks on
        # an x86-64.
        var avlNode = inRange(a.root, q)
        if avlNode != nil:
          var k = cast[pointer](avlNode.key)
          var c = cast[PBigChunk](pageAddr(k))
          sysAssert(addr(c.data) == k, " k is not the same as addr(c.data)!")
          if cast[ptr FreeCell](k).zeroField >% 1:
            result = k
            sysAssert isAllocatedPtr(a, result), " result wrong pointer!"

proc ptrSize(p: pointer): int =
  when not defined(gcDestructors):
    var x = cast[pointer](cast[int](p) -% sizeof(FreeCell))
    var c = pageAddr(p)
    sysAssert(not chunkUnused(c), "ptrSize")
    result = c.size -% sizeof(FreeCell)
    if not isSmallChunk(c):
      dec result, bigChunkOverhead()
  else:
    var c = pageAddr(p)
    sysAssert(not chunkUnused(c), "ptrSize")
    result = c.size
    if not isSmallChunk(c):
      dec result, bigChunkOverhead()

proc alloc(allocator: var MemRegion, size: Natural): pointer {.gcsafe.} =
  when not defined(gcDestructors):
    result = rawAlloc(allocator, size+sizeof(FreeCell))
    cast[ptr FreeCell](result).zeroField = 1 # mark it as used
    sysAssert(not isAllocatedPtr(allocator, result), "alloc")
    result = cast[pointer](cast[int](result) +% sizeof(FreeCell))
    track("alloc", result, size)
  else:
    result = rawAlloc(allocator, size)

proc alloc0(allocator: var MemRegion, size: Natural): pointer =
  result = alloc(allocator, size)
  zeroMem(result, size)

proc dealloc(allocator: var MemRegion, p: pointer) =
  when not defined(gcDestructors):
    sysAssert(p != nil, "dealloc: p is nil")
    var x = cast[pointer](cast[int](p) -% sizeof(FreeCell))
    sysAssert(x != nil, "dealloc: x is nil")
    sysAssert(isAccessible(allocator, x), "is not accessible")
    sysAssert(cast[ptr FreeCell](x).zeroField == 1, "dealloc: object header corrupted")
    rawDealloc(allocator, x)
    sysAssert(not isAllocatedPtr(allocator, x), "dealloc: object still accessible")
    track("dealloc", p, 0)
  else:
    rawDealloc(allocator, p)

proc realloc(allocator: var MemRegion, p: pointer, newsize: Natural): pointer =
  result = nil
  if newsize > 0:
    result = alloc(allocator, newsize)
    if p != nil:
      copyMem(result, p, min(ptrSize(p), newsize))
      dealloc(allocator, p)
  elif p != nil:
    dealloc(allocator, p)

proc realloc0(allocator: var MemRegion, p: pointer, oldsize, newsize: Natural): pointer =
  result = realloc(allocator, p, newsize)
  if newsize > oldsize:
    zeroMem(cast[pointer](cast[uint](result) + uint(oldsize)), newsize - oldsize)

proc deallocOsPages(a: var MemRegion) =
  # we free every 'ordinarily' allocated page by iterating over the page bits:
  var it = addr(a.heapLinks)
  while true:
    let next = it.next
    for i in 0..it.len-1:
      let (p, size) = it.chunks[i]
      when defined(debugHeapLinks):
        cprintf("owner %p; dealloc A: %p size: %ld; next: %p\n", addr(a),
          it, size, next)
      sysAssert size >= PageSize, "origSize too small"
      osDeallocPages(p, size)
    it = next
    if it == nil: break
  # And then we free the pages that are in use for the page bits:
  llDeallocAll(a)

proc getFreeMem(a: MemRegion): int {.inline.} = result = a.freeMem
proc getTotalMem(a: MemRegion): int {.inline.} = result = a.currMem
proc getOccupiedMem(a: MemRegion): int {.inline.} =
  result = a.occ
  # a.currMem - a.freeMem

when defined(nimTypeNames):
  proc getMemCounters(a: MemRegion): (int, int) {.inline.} =
    (a.allocCounter, a.deallocCounter)

# ---------------------- thread memory region -------------------------------

template instantiateForRegion(allocator: untyped) {.dirty.} =
  {.push stackTrace: off.}

  when defined(nimFulldebug):
    proc interiorAllocatedPtr*(p: pointer): pointer =
      result = interiorAllocatedPtr(allocator, p)

    proc isAllocatedPtr*(p: pointer): bool =
      let p = cast[pointer](cast[int](p)-%ByteAddress(sizeof(Cell)))
      result = isAllocatedPtr(allocator, p)

  proc deallocOsPages = deallocOsPages(allocator)

  proc allocImpl(size: Natural): pointer =
    result = alloc(allocator, size)

  proc alloc0Impl(size: Natural): pointer =
    result = alloc0(allocator, size)

  proc deallocImpl(p: pointer) =
    dealloc(allocator, p)

  proc reallocImpl(p: pointer, newSize: Natural): pointer =
    result = realloc(allocator, p, newSize)

  proc realloc0Impl(p: pointer, oldSize, newSize: Natural): pointer =
    result = realloc(allocator, p, newSize)
    if newSize > oldSize:
      zeroMem(cast[pointer](cast[uint](result) + uint(oldSize)), newSize - oldSize)

  when false:
    proc countFreeMem(): int =
      # only used for assertions
      var it = allocator.freeChunksList
      while it != nil:
        inc(result, it.size)
        it = it.next

  when hasThreadSupport and not defined(gcDestructors):
    proc addSysExitProc(quitProc: proc() {.noconv.}) {.importc: "atexit", header: "<stdlib.h>".}

    var sharedHeap: MemRegion
    var heapLock: SysLock
    initSysLock(heapLock)
    addSysExitProc(proc() {.noconv.} = deinitSys(heapLock))

  proc getFreeMem(): int =
    #sysAssert(result == countFreeMem())
    result = allocator.freeMem

  proc getTotalMem(): int =
    result = allocator.currMem

  proc getOccupiedMem(): int =
    result = allocator.occ #getTotalMem() - getFreeMem()

  proc getMaxMem*(): int =
    result = getMaxMem(allocator)

  when defined(nimTypeNames):
    proc getMemCounters*(): (int, int) = getMemCounters(allocator)

  # -------------------- shared heap region ----------------------------------

  proc allocSharedImpl(size: Natural): pointer =
    when hasThreadSupport and not defined(gcDestructors):
      acquireSys(heapLock)
      result = alloc(sharedHeap, size)
      releaseSys(heapLock)
    else:
      result = allocImpl(size)

  proc allocShared0Impl(size: Natural): pointer =
    result = allocSharedImpl(size)
    zeroMem(result, size)

  proc deallocSharedImpl(p: pointer) =
    when hasThreadSupport and not defined(gcDestructors):
      acquireSys(heapLock)
      dealloc(sharedHeap, p)
      releaseSys(heapLock)
    else:
      deallocImpl(p)

  proc reallocSharedImpl(p: pointer, newSize: Natural): pointer =
    when hasThreadSupport and not defined(gcDestructors):
      acquireSys(heapLock)
      result = realloc(sharedHeap, p, newSize)
      releaseSys(heapLock)
    else:
      result = reallocImpl(p, newSize)

  proc reallocShared0Impl(p: pointer, oldSize, newSize: Natural): pointer =
    when hasThreadSupport and not defined(gcDestructors):
      acquireSys(heapLock)
      result = realloc0(sharedHeap, p, oldSize, newSize)
      releaseSys(heapLock)
    else:
      result = realloc0Impl(p, oldSize, newSize)

  when hasThreadSupport:
    when defined(gcDestructors):
      proc getFreeSharedMem(): int =
        allocator.freeMem

      proc getTotalSharedMem(): int =
        allocator.currMem

      proc getOccupiedSharedMem(): int =
        allocator.occ

    else:
      template sharedMemStatsShared(v: int) =
        acquireSys(heapLock)
        result = v
        releaseSys(heapLock)

      proc getFreeSharedMem(): int =
        sharedMemStatsShared(sharedHeap.freeMem)

      proc getTotalSharedMem(): int =
        sharedMemStatsShared(sharedHeap.currMem)

      proc getOccupiedSharedMem(): int =
        sharedMemStatsShared(sharedHeap.occ)
        #sharedMemStatsShared(sharedHeap.currMem - sharedHeap.freeMem)
  {.pop.}

{.pop.}
