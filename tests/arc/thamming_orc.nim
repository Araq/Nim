discard """
  output: '''(allocCount: 1114, deallocCount: 1112)
created 491 destroyed 491'''
  cmd: "nim c --gc:orc -d:nimAllocStats $file"
"""

# bug #18421

# test Nim Hamming Number Lazy List algo with reference counts and not...
# compile with "-d:release -d:danger" and test with various
# memory managment GC's, allocators, threading, etc.
# it should be guaranteed to work with zero memory leaks with `--gc:orc`...

# compile with `-d:trace20` to trace creation and destruction of first 20 values.

from math import log2

# implement our own basic BigInt so the bigints library isn't necessary...
type
  BigInt = object
    digits: seq[uint32]
let zeroBigInt = BigInt(digits: @[ 0'u32 ])
let oneBigInt = BigInt(digits: @[ 1'u32 ])

proc shladd(bi: var BigInt; n: int; a: BigInt) =
  # assume that both `bi` and `a` are sized correctly with
  # msuint32 for both not containing a zero
  let alen = a.digits.len
  let mx = max(bi.digits.len, a.digits.len)
  for i in bi.digits.len ..< mx: bi.digits.add 0'u32
  var cry = 0'u64
  for i in 0 ..< alen:
    cry += (bi.digits[i].uint64 shl n) + a.digits[i].uint64
    bi.digits[i] = cry.uint32; cry = cry shr 32
  for i in alen ..< mx:
    cry += bi.digits[i].uint64 shl n
    bi.digits[i] = cry.uint32; cry = cry shr 32
  if cry > 0'u64:
    bi.digits.add cry.uint32

proc `$`(x: BigInt): string =
  if x.digits.len == 0 or (x.digits.len == 1 and x.digits[0] == 0'u32):
    return "0"
  result = ""; var n = x; var msd = n.digits.high
  while msd >= 0:
    if n.digits[msd] == 0'u32: msd.dec; continue
    var brw = 0.uint64
    for i in countdown(msd, 0):
      let dvdnd = n.digits[i].uint64 + (brw shl 32)
      let q = dvdnd div 10'u64; brw = dvdnd - q * 10'u64
      n.digits[i] = q.uint32
    result &= $brw
  for i in 0 .. result.high shr 1: # reverse result string in place
    let tmp = result[^(i + 1)]
    result[^(i + 1)] = result[i]
    result[i] = tmp

type TriVal = (uint32, uint32, uint32)
type LogRep = (float64, TriVal)
type LogRepf = proc(x: LogRep): LogRep
const one: LogRep = (0.0'f64, (0'u32, 0'u32, 0'u32))
proc `<`(me: LogRep, othr: LogRep): bool = me[0] < othr[0]

proc convertTriVal2BigInt(tpl: TriVal): BigInt =
  result = oneBigInt
  let (x2, x3, x5) = tpl
  for _ in 1 .. x2: result.shladd 1, zeroBigInt
  for _ in 1 .. x3: result.shladd 1, result
  for _ in 1 .. x5: result.shladd 2, result

const lb2 = 1.0'f64
const lb3 = 3.0'f64.log2
const lb5 = 5.0'f64.log2

proc mul2(me: LogRep): LogRep =
  let (lr, tpl) = me; let (x2, x3, x5) = tpl
  (lr + lb2, (x2 + 1, x3, x5))

proc mul3(me: LogRep): LogRep =
  let (lr, tpl) = me; let (x2, x3, x5) = tpl
  (lr + lb3, (x2, x3 + 1, x5))

proc mul5(me: LogRep): LogRep =
  let (lr, tpl) = me; let (x2, x3, x5) = tpl
  (lr + lb5, (x2, x3, x5 + 1))

type
  LazyListObj = object
    hd: LogRep
    tlf: proc(): LazyList {.closure.}
    tl: LazyList
  LazyList = ref LazyListObj

var destroyed = 0

proc `=destroy`(ll: var LazyListObj) =
  destroyed += 1
  if ll.tlf == nil and ll.tl == nil: return

  when defined(trace20):
    echo "destroying:  ", (destroyed, ll.hd[1].convertTriVal2BigInt)
  if ll.tlf != nil: ll.tlf.`=destroy`
  if ll.tl != nil: ll.tl.`=destroy`
  #wasMoved(ll)

proc rest(ll: LazyList): LazyList = # not thread-safe; needs lock on thunk
  if ll.tlf != nil: ll.tl = ll.tlf(); ll.tlf = nil
  ll.tl

var created = 0
iterator hammings(until: int): TriVal =
  proc merge(x, y: LazyList): LazyList =
    let xh = x.hd; let yh = y.hd; created += 1
    when defined(trace20):
      echo "merge create:  ", (created - 1, (if xh < yh: xh else: yh)[1].convertTriVal2BigInt)
    if xh < yh: LazyList(hd: xh, tlf: proc(): auto = merge x.rest, y)
    else: LazyList(hd: yh, tlf: proc(): auto = merge x, y.rest)
  proc smult(mltf: LogRepf; s: LazyList): LazyList =
    proc smults(ss: LazyList): LazyList =
      when defined(trace20):
        echo "mult create:  ", (created, ss.hd.mltf[1].convertTriVal2BigInt)
      created += 1; LazyList(hd: ss.hd.mltf, tlf: proc(): auto = ss.rest.smults)
    s.smults
  proc unnsm(s: LazyList, mltf: LogRepf): LazyList =
    var r: LazyList = nil
    when defined(trace20):
      echo "first create:  ", (created, one[1].convertTriVal2BigInt)
    let frst = LazyList(hd: one, tlf: proc(): LazyList = r); created += 1
    r = if s == nil: smult(mltf, frst) else: s.merge smult(mltf, frst)
    r
  yield one[1]
  var hmpll: LazyList = ((nil.unnsm mul5).unnsm mul3).unnsm mul2
  for _ in 2 .. until:
    yield hmpll.hd[1]; hmpll = hmpll.rest # almost forever

proc main =
  var s = ""
  for h in hammings(20): s &= $h.convertTrival2BigInt & " "
  doAssert s == "1 2 3 4 5 6 8 9 10 12 15 16 18 20 24 25 27 30 32 36 ",
           "Algorithmic error finding first 20 Hamming numbers!!!"

  when not defined(trace20):
    var lsth: TriVal = default(TriVal)
    for h in hammings(200): lsth = h
    doAssert $lsth.convertTriVal2BigInt == "16200",
             "Algorithmic error finding 200th Hamming number!!!"

let mem = getOccupiedMem()
main()
GC_FullCollect()
let mb = getOccupiedMem() - mem
doAssert mb == 0, "Found memory leak of " & $mb & " bytes!!!"

echo getAllocStats()
echo "created ", created, " destroyed ", destroyed
