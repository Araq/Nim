discard """
  matrix: "-d:nimNoLentIterators --mm:arc"
  output: '''PUSH DATA: {"test.message":{"test":{"nested":"v1"}}}'''
  joinable: false
"""

# bug #22748
import std/[json, typetraits, times]

# publish

proc publish*[T](payload: T) =
  discard

type MetricsPoint* = JsonNode

proc push*(stat: string, data: JsonNode, usec: int64 = 0) =
  let payload = newJObject()

  # this results in a infinite recursion unless we deepCopy()
  payload[stat] = data #.deepCopy

  echo "PUSH DATA: ", payload

  publish[MetricsPoint](payload)

var scopes {.threadvar.}: seq[JsonNode]

type WithTimeCallback*[T] = proc(data: var JsonNode): T

proc pushScoped*[T](metric: string, blk: WithTimeCallback[T]): T {.gcsafe.} =
  scopes.add newJObject()
  defer: discard scopes.pop()

  let stc = (cpuTime() * 1000_000).int64
  result = blk(scopes[^1])
  let dfc = (cpuTime() * 1000_000).int64 - stc

  push(metric, scopes[^1], dfc)

# demo code

discard pushScoped[int]("test.message") do (data: var JsonNode) -> int:
  result = 0
  data["test"] = %*{
    "nested": "v1"
  }