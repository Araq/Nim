discard """
  output: '''
A: abc
B: 123
A: def
4
'''
"""
# Module C
import mambsym3, mambsym4

foo("abc") # A: abc
foo(123) # B: 123
let inferred: proc (x: string) = foo
foo("def") # A: def

doAssert not compiles(write(stdout, x)) # error: x is ambiguous
write(stdout, mambsym3.x) # no error: qualifier used

proc bar(a: int): int = a + 1
doAssert bar(x) == x + 1 # no error: only A.x of type int matches

var x = 4
write(stdout, x) # not ambiguous: uses the module C's x
echo() # for test output
