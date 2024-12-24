when notJSnotNims:
  proc zeroMem*(p: pointer, size: Natural) {.inline, noSideEffect,
    tags: [], raises: [].}
    ## Overwrites the contents of the memory at `p` with the value 0.
    ##
    ## Exactly `size` bytes will be overwritten. Like any procedure
    ## dealing with raw memory this is **unsafe**.

  proc copyMem*(dest, source: pointer, size: Natural) {.inline, benign,
    tags: [], raises: [].}
    ## Copies the contents from the memory at `source` to the memory
    ## at `dest`.
    ## Exactly `size` bytes will be copied. The memory
    ## regions may not overlap. Like any procedure dealing with raw
    ## memory this is **unsafe**.

  proc moveMem*(dest, source: pointer, size: Natural) {.inline, benign,
    tags: [], raises: [].}
    ## Copies the contents from the memory at `source` to the memory
    ## at `dest`.
    ##
    ## Exactly `size` bytes will be copied. The memory
    ## regions may overlap, `moveMem` handles this case appropriately
    ## and is thus somewhat more safe than `copyMem`. Like any procedure
    ## dealing with raw memory this is still **unsafe**, though.

  proc equalMem*(a, b: pointer, size: Natural): bool {.inline, noSideEffect,
    tags: [], raises: [].}
    ## Compares the memory blocks `a` and `b`. `size` bytes will
    ## be compared.
    ##
    ## If the blocks are equal, `true` is returned, `false`
    ## otherwise. Like any procedure dealing with raw memory this is
    ## **unsafe**.

  proc cmpMem*(a, b: pointer, size: Natural): int {.inline, noSideEffect,
    tags: [], raises: [].}
    ## Compares the memory blocks `a` and `b`. `size` bytes will
    ## be compared.
    ##
    ## Returns:
    ## * a value less than zero, if `a < b`
    ## * a value greater than zero, if `a > b`
    ## * zero, if `a == b`
    ##
    ## Like any procedure dealing with raw memory this is
    ## **unsafe**.

when hasAlloc and not defined(js):

  proc allocImpl*(size: Natural): pointer {.noconv, rtl, tags: [], benign, raises: [].}
  proc alloc0Impl*(size: Natural): pointer {.noconv, rtl, tags: [], benign, raises: [].}
  proc deallocImpl*(p: pointer) {.noconv, rtl, tags: [], benign, raises: [].}
  proc reallocImpl*(p: pointer, newSize: Natural): pointer {.noconv, rtl, tags: [], benign, raises: [].}
  proc realloc0Impl*(p: pointer, oldSize, newSize: Natural): pointer {.noconv, rtl, tags: [], benign, raises: [].}

  proc allocSharedImpl*(size: Natural): pointer {.noconv, compilerproc, rtl, benign, raises: [], tags: [].}
  proc allocShared0Impl*(size: Natural): pointer {.noconv, rtl, benign, raises: [], tags: [].}
  proc deallocSharedImpl*(p: pointer) {.noconv, rtl, benign, raises: [], tags: [].}
  proc reallocSharedImpl*(p: pointer, newSize: Natural): pointer {.noconv, rtl, tags: [], benign, raises: [].}
  proc reallocShared0Impl*(p: pointer, oldSize, newSize: Natural): pointer {.noconv, rtl, tags: [], benign, raises: [].}

  # Allocator statistics for memory leak tests

  {.push stackTrace: off.}

  type AllocStats* = object
    allocCount: int
    deallocCount: int

  proc `-`*(a, b: AllocStats): AllocStats =
    result.allocCount = a.allocCount - b.allocCount
    result.deallocCount = a.deallocCount - b.deallocCount

  template dumpAllocstats*(code: untyped) =
    let stats1 = getAllocStats()
    code
    let stats2 = getAllocStats()
    echo $(stats2 - stats1)

  when defined(nimAllocStats):
    var stats: AllocStats
    template incStat(what: untyped) = atomicInc stats.what
    proc getAllocStats*(): AllocStats = stats

  else:
    template incStat(what: untyped) = discard
    proc getAllocStats*(): AllocStats = result = default(AllocStats)

  template alloc*(size: Natural): pointer =
    ## Allocates a new memory block with at least `size` bytes.
    ##
    ## The block has to be freed with `realloc(block, 0) <#realloc.t,pointer,Natural>`_
    ## or `dealloc(block) <#dealloc,pointer>`_.
    ## The block is not initialized, so reading
    ## from it before writing to it is undefined behaviour!
    ##
    ## The allocated memory belongs to its allocating thread!
    ## Use `allocShared <#allocShared.t,Natural>`_ to allocate from a shared heap.
    ##
    ## See also:
    ## * `alloc0 <#alloc0.t,Natural>`_
    incStat(allocCount)
    allocImpl(size)

  proc createU*(T: typedesc, size = 1.Positive): ptr T {.inline, benign, raises: [].} =
    ## Allocates a new memory block with at least `T.sizeof * size` bytes.
    ##
    ## The block has to be freed with `resize(block, 0) <#resize,ptr.T,Natural>`_
    ## or `dealloc(block) <#dealloc,pointer>`_.
    ## The block is not initialized, so reading
    ## from it before writing to it is undefined behaviour!
    ##
    ## The allocated memory belongs to its allocating thread!
    ## Use `createSharedU <#createSharedU,typedesc>`_ to allocate from a shared heap.
    ##
    ## See also:
    ## * `create <#create,typedesc>`_
    cast[ptr T](alloc(T.sizeof * size))

  template alloc0*(size: Natural): pointer =
    ## Allocates a new memory block with at least `size` bytes.
    ##
    ## The block has to be freed with `realloc(block, 0) <#realloc.t,pointer,Natural>`_
    ## or `dealloc(block) <#dealloc,pointer>`_.
    ## The block is initialized with all bytes containing zero, so it is
    ## somewhat safer than  `alloc <#alloc.t,Natural>`_.
    ##
    ## The allocated memory belongs to its allocating thread!
    ## Use `allocShared0 <#allocShared0.t,Natural>`_ to allocate from a shared heap.
    incStat(allocCount)
    alloc0Impl(size)

  proc create*(T: typedesc, size = 1.Positive): ptr T {.inline, benign, raises: [].} =
    ## Allocates a new memory block with at least `T.sizeof * size` bytes.
    ##
    ## The block has to be freed with `resize(block, 0) <#resize,ptr.T,Natural>`_
    ## or `dealloc(block) <#dealloc,pointer>`_.
    ## The block is initialized with all bytes containing zero, so it is
    ## somewhat safer than `createU <#createU,typedesc>`_.
    ##
    ## The allocated memory belongs to its allocating thread!
    ## Use `createShared <#createShared,typedesc>`_ to allocate from a shared heap.
    cast[ptr T](alloc0(sizeof(T) * size))

  template realloc*(p: pointer, newSize: Natural): pointer =
    ## Grows or shrinks a given memory block.
    ##
    ## If `p` is **nil** then a new memory block is returned.
    ## In either way the block has at least `newSize` bytes.
    ## If `newSize == 0` and `p` is not **nil** `realloc` calls `dealloc(p)`.
    ## In other cases the block has to be freed with
    ## `dealloc(block) <#dealloc,pointer>`_.
    ##
    ## The allocated memory belongs to its allocating thread!
    ## Use `reallocShared <#reallocShared.t,pointer,Natural>`_ to reallocate
    ## from a shared heap.
    reallocImpl(p, newSize)

  template realloc0*(p: pointer, oldSize, newSize: Natural): pointer =
    ## Grows or shrinks a given memory block.
    ##
    ## If `p` is **nil** then a new memory block is returned.
    ## In either way the block has at least `newSize` bytes.
    ## If `newSize == 0` and `p` is not **nil** `realloc` calls `dealloc(p)`.
    ## In other cases the block has to be freed with
    ## `dealloc(block) <#dealloc,pointer>`_.
    ##
    ## The block is initialized with all bytes containing zero, so it is
    ## somewhat safer then realloc
    ##
    ## The allocated memory belongs to its allocating thread!
    ## Use `reallocShared <#reallocShared.t,pointer,Natural>`_ to reallocate
    ## from a shared heap.
    realloc0Impl(p, oldSize, newSize)

  proc resize*[T](p: ptr T, newSize: Natural): ptr T {.inline, benign, raises: [].} =
    ## Grows or shrinks a given memory block.
    ##
    ## If `p` is **nil** then a new memory block is returned.
    ## In either way the block has at least `T.sizeof * newSize` bytes.
    ## If `newSize == 0` and `p` is not **nil** `resize` calls `dealloc(p)`.
    ## In other cases the block has to be freed with `free`.
    ##
    ## The allocated memory belongs to its allocating thread!
    ## Use `resizeShared <#resizeShared,ptr.T,Natural>`_ to reallocate
    ## from a shared heap.
    cast[ptr T](realloc(p, T.sizeof * newSize))

  proc dealloc*(p: pointer) {.noconv, compilerproc, rtl, benign, raises: [], tags: [].} =
    ## Frees the memory allocated with `alloc`, `alloc0`,
    ## `realloc`, `create` or `createU`.
    ##
    ## **This procedure is dangerous!**
    ## If one forgets to free the memory a leak occurs; if one tries to
    ## access freed memory (or just freeing it twice!) a core dump may happen
    ## or other memory may be corrupted.
    ##
    ## The freed memory must belong to its allocating thread!
    ## Use `deallocShared <#deallocShared,pointer>`_ to deallocate from a shared heap.
    incStat(deallocCount)
    deallocImpl(p)

  template allocShared*(size: Natural): pointer =
    ## Allocates a new memory block on the shared heap with at
    ## least `size` bytes.
    ##
    ## The block has to be freed with
    ## `reallocShared(block, 0) <#reallocShared.t,pointer,Natural>`_
    ## or `deallocShared(block) <#deallocShared,pointer>`_.
    ##
    ## The block is not initialized, so reading from it before writing
    ## to it is undefined behaviour!
    ##
    ## See also:
    ## * `allocShared0 <#allocShared0.t,Natural>`_.
    incStat(allocCount)
    allocSharedImpl(size)

  proc createSharedU*(T: typedesc, size = 1.Positive): ptr T {.inline, tags: [],
                                                               benign, raises: [].} =
    ## Allocates a new memory block on the shared heap with at
    ## least `T.sizeof * size` bytes.
    ##
    ## The block has to be freed with
    ## `resizeShared(block, 0) <#resizeShared,ptr.T,Natural>`_ or
    ## `freeShared(block) <#freeShared,ptr.T>`_.
    ##
    ## The block is not initialized, so reading from it before writing
    ## to it is undefined behaviour!
    ##
    ## See also:
    ## * `createShared <#createShared,typedesc>`_
    cast[ptr T](allocShared(T.sizeof * size))

  template allocShared0*(size: Natural): pointer =
    ## Allocates a new memory block on the shared heap with at
    ## least `size` bytes.
    ##
    ## The block has to be freed with
    ## `reallocShared(block, 0) <#reallocShared.t,pointer,Natural>`_
    ## or `deallocShared(block) <#deallocShared,pointer>`_.
    ##
    ## The block is initialized with all bytes
    ## containing zero, so it is somewhat safer than
    ## `allocShared <#allocShared.t,Natural>`_.
    incStat(allocCount)
    allocShared0Impl(size)

  proc createShared*(T: typedesc, size = 1.Positive): ptr T {.inline.} =
    ## Allocates a new memory block on the shared heap with at
    ## least `T.sizeof * size` bytes.
    ##
    ## The block has to be freed with
    ## `resizeShared(block, 0) <#resizeShared,ptr.T,Natural>`_ or
    ## `freeShared(block) <#freeShared,ptr.T>`_.
    ##
    ## The block is initialized with all bytes
    ## containing zero, so it is somewhat safer than
    ## `createSharedU <#createSharedU,typedesc>`_.
    cast[ptr T](allocShared0(T.sizeof * size))

  template reallocShared*(p: pointer, newSize: Natural): pointer =
    ## Grows or shrinks a given memory block on the heap.
    ##
    ## If `p` is **nil** then a new memory block is returned.
    ## In either way the block has at least `newSize` bytes.
    ## If `newSize == 0` and `p` is not **nil** `reallocShared` calls
    ## `deallocShared(p)`.
    ## In other cases the block has to be freed with
    ## `deallocShared <#deallocShared,pointer>`_.
    reallocSharedImpl(p, newSize)

  template reallocShared0*(p: pointer, oldSize, newSize: Natural): pointer =
    ## Grows or shrinks a given memory block on the heap.
    ##
    ## When growing, the new bytes of the block is initialized with all bytes
    ## containing zero, so it is somewhat safer then reallocShared
    ##
    ## If `p` is **nil** then a new memory block is returned.
    ## In either way the block has at least `newSize` bytes.
    ## If `newSize == 0` and `p` is not **nil** `reallocShared` calls
    ## `deallocShared(p)`.
    ## In other cases the block has to be freed with
    ## `deallocShared <#deallocShared,pointer>`_.
    reallocShared0Impl(p, oldSize, newSize)

  proc resizeShared*[T](p: ptr T, newSize: Natural): ptr T {.inline, raises: [].} =
    ## Grows or shrinks a given memory block on the heap.
    ##
    ## If `p` is **nil** then a new memory block is returned.
    ## In either way the block has at least `T.sizeof * newSize` bytes.
    ## If `newSize == 0` and `p` is not **nil** `resizeShared` calls
    ## `freeShared(p)`.
    ## In other cases the block has to be freed with
    ## `freeShared <#freeShared,ptr.T>`_.
    cast[ptr T](reallocShared(p, T.sizeof * newSize))

  proc deallocShared*(p: pointer) {.noconv, compilerproc, rtl, benign, raises: [], tags: [].} =
    ## Frees the memory allocated with `allocShared`, `allocShared0` or
    ## `reallocShared`.
    ##
    ## **This procedure is dangerous!**
    ## If one forgets to free the memory a leak occurs; if one tries to
    ## access freed memory (or just freeing it twice!) a core dump may happen
    ## or other memory may be corrupted.
    incStat(deallocCount)
    deallocSharedImpl(p)

  proc freeShared*[T](p: ptr T) {.inline, benign, raises: [].} =
    ## Frees the memory allocated with `createShared`, `createSharedU` or
    ## `resizeShared`.
    ##
    ## **This procedure is dangerous!**
    ## If one forgets to free the memory a leak occurs; if one tries to
    ## access freed memory (or just freeing it twice!) a core dump may happen
    ## or other memory may be corrupted.
    deallocShared(p)

  include bitmasks

  template `+!`(p: pointer, s: SomeInteger): pointer =
    cast[pointer](cast[int](p) +% int(s))

  template `-!`(p: pointer, s: SomeInteger): pointer =
    cast[pointer](cast[int](p) -% int(s))

  proc alignedAlloc(size, align: Natural): pointer =
    if align <= MemAlign:
      when compileOption("threads"):
        result = allocShared(size)
      else:
        result = alloc(size)
    else:
      # allocate (size + align - 1) necessary for alignment,
      # plus 2 bytes to store offset
      when compileOption("threads"):
        let base = allocShared(size + align - 1 + sizeof(uint16))
      else:
        let base = alloc(size + align - 1 + sizeof(uint16))
      # memory layout: padding + offset (2 bytes) + user_data
      # in order to deallocate: read offset at user_data - 2 bytes,
      # then deallocate user_data - offset
      let offset = align - (cast[int](base) and (align - 1))
      cast[ptr uint16](base +! (offset - sizeof(uint16)))[] = uint16(offset)
      result = base +! offset

  proc alignedAlloc0(size, align: Natural): pointer =
    if align <= MemAlign:
      when compileOption("threads"):
        result = allocShared0(size)
      else:
        result = alloc0(size)
    else:
      # see comments for alignedAlloc
      when compileOption("threads"):
        let base = allocShared0(size + align - 1 + sizeof(uint16))
      else:
        let base = alloc0(size + align - 1 + sizeof(uint16))
      let offset = align - (cast[int](base) and (align - 1))
      cast[ptr uint16](base +! (offset - sizeof(uint16)))[] = uint16(offset)
      result = base +! offset

  proc alignedDealloc(p: pointer, align: int) {.compilerproc.} =
    if align <= MemAlign:
      when compileOption("threads"):
        deallocShared(p)
      else:
        dealloc(p)
    else:
      # read offset at p - 2 bytes, then deallocate (p - offset) pointer
      let offset = cast[ptr uint16](p -! sizeof(uint16))[]
      when compileOption("threads"):
        deallocShared(p -! offset)
      else:
        dealloc(p -! offset)

  proc alignedRealloc(p: pointer, oldSize, newSize, align: Natural): pointer =
    if align <= MemAlign:
      when compileOption("threads"):
        result = reallocShared(p, newSize)
      else:
        result = realloc(p, newSize)
    else:
      result = alignedAlloc(newSize, align)
      copyMem(result, p, oldSize)
      alignedDealloc(p, align)

  proc alignedRealloc0(p: pointer, oldSize, newSize, align: Natural): pointer =
    if align <= MemAlign:
      when compileOption("threads"):
        result = reallocShared0(p, oldSize, newSize)
      else:
        result = realloc0(p, oldSize, newSize)
    else:
      result = alignedAlloc(newSize, align)
      copyMem(result, p, oldSize)
      zeroMem(result +! oldSize, newSize - oldSize)
      alignedDealloc(p, align)

  {.pop.}

# GC interface:

when hasAlloc:
  proc getOccupiedMem*(): int {.rtl.}
    ## Returns the number of bytes that are owned by the process and hold data.

  proc getFreeMem*(): int {.rtl.}
    ## Returns the number of bytes that are owned by the process, but do not
    ## hold any meaningful data.

  proc getTotalMem*(): int {.rtl.}
    ## Returns the number of bytes that are owned by the process.


when defined(js):
  # Stubs:
  proc getOccupiedMem(): int = return -1
  proc getFreeMem(): int = return -1
  proc getTotalMem(): int = return -1

  proc dealloc(p: pointer) = discard
  proc alloc(size: Natural): pointer = discard
  proc alloc0(size: Natural): pointer = discard
  proc realloc(p: pointer, newsize: Natural): pointer = discard
  proc realloc0(p: pointer, oldsize, newsize: Natural): pointer = discard

  proc allocShared(size: Natural): pointer = discard
  proc allocShared0(size: Natural): pointer = discard
  proc deallocShared(p: pointer) = discard
  proc reallocShared(p: pointer, newsize: Natural): pointer = discard
  proc reallocShared0(p: pointer, oldsize, newsize: Natural): pointer = discard


when hasAlloc and hasThreadSupport and not defined(useMalloc):
  proc getOccupiedSharedMem*(): int {.rtl.}
    ## Returns the number of bytes that are owned by the process
    ## on the shared heap and hold data. This is only available when
    ## threads are enabled.

  proc getFreeSharedMem*(): int {.rtl.}
    ## Returns the number of bytes that are owned by the
    ## process on the shared heap, but do not hold any meaningful data.
    ## This is only available when threads are enabled.

  proc getTotalSharedMem*(): int {.rtl.}
    ## Returns the number of bytes on the shared heap that are owned by the
    ## process. This is only available when threads are enabled.
