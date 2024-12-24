import std/[asyncdispatch, httpclient, strutils, json, times]

type
  Tree[T] = object
    x: T
    rr: seq[Tree[T]]
  I = Tree[int]
  F = Tree[Future[string]]

proc title(t: I): Future[string] {.async,gcsafe.} =
  let cli = newAsyncHttpClient()
  let c = await cli.getContent("https://jsonplaceholder.typicode.com/todos/" & $t.x)
  c.parseJson()["title"].getStr()

proc map[T,U](t: T, f: proc (x: T): U{.async.gcsafe.}): U = #[tt.Error
                                            ^ invalid pragma: async.gcsafe]#
  result.x = f(t)
  for r in t.rr:
    result.rr.add map(r, f)

proc f(t: F, l: int) {.async.} =
  echo repeat(' ', l), (await t.x)
  for r in t.rr:
    await f(r, l+1)

proc asyncMain() {.async.} =
  let t = I(x: 1, rr: @[I(x: 2), I(x: 3, rr: @[I(x: 4), I(x: 5)])])
  await f(map[I,F](t, title), 0)

let a = now()
waitFor asyncMain()
echo now() - a
