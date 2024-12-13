discard """
  cmd: "nim c --gc:arc --deepcopy:on $file"
  output: '''13 abc
13 abc
13 abc
13 abc
13 abc
13 abc
13 abc
13 abc
13 abc
13 abc
13 abc
called deepCopy for int
called deepCopy for int
called deepCopy for int
called deepCopy for int
called deepCopy for int
called deepCopy for int
called deepCopy for int
called deepCopy for int
called deepCopy for int
called deepCopy for int
called deepCopy for int
0'''
"""

type
  PBinaryTree = ref object of RootObj
    le, ri: PBinaryTree
    value: int

proc mainB =
  var x: PBinaryTree = nil
  deepCopy(x, PBinaryTree(ri: PBinaryTree(le: PBinaryTree(value: 13))))

  var y: string = ""
  deepCopy y, "abc"
  echo x.ri.le.value, " ", y

for i in 0..10:
  mainB()


type
  Bar[T] = object
    x: T

proc `=deepCopy`[T](b: ref Bar[T]): ref Bar[T] =
  result.new
  result.x = b.x
  when T is int:
    echo "called deepCopy for int"
  else:
    echo "called deepCopy for something else"

proc main =
  var dummy, c: ref Bar[int] = nil
  new(dummy)
  dummy.x = 44

  deepCopy c, dummy

for i in 0..10:
  main()

echo getOccupiedMem()
