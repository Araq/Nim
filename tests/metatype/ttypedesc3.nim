discard """
output: '''
proc Base
proc Child
method Base
yield Base
yield Child
12
'''
"""

import typetraits

type
  Base = object of RootObj
  Child = object of Base

proc pr(T: type[Base]) = echo "proc " & T.name
method me(T: type[Base]) = echo "method " & T.name
iterator it(T: type[Base]): auto = yield "yield " & T.name

Base.pr
Child.pr

Base.me
when false:
  Child.me #<- bug #2710

for s in Base.it: echo s
for s in Child.it: echo s #<- bug #2662


# bug #11747

type
  MyType = object
    a: int32
    b: int32
    c: int32

  MyRefType = ref MyType

echo sizeof(default(MyRefType)[])
