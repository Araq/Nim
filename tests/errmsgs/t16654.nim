discard """
  cmd: "nim check $options $file"
  errormsg: "type mismatch: got <int literal(1), proc (r: GenericParam): auto>"
"""

when true: # bug #16654
  func fn[T](a: T, op: proc(a: T): float) = discard
  proc main() =
    let v = 1
    proc bar(r: auto): auto = v
    fn(1, bar)
  main()
