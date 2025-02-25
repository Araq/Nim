# issue #23855, not entirely fixed

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

func bits*[Name: static Algebra](T: type FF[Name]): static int =
  T.getBigInt().bits

# ------------------------------------------------------------------------------

type
  ECFFT_Descriptor*[EC] = object
    ## Metadata for FFT on Elliptic Curve
    order*: int
    rootsOfUnity*: ptr UncheckedArray[BigInt[Fr[EC.F.Name].bits()]] # Undeclared identifier `Name`

func new*(T: type ECFFT_Descriptor): T =
  discard

# ------------------------------------------------------------------------------

template getBits[bits: static int](x: ptr UncheckedArray[BigInt[bits]]): int = bits

proc main() =
  let ctx = ECFFT_Descriptor[EC_ShortW_Aff[Fp[BLS12_381]]].new()
  doAssert getBits(ctx.rootsOfUnity) == 255
  doAssert ctx.rootsOfUnity[0].limbs.len == wordsRequired(255)

main()
