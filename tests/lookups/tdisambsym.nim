# issue #15247

import mdisambsym1, mdisambsym2, mdisambsym3

proc twice(n: int): int =
  n*2

doAssert twice(count) == 20
