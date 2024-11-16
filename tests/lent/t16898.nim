discard """
  errormsg: "invalid type: 'lent Fp2[6, system.uint64]' in this context: 'proc (r: var Fp2[6, system.uint64], a: lent Fp2[6, system.uint64], b: lent Fp2[6, system.uint64]){.noSideEffect, gcsafe.}' for proc"
"""

# bug #16898
type
  Fp[N: static int, T] = object
    big: array[N, T]

type
  QuadraticExt* = concept x
    ## Quadratic Extension concept (like complex)
    type BaseField = auto
    x.c0 is BaseField
    x.c1 is BaseField

{.experimental:"views".}

func prod(r: var QuadraticExt, a, b: lent QuadraticExt) =
  discard

type
  Fp2[N: static int, T] = object
    c0, c1: Fp[N, T]

# This should be passed by reference,
# but concepts do not respect the 24 bytes rule
# or `byref` pragma.
var r, a, b: Fp2[6, uint64]

prod(r, a, b)
