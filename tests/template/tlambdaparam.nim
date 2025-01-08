discard """
  action: compile
"""

# issue #18648

type
  X* = ref object
    bar: proc (p: proc(v: openArray[byte]))

template foo(x: X, p: proc(v: openArray[byte])) =
  x.bar(p)

X().foo(proc(v: openArray[byte]) = discard @v)
