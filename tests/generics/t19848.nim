discard """
  output: '''
todo
'''
"""

type
  Maybe[T] = object
  List[T] = object

proc dump[M: Maybe](a: List[M]) =
  echo "todo"

var a: List[Maybe[int]]
  
dump(a)
