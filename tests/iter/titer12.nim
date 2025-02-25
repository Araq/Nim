discard """
targets: "c js"
output: '''
Selecting 2
1.0
Selecting 4
2.0
'''
"""


# bug #5522
import macros, sugar, sequtils

proc tryS(f: () -> void): void =
  (try: f() except: discard)

template trySTImpl(body: untyped): untyped =
  tryS do() -> auto:
    `body`

macro tryST*(body: untyped): untyped =
  var b = if body.kind == nnkDo: body[^1] else: body
  result = quote do:
    trySTImpl((block:
      `b`
    ))

iterator testIt(): int {.closure.} =
  for x in 0..10:
    yield x

var xs = newSeq[int]()
proc test = tryST do:
  for x in testIt():
    xs.add(x)

test()

doAssert xs == toSeq(0..10)



# bug #5690
proc filter[T](it: (iterator : T), f: proc(x: T): bool): (iterator : T) =
  return iterator (): T {.closure.} =
    for x in it():
      if f(x): 
        yield x

proc len[T](it : iterator : T) : Natural =
  for i in it():
    result += 1

proc simpleSeqIterator(s :seq[int]) : iterator : int =
  iterator it: int {.closure.} =
    for x in s:
      yield x
  result = it

let a = newSeq[int](99)

doAssert len(simpleSeqIterator(a).filter(proc(x : int) : bool = true)) == 99



# bug #5340
proc where[A](input: seq[A], filter: (A) -> bool): iterator (): A =
  result = iterator (): A {.closure.} = 
    for item in input:
      if filter(item):
        yield item

proc select[A,B](input: iterator(): A {.closure.}, selector: (A) -> B): iterator (): B {.closure.} = 
  result = iterator (): B =
    for item in input():
      echo "Selecting " & $item
      yield selector(item)

let query = @[1,2,3,4].where(x=>x mod 2==0).select((x)=>x/2)

for i in query():
  echo $i
