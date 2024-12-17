discard """
  joinable: false
"""


# debug ICE: genCheckedRecordField
# apparently after https://github.com/nim-lang/Nim/pull/23477

# bug #23784

import std/bitops, std/macros

# --------------------------------------------------------------

type Algebra = enum
  BN254_Snarks

type SecretWord* = distinct uint64
const WordBitWidth* = sizeof(SecretWord) * 8

func wordsRequired*(bits: int): int {.inline.} =
  const divShiftor = fastLog2(WordBitWidth)
  result = (bits + WordBitWidth - 1) shr divShiftor

type
  BigInt*[bits: static int] = object
    limbs*: array[bits.wordsRequired, SecretWord]  # <--- crash points to here

# --------------------------------------------------------------

const CurveBitWidth = [
  BN254_Snarks: 254
]

const BN254_Snarks_Modulus = BigInt[254](limbs: [SecretWord 0x1, SecretWord 0x2, SecretWord 0x3, SecretWord 0x4])
const BN254_Snarks_Order = BigInt[254](limbs: [SecretWord 0x1, SecretWord 0x1, SecretWord 0x2, SecretWord 0x2])

func montyOne*(M: BigInt[254]): BigInt[254] =
  ## Returns "1 (mod M)" in the Montgomery domain.
  ## This is equivalent to R (mod M) in the natural domain
  BigInt[254](limbs: [SecretWord 0x1, SecretWord 0x1, SecretWord 0x1, SecretWord 0x1])


{.experimental: "dynamicBindSym".}

type
  DerivedConstantMode* = enum
    kModulus
    kOrder

macro genDerivedConstants*(mode: static DerivedConstantMode): untyped =
  ## Generate constants derived from the main constants
  ##
  ## For example
  ## - the Montgomery magic constant "R^2 mod N" in ROM
  ##   For each curve under the private symbol "MyCurve_R2modP"
  ## - the Montgomery magic constant -1/P mod 2^Wordbitwidth
  ##   For each curve under the private symbol "MyCurve_NegInvModWord
  ## - ...

  # Now typedesc are NimNode and there is no way to translate
  # NimNode -> typedesc easily so we can't
  # "for curve in low(Curve) .. high(Curve):"
  # As an ugly workaround, we count
  # The item at position 0 is a pragma
  result = newStmtList()

  template used(name: string): NimNode =
    nnkPragmaExpr.newTree(
      ident(name),
      nnkPragma.newTree(ident"used")
    )

  let ff = if mode == kModulus: "_Fp" else: "_Fr"

  for curveSym in low(Algebra) .. high(Algebra):
    let curve = $curveSym
    let M = if mode == kModulus: bindSym(curve & "_Modulus")
            else: bindSym(curve & "_Order")

    # const MyCurve_montyOne = montyOne(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & ff & "_MontyOne"), newCall(
        bindSym"montyOne",
        M
      )
    )

# --------------------------------------------------------------

{.experimental: "dynamicBindSym".}

genDerivedConstants(kModulus)
genDerivedConstants(kOrder)

proc bindConstant(ff: NimNode, property: string): NimNode =
  # Need to workaround https://github.com/nim-lang/Nim/issues/14021
  # which prevents checking if a type FF[Name] = Fp[Name] or Fr[Name]
  # was instantiated with Fp or Fr.
  # getTypeInst only returns FF and sameType doesn't work.
  # so quote do + when checks.
  let T = getTypeInst(ff)
  T.expectKind(nnkBracketExpr)
  doAssert T[0].eqIdent("typedesc")

  let curve =
    if T[1].kind == nnkBracketExpr: # typedesc[Fp[BLS12_381]] as used internally
      # doAssert T[1][0].eqIdent"Fp" or T[1][0].eqIdent"Fr", "Found ident: '" & $T[1][0] & "' instead of 'Fp' or 'Fr'"
      T[1][1].expectKind(nnkIntLit) # static enum are ints in the VM
      $Algebra(T[1][1].intVal)
    else: # typedesc[bls12381_fp] alias as used for C exports
      let T1 = getTypeInst(T[1].getImpl()[2])
      if T1.kind != nnkBracketExpr or
         T1[1].kind != nnkIntLit:
        echo T.repr()
        echo T1.repr()
        echo getTypeInst(T1).treerepr()
        error "getTypeInst didn't return the full instantiation." &
          " Dealing with types in macros is hard, complain at https://github.com/nim-lang/RFCs/issues/44"
      $Algebra(T1[1].intVal)

  let curve_fp = bindSym(curve & "_Fp_" & property)
  let curve_fr = bindSym(curve & "_Fr_" & property)
  result = quote do:
    when `ff` is Fp:
      `curve_fp`
    elif `ff` is Fr:
      `curve_fr`
    else:
      {.error: "Unreachable, received type: " & $`ff`.}

# --------------------------------------------------------------

template matchingBigInt*(Name: static Algebra): untyped =
  ## BigInt type necessary to store the prime field Fp
  # Workaround: https://github.com/nim-lang/Nim/issues/16774
  # as we cannot do array accesses in type section.
  # Due to generic sandwiches, it must be exported.
  BigInt[CurveBitWidth[Name]]

type
  Fp*[Name: static Algebra] = object
    mres*: matchingBigInt(Name)

macro getMontyOne*(ff: type Fp): untyped =
  ## Get one in Montgomery representation (i.e. R mod P)
  result = bindConstant(ff, "MontyOne")

func getOne*(T: type Fp): T {.noInit, inline.} =
  result = cast[ptr T](unsafeAddr getMontyOne(T))[]

# --------------------------------------------------------------
proc foo(T: Fp) =
  discard T

let a = Fp[BN254_Snarks].getOne()
foo(a) # oops this was a leftover that broke the bisect.
