#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# An `include` file for the different table implementations.

include hashcommon

const
  defaultInitialSize* = 32

template rawGetDeepImpl() {.dirty.} =   # Search algo for unconditional add
  genHashImpl(key, hc)
  var h: Hash = hc and maxHash(t)
  while isFilled(t.data[h].hcode):
    h = nextTry(h, maxHash(t))
  result = h

template rawInsertImpl() {.dirty.} =
  data[h].key = key
  data[h].val = val
  data[h].hcode = hc

proc rawGetDeep[X, A](t: X, key: A, hc: var Hash): int {.inline, outParamsAt: [3].} =
  rawGetDeepImpl()

proc rawInsert[X, A, B](t: var X, data: var KeyValuePairSeq[A, B],
                     key: A, val: sink B, hc: Hash, h: Hash) =
  rawInsertImpl()

template checkIfInitialized() =
  if t.dataLen == 0:
    initImpl(t, defaultInitialSize)

template addImpl(enlarge) {.dirty.} =
  checkIfInitialized()
  if mustRehash(t): enlarge(t)
  var hc: Hash
  var j = rawGetDeep(t, key, hc)
  rawInsert(t, t.data, key, val, hc, j)
  inc(t.counter)

template maybeRehashPutImpl(enlarge, val) {.dirty.} =
  checkIfInitialized()
  if mustRehash(t):
    enlarge(t)
    index = rawGetKnownHC(t, key, hc)
  index = -1 - index                  # important to transform for mgetOrPutImpl
  rawInsert(t, t.data, key, val, hc, index)
  inc(t.counter)

template putImpl(enlarge) {.dirty.} =
  checkIfInitialized()
  var hc: Hash = default(Hash)
  var index = rawGet(t, key, hc)
  if index >= 0: t.data[index].val = val
  else: maybeRehashPutImpl(enlarge, val)

template mgetOrPutImpl(enlarge) {.dirty.} =
  checkIfInitialized()
  var hc: Hash = default(Hash)
  var index = rawGet(t, key, hc)
  if index < 0:
    # not present: insert (flipping index)
    when declared(val):
      maybeRehashPutImpl(enlarge, val)
    else:
      maybeRehashPutImpl(enlarge, default(B))
  # either way return modifiable val
  result = t.data[index].val

# template mgetOrPutDefaultImpl(enlarge) {.dirty.} =
#   checkIfInitialized()
#   var hc: Hash = default(Hash)
#   var index = rawGet(t, key, hc)
#   if index < 0:
#     # not present: insert (flipping index)
#     maybeRehashPutImpl(enlarge, default(B))
#   # either way return modifiable val
#   result = t.data[index].val

template hasKeyOrPutImpl(enlarge) {.dirty.} =
  checkIfInitialized()
  var hc: Hash = default(Hash)
  var index = rawGet(t, key, hc)
  if index < 0:
    result = false
    maybeRehashPutImpl(enlarge, val)
  else: result = true

# delImplIdx is KnuthV3 Algo6.4R adapted to i=i+1 (from i=i-1) which has come to
# be called "back shift delete".  It shifts elements in the collision cluster of
# a victim backward to make things as-if the victim were never inserted in the
# first place.  This is desirable to keep things "ageless" after many deletes.
# It is trickier than you might guess since initial probe (aka "home") locations
# of keys in a cluster may collide and since table addresses wrap around.
#
# A before-after diagram might look like ('.' means empty):
#   slot:   0   1   2   3   4   5   6   7
# before(1)
#   hash1:  6   7   .   3   .   5   5   6  ; Really hash() and msk
#   data1:  E   F   .   A   .   B   C   D  ; About to delete C @index 6
# after(2)
#   hash2:  7   .   .   3   .   5   6   6  ; Really hash() and msk
#   data2:  F   .   .   A   .   B   D   E  ; After deletion of C
#
# This lowers total search depth over the whole table from 1+1+2+2+2+2=10 to 7.
# Had the victim been B@5, C would need back shifting to slot 5.  Total depth is
# always lowered by at least 1, e.g. victim A@3.  This is all quite fast when
# empty slots are frequent (also needed to keep insert/miss searches fast) and
# hash() is either fast or avoided (via `.hcode`).  It need not compare keys.
#
# delImplIdx realizes the above transformation, but only works for dense Linear
# Probing, nextTry(h)=h+1.  This is not an important limitation since that's the
# fastest sequence on any CPU made since the 1980s. { Performance analysis often
# overweights "key cmp" neglecting cache behavior, giving bad ideas how big/slow
# tables behave (when perf matters most!).  Comparing hcode first means usually
# only 1 key cmp is needed for *any* seq.  Timing only predictable activity,
# small tables, and/or integer keys often perpetuates such bad ideas. }

template delImplIdx(t, i, makeEmpty, cellEmpty, cellHash) =
  let msk = maxHash(t)
  if i >= 0:
    dec(t.counter)
    block outer:
      while true:         # KnuthV3 Algo6.4R adapted for i=i+1 instead of i=i-1
        var j = i         # The correctness of this depends on (h+1) in nextTry
        var r = j         # though may be adaptable to other simple sequences.
        makeEmpty(i)                     # mark current EMPTY
        {.push warning[UnsafeDefault]:off.}
        reset(t.data[i].key)
        reset(t.data[i].val)
        {.pop.}
        while true:
          i = (i + 1) and msk            # increment mod table size
          if cellEmpty(i):               # end of collision cluster; So all done
            break outer
          r = cellHash(i) and msk        # initial probe index for key@slot i
          if not ((i >= r and r > j) or (r > j and j > i) or (j > i and i >= r)):
            break
        when defined(js):
          t.data[j] = t.data[i]
        else:
          t.data[j] = move(t.data[i]) # data[j] will be marked EMPTY next loop

template delImpl(makeEmpty, cellEmpty, cellHash) {.dirty.} =
  var hc: Hash
  var i = rawGet(t, key, hc)
  delImplIdx(t, i, makeEmpty, cellEmpty, cellHash)

template delImplNoHCode(makeEmpty, cellEmpty, cellHash) {.dirty.} =
  if t.dataLen > 0:
    var i: Hash = hash(key) and maxHash(t)
    while not cellEmpty(i):
      if t.data[i].key == key:
        delImplIdx(t, i, makeEmpty, cellEmpty, cellHash)
        break
      i = nextTry(i, maxHash(t))

template clearImpl() {.dirty.} =
  for i in 0 ..< t.dataLen:
    when compiles(t.data[i].hcode): # CountTable records don't contain a hcode
      t.data[i].hcode = 0
    {.push warning[UnsafeDefault]:off.}
    reset(t.data[i].key)
    reset(t.data[i].val)
    {.pop.}
  t.counter = 0

template ctAnd(a, b): bool =
  when a:
    when b: true
    else: false
  else: false

template initImpl(result: typed, size: int) =
  let correctSize = slotsNeeded(size)
  when ctAnd(declared(SharedTable), typeof(result) is SharedTable):
    init(result, correctSize)
  else:
    result.counter = 0
    newSeq(result.data, correctSize)
    when compiles(result.first):
      result.first = -1
      result.last = -1

template insertImpl() = # for CountTable
  if t.dataLen == 0: initImpl(t, defaultInitialSize)
  if mustRehash(t): enlarge(t)
  ctRawInsert(t, t.data, key, val)
  inc(t.counter)

template getOrDefaultImpl(t, key): untyped =
  mixin rawGet
  var hc: Hash
  var index = rawGet(t, key, hc)
  if index >= 0: result = t.data[index].val

template getOrDefaultImpl(t, key, default: untyped): untyped =
  mixin rawGet
  var hc: Hash
  var index = rawGet(t, key, hc)
  result = if index >= 0: t.data[index].val else: default

template dollarImpl(): untyped {.dirty.} =
  if t.len == 0:
    result = "{:}"
  else:
    result = "{"
    for key, val in pairs(t):
      if result.len > 1: result.add(", ")
      result.addQuoted(key)
      result.add(": ")
      result.addQuoted(val)
    result.add("}")

template equalsImpl(s, t: typed) =
  if s.counter == t.counter:
    # different insertion orders mean different 'data' seqs, so we have
    # to use the slow route here:
    for key, val in s:
      if not t.hasKey(key): return false
      if t.getOrDefault(key) != val: return false
    return true
  else:
    return false
