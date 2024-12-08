block: # issue #6013
  type
    n16 = range[0'i16..high(int16)]
    SomeObj = ref object

  proc doSomethingMore(idOrObj: n16 or SomeObj) =
    discard

  proc doSomething(idOrObj: n16 or SomeObj) =
    doSomethingMore(idOrObj) # Error: type mismatch: got (int16)

  doSomething(0.n16)
