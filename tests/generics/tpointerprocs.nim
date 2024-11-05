discard """
cmd: "nim check $options --hints:off $file"
action: "reject"
nimout:'''
tpointerprocs.nim(22, 11) Error: 'foo' doesn't have a concrete type, due to unspecified generic parameters.
tpointerprocs.nim(34, 14) Error: type mismatch: got <int>
but expected one of:
proc foo(x: int | float; y: int or string): float
  first type mismatch at position: 2 in generic parameters
  missing generic parameter: y:type

expression: foo[int]
tpointerprocs.nim(34, 14) Error: cannot instantiate: 'foo[int]'
tpointerprocs.nim(34, 14) Error: expression 'foo[int]' has no type (or is ambiguous)
tpointerprocs.nim(35, 11) Error: expression 'bar' has no type (or is ambiguous)
'''
"""

block:
  proc foo(x: int | float): float = result = 1.0
  let
    bar = foo
    baz = bar

block:
  proc foo(x: int | float): float = result = 1.0
  let
    bar = foo[int]
    baz = bar

block:
  proc foo(x: int | float, y: int or string): float = result = 1.0
  let
    bar = foo[int]
    baz = bar
