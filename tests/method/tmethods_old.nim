discard """
  matrix: "--mm:arc -d:nimInternalNonVtablesTesting"
  output: '''
do nothing
'''
"""

# tmethods1
method somethin(obj: RootObj) {.base.} =
  echo "do nothing"
var o: RootObj
o.somethin()
