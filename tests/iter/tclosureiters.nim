discard """
  targets: "c js"
  output: '''0
1
2
3
4
5
6
7
8
9
10
5 5
7 7
9 9
0
0
0
0
1
2
70
0
(1, 1)
(1, 2)
(1, 3)
(2, 1)
(2, 2)
(2, 3)
(3, 1)
(3, 2)
(3, 3)
'''
"""

when true:
  proc main() =
    let
      lo=0
      hi=10

    iterator itA(): int =
      for x in lo..hi:
        yield x

    for x in itA():
      echo x

    var y: int

    iterator itB(): int =
      while y <= hi:
        yield y
        inc y

    y = 5
    for x in itB():
      echo x, " ", y
      inc y

  main()


iterator infinite(): int {.closure.} =
  var i = 0
  while true:
    yield i
    inc i

iterator take[T](it: iterator (): T, numToTake: int): T {.closure.} =
  var i = 0
  for x in it():
    if i >= numToTake:
      break
    yield x
    inc i

# gives wrong reasult (3 times 0)
for x in infinite.take(3):
  echo x

# does what we want
let inf = infinite
for x in inf.take(3):
  echo x

# bug #3583
proc foo(f: (iterator(): int)) =
  for i in f(): echo i

let fIt = iterator(): int = yield 70
foo fIt

# bug #5321

proc lineIter*(filename: string): iterator(): string =
  result = iterator(): string {.closure.} =
    for line in lines(filename):
      yield line

proc unused =
  var count = 0
  let iter = lineIter("temp10.nim")
  for line in iter():
    count += 1

iterator lineIter2*(filename: string): string {.closure.} =
  var f = open(filename, bufSize=8000)
  defer: close(f)   # <-- commenting defer "solves" the problem
  var res = newStringOfCap(80)
  while f.readLine(res): yield res

proc unusedB =
  var count = 0
  for line in lineIter2("temp10.nim"):
    count += 1

# bug #5519
import os, algorithm

iterator filesIt(path: string): auto {.closure.} =
  var files = newSeq[string]()
  var dirs = newSeq[string]()
  for k, p in os.walkDir(path):
    let (_, n, e) = p.splitFile
    if e != "":
      continue
    case k
    of pcFile, pcLinkToFile:
      files.add(n)
    else:
      dirs.add(n)
  files.sort(system.cmp)
  dirs.sort(system.cmp)
  for f in files:
    yield f

  for d in dirs:
    files = newSeq[string]()
    for k, p in os.walkDir(path / d):
      let (_, n, e) = p.splitFile
      if e != "":
        continue
      case k
      of pcFile, pcLinkToFile:
        files.add(n)
      else:
        discard
    files.sort(system.cmp)
    let prefix = path.splitPath[1]
    for f in files:
      yield prefix / f

# bug #13815
when not defined(js):
  var love = iterator: int {.closure.} =
    yield cast[type(
      block:
        var a = 0
        yield a
        a)](0)

  for i in love():
    echo i
else:
  echo 0

# bug #18474
iterator pairs(): (int, int) {.closure.} =
  for i in 1..3:
    for j in 1..3:
      yield (i, j)

for pair in pairs():
  echo pair
