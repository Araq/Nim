discard """
  errormsg: "cannot instantiate: 'T'"
  file: "system.nim"
"""

# issue #24091

type M[V] = object
type Foo = object # notice not generic
  x: typeof(default(M))
echo Foo() # ()
