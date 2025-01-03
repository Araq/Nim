discard """
  targets: "c"
  output: '''
Test 1:
12
Test 2:
23
23
Test 3:
34
34
Test 4:
45
45
50
50
Test 5:
45
123
47
50
Test 6:
<hi>
Test 7:
0
1
2
'''
"""

block: #24094
  echo "Test 1:"
  proc foo() =
    let x = 12
    iterator bar2(): int {.closure.} =
      yield x
    proc bar() =
      let z = bar2
      for y in z(): # just doing bar2() gives param not in env: x
        echo y
    bar()

  foo()

block: #24094
  echo "Test 2:"
  iterator foo(): int {.closure.} =
    let x = 23
    iterator bar2(): int {.closure.} =
      yield x
    proc bar() =
      let z = bar2
      for y in z():
        echo y
    bar()
    yield x

  for x in foo(): echo x

block: #24094
  echo "Test 3:"
  iterator foo(): int {.closure.} =
    let x = 34
    proc bar() =
      echo x
    iterator bar2(): int {.closure.} =
      bar()
      yield x
    for y in bar2():
      yield y

  for x in foo(): echo x

block:
  echo "Test 4:"
  proc foo() =
    var x = 45
    iterator bar2(): int {.closure.} =
      yield x
      yield x + 3

    let b1 = bar2
    let b2 = bar2
    echo b1()
    echo b2()
    x = 47
    echo b1()
    echo b2()
  foo()

block:
  echo "Test 5:"
  proc foo() =
    var x = 45
    iterator bar2(): int {.closure.} =
      yield x
      yield x + 3

    proc bar() =
      var y = 123
      iterator bar3(): int {.closure.} =
        yield x
        yield y
      let b3 = bar3
      for z in b3():
        echo z
      x = 47
      let b2 = bar2
      for z in b2():
        echo z
    bar()
  foo()

block: #19154
  echo "Test 6:"
  proc test(s: string): proc(): iterator(): string =
    iterator it(): string = yield s
    proc f(): iterator(): string = it
    return f

  let it = test("hi")()
  for s in it():
    echo "<", s, ">"

block: #3824
  echo "Test 7:"
  proc main =
    iterator factory(): int {.closure.} =
      iterator bar(): int {.closure.} =
        yield 0
        yield 1
        yield 2

      for x in bar(): yield x

    for x in factory():
      echo x

  main()

block: # issue #12487
  iterator FaiReader(): string {.closure.} =
    yield "something"

  template toClosure(i): auto =
    iterator j: string {.closure.} =
      for x in FaiReader():
        yield x
    j

  proc main = 
    var reader = toClosure(FaiReader())
    var s: seq[string] = @[]
    for x in reader():
      s.add(x)
    doAssert s == @["something"]

  main()
