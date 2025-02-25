discard """
  action: reject
nimout: '''
t20883.nim(13, 4) template/generic instantiation of `foo` from here
t20883.nim(9, 11) Error: cannot instantiate: 'U'
'''
"""

proc foo*[U](x: U = U(1e-6)) =
  echo x

foo[float]()
foo()
