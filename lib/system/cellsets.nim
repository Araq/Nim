#
#
#            Nim's Runtime Library
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#


#[

Efficient set of pointers for the GC (and repr)
-----------------------------------------------

The GC depends on an extremely efficient datastructure for storing a
set of pointers - this is called a `CellSet` in the source code.
Inserting, deleting and searching are done in constant time. However,
modifying a `CellSet` during traversal leads to undefined behaviour.

All operations on a CellSet have to perform efficiently. Because a Cellset can
become huge a hash table alone is not suitable for this.

We use a mixture of bitset and hash table for this. The hash table maps *pages*
to a page descriptor. The page descriptor contains a bit for any possible cell
address within this page. So including a cell is done as follows:

- Find the page descriptor for the page the cell belongs to.
- Set the appropriate bit in the page descriptor indicating that the
  cell points to the start of a memory block.

Removing a cell is analogous - the bit has to be set to zero.
Single page descriptors are never deleted from the hash table. This is not
needed as the data structures needs to be rebuilt periodically anyway.

Complete traversal is done in this way::

  for each page descriptor d:
    for each bit in d:
      if bit == 1:
        traverse the pointer belonging to this bit

]#

when defined(gcOrc) or defined(gcArc) or defined(gcAtomicArc):
  type
    PCell = Cell

  when not declaredInScope(PageShift):
    include bitmasks

else:
  type
    RefCount = int

    Cell {.pure.} = object
      refcount: RefCount  # the refcount and some flags
      typ: PNimType
      when trackAllocationSource:
        filename: cstring
        line: int
      when useCellIds:
        id: int

    PCell = ptr Cell

type
  PPageDesc = ptr PageDesc
  BitIndex = range[0..UnitsPerPage-1]
  PageDesc {.final, pure.} = object
    next: PPageDesc # all nodes are connected with this pointer
    key: uint   # start address at bit 0
    bits: array[BitIndex, int] # a bit vector

  PPageDescArray = ptr UncheckedArray[PPageDesc]
  CellSet {.final, pure.} = object
    counter, max: int
    head: PPageDesc
    data: PPageDescArray

when defined(gcOrc) or defined(gcArc) or defined(gcAtomicArc):
  discard
else:
  include cellseqs_v1

# ------------------- cell set handling ---------------------------------------

const
  InitCellSetSize = 1024 # must be a power of two!

proc init(s: var CellSet) =
  s.data = cast[PPageDescArray](alloc0(InitCellSetSize * sizeof(PPageDesc)))
  s.max = InitCellSetSize-1
  s.counter = 0
  s.head = nil

proc deinit(s: var CellSet) =
  var it = s.head
  while it != nil:
    var n = it.next
    dealloc(it)
    it = n
  s.head = nil # play it safe here
  dealloc(s.data)
  s.data = nil
  s.counter = 0

proc nextTry(h, maxHash: int): int {.inline.} =
  result = ((5*h) + 1) and maxHash
  # For any initial h in range(maxHash), repeating that maxHash times
  # generates each int in range(maxHash) exactly once (see any text on
  # random-number generation for proof).

proc cellSetGet(t: CellSet, key: uint): PPageDesc =
  var h = cast[int](key) and t.max
  while t.data[h] != nil:
    if t.data[h].key == key: return t.data[h]
    h = nextTry(h, t.max)
  return nil

proc cellSetRawInsert(t: CellSet, data: PPageDescArray, desc: PPageDesc) =
  var h = cast[int](desc.key) and t.max
  while data[h] != nil:
    sysAssert(data[h] != desc, "CellSetRawInsert 1")
    h = nextTry(h, t.max)
  sysAssert(data[h] == nil, "CellSetRawInsert 2")
  data[h] = desc

proc cellSetEnlarge(t: var CellSet) =
  var oldMax = t.max
  t.max = ((t.max+1)*2)-1
  var n = cast[PPageDescArray](alloc0((t.max + 1) * sizeof(PPageDesc)))
  for i in 0 .. oldMax:
    if t.data[i] != nil:
      cellSetRawInsert(t, n, t.data[i])
  dealloc(t.data)
  t.data = n

proc cellSetPut(t: var CellSet, key: uint): PPageDesc =
  var h = cast[int](key) and t.max
  while true:
    var x = t.data[h]
    if x == nil: break
    if x.key == key: return x
    h = nextTry(h, t.max)

  if ((t.max+1) < t.counter div 2 + t.counter) or ((t.max+1)-t.counter < 4):
    cellSetEnlarge(t)
  inc(t.counter)
  h = cast[int](key) and t.max
  while t.data[h] != nil: h = nextTry(h, t.max)
  sysAssert(t.data[h] == nil, "CellSetPut")
  # the new page descriptor goes into result
  result = cast[PPageDesc](alloc0(sizeof(PageDesc)))
  result.next = t.head
  result.key = key
  t.head = result
  t.data[h] = result

# ---------- slightly higher level procs --------------------------------------

proc contains(s: CellSet, cell: PCell): bool =
  var u = cast[uint](cell)
  var t = cellSetGet(s, u shr PageShift)
  if t != nil:
    u = (u mod PageSize) div MemAlign
    result = (t.bits[u shr IntShift] and (1 shl (u and IntMask))) != 0
  else:
    result = false

proc incl(s: var CellSet, cell: PCell) =
  var u = cast[uint](cell)
  var t = cellSetPut(s, u shr PageShift)
  u = (u mod PageSize) div MemAlign
  t.bits[u shr IntShift] = t.bits[u shr IntShift] or (1 shl (u and IntMask))

proc excl(s: var CellSet, cell: PCell) =
  var u = cast[uint](cell)
  var t = cellSetGet(s, u shr PageShift)
  if t != nil:
    u = (u mod PageSize) div MemAlign
    t.bits[u shr IntShift] = (t.bits[u shr IntShift] and
                              not (1 shl (u and IntMask)))

proc containsOrIncl(s: var CellSet, cell: PCell): bool =
  var u = cast[uint](cell)
  var t = cellSetGet(s, u shr PageShift)
  if t != nil:
    u = (u mod PageSize) div MemAlign
    result = (t.bits[u shr IntShift] and (1 shl (u and IntMask))) != 0
    if not result:
      t.bits[u shr IntShift] = t.bits[u shr IntShift] or
          (1 shl (u and IntMask))
  else:
    incl(s, cell)
    result = false

iterator elements(t: CellSet): PCell {.inline.} =
  # while traversing it is forbidden to add pointers to the tree!
  var r = t.head
  while r != nil:
    var i: uint = 0
    while int(i) <= high(r.bits):
      var w = r.bits[i] # taking a copy of r.bits[i] here is correct, because
      # modifying operations are not allowed during traversation
      var j: uint = 0
      while w != 0:         # test all remaining bits for zero
        if (w and 1) != 0:  # the bit is set!
          yield cast[PCell]((r.key shl PageShift) or
                              (i shl IntShift + j) * MemAlign)
        inc(j)
        w = w shr 1
      inc(i)
    r = r.next

when false:
  type
    CellSetIter = object
      p: PPageDesc
      i, w, j: int

  proc next(it: var CellSetIter): PCell =
    while true:
      while it.w != 0:         # test all remaining bits for zero
        if (it.w and 1) != 0:  # the bit is set!
          result = cast[PCell]((it.p.key shl PageShift) or
                               (it.i shl IntShift +% it.j) *% MemAlign)

          inc(it.j)
          it.w = it.w shr 1
          return
        else:
          inc(it.j)
          it.w = it.w shr 1
      # load next w:
      if it.i >= high(it.p.bits):
        it.i = 0
        it.j = 0
        it.p = it.p.next
        if it.p == nil: return nil
      else:
        inc it.i
      it.w = it.p.bits[i]

  proc init(it: var CellSetIter; t: CellSet): PCell =
    it.p = t.head
    it.i = -1
    it.w = 0
    result = it.next

iterator elementsExcept(t, s: CellSet): PCell {.inline.} =
  var r = t.head
  while r != nil:
    let ss = cellSetGet(s, r.key)
    var i:uint = 0
    while int(i) <= high(r.bits):
      var w = r.bits[i]
      if ss != nil:
        w = w and not ss.bits[i]
      var j:uint = 0
      while w != 0:
        if (w and 1) != 0:
          yield cast[PCell]((r.key shl PageShift) or
                              (i shl IntShift + j) * MemAlign)
        inc(j)
        w = w shr 1
      inc(i)
    r = r.next
