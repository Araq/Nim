discard """
  errormsg: "type mismatch: got <int literal(1), proc (a: GenericParam): auto>"
  line: 11
""" 

proc takesProc[T](x: T, f: proc(x: T): int) =
    echo f(x) + 2

takesProc(1, proc (a: int): int = 2) # ok, prints 4
takesProc(1, proc (a: auto): auto = 2) # ok, prints 4
takesProc(1, proc (a: auto): auto = "uh uh") # prints garbage
