discard """
  output: '''
23
23
23
23
23
23
'''
"""

block: # issue #24305
  iterator demo(a: openArray[int]): int =
    for k in countUp(a[0], 19):
      yield 23

  for k in demo(@[17]):
    echo k

block: # issue #24305 with array
  iterator demo(a: array[1, int]): int =
    for k in countUp(a[0], 19):
      yield 23

  for k in demo([17]):
    echo k

block: # related regression
  proc main =
    let a = [0, 1, 2]
    let x = addr a[low(a)]
  main()
