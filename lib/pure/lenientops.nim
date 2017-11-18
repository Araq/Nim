#
#
#            Nim's Runtime Library
#        (c) Copyright 2017 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module offers implementations of common binary operations
## like ``+``, ``-``, ``*``, ``/`` and comparison operations,
## which work for mixed float/int operands.
## All operations convert the integer operand into the
## type of the float operand. For numerical expressions, the return
## type is always the type of the float involved in the expresssion,
## i.e., there is no auto conversion from float32 to float64.
##
## Note: In general, auto-converting from int to float loses
## information, which is why these operators live in a separate
## module. Use with care.

import typetraits

proc `+`*[I: SomeInteger, F: SomeReal](i: I, f: F): F {.noSideEffect, inline.} =
  F(i) + f
proc `+`*[I: SomeInteger, F: SomeReal](f: F, i: I): F {.noSideEffect, inline.} =
  f + F(i)

proc `-`*[I: SomeInteger, F: SomeReal](i: I, f: F): F {.noSideEffect, inline.} =
  F(i) - f
proc `-`*[I: SomeInteger, F: SomeReal](f: F, i: I): F {.noSideEffect, inline.} =
  f - F(i)

proc `*`*[I: SomeInteger, F: SomeReal](i: I, f: F): F {.noSideEffect, inline.} =
  F(i) * f
proc `*`*[I: SomeInteger, F: SomeReal](f: F, i: I): F {.noSideEffect, inline.} =
  f * F(i)

proc `/`*[I: SomeInteger, F: SomeReal](i: I, f: F): F {.noSideEffect, inline.} =
  F(i) / f
proc `/`*[I: SomeInteger, F: SomeReal](f: F, i: I): F {.noSideEffect, inline.} =
  f / F(i)

proc `<`*[I: SomeInteger, F: SomeReal](i: I, f: F): bool {.noSideEffect, inline.} =
  F(i) < f
proc `<`*[I: SomeInteger, F: SomeReal](f: F, i: I): bool {.noSideEffect, inline.} =
  f < F(i)
proc `<=`*[I: SomeInteger, F: SomeReal](i: I, f: F): bool {.noSideEffect, inline.} =
  F(i) <= f
proc `<=`*[I: SomeInteger, F: SomeReal](f: F, i: I): bool {.noSideEffect, inline.} =
  f <= F(i)
proc `==`*[I: SomeInteger, F: SomeReal](i: I, f: F): bool {.noSideEffect, inline.} =
  const msg = "Equality comparison between " & typetraits.name(I) & " and " & typetraits.name(F) & " should have explicit type conversion."
  {.warning: msg.}
  F(i) == f
proc `==`*[I: SomeInteger, F: SomeReal](f: F, i: I): bool {.noSideEffect, inline.} =
  const msg = "Equality comparison between " & typetraits.name(I) & " and " & typetraits.name(F) & " should have explicit type conversion."
  {.warning: msg.}
  f == F(i)

# Note that we must not defined `>=` and `>`, because system.nim already has a
# template with signature (x, y: untyped): untyped, which would lead to
# ambigous calls.
