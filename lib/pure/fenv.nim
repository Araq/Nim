#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Floating-point environment. Handling of floating-point rounding and
## exceptions (overflow, division by zero, etc.).
## The types, vars and procs are bindings for the C standard library
## [<fenv.h>](https://en.cppreference.com/w/c/numeric/fenv) header.

when defined(posix) and not defined(genode) and not defined(macosx):
  {.passl: "-lm".}

var
  FE_DIVBYZERO* {.importc, header: "<fenv.h>".}: cint
    ## division by zero
  FE_INEXACT* {.importc, header: "<fenv.h>".}: cint
    ## inexact result
  FE_INVALID* {.importc, header: "<fenv.h>".}: cint
    ## invalid operation
  FE_OVERFLOW* {.importc, header: "<fenv.h>".}: cint
    ## result not representable due to overflow
  FE_UNDERFLOW* {.importc, header: "<fenv.h>".}: cint
    ## result not representable due to underflow
  FE_ALL_EXCEPT* {.importc, header: "<fenv.h>".}: cint
    ## bitwise OR of all supported exceptions
  FE_DOWNWARD* {.importc, header: "<fenv.h>".}: cint
    ## round toward -Inf
  FE_TONEAREST* {.importc, header: "<fenv.h>".}: cint
    ## round to nearest
  FE_TOWARDZERO* {.importc, header: "<fenv.h>".}: cint
    ## round toward 0
  FE_UPWARD* {.importc, header: "<fenv.h>".}: cint
    ## round toward +Inf
  FE_DFL_ENV* {.importc, header: "<fenv.h>".}: cint
    ## macro of type pointer to `fenv_t` to be used as the argument
    ## to functions taking an argument of type `fenv_t`; in this
    ## case the default environment will be used

type
  Tfenv* {.importc: "fenv_t", header: "<fenv.h>", final, pure.} =
    object ## Represents the entire floating-point environment. The
           ## floating-point environment refers collectively to any
           ## floating-point status flags and control modes supported
           ## by the implementation.
  Tfexcept* {.importc: "fexcept_t", header: "<fenv.h>", final, pure.} =
    object ## Represents the floating-point status flags collectively,
           ## including any status the implementation associates with the
           ## flags. A floating-point status flag is a system variable
           ## whose value is set (but never cleared) when a floating-point
           ## exception is raised, which occurs as a side effect of
           ## exceptional floating-point arithmetic to provide auxiliary
           ## information. A floating-point control mode is a system variable
           ## whose value may be set by the user to affect the subsequent
           ## behavior of floating-point arithmetic.

proc feclearexcept*(excepts: cint): cint {.importc, header: "<fenv.h>".}
  ## Clear the supported exceptions represented by `excepts`.

proc fegetexceptflag*(flagp: ptr Tfexcept, excepts: cint): cint {.
  importc, header: "<fenv.h>".}
  ## Store implementation-defined representation of the exception flags
  ## indicated by `excepts` in the object pointed to by `flagp`.

proc feraiseexcept*(excepts: cint): cint {.importc, header: "<fenv.h>".}
  ## Raise the supported exceptions represented by `excepts`.

proc fesetexceptflag*(flagp: ptr Tfexcept, excepts: cint): cint {.
  importc, header: "<fenv.h>".}
  ## Set complete status for exceptions indicated by `excepts` according to
  ## the representation in the object pointed to by `flagp`.

proc fetestexcept*(excepts: cint): cint {.importc, header: "<fenv.h>".}
  ## Determine which of subset of the exceptions specified by `excepts` are
  ## currently set.

proc fegetround*(): cint {.importc, header: "<fenv.h>".}
  ## Get current rounding direction.

proc fesetround*(roundingDirection: cint): cint {.importc, header: "<fenv.h>".}
  ## Establish the rounding direction represented by `roundingDirection`.

proc fegetenv*(envp: ptr Tfenv): cint {.importc, header: "<fenv.h>".}
  ## Store the current floating-point environment in the object pointed
  ## to by `envp`.

proc feholdexcept*(envp: ptr Tfenv): cint {.importc, header: "<fenv.h>".}
  ## Save the current environment in the object pointed to by `envp`, clear
  ## exception flags and install a non-stop mode (if available) for all
  ## exceptions.

proc fesetenv*(a1: ptr Tfenv): cint {.importc, header: "<fenv.h>".}
  ## Establish the floating-point environment represented by the object
  ## pointed to by `envp`.

proc feupdateenv*(envp: ptr Tfenv): cint {.importc, header: "<fenv.h>".}
  ## Save current exceptions in temporary storage, install environment
  ## represented by object pointed to by `envp` and raise exceptions
  ## according to saved exceptions.

const
  FLT_RADIX = 2                     ## the radix of the exponent representation

  FLT_MANT_DIG = 24                ## the number of base FLT_RADIX digits in the mantissa part of a float
  FLT_DIG = 6                      ## the number of digits of precision of a float
  FLT_MIN_EXP = -125               ## the minimum value of base FLT_RADIX in the exponent part of a float
  FLT_MAX_EXP = 128                ## the maximum value of base FLT_RADIX in the exponent part of a float
  FLT_MIN_10_EXP = -37             ## the minimum value in base 10 of the exponent part of a float
  FLT_MAX_10_EXP = 38              ## the maximum value in base 10 of the exponent part of a float
  FLT_MIN = 1.17549435e-38'f32     ## the minimum value of a float
  FLT_MAX = 3.40282347e+38'f32     ## the maximum value of a float
  FLT_EPSILON = 1.19209290e-07'f32 ## the difference between 1 and the least value greater than 1 of a float

  DBL_MANT_DIG = 53                    ## the number of base FLT_RADIX digits in the mantissa part of a double
  DBL_DIG = 15                         ## the number of digits of precision of a double
  DBL_MIN_EXP = -1021                  ## the minimum value of base FLT_RADIX in the exponent part of a double
  DBL_MAX_EXP = 1024                   ## the maximum value of base FLT_RADIX in the exponent part of a double
  DBL_MIN_10_EXP = -307                ## the minimum value in base 10 of the exponent part of a double
  DBL_MAX_10_EXP = 308                 ## the maximum value in base 10 of the exponent part of a double
  DBL_MIN = 2.2250738585072014E-308    ## the minimal value of a double
  DBL_MAX = 1.7976931348623157E+308    ## the minimal value of a double
  DBL_EPSILON = 2.2204460492503131E-16 ## the difference between 1 and the least value greater than 1 of a double

template fpRadix*: int = FLT_RADIX
  ## The (integer) value of the radix used to represent any floating
  ## point type on the architecture used to build the program.

template mantissaDigits*(T: typedesc[float32]): int = FLT_MANT_DIG
  ## Number of digits (in base `floatingPointRadix`) in the mantissa
  ## of 32-bit floating-point numbers.
template digits*(T: typedesc[float32]): int = FLT_DIG
  ## Number of decimal digits that can be represented in a
  ## 32-bit floating-point type without losing precision.
template minExponent*(T: typedesc[float32]): int = FLT_MIN_EXP
  ## Minimum (negative) exponent for 32-bit floating-point numbers.
template maxExponent*(T: typedesc[float32]): int = FLT_MAX_EXP
  ## Maximum (positive) exponent for 32-bit floating-point numbers.
template min10Exponent*(T: typedesc[float32]): int = FLT_MIN_10_EXP
  ## Minimum (negative) exponent in base 10 for 32-bit floating-point
  ## numbers.
template max10Exponent*(T: typedesc[float32]): int = FLT_MAX_10_EXP
  ## Maximum (positive) exponent in base 10 for 32-bit floating-point
  ## numbers.
template minimumPositiveValue*(T: typedesc[float32]): float32 = FLT_MIN
  ## The smallest positive (nonzero) number that can be represented in a
  ## 32-bit floating-point type.
template maximumPositiveValue*(T: typedesc[float32]): float32 = FLT_MAX
  ## The largest positive number that can be represented in a 32-bit
  ## floating-point type.
template epsilon*(T: typedesc[float32]): float32 = FLT_EPSILON
  ## The difference between 1.0 and the smallest number greater than
  ## 1.0 that can be represented in a 32-bit floating-point type.

template mantissaDigits*(T: typedesc[float64]): int = DBL_MANT_DIG
  ## Number of digits (in base `floatingPointRadix`) in the mantissa
  ## of 64-bit floating-point numbers.
template digits*(T: typedesc[float64]): int = DBL_DIG
  ## Number of decimal digits that can be represented in a
  ## 64-bit floating-point type without losing precision.
template minExponent*(T: typedesc[float64]): int = DBL_MIN_EXP
  ## Minimum (negative) exponent for 64-bit floating-point numbers.
template maxExponent*(T: typedesc[float64]): int = DBL_MAX_EXP
  ## Maximum (positive) exponent for 64-bit floating-point numbers.
template min10Exponent*(T: typedesc[float64]): int = DBL_MIN_10_EXP
  ## Minimum (negative) exponent in base 10 for 64-bit floating-point
  ## numbers.
template max10Exponent*(T: typedesc[float64]): int = DBL_MAX_10_EXP
  ## Maximum (positive) exponent in base 10 for 64-bit floating-point
  ## numbers.
template minimumPositiveValue*(T: typedesc[float64]): float64 = DBL_MIN
  ## The smallest positive (nonzero) number that can be represented in a
  ## 64-bit floating-point type.
template maximumPositiveValue*(T: typedesc[float64]): float64 = DBL_MAX
  ## The largest positive number that can be represented in a 64-bit
  ## floating-point type.
template epsilon*(T: typedesc[float64]): float64 = DBL_EPSILON
  ## The difference between 1.0 and the smallest number greater than
  ## 1.0 that can be represented in a 64-bit floating-point type.
