discard """
  cmd: "nim check $file"
"""

block:
  template foo(x: var int, y: untyped) = discard
  var a: float
  foo(a, undeclared) #[tt.Error
     ^ type mismatch: got <float, untyped>]# # `untyped` is arbitary
  # previous error: undeclared identifier: 'undeclared'

block: # issue #8697
  type
    Fruit = enum
      apple
      banana
      orange
  macro hello(x, y: untyped) = discard
  hello(apple, banana, orange) #[tt.Error
       ^ type mismatch: got <Fruit, Fruit, Fruit>]#

block: # issue #23265
  template declareFoo(fooName: untyped, value: uint16) =
    const `fooName Value` {.inject.} = value

  declareFoo(FOO, 0xFFFF)
  declareFoo(BAR, 0xFFFFF) #[tt.Error
            ^ type mismatch: got <untyped, int literal(1048575)>]#

block: # issue #9620
  template forLoop(index: untyped, length: int{lvalue}, body: untyped) =
    for `index`{.inject.} in 0 ..< length:
      body
  var x = newSeq[int](10)
  forLoop(i, x.len): #[tt.Error
         ^ type mismatch: got <untyped, int, void>]#
    x[i] = i
