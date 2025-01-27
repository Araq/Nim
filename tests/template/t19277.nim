discard """
  output: '''
got: 0
'''
"""

# issue #19277

import m19277_1, m19277_2

template injector(val: untyped): untyped =
  template subtemplate: untyped = val
  subtemplate()

template methodCall(val: untyped): untyped = val

{.push raises: [Defect].}

foo(injector(0).methodCall())
