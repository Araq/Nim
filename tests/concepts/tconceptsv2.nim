discard """
action: "run"
output: '''
B[system.int]
'''
"""

block: # issue  #24451
  type
    A = object
      x: int
    B[T] = object
      b: T
    AConcept = concept
      proc implementation(s: var Self, p1: B[int])

  proc implementation(r: var A, p1: B[int])=
    echo typeof(p1)

  proc accept(r: var AConcept)=
    r.implementation(B[int]())

  var a = A()
  a.accept()

