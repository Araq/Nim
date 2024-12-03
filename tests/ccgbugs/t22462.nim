discard """
  action: "run"
  output: '''
1
1
1
'''
  matrix: "--mm:refc"
  targets: "c cpp"
"""

type Object = object
  someComplexType: seq[int]
  index: Natural

func newObject(): Object = result.index.inc

for i in 1..3:
  let o = newObject()
  echo o.index
