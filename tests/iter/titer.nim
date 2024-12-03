discard """
output: '''
testtesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttesttest2!test3?hi
what's
your
name
hi
what's
your
name
'''
"""

# Test the new iterators

iterator xrange(fromm, to: int, step = 1): int =
  var a = fromm
  while a <= to:
    yield a
    inc(a, step)

iterator interval[T](a, b: T): T =
  var x = a
  while x <= b:
    yield x
    inc(x)

#
#iterator lines(filename: string): (line: string) =
#  var
#    f: tTextfile
#    shouldClose = open(f, filename)
#  if shouldClose:
#    setSpace(line, 256)
#    while readTextLine(f, line):
#      yield line
#  finally:
#    if shouldClose: close(f)
#

for i in xrange(0, 5):
  for k in xrange(1, 7):
    write(stdout, "test")

for j in interval(45, 45):
  write(stdout, "test2!")
  write(stdout, "test3?")

for x in items(["hi", "what's", "your", "name"]):
  echo(x)

const
  stringArray = ["hi", "what's", "your", "name"]

for i in 0..len(stringArray)-1:
  echo(stringArray[i])

# bug #15360

type Rule[T] = (int, T)

var t: seq[Rule[int]]
for (c, t) in t:
  discard



import std/sugar

# bug #14165
iterator log_nodups_hamming(): int {.inline.} =
  let lb3 = 1
  let lb4 = 123
  proc mul3(): int = lb3 + lb4
  yield mul3()

for h in log_nodups_hamming():
  break
for h in log_nodups_hamming():
  break
for h in log_nodups_hamming():
  break

# bug #18536
iterator envPairs*(): int =
  var foo: seq[int]
  proc fun() =
    foo = @[]
  fun()
  yield 3

proc main() =
  for a in envPairs():
    discard
  for a in envPairs():
    discard
static: main()
main()

# bug #6269
iterator makeFn(outer_val: int): proc(a: int): int =
  for i in 0..1:
    yield proc(a:int): int =
      return a + i.int

let v1 = 42

let res = collect:
  for fn1 in makeFn(v1):
    let v2 = fn1(v1)
    for fn2 in makeFn(v2):
      fn2(v2)

doAssert res == @[42, 43, 43, 44]

block: # bug #21110
  iterator p(): int =
    when nimvm:
      yield 0
    else:
      yield 0

  template foo =
    for k in p():
      let m = ""
      proc e() = discard m & ""
      e()
  static: foo()
  foo()


# bug #15924
iterator walk(): (int, int) {.closure.} =
  yield (10,11)

for (i,j) in walk():
  doAssert i == 10

proc main123() =
  let x = false
  iterator it(): (bool, bool) {.closure.} = # normally {.closure.} here makes #21476 work
    discard x

  for (_, _) in it():
    discard

main123()
