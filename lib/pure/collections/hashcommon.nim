#
#
#            Nim's Runtime Library
#        (c) Copyright 2019 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# An `include` file which contains common code for
# hash sets and tables.

when defined(nimPreviewSlimSystem):
  import std/assertions

import std / outparams

const
  growthFactor = 2

# hcode for real keys cannot be zero.  hcode==0 signifies an empty slot.  These
# two procs retain clarity of that encoding without the space cost of an enum.
proc isEmpty(hcode: Hash): bool {.inline.} =
  result = hcode == 0

proc isFilled(hcode: Hash): bool {.inline.} =
  result = hcode != 0

proc nextTry(h, maxHash: Hash): Hash {.inline.} =
  result = (h + 1) and maxHash

proc mustRehash[T](t: T): bool {.inline.} =
  # If this is changed, make sure to synchronize it with `slotsNeeded` below
  assert(t.dataLen > t.counter)
  result = (t.dataLen < (t.counter + t.counter div 2)) or (t.dataLen - t.counter < 4)

proc slotsNeeded(count: Natural): int {.inline.} =
  # Make sure to synchronize with `mustRehash` above
  result = nextPowerOfTwo(count div 2 + count + 4)

template rawGetKnownHCImpl() {.dirty.} =
  if t.dataLen == 0:
    return -1
  var h: Hash = hc and maxHash(t) # start with real hash value
  while isFilled(t.data[h].hcode):
    # Compare hc THEN key with boolean short circuit. This makes the common case
    # zero ==key's for missing (e.g.inserts) and exactly one ==key for present.
    # It does slow down succeeding lookups by one extra Hash cmp&and..usually
    # just a few clock cycles, generally worth it for any non-integer-like A.
    if t.data[h].hcode == hc and t.data[h].key == key:
      return h
    h = nextTry(h, maxHash(t))
  result = -1 - h # < 0 => MISSING; insert idx = -1 - result

proc rawGetKnownHC[X, A](t: X, key: A, hc: Hash): int {.inline.} =
  rawGetKnownHCImpl()

template genHashImpl(key, hc: typed) =
  hc = hash(key)
  if hc == 0: # This almost never taken branch should be very predictable.
    when sizeof(int) < 4:
      hc = 31415 # Value doesn't matter; Any non-zero favorite is fine <= 16-bit.
    else:
      hc = 314159265 # Value doesn't matter; Any non-zero favorite is fine.

template genHash(key: typed): Hash =
  var res: Hash
  genHashImpl(key, res)
  res

template rawGetImpl() {.dirty.} =
  genHashImpl(key, hc)
  rawGetKnownHCImpl()

proc rawGet[X, A](t: X, key: A, hc: var Hash): int {.inline, outParamsAt: [3].} =
  rawGetImpl()
