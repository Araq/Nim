discard """
  matrix: ";-d:useMalloc"
"""

# bug #23247
import std/hashes

func baseAddr[T](x: openArray[T]): ptr T =
  # Return the address of the zero:th element of x or `nil` if x is empty
  if x.len == 0: nil else: cast[ptr T](x)

func makeUncheckedArray[T](p: ptr T): ptr UncheckedArray[T] =
  cast[ptr UncheckedArray[T]](p)

type
  LabelKey = object
    data: seq[string]
    refs: ptr UncheckedArray[string]
    refslen: int

  Gauge = ref object
    metrics: seq[seq[seq[string]]]

template values(key: LabelKey): openArray[string] =
  if key.refslen > 0:
    key.refs.toOpenArray(0, key.refslen - 1)
  else:
    key.data

proc hash(key: LabelKey): Hash =
  hash(key.values)

proc view(T: type LabelKey, values: openArray[string]): T =
  # TODO some day, we might get view types - until then..
  LabelKey(refs: baseAddr(values).makeUncheckedArray(), refslen: values.len())

template withValue2(k: untyped) =
  discard hash(k)

proc setGauge(
    collector: Gauge,
    labelValues: openArray[string],
) =
  let v = LabelKey.view(labelValues)
  withValue2(v)
  collector.metrics.add @[@labelValues, @labelValues]
  discard @labelValues

var nim_gc_mem_bytes = Gauge()
let threadID = $getThreadId()
setGauge(nim_gc_mem_bytes, @[threadID])
setGauge(nim_gc_mem_bytes, @[threadID])