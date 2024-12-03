# issue #23853

block simplified:
  type QuadraticExt[F] = object
    coords: array[2, F]
  template Name(E: type QuadraticExt): int = 123
  template getBigInt(Name: static int): untyped = int
  type Foo[GT] = object
    a: getBigInt(GT.Name)
  var x: Foo[QuadraticExt[int]]
  
import std/macros

type
  Algebra* = enum
    BN254_Snarks
    BLS12_381

  Fp*[Name: static Algebra] = object
    limbs*: array[4, uint64]

  QuadraticExt*[F] = object
    ## Quadratic Extension field
    coords*: array[2, F]

  CubicExt*[F] = object
    ## Cubic Extension field
    coords*: array[3, F]

  ExtensionField*[F] = QuadraticExt[F] or CubicExt[F]

  Fp2*[Name: static Algebra] =
    QuadraticExt[Fp[Name]]

  Fp4*[Name: static Algebra] =
    QuadraticExt[Fp2[Name]]

  Fp6*[Name: static Algebra] =
    CubicExt[Fp2[Name]]

  Fp12*[Name: static Algebra] =
    CubicExt[Fp4[Name]]
    # QuadraticExt[Fp6[Name]]

template Name*(E: type ExtensionField): Algebra =
  E.F.Name

const BLS12_381_Order = [uint64 0x1, 0x2, 0x3, 0x4]
const BLS12_381_Modulus = [uint64 0x5, 0x6, 0x7, 0x8]


{.experimental: "dynamicBindSym".}

macro baseFieldModulus*(Name: static Algebra): untyped =
  result = bindSym($Name & "_Modulus")

macro scalarFieldModulus*(Name: static Algebra): untyped =
  result = bindSym($Name & "_Order")

type FieldKind* = enum
  kBaseField
  kScalarField

template getBigInt*(Name: static Algebra, kind: static FieldKind): untyped =
  # Workaround:
  # in `ptr UncheckedArray[BigInt[EC.getScalarField().bits()]]
  # EC.getScalarField is not accepted by the compiler
  #
  # and `ptr UncheckedArray[BigInt[Fr[EC.F.Name].bits]]` gets undeclared field: 'Name'
  #
  # but `ptr UncheckedArray[getBigInt(EC.getName(), kScalarField)]` works fine
  when kind == kBaseField:
    Name.baseFieldModulus().typeof()
  else:
    Name.scalarFieldModulus().typeof()

# ------------------------------------------------------------------------------

type BenchMultiexpContext*[GT] = object
  elems: seq[GT]
  exponents: seq[getBigInt(GT.Name, kScalarField)]

proc createBenchMultiExpContext*(GT: typedesc, inputSizes: openArray[int]): BenchMultiexpContext[GT] =
  discard

# ------------------------------------------------------------------------------

proc main() =
  let ctx = createBenchMultiExpContext(Fp12[BLS12_381], [2, 4, 8, 16])

main()
