block: # issue #22661
  template foo(a: typed) =
    a
    
  foo:
    case false
    of false..true: discard
