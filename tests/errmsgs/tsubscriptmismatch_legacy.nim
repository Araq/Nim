discard """
  nimout: '''
  but expression 'x' is of type: Foo
'''
"""

type Foo = object
let x = Foo()
discard x[1] #[tt.Error
         ^ type mismatch: got <Foo, int literal(1)>]#
