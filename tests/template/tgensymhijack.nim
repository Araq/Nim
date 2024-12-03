# issue #23326

type Result*[E] = object
  e*: E

proc error*[E](v: Result[E]): E = discard

template valueOr*[E](self: Result[E], def: untyped): int =
  when E isnot void:
    when false:
      # Comment line below to make it work
      template error(): E {.used, gensym.} = s.e
      discard
    else:
      template error(): E {.used, inject.} =
        self.e

      def
  else:
    def


block:
  let rErr = Result[string](e: "a")
  let rErrV = rErr.valueOr:
    ord(error[0])

block:
  template foo(x: static bool): untyped =
    when x:
      let a = 123
    else:
      template a: untyped {.gensym.} = 456
    a
  
  doAssert foo(false) == 456
  doAssert foo(true) == 123
