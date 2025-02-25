discard """
  output: '''
1
2
3
FooBar
foo1
foo2
foo3
seq[int]
@[5, 6]
'''
"""

# issue #13252

import macros

type
  FooBar = object
    a: seq[int]

macro genFoobar(fb: static FooBar): untyped =
  result = newStmtList()
  for b in fb.a:
    result.add(newCall(bindSym"echo", newLit b))

proc foobar(fb: static FooBar) =
  genFoobar(fb)
  echo fb.type # added line, same error when wrapped in static:
  # Error: undeclared field: 'a'
  for b in fb.a:
    echo "foo" & $b

proc main() =
  const a: seq[int] = @[1, 2, 3]
  const fb = Foobar(a: a)
  foobar(fb)
main()

# issue #14917

proc passSeq2[T](a : static seq[T]) =
  echo a

template passSeq1[T](a : static seq[T]) =
  echo type(a)
  passSeq2(a)

passSeq1(@[5,6])
