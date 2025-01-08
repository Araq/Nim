discard """
  targets: "cpp"
  output: '''
int
float'''
"""

import typetraits

# bug #4625
type
  Vector[T] {.importcpp: "std::vector<'0 >", header: "vector".} = object

proc initVector[T](): Vector[T] {.importcpp: "'0(@)", header: "vector", constructor.}

proc doSomething[T](v: var Vector[T]) =
  echo T.name

var v = initVector[int]()
v.doSomething()

var vf = initVector[float]()
vf.doSomething() # Nim uses doSomething[int] here in C++

# Alternative definition:
# https://github.com/nim-lang/Nim/issues/7653

type VectorAlt*[T] {.importcpp: "std::vector", header: "<vector>", nodecl.} = object
proc mkVector*[T]: VectorAlt[T] {.importcpp: "std::vector<'*0>()", header: "<vector>", constructor, nodecl.}

proc foo(): VectorAlt[cint] =
  mkVector[cint]()

proc bar(): VectorAlt[cstring] =
  mkVector[cstring]()

var x = foo()
var y = bar()

proc init[T; Self: Vector[T]](_: typedesc[Self], n: csize_t): Vector[T]
  {.importcpp: "std::vector<'*0>(@)", header: "<vector>", constructor, nodecl.}
proc size[T](x: Vector[T]): csize_t
  {.importcpp: "#.size()", header: "<vector>", nodecl.}

var z = Vector[int16].init(32)
assert z.size == 32
