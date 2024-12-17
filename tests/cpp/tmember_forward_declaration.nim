discard """
  targets: "cpp"
  cmd: "nim cpp $file"
  output: '''
abc called
def called
abc called
'''
"""

type Foo = object

proc abc(this: Foo, x: int): void {.member: "$1('2 #2)".}
proc def(this: Foo, y: int): void {.virtual: "$1('2 #2)".}

proc abc(this: Foo, x: int): void =
  echo "abc called"
  if x > 0:
    this.def(x - 1)

proc def(this: Foo, y: int): void =
  echo "def called"
  this.abc(y)

var x = Foo()
x.abc(1)

