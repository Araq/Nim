# issue #23854, not entirely fixed

import std/bitops

const WordBitWidth = sizeof(pointer) * 8

func wordsRequired*(bits: int): int {.inline.} =
  const divShiftor = fastLog2(uint32(WordBitWidth))
  result = (bits + WordBitWidth - 1) shr divShiftor

type
  Algebra* = enum
    BLS12_381

  BigInt*[bits: static int] = object
    limbs*: array[wordsRequired(bits), uint]

  Fr*[Name: static Algebra] = object
    residue_form*: BigInt[255]

  Fp*[Name: static Algebra] = object
    residue_form*: BigInt[381]

  FF*[Name: static Algebra] = Fp[Name] or Fr[Name]

template getBigInt*[Name: static Algebra](T: type FF[Name]): untyped =
  ## Get the underlying BigInt type.
  typeof(default(T).residue_form)

type
  EC_ShortW_Aff*[F] = object
    ## Elliptic curve point for a curve in Short Weierstrass form
    ##   y² = x³ + a x + b
    ##
    ## over a field F
    x*, y*: F

type FieldKind* = enum
  kBaseField
  kScalarField

func bits*[Name: static Algebra](T: type FF[Name]): static int =
  T.getBigInt().bits

template getScalarField*(EC: type EC_ShortW_Aff): untyped =
  Fr[EC.F.Name]

# ------------------------------------------------------------------------------

type
  ECFFT_Descriptor*[EC] = object
    ## Metadata for FFT on Elliptic Curve
    order*: int
    rootsOfUnity1*: ptr UncheckedArray[BigInt[EC.getScalarField().bits()]]  # Error: in expression 'EC.getScalarField()': identifier expected, but found 'EC.getScalarField'
    rootsOfUnity2*: ptr UncheckedArray[BigInt[getScalarField(EC).bits()]] # Compiler SIGSEGV: Illegal Storage Access

func new*(T: type ECFFT_Descriptor): T =
  discard

# ------------------------------------------------------------------------------

template getBits[bits: static int](x: ptr UncheckedArray[BigInt[bits]]): int = bits

proc main() =
  let ctx = ECFFT_Descriptor[EC_ShortW_Aff[Fp[BLS12_381]]].new()
  doAssert getBits(ctx.rootsOfUnity1) == 255
  doAssert getBits(ctx.rootsOfUnity2) == 255
  doAssert ctx.rootsOfUnity1[0].limbs.len == wordsRequired(255)
  doAssert ctx.rootsOfUnity2[0].limbs.len == wordsRequired(255)

main()

block: # bug #24045
  type ArrayBuf[N: static int, T] = object
    buf: array[N, T]

  func maxLen(T: type): int =
    sizeof(T) * 2

  type MyBuf[I: type] = ArrayBuf[maxLen(I), byte]

  var v: MyBuf[int]

block: # bug #24043
  type ArrayBuf[N: static int, T = byte] = object
    buf: array[N, T]

  func maxLen(T: type): int =
    sizeof(T) * 2

  type MyBuf[I] = ArrayBuf[maxLen(I)]

  var v: MyBuf[int]
