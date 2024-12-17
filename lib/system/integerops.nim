#
#
#            Nim's Runtime Library
#        (c) Copyright 2020 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# Integer arithmetic with overflow checking. Uses
# intrinsics or inline assembler.

proc raiseOverflow {.compilerproc, noinline.} =
  # a single proc to reduce code size to a minimum
  sysFatal(OverflowDefect, "over- or underflow")

proc raiseDivByZero {.compilerproc, noinline.} =
  sysFatal(DivByZeroDefect, "division by zero")

{.pragma: nimbaseH, importc, nodecl, noSideEffect, compilerproc.}

when not defined(nimEmulateOverflowChecks):
  # take the #define from nimbase.h

  proc nimAddInt(a, b: int, res: ptr int): bool {.nimbaseH.}
  proc nimSubInt(a, b: int, res: ptr int): bool {.nimbaseH.}
  proc nimMulInt(a, b: int, res: ptr int): bool {.nimbaseH.}

  proc nimAddInt64(a, b: int64; res: ptr int64): bool {.nimbaseH.}
  proc nimSubInt64(a, b: int64; res: ptr int64): bool {.nimbaseH.}
  proc nimMulInt64(a, b: int64; res: ptr int64): bool {.nimbaseH.}

# unary minus and 'abs' not required here anymore and are directly handled
# in the code generator.
# 'nimModInt' does exist in nimbase.h without check as we moved the
# check for 0 to the codgen.
proc nimModInt(a, b: int; res: ptr int): bool {.nimbaseH.}

proc nimModInt64(a, b: int64; res: ptr int64): bool {.nimbaseH.}

# Platform independent versions.

template addImplFallback(name, T, U) {.dirty.} =
  when not declared(name):
    proc name(a, b: T; res: ptr T): bool {.compilerproc, inline.} =
      let r = cast[T](cast[U](a) + cast[U](b))
      if (r xor a) >= T(0) or (r xor b) >= T(0):
        res[] = r
      else:
        result = true

addImplFallback(nimAddInt, int, uint)
addImplFallback(nimAddInt64, int64, uint64)

template subImplFallback(name, T, U) {.dirty.} =
  when not declared(name):
    proc name(a, b: T; res: ptr T): bool {.compilerproc, inline.} =
      let r = cast[T](cast[U](a) - cast[U](b))
      if (r xor a) >= 0 or (r xor not b) >= 0:
        res[] = r
      else:
        result = true

subImplFallback(nimSubInt, int, uint)
subImplFallback(nimSubInt64, int64, uint64)

template mulImplFallback(name, T, U, conv) {.dirty.} =
  #
  # This code has been inspired by Python's source code.
  # The native int product x*y is either exactly right or *way* off, being
  # just the last n bits of the true product, where n is the number of bits
  # in an int (the delivered product is the true product plus i*2**n for
  # some integer i).
  #
  # The native float64 product x*y is subject to three
  # rounding errors: on a sizeof(int)==8 box, each cast to double can lose
  # info, and even on a sizeof(int)==4 box, the multiplication can lose info.
  # But, unlike the native int product, it's not in *range* trouble:  even
  # if sizeof(int)==32 (256-bit ints), the product easily fits in the
  # dynamic range of a float64. So the leading 50 (or so) bits of the float64
  # product are correct.
  #
  # We check these two ways against each other, and declare victory if
  # they're approximately the same. Else, because the native int product is
  # the only one that can lose catastrophic amounts of information, it's the
  # native int product that must have overflowed.
  #
  when not declared(name):
    proc name(a, b: T; res: ptr T): bool {.compilerproc, inline.} =
      let r = cast[T](cast[U](a) * cast[U](b))
      let floatProd = conv(a) * conv(b)
      let resAsFloat = conv(r)
      # Fast path for normal case: small multiplicands, and no info
      # is lost in either method.
      if resAsFloat == floatProd:
        res[] = r
      else:
        # Somebody somewhere lost info. Close enough, or way off? Note
        # that a != 0 and b != 0 (else resAsFloat == floatProd == 0).
        # The difference either is or isn't significant compared to the
        # true value (of which floatProd is a good approximation).

        # abs(diff)/abs(prod) <= 1/32 iff
        #   32 * abs(diff) <= abs(prod) -- 5 good bits is "close enough"
        if 32.0 * abs(resAsFloat - floatProd) <= abs(floatProd):
          res[] = r
        else:
          result = true

mulImplFallback(nimMulInt, int, uint, toFloat)
mulImplFallback(nimMulInt64, int64, uint64, toBiggestFloat)


template divImplFallback(name, T) {.dirty.} =
  proc name(a, b: T; res: ptr T): bool {.compilerproc, inline.} =
    # we moved the b == 0 case out into the codegen.
    if a == low(T) and b == T(-1):
      result = true
    else:
      result = false
      res[] = a div b

divImplFallback(nimDivInt, int)
divImplFallback(nimDivInt64, int64)

proc raiseFloatInvalidOp {.compilerproc, noinline.} =
  sysFatal(FloatInvalidOpDefect, "FPU operation caused a NaN result")

proc raiseFloatOverflow(x: float64) {.compilerproc, noinline.} =
  if x > 0.0:
    sysFatal(FloatOverflowDefect, "FPU operation caused an overflow")
  else:
    sysFatal(FloatUnderflowDefect, "FPU operations caused an underflow")
