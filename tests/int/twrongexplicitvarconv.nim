discard """
  action: reject
  nimout: '''
  but expression 'int(a)' is immutable, not 'var'
'''
"""

proc `++`(n: var int) =
  n += 1

var a: int32 = 15

++int(a) #[tt.Error
^ type mismatch: got <int>]#

echo a
