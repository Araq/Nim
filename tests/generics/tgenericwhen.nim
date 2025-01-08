discard """
  targets: "c js"
"""

block: # issue #24041
  type ArrayBuf[N: static int, T = byte] = object
    when sizeof(int) > sizeof(uint8):
      when N <= int(uint8.high):
        n: uint8
      else:
        when sizeof(int) > sizeof(uint16):
          when N <= int(uint16.high):
            n: uint16
          else:
            when sizeof(int) > sizeof(uint32):
              when N <= int(uint32.high):
                n: uint32
              else:
                n: int
            else:
              n: int
        else:
          n: int
    else:
      n: int

  var x: ArrayBuf[8]
  doAssert x.n is uint8
  when sizeof(int) > sizeof(uint32):
    var y: ArrayBuf[int(uint32.high) * 8]
    doAssert y.n is int

block: # constant condition after dynamic one
  type Foo[T] = object
    when T is int:
      a: int
    elif true:
      a: string
    else:
      a: bool
  var x: Foo[string]
  doAssert x.a is string
  var y: Foo[int]
  doAssert y.a is int
  var z: Foo[float]
  doAssert z.a is string

block: # issue #4774, but not with threads
  const hasThreadSupport = not defined(js)
  when hasThreadSupport:
    type Channel[T] = object
      value: T
  type
    SomeObj[T] = object
      when hasThreadSupport:
        channel: ptr Channel[T]
  var x: SomeObj[int]
  doAssert compiles(x.channel) == hasThreadSupport
