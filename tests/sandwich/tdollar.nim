discard """
  output: '''
used: Foo(123, 456)
debugging: Foo(123, 456)
'''
"""

import mdollar2, mdollar3 # `mdollar1` not imported, so `mdollar1.$` not in scope

let f = makeFoo(123, 456)
useFoo(f) # used: Foo(123, 456)
debug(f) # debugging: Foo(123, 456)
