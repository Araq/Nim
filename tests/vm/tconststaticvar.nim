block: # issue #8758
  template baz() =
    var i = 0

  proc foo() =
    static:
      var i = 0
      baz()

block: # issue #10828
  proc test(i: byte): bool =  
    const SET = block: # No issues when defined outside proc
      var s: set[byte]
      for i in 0u8 .. 255u8: incl(s, i)
      s
    return i in SET
  doAssert test(0)
  doAssert test(127)
  doAssert test(255)

block: # issue #12172
  const TEST = block:
    var test: array[5, string]
    for i in low(test)..high(test):
      test[i] = $i
    test
  proc test =
    const TEST2 = block:
      var test: array[5, string] # Error here
      for i in low(test)..high(test):
        test[i] = $i
      test
    doAssert TEST == TEST2
    doAssert TEST == @["0", "1", "2", "3", "4"]
    doAssert TEST2 == @["0", "1", "2", "3", "4"]
  test()

block: # issue #21610
  func stuff(): int =
    const r = block:
      var r = 1 # Error: cannot evaluate at compile time: r
      for i in 2..10:
        r *= i
      r
    r
  doAssert stuff() == 3628800

block: # issue #23803
  func foo1(c: int): int {.inline.} =
    const arr = block:
      var res: array[0..99, int]
      res[42] = 43
      res
    arr[c]
  doAssert foo1(41) == 0
  doAssert foo1(42) == 43
  doAssert foo1(43) == 0

  # works
  func foo2(c: int): int {.inline.} =
    func initArr(): auto =
      var res: array[0..99, int]
      res[42] = 43
      res
    const arr = initArr()
    arr[c]
  doAssert foo2(41) == 0
  doAssert foo2(42) == 43
  doAssert foo2(43) == 0

  # also works
  const globalArr = block:
    var res: array[0..99, int]
    res[42] = 43
    res
  func foo3(c: int): int {.inline.} = globalArr[c]
  doAssert foo3(41) == 0
  doAssert foo3(42) == 43
  doAssert foo3(43) == 0
