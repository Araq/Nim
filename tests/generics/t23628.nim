discard """
output: '''5
'''
"""

type
  Bar[T; C: static int] = object
    arr: array[C, ptr T]

  Foo[T; C: static int] = object
    bar: Bar[Foo[T, C], C]

var f: Foo[int, 5]
echo f.bar.arr.len
