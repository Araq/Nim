block: # issue #24450
  type
    B = object
      b: int
    A = object
      x: int
    AConcept = concept
      proc implementation(s: var Self, p1: B)

  proc implementation(r: var A, p1: B)=
    discard

  proc accept(r: var AConcept)=
    discard

  var a = A()
  a.accept()
