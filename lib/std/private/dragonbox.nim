##  Copyright 2020 Junekey Jeon
##  Copyright 2020 Alexander Bolz
##
##  Distributed under the Boost Software License, Version 1.0.
##   (See accompanying file LICENSE_1_0.txt or copy at https://www.boost.org/LICENSE_1_0.txt)

##  char* output_end = Dtoa(buffer, value);
##
##  Converts the given double-precision number into decimal form and stores the result in the given
##  buffer.
##
##  The buffer must be large enough, i.e. >= DtoaMinBufferLength.
##  The output format is similar to printf("%g").
##  The output is _not_ null-terminted.
##
##  The output is optimal, i.e. the output string
##   1. rounds back to the input number when read in (using round-to-nearest-even)
##   2. is as short as possible,
##   3. is as close to the input number as possible.
##
##  Note:
##  This function may temporarily write up to DtoaMinBufferLength characters into the buffer.


import std/private/digitsutils

when defined(nimPreviewSlimSystem):
  import std/assertions

const
  dtoaMinBufferLength*: cint = 64

##  This file contains an implementation of Junekey Jeon's Dragonbox algorithm.
##
##  It is a simplified version of the reference implementation found here:
##  https://github.com/jk-jeon/dragonbox
##
##  The reference implementation also works with single-precision floating-point numbers and
##  has options to configure the rounding mode.

template dragonbox_Assert*(x: untyped): untyped =
  assert(x)

# ==================================================================================================
#
# ==================================================================================================

type
  ValueType* = float
  BitsType* = uint64

type
  Double* = object
    bits*: BitsType

const                         ##  = p   (includes the hidden bit)
  significandSize*: int32 = 53

const ##   static constexpr int32_t   MaxExponent     = 1024 - 1 - (SignificandSize - 1);
     ##   static constexpr int32_t   MinExponent     = std::numeric_limits<value_type>::min_exponent - 1 - (SignificandSize - 1);
  exponentBias*: int32 = 1024 - 1 + (significandSize - 1)

const
  maxIeeeExponent*: BitsType = BitsType(2 * 1024 - 1)

const                         ##  = 2^(p-1)
  hiddenBit*: BitsType = BitsType(1) shl (significandSize - 1)

const                         ##  = 2^(p-1) - 1
  significandMask*: BitsType = hiddenBit - 1

const
  exponentMask*: BitsType = maxIeeeExponent shl (significandSize - 1)

const
  signMask*: BitsType = not (not BitsType(0) shr 1)

proc constructDouble*(bits: BitsType): Double =
  result = Double(bits: bits)

proc constructDouble*(value: ValueType): Double =
  result = Double(bits: cast[typeof(result.bits)](value))

proc physicalSignificand*(this: Double): BitsType {.noSideEffect.} =
  return this.bits and significandMask

proc physicalExponent*(this: Double): BitsType {.noSideEffect.} =
  return (this.bits and exponentMask) shr (significandSize - 1)

proc isFinite*(this: Double): bool {.noSideEffect.} =
  return (this.bits and exponentMask) != exponentMask

proc isInf*(this: Double): bool {.noSideEffect.} =
  return (this.bits and exponentMask) == exponentMask and
      (this.bits and significandMask) == 0

proc isNaN*(this: Double): bool {.noSideEffect.} =
  return (this.bits and exponentMask) == exponentMask and
      (this.bits and significandMask) != 0

proc isZero*(this: Double): bool {.noSideEffect.} =
  return (this.bits and not signMask) == 0

proc signBit*(this: Double): int {.noSideEffect.} =
  return ord((this.bits and signMask) != 0)


# ==================================================================================================
#
# ==================================================================================================
##  namespace
##  Returns floor(x / 2^n).
##
##  Technically, right-shift of negative integers is implementation defined...
##  Should easily be optimized into SAR (or equivalent) instruction.

proc floorDivPow2*(x: int32; n: int32): int32 {.inline.} =
  return x shr n

proc floorLog2Pow10*(e: int32): int32 {.inline.} =
  dragonbox_Assert(e >= -1233)
  dragonbox_Assert(e <= 1233)
  return floorDivPow2(e * 1741647, 19)

proc floorLog10Pow2*(e: int32): int32 {.inline.} =
  dragonbox_Assert(e >= -1500)
  dragonbox_Assert(e <= 1500)
  return floorDivPow2(e * 1262611, 22)

proc floorLog10ThreeQuartersPow2*(e: int32): int32 {.inline.} =
  dragonbox_Assert(e >= -1500)
  dragonbox_Assert(e <= 1500)
  return floorDivPow2(e * 1262611 - 524031, 22)

# ==================================================================================================
#
# ==================================================================================================

type
  uint64x2* {.bycopy.} = object
    hi*: uint64
    lo*: uint64


proc computePow10*(k: int32): uint64x2 {.inline.} =
  const
    kMin: int32 = -292
  const
    kMax: int32 = 326
  const
    pow10: array[kMax - kMin + 1, uint64x2] = [
      uint64x2(hi: 0xFF77B1FCBEBCDC4F'u, lo: 0x25E8E89C13BB0F7B'u),
      uint64x2(hi: 0x9FAACF3DF73609B1'u, lo: 0x77B191618C54E9AD'u),
      uint64x2(hi: 0xC795830D75038C1D'u, lo: 0xD59DF5B9EF6A2418'u),
      uint64x2(hi: 0xF97AE3D0D2446F25'u, lo: 0x4B0573286B44AD1E'u),
      uint64x2(hi: 0x9BECCE62836AC577'u, lo: 0x4EE367F9430AEC33'u),
      uint64x2(hi: 0xC2E801FB244576D5'u, lo: 0x229C41F793CDA740'u),
      uint64x2(hi: 0xF3A20279ED56D48A'u, lo: 0x6B43527578C11110'u),
      uint64x2(hi: 0x9845418C345644D6'u, lo: 0x830A13896B78AAAA'u),
      uint64x2(hi: 0xBE5691EF416BD60C'u, lo: 0x23CC986BC656D554'u),
      uint64x2(hi: 0xEDEC366B11C6CB8F'u, lo: 0x2CBFBE86B7EC8AA9'u),
      uint64x2(hi: 0x94B3A202EB1C3F39'u, lo: 0x7BF7D71432F3D6AA'u),
      uint64x2(hi: 0xB9E08A83A5E34F07'u, lo: 0xDAF5CCD93FB0CC54'u),
      uint64x2(hi: 0xE858AD248F5C22C9'u, lo: 0xD1B3400F8F9CFF69'u),
      uint64x2(hi: 0x91376C36D99995BE'u, lo: 0x23100809B9C21FA2'u),
      uint64x2(hi: 0xB58547448FFFFB2D'u, lo: 0xABD40A0C2832A78B'u),
      uint64x2(hi: 0xE2E69915B3FFF9F9'u, lo: 0x16C90C8F323F516D'u),
      uint64x2(hi: 0x8DD01FAD907FFC3B'u, lo: 0xAE3DA7D97F6792E4'u),
      uint64x2(hi: 0xB1442798F49FFB4A'u, lo: 0x99CD11CFDF41779D'u),
      uint64x2(hi: 0xDD95317F31C7FA1D'u, lo: 0x40405643D711D584'u),
      uint64x2(hi: 0x8A7D3EEF7F1CFC52'u, lo: 0x482835EA666B2573'u),
      uint64x2(hi: 0xAD1C8EAB5EE43B66'u, lo: 0xDA3243650005EED0'u),
      uint64x2(hi: 0xD863B256369D4A40'u, lo: 0x90BED43E40076A83'u),
      uint64x2(hi: 0x873E4F75E2224E68'u, lo: 0x5A7744A6E804A292'u),
      uint64x2(hi: 0xA90DE3535AAAE202'u, lo: 0x711515D0A205CB37'u),
      uint64x2(hi: 0xD3515C2831559A83'u, lo: 0x0D5A5B44CA873E04'u),
      uint64x2(hi: 0x8412D9991ED58091'u, lo: 0xE858790AFE9486C3'u),
      uint64x2(hi: 0xA5178FFF668AE0B6'u, lo: 0x626E974DBE39A873'u),
      uint64x2(hi: 0xCE5D73FF402D98E3'u, lo: 0xFB0A3D212DC81290'u),
      uint64x2(hi: 0x80FA687F881C7F8E'u, lo: 0x7CE66634BC9D0B9A'u),
      uint64x2(hi: 0xA139029F6A239F72'u, lo: 0x1C1FFFC1EBC44E81'u),
      uint64x2(hi: 0xC987434744AC874E'u, lo: 0xA327FFB266B56221'u),
      uint64x2(hi: 0xFBE9141915D7A922'u, lo: 0x4BF1FF9F0062BAA9'u),
      uint64x2(hi: 0x9D71AC8FADA6C9B5'u, lo: 0x6F773FC3603DB4AA'u),
      uint64x2(hi: 0xC4CE17B399107C22'u, lo: 0xCB550FB4384D21D4'u),
      uint64x2(hi: 0xF6019DA07F549B2B'u, lo: 0x7E2A53A146606A49'u),
      uint64x2(hi: 0x99C102844F94E0FB'u, lo: 0x2EDA7444CBFC426E'u),
      uint64x2(hi: 0xC0314325637A1939'u, lo: 0xFA911155FEFB5309'u),
      uint64x2(hi: 0xF03D93EEBC589F88'u, lo: 0x793555AB7EBA27CB'u),
      uint64x2(hi: 0x96267C7535B763B5'u, lo: 0x4BC1558B2F3458DF'u),
      uint64x2(hi: 0xBBB01B9283253CA2'u, lo: 0x9EB1AAEDFB016F17'u),
      uint64x2(hi: 0xEA9C227723EE8BCB'u, lo: 0x465E15A979C1CADD'u),
      uint64x2(hi: 0x92A1958A7675175F'u, lo: 0x0BFACD89EC191ECA'u),
      uint64x2(hi: 0xB749FAED14125D36'u, lo: 0xCEF980EC671F667C'u),
      uint64x2(hi: 0xE51C79A85916F484'u, lo: 0x82B7E12780E7401B'u),
      uint64x2(hi: 0x8F31CC0937AE58D2'u, lo: 0xD1B2ECB8B0908811'u),
      uint64x2(hi: 0xB2FE3F0B8599EF07'u, lo: 0x861FA7E6DCB4AA16'u),
      uint64x2(hi: 0xDFBDCECE67006AC9'u, lo: 0x67A791E093E1D49B'u),
      uint64x2(hi: 0x8BD6A141006042BD'u, lo: 0xE0C8BB2C5C6D24E1'u),
      uint64x2(hi: 0xAECC49914078536D'u, lo: 0x58FAE9F773886E19'u),
      uint64x2(hi: 0xDA7F5BF590966848'u, lo: 0xAF39A475506A899F'u),
      uint64x2(hi: 0x888F99797A5E012D'u, lo: 0x6D8406C952429604'u),
      uint64x2(hi: 0xAAB37FD7D8F58178'u, lo: 0xC8E5087BA6D33B84'u),
      uint64x2(hi: 0xD5605FCDCF32E1D6'u, lo: 0xFB1E4A9A90880A65'u),
      uint64x2(hi: 0x855C3BE0A17FCD26'u, lo: 0x5CF2EEA09A550680'u),
      uint64x2(hi: 0xA6B34AD8C9DFC06F'u, lo: 0xF42FAA48C0EA481F'u),
      uint64x2(hi: 0xD0601D8EFC57B08B'u, lo: 0xF13B94DAF124DA27'u),
      uint64x2(hi: 0x823C12795DB6CE57'u, lo: 0x76C53D08D6B70859'u),
      uint64x2(hi: 0xA2CB1717B52481ED'u, lo: 0x54768C4B0C64CA6F'u),
      uint64x2(hi: 0xCB7DDCDDA26DA268'u, lo: 0xA9942F5DCF7DFD0A'u),
      uint64x2(hi: 0xFE5D54150B090B02'u, lo: 0xD3F93B35435D7C4D'u),
      uint64x2(hi: 0x9EFA548D26E5A6E1'u, lo: 0xC47BC5014A1A6DB0'u),
      uint64x2(hi: 0xC6B8E9B0709F109A'u, lo: 0x359AB6419CA1091C'u),
      uint64x2(hi: 0xF867241C8CC6D4C0'u, lo: 0xC30163D203C94B63'u),
      uint64x2(hi: 0x9B407691D7FC44F8'u, lo: 0x79E0DE63425DCF1E'u),
      uint64x2(hi: 0xC21094364DFB5636'u, lo: 0x985915FC12F542E5'u),
      uint64x2(hi: 0xF294B943E17A2BC4'u, lo: 0x3E6F5B7B17B2939E'u),
      uint64x2(hi: 0x979CF3CA6CEC5B5A'u, lo: 0xA705992CEECF9C43'u),
      uint64x2(hi: 0xBD8430BD08277231'u, lo: 0x50C6FF782A838354'u),
      uint64x2(hi: 0xECE53CEC4A314EBD'u, lo: 0xA4F8BF5635246429'u),
      uint64x2(hi: 0x940F4613AE5ED136'u, lo: 0x871B7795E136BE9A'u),
      uint64x2(hi: 0xB913179899F68584'u, lo: 0x28E2557B59846E40'u),
      uint64x2(hi: 0xE757DD7EC07426E5'u, lo: 0x331AEADA2FE589D0'u),
      uint64x2(hi: 0x9096EA6F3848984F'u, lo: 0x3FF0D2C85DEF7622'u),
      uint64x2(hi: 0xB4BCA50B065ABE63'u, lo: 0x0FED077A756B53AA'u),
      uint64x2(hi: 0xE1EBCE4DC7F16DFB'u, lo: 0xD3E8495912C62895'u),
      uint64x2(hi: 0x8D3360F09CF6E4BD'u, lo: 0x64712DD7ABBBD95D'u),
      uint64x2(hi: 0xB080392CC4349DEC'u, lo: 0xBD8D794D96AACFB4'u),
      uint64x2(hi: 0xDCA04777F541C567'u, lo: 0xECF0D7A0FC5583A1'u),
      uint64x2(hi: 0x89E42CAAF9491B60'u, lo: 0xF41686C49DB57245'u),
      uint64x2(hi: 0xAC5D37D5B79B6239'u, lo: 0x311C2875C522CED6'u),
      uint64x2(hi: 0xD77485CB25823AC7'u, lo: 0x7D633293366B828C'u),
      uint64x2(hi: 0x86A8D39EF77164BC'u, lo: 0xAE5DFF9C02033198'u),
      uint64x2(hi: 0xA8530886B54DBDEB'u, lo: 0xD9F57F830283FDFD'u),
      uint64x2(hi: 0xD267CAA862A12D66'u, lo: 0xD072DF63C324FD7C'u),
      uint64x2(hi: 0x8380DEA93DA4BC60'u, lo: 0x4247CB9E59F71E6E'u),
      uint64x2(hi: 0xA46116538D0DEB78'u, lo: 0x52D9BE85F074E609'u),
      uint64x2(hi: 0xCD795BE870516656'u, lo: 0x67902E276C921F8C'u),
      uint64x2(hi: 0x806BD9714632DFF6'u, lo: 0x00BA1CD8A3DB53B7'u),
      uint64x2(hi: 0xA086CFCD97BF97F3'u, lo: 0x80E8A40ECCD228A5'u),
      uint64x2(hi: 0xC8A883C0FDAF7DF0'u, lo: 0x6122CD128006B2CE'u),
      uint64x2(hi: 0xFAD2A4B13D1B5D6C'u, lo: 0x796B805720085F82'u),
      uint64x2(hi: 0x9CC3A6EEC6311A63'u, lo: 0xCBE3303674053BB1'u),
      uint64x2(hi: 0xC3F490AA77BD60FC'u, lo: 0xBEDBFC4411068A9D'u),
      uint64x2(hi: 0xF4F1B4D515ACB93B'u, lo: 0xEE92FB5515482D45'u),
      uint64x2(hi: 0x991711052D8BF3C5'u, lo: 0x751BDD152D4D1C4B'u),
      uint64x2(hi: 0xBF5CD54678EEF0B6'u, lo: 0xD262D45A78A0635E'u),
      uint64x2(hi: 0xEF340A98172AACE4'u, lo: 0x86FB897116C87C35'u),
      uint64x2(hi: 0x9580869F0E7AAC0E'u, lo: 0xD45D35E6AE3D4DA1'u),
      uint64x2(hi: 0xBAE0A846D2195712'u, lo: 0x8974836059CCA10A'u),
      uint64x2(hi: 0xE998D258869FACD7'u, lo: 0x2BD1A438703FC94C'u),
      uint64x2(hi: 0x91FF83775423CC06'u, lo: 0x7B6306A34627DDD0'u),
      uint64x2(hi: 0xB67F6455292CBF08'u, lo: 0x1A3BC84C17B1D543'u),
      uint64x2(hi: 0xE41F3D6A7377EECA'u, lo: 0x20CABA5F1D9E4A94'u),
      uint64x2(hi: 0x8E938662882AF53E'u, lo: 0x547EB47B7282EE9D'u),
      uint64x2(hi: 0xB23867FB2A35B28D'u, lo: 0xE99E619A4F23AA44'u),
      uint64x2(hi: 0xDEC681F9F4C31F31'u, lo: 0x6405FA00E2EC94D5'u),
      uint64x2(hi: 0x8B3C113C38F9F37E'u, lo: 0xDE83BC408DD3DD05'u),
      uint64x2(hi: 0xAE0B158B4738705E'u, lo: 0x9624AB50B148D446'u),
      uint64x2(hi: 0xD98DDAEE19068C76'u, lo: 0x3BADD624DD9B0958'u),
      uint64x2(hi: 0x87F8A8D4CFA417C9'u, lo: 0xE54CA5D70A80E5D7'u),
      uint64x2(hi: 0xA9F6D30A038D1DBC'u, lo: 0x5E9FCF4CCD211F4D'u),
      uint64x2(hi: 0xD47487CC8470652B'u, lo: 0x7647C32000696720'u),
      uint64x2(hi: 0x84C8D4DFD2C63F3B'u, lo: 0x29ECD9F40041E074'u),
      uint64x2(hi: 0xA5FB0A17C777CF09'u, lo: 0xF468107100525891'u),
      uint64x2(hi: 0xCF79CC9DB955C2CC'u, lo: 0x7182148D4066EEB5'u),
      uint64x2(hi: 0x81AC1FE293D599BF'u, lo: 0xC6F14CD848405531'u),
      uint64x2(hi: 0xA21727DB38CB002F'u, lo: 0xB8ADA00E5A506A7D'u),
      uint64x2(hi: 0xCA9CF1D206FDC03B'u, lo: 0xA6D90811F0E4851D'u),
      uint64x2(hi: 0xFD442E4688BD304A'u, lo: 0x908F4A166D1DA664'u),
      uint64x2(hi: 0x9E4A9CEC15763E2E'u, lo: 0x9A598E4E043287FF'u),
      uint64x2(hi: 0xC5DD44271AD3CDBA'u, lo: 0x40EFF1E1853F29FE'u),
      uint64x2(hi: 0xF7549530E188C128'u, lo: 0xD12BEE59E68EF47D'u),
      uint64x2(hi: 0x9A94DD3E8CF578B9'u, lo: 0x82BB74F8301958CF'u),
      uint64x2(hi: 0xC13A148E3032D6E7'u, lo: 0xE36A52363C1FAF02'u),
      uint64x2(hi: 0xF18899B1BC3F8CA1'u, lo: 0xDC44E6C3CB279AC2'u),
      uint64x2(hi: 0x96F5600F15A7B7E5'u, lo: 0x29AB103A5EF8C0BA'u),
      uint64x2(hi: 0xBCB2B812DB11A5DE'u, lo: 0x7415D448F6B6F0E8'u),
      uint64x2(hi: 0xEBDF661791D60F56'u, lo: 0x111B495B3464AD22'u),
      uint64x2(hi: 0x936B9FCEBB25C995'u, lo: 0xCAB10DD900BEEC35'u),
      uint64x2(hi: 0xB84687C269EF3BFB'u, lo: 0x3D5D514F40EEA743'u),
      uint64x2(hi: 0xE65829B3046B0AFA'u, lo: 0x0CB4A5A3112A5113'u),
      uint64x2(hi: 0x8FF71A0FE2C2E6DC'u, lo: 0x47F0E785EABA72AC'u),
      uint64x2(hi: 0xB3F4E093DB73A093'u, lo: 0x59ED216765690F57'u),
      uint64x2(hi: 0xE0F218B8D25088B8'u, lo: 0x306869C13EC3532D'u),
      uint64x2(hi: 0x8C974F7383725573'u, lo: 0x1E414218C73A13FC'u),
      uint64x2(hi: 0xAFBD2350644EEACF'u, lo: 0xE5D1929EF90898FB'u),
      uint64x2(hi: 0xDBAC6C247D62A583'u, lo: 0xDF45F746B74ABF3A'u),
      uint64x2(hi: 0x894BC396CE5DA772'u, lo: 0x6B8BBA8C328EB784'u),
      uint64x2(hi: 0xAB9EB47C81F5114F'u, lo: 0x066EA92F3F326565'u),
      uint64x2(hi: 0xD686619BA27255A2'u, lo: 0xC80A537B0EFEFEBE'u),
      uint64x2(hi: 0x8613FD0145877585'u, lo: 0xBD06742CE95F5F37'u),
      uint64x2(hi: 0xA798FC4196E952E7'u, lo: 0x2C48113823B73705'u),
      uint64x2(hi: 0xD17F3B51FCA3A7A0'u, lo: 0xF75A15862CA504C6'u),
      uint64x2(hi: 0x82EF85133DE648C4'u, lo: 0x9A984D73DBE722FC'u),
      uint64x2(hi: 0xA3AB66580D5FDAF5'u, lo: 0xC13E60D0D2E0EBBB'u),
      uint64x2(hi: 0xCC963FEE10B7D1B3'u, lo: 0x318DF905079926A9'u),
      uint64x2(hi: 0xFFBBCFE994E5C61F'u, lo: 0xFDF17746497F7053'u),
      uint64x2(hi: 0x9FD561F1FD0F9BD3'u, lo: 0xFEB6EA8BEDEFA634'u),
      uint64x2(hi: 0xC7CABA6E7C5382C8'u, lo: 0xFE64A52EE96B8FC1'u),
      uint64x2(hi: 0xF9BD690A1B68637B'u, lo: 0x3DFDCE7AA3C673B1'u),
      uint64x2(hi: 0x9C1661A651213E2D'u, lo: 0x06BEA10CA65C084F'u),
      uint64x2(hi: 0xC31BFA0FE5698DB8'u, lo: 0x486E494FCFF30A63'u),
      uint64x2(hi: 0xF3E2F893DEC3F126'u, lo: 0x5A89DBA3C3EFCCFB'u),
      uint64x2(hi: 0x986DDB5C6B3A76B7'u, lo: 0xF89629465A75E01D'u),
      uint64x2(hi: 0xBE89523386091465'u, lo: 0xF6BBB397F1135824'u),
      uint64x2(hi: 0xEE2BA6C0678B597F'u, lo: 0x746AA07DED582E2D'u),
      uint64x2(hi: 0x94DB483840B717EF'u, lo: 0xA8C2A44EB4571CDD'u),
      uint64x2(hi: 0xBA121A4650E4DDEB'u, lo: 0x92F34D62616CE414'u),
      uint64x2(hi: 0xE896A0D7E51E1566'u, lo: 0x77B020BAF9C81D18'u),
      uint64x2(hi: 0x915E2486EF32CD60'u, lo: 0x0ACE1474DC1D122F'u),
      uint64x2(hi: 0xB5B5ADA8AAFF80B8'u, lo: 0x0D819992132456BB'u),
      uint64x2(hi: 0xE3231912D5BF60E6'u, lo: 0x10E1FFF697ED6C6A'u),
      uint64x2(hi: 0x8DF5EFABC5979C8F'u, lo: 0xCA8D3FFA1EF463C2'u),
      uint64x2(hi: 0xB1736B96B6FD83B3'u, lo: 0xBD308FF8A6B17CB3'u),
      uint64x2(hi: 0xDDD0467C64BCE4A0'u, lo: 0xAC7CB3F6D05DDBDF'u),
      uint64x2(hi: 0x8AA22C0DBEF60EE4'u, lo: 0x6BCDF07A423AA96C'u),
      uint64x2(hi: 0xAD4AB7112EB3929D'u, lo: 0x86C16C98D2C953C7'u),
      uint64x2(hi: 0xD89D64D57A607744'u, lo: 0xE871C7BF077BA8B8'u),
      uint64x2(hi: 0x87625F056C7C4A8B'u, lo: 0x11471CD764AD4973'u),
      uint64x2(hi: 0xA93AF6C6C79B5D2D'u, lo: 0xD598E40D3DD89BD0'u),
      uint64x2(hi: 0xD389B47879823479'u, lo: 0x4AFF1D108D4EC2C4'u),
      uint64x2(hi: 0x843610CB4BF160CB'u, lo: 0xCEDF722A585139BB'u),
      uint64x2(hi: 0xA54394FE1EEDB8FE'u, lo: 0xC2974EB4EE658829'u),
      uint64x2(hi: 0xCE947A3DA6A9273E'u, lo: 0x733D226229FEEA33'u),
      uint64x2(hi: 0x811CCC668829B887'u, lo: 0x0806357D5A3F5260'u),
      uint64x2(hi: 0xA163FF802A3426A8'u, lo: 0xCA07C2DCB0CF26F8'u),
      uint64x2(hi: 0xC9BCFF6034C13052'u, lo: 0xFC89B393DD02F0B6'u),
      uint64x2(hi: 0xFC2C3F3841F17C67'u, lo: 0xBBAC2078D443ACE3'u),
      uint64x2(hi: 0x9D9BA7832936EDC0'u, lo: 0xD54B944B84AA4C0E'u),
      uint64x2(hi: 0xC5029163F384A931'u, lo: 0x0A9E795E65D4DF12'u),
      uint64x2(hi: 0xF64335BCF065D37D'u, lo: 0x4D4617B5FF4A16D6'u),
      uint64x2(hi: 0x99EA0196163FA42E'u, lo: 0x504BCED1BF8E4E46'u),
      uint64x2(hi: 0xC06481FB9BCF8D39'u, lo: 0xE45EC2862F71E1D7'u),
      uint64x2(hi: 0xF07DA27A82C37088'u, lo: 0x5D767327BB4E5A4D'u),
      uint64x2(hi: 0x964E858C91BA2655'u, lo: 0x3A6A07F8D510F870'u),
      uint64x2(hi: 0xBBE226EFB628AFEA'u, lo: 0x890489F70A55368C'u),
      uint64x2(hi: 0xEADAB0ABA3B2DBE5'u, lo: 0x2B45AC74CCEA842F'u),
      uint64x2(hi: 0x92C8AE6B464FC96F'u, lo: 0x3B0B8BC90012929E'u),
      uint64x2(hi: 0xB77ADA0617E3BBCB'u, lo: 0x09CE6EBB40173745'u),
      uint64x2(hi: 0xE55990879DDCAABD'u, lo: 0xCC420A6A101D0516'u),
      uint64x2(hi: 0x8F57FA54C2A9EAB6'u, lo: 0x9FA946824A12232E'u),
      uint64x2(hi: 0xB32DF8E9F3546564'u, lo: 0x47939822DC96ABFA'u),
      uint64x2(hi: 0xDFF9772470297EBD'u, lo: 0x59787E2B93BC56F8'u),
      uint64x2(hi: 0x8BFBEA76C619EF36'u, lo: 0x57EB4EDB3C55B65B'u),
      uint64x2(hi: 0xAEFAE51477A06B03'u, lo: 0xEDE622920B6B23F2'u),
      uint64x2(hi: 0xDAB99E59958885C4'u, lo: 0xE95FAB368E45ECEE'u),
      uint64x2(hi: 0x88B402F7FD75539B'u, lo: 0x11DBCB0218EBB415'u),
      uint64x2(hi: 0xAAE103B5FCD2A881'u, lo: 0xD652BDC29F26A11A'u),
      uint64x2(hi: 0xD59944A37C0752A2'u, lo: 0x4BE76D3346F04960'u),
      uint64x2(hi: 0x857FCAE62D8493A5'u, lo: 0x6F70A4400C562DDC'u),
      uint64x2(hi: 0xA6DFBD9FB8E5B88E'u, lo: 0xCB4CCD500F6BB953'u),
      uint64x2(hi: 0xD097AD07A71F26B2'u, lo: 0x7E2000A41346A7A8'u),
      uint64x2(hi: 0x825ECC24C873782F'u, lo: 0x8ED400668C0C28C9'u),
      uint64x2(hi: 0xA2F67F2DFA90563B'u, lo: 0x728900802F0F32FB'u),
      uint64x2(hi: 0xCBB41EF979346BCA'u, lo: 0x4F2B40A03AD2FFBA'u),
      uint64x2(hi: 0xFEA126B7D78186BC'u, lo: 0xE2F610C84987BFA9'u),
      uint64x2(hi: 0x9F24B832E6B0F436'u, lo: 0x0DD9CA7D2DF4D7CA'u),
      uint64x2(hi: 0xC6EDE63FA05D3143'u, lo: 0x91503D1C79720DBC'u),
      uint64x2(hi: 0xF8A95FCF88747D94'u, lo: 0x75A44C6397CE912B'u),
      uint64x2(hi: 0x9B69DBE1B548CE7C'u, lo: 0xC986AFBE3EE11ABB'u),
      uint64x2(hi: 0xC24452DA229B021B'u, lo: 0xFBE85BADCE996169'u),
      uint64x2(hi: 0xF2D56790AB41C2A2'u, lo: 0xFAE27299423FB9C4'u),
      uint64x2(hi: 0x97C560BA6B0919A5'u, lo: 0xDCCD879FC967D41B'u),
      uint64x2(hi: 0xBDB6B8E905CB600F'u, lo: 0x5400E987BBC1C921'u),
      uint64x2(hi: 0xED246723473E3813'u, lo: 0x290123E9AAB23B69'u),
      uint64x2(hi: 0x9436C0760C86E30B'u, lo: 0xF9A0B6720AAF6522'u),
      uint64x2(hi: 0xB94470938FA89BCE'u, lo: 0xF808E40E8D5B3E6A'u),
      uint64x2(hi: 0xE7958CB87392C2C2'u, lo: 0xB60B1D1230B20E05'u),
      uint64x2(hi: 0x90BD77F3483BB9B9'u, lo: 0xB1C6F22B5E6F48C3'u),
      uint64x2(hi: 0xB4ECD5F01A4AA828'u, lo: 0x1E38AEB6360B1AF4'u),
      uint64x2(hi: 0xE2280B6C20DD5232'u, lo: 0x25C6DA63C38DE1B1'u),
      uint64x2(hi: 0x8D590723948A535F'u, lo: 0x579C487E5A38AD0F'u),
      uint64x2(hi: 0xB0AF48EC79ACE837'u, lo: 0x2D835A9DF0C6D852'u),
      uint64x2(hi: 0xDCDB1B2798182244'u, lo: 0xF8E431456CF88E66'u),
      uint64x2(hi: 0x8A08F0F8BF0F156B'u, lo: 0x1B8E9ECB641B5900'u),
      uint64x2(hi: 0xAC8B2D36EED2DAC5'u, lo: 0xE272467E3D222F40'u),
      uint64x2(hi: 0xD7ADF884AA879177'u, lo: 0x5B0ED81DCC6ABB10'u),
      uint64x2(hi: 0x86CCBB52EA94BAEA'u, lo: 0x98E947129FC2B4EA'u),
      uint64x2(hi: 0xA87FEA27A539E9A5'u, lo: 0x3F2398D747B36225'u),
      uint64x2(hi: 0xD29FE4B18E88640E'u, lo: 0x8EEC7F0D19A03AAE'u),
      uint64x2(hi: 0x83A3EEEEF9153E89'u, lo: 0x1953CF68300424AD'u),
      uint64x2(hi: 0xA48CEAAAB75A8E2B'u, lo: 0x5FA8C3423C052DD8'u),
      uint64x2(hi: 0xCDB02555653131B6'u, lo: 0x3792F412CB06794E'u),
      uint64x2(hi: 0x808E17555F3EBF11'u, lo: 0xE2BBD88BBEE40BD1'u),
      uint64x2(hi: 0xA0B19D2AB70E6ED6'u, lo: 0x5B6ACEAEAE9D0EC5'u),
      uint64x2(hi: 0xC8DE047564D20A8B'u, lo: 0xF245825A5A445276'u),
      uint64x2(hi: 0xFB158592BE068D2E'u, lo: 0xEED6E2F0F0D56713'u),
      uint64x2(hi: 0x9CED737BB6C4183D'u, lo: 0x55464DD69685606C'u),
      uint64x2(hi: 0xC428D05AA4751E4C'u, lo: 0xAA97E14C3C26B887'u),
      uint64x2(hi: 0xF53304714D9265DF'u, lo: 0xD53DD99F4B3066A9'u),
      uint64x2(hi: 0x993FE2C6D07B7FAB'u, lo: 0xE546A8038EFE402A'u),
      uint64x2(hi: 0xBF8FDB78849A5F96'u, lo: 0xDE98520472BDD034'u),
      uint64x2(hi: 0xEF73D256A5C0F77C'u, lo: 0x963E66858F6D4441'u),
      uint64x2(hi: 0x95A8637627989AAD'u, lo: 0xDDE7001379A44AA9'u),
      uint64x2(hi: 0xBB127C53B17EC159'u, lo: 0x5560C018580D5D53'u),
      uint64x2(hi: 0xE9D71B689DDE71AF'u, lo: 0xAAB8F01E6E10B4A7'u),
      uint64x2(hi: 0x9226712162AB070D'u, lo: 0xCAB3961304CA70E9'u),
      uint64x2(hi: 0xB6B00D69BB55C8D1'u, lo: 0x3D607B97C5FD0D23'u),
      uint64x2(hi: 0xE45C10C42A2B3B05'u, lo: 0x8CB89A7DB77C506B'u),
      uint64x2(hi: 0x8EB98A7A9A5B04E3'u, lo: 0x77F3608E92ADB243'u),
      uint64x2(hi: 0xB267ED1940F1C61C'u, lo: 0x55F038B237591ED4'u),
      uint64x2(hi: 0xDF01E85F912E37A3'u, lo: 0x6B6C46DEC52F6689'u),
      uint64x2(hi: 0x8B61313BBABCE2C6'u, lo: 0x2323AC4B3B3DA016'u),
      uint64x2(hi: 0xAE397D8AA96C1B77'u, lo: 0xABEC975E0A0D081B'u),
      uint64x2(hi: 0xD9C7DCED53C72255'u, lo: 0x96E7BD358C904A22'u),
      uint64x2(hi: 0x881CEA14545C7575'u, lo: 0x7E50D64177DA2E55'u),
      uint64x2(hi: 0xAA242499697392D2'u, lo: 0xDDE50BD1D5D0B9EA'u),
      uint64x2(hi: 0xD4AD2DBFC3D07787'u, lo: 0x955E4EC64B44E865'u),
      uint64x2(hi: 0x84EC3C97DA624AB4'u, lo: 0xBD5AF13BEF0B113F'u),
      uint64x2(hi: 0xA6274BBDD0FADD61'u, lo: 0xECB1AD8AEACDD58F'u),
      uint64x2(hi: 0xCFB11EAD453994BA'u, lo: 0x67DE18EDA5814AF3'u),
      uint64x2(hi: 0x81CEB32C4B43FCF4'u, lo: 0x80EACF948770CED8'u),
      uint64x2(hi: 0xA2425FF75E14FC31'u, lo: 0xA1258379A94D028E'u),
      uint64x2(hi: 0xCAD2F7F5359A3B3E'u, lo: 0x096EE45813A04331'u),
      uint64x2(hi: 0xFD87B5F28300CA0D'u, lo: 0x8BCA9D6E188853FD'u),
      uint64x2(hi: 0x9E74D1B791E07E48'u, lo: 0x775EA264CF55347E'u),
      uint64x2(hi: 0xC612062576589DDA'u, lo: 0x95364AFE032A819E'u),
      uint64x2(hi: 0xF79687AED3EEC551'u, lo: 0x3A83DDBD83F52205'u),
      uint64x2(hi: 0x9ABE14CD44753B52'u, lo: 0xC4926A9672793543'u),
      uint64x2(hi: 0xC16D9A0095928A27'u, lo: 0x75B7053C0F178294'u),
      uint64x2(hi: 0xF1C90080BAF72CB1'u, lo: 0x5324C68B12DD6339'u),
      uint64x2(hi: 0x971DA05074DA7BEE'u, lo: 0xD3F6FC16EBCA5E04'u),
      uint64x2(hi: 0xBCE5086492111AEA'u, lo: 0x88F4BB1CA6BCF585'u),
      uint64x2(hi: 0xEC1E4A7DB69561A5'u, lo: 0x2B31E9E3D06C32E6'u),
      uint64x2(hi: 0x9392EE8E921D5D07'u, lo: 0x3AFF322E62439FD0'u),
      uint64x2(hi: 0xB877AA3236A4B449'u, lo: 0x09BEFEB9FAD487C3'u),
      uint64x2(hi: 0xE69594BEC44DE15B'u, lo: 0x4C2EBE687989A9B4'u),
      uint64x2(hi: 0x901D7CF73AB0ACD9'u, lo: 0x0F9D37014BF60A11'u),
      uint64x2(hi: 0xB424DC35095CD80F'u, lo: 0x538484C19EF38C95'u),
      uint64x2(hi: 0xE12E13424BB40E13'u, lo: 0x2865A5F206B06FBA'u),
      uint64x2(hi: 0x8CBCCC096F5088CB'u, lo: 0xF93F87B7442E45D4'u),
      uint64x2(hi: 0xAFEBFF0BCB24AAFE'u, lo: 0xF78F69A51539D749'u),
      uint64x2(hi: 0xDBE6FECEBDEDD5BE'u, lo: 0xB573440E5A884D1C'u),
      uint64x2(hi: 0x89705F4136B4A597'u, lo: 0x31680A88F8953031'u),
      uint64x2(hi: 0xABCC77118461CEFC'u, lo: 0xFDC20D2B36BA7C3E'u),
      uint64x2(hi: 0xD6BF94D5E57A42BC'u, lo: 0x3D32907604691B4D'u),
      uint64x2(hi: 0x8637BD05AF6C69B5'u, lo: 0xA63F9A49C2C1B110'u),
      uint64x2(hi: 0xA7C5AC471B478423'u, lo: 0x0FCF80DC33721D54'u),
      uint64x2(hi: 0xD1B71758E219652B'u, lo: 0xD3C36113404EA4A9'u),
      uint64x2(hi: 0x83126E978D4FDF3B'u, lo: 0x645A1CAC083126EA'u),
      uint64x2(hi: 0xA3D70A3D70A3D70A'u, lo: 0x3D70A3D70A3D70A4'u),
      uint64x2(hi: 0xCCCCCCCCCCCCCCCC'u, lo: 0xCCCCCCCCCCCCCCCD'u),
      uint64x2(hi: 0x8000000000000000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0xA000000000000000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0xC800000000000000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0xFA00000000000000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0x9C40000000000000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0xC350000000000000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0xF424000000000000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0x9896800000000000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0xBEBC200000000000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0xEE6B280000000000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0x9502F90000000000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0xBA43B74000000000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0xE8D4A51000000000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0x9184E72A00000000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0xB5E620F480000000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0xE35FA931A0000000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0x8E1BC9BF04000000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0xB1A2BC2EC5000000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0xDE0B6B3A76400000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0x8AC7230489E80000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0xAD78EBC5AC620000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0xD8D726B7177A8000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0x878678326EAC9000'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0xA968163F0A57B400'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0xD3C21BCECCEDA100'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0x84595161401484A0'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0xA56FA5B99019A5C8'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0xCECB8F27F4200F3A'u, lo: 0x0000000000000000'u),
      uint64x2(hi: 0x813F3978F8940984'u, lo: 0x4000000000000000'u),
      uint64x2(hi: 0xA18F07D736B90BE5'u, lo: 0x5000000000000000'u),
      uint64x2(hi: 0xC9F2C9CD04674EDE'u, lo: 0xA400000000000000'u),
      uint64x2(hi: 0xFC6F7C4045812296'u, lo: 0x4D00000000000000'u),
      uint64x2(hi: 0x9DC5ADA82B70B59D'u, lo: 0xF020000000000000'u),
      uint64x2(hi: 0xC5371912364CE305'u, lo: 0x6C28000000000000'u),
      uint64x2(hi: 0xF684DF56C3E01BC6'u, lo: 0xC732000000000000'u),
      uint64x2(hi: 0x9A130B963A6C115C'u, lo: 0x3C7F400000000000'u),
      uint64x2(hi: 0xC097CE7BC90715B3'u, lo: 0x4B9F100000000000'u),
      uint64x2(hi: 0xF0BDC21ABB48DB20'u, lo: 0x1E86D40000000000'u),
      uint64x2(hi: 0x96769950B50D88F4'u, lo: 0x1314448000000000'u),
      uint64x2(hi: 0xBC143FA4E250EB31'u, lo: 0x17D955A000000000'u),
      uint64x2(hi: 0xEB194F8E1AE525FD'u, lo: 0x5DCFAB0800000000'u),
      uint64x2(hi: 0x92EFD1B8D0CF37BE'u, lo: 0x5AA1CAE500000000'u),
      uint64x2(hi: 0xB7ABC627050305AD'u, lo: 0xF14A3D9E40000000'u),
      uint64x2(hi: 0xE596B7B0C643C719'u, lo: 0x6D9CCD05D0000000'u),
      uint64x2(hi: 0x8F7E32CE7BEA5C6F'u, lo: 0xE4820023A2000000'u),
      uint64x2(hi: 0xB35DBF821AE4F38B'u, lo: 0xDDA2802C8A800000'u),
      uint64x2(hi: 0xE0352F62A19E306E'u, lo: 0xD50B2037AD200000'u),
      uint64x2(hi: 0x8C213D9DA502DE45'u, lo: 0x4526F422CC340000'u),
      uint64x2(hi: 0xAF298D050E4395D6'u, lo: 0x9670B12B7F410000'u),
      uint64x2(hi: 0xDAF3F04651D47B4C'u, lo: 0x3C0CDD765F114000'u),
      uint64x2(hi: 0x88D8762BF324CD0F'u, lo: 0xA5880A69FB6AC800'u),
      uint64x2(hi: 0xAB0E93B6EFEE0053'u, lo: 0x8EEA0D047A457A00'u),
      uint64x2(hi: 0xD5D238A4ABE98068'u, lo: 0x72A4904598D6D880'u),
      uint64x2(hi: 0x85A36366EB71F041'u, lo: 0x47A6DA2B7F864750'u),
      uint64x2(hi: 0xA70C3C40A64E6C51'u, lo: 0x999090B65F67D924'u),
      uint64x2(hi: 0xD0CF4B50CFE20765'u, lo: 0xFFF4B4E3F741CF6D'u),
      uint64x2(hi: 0x82818F1281ED449F'u, lo: 0xBFF8F10E7A8921A4'u),
      uint64x2(hi: 0xA321F2D7226895C7'u, lo: 0xAFF72D52192B6A0D'u),
      uint64x2(hi: 0xCBEA6F8CEB02BB39'u, lo: 0x9BF4F8A69F764490'u),
      uint64x2(hi: 0xFEE50B7025C36A08'u, lo: 0x02F236D04753D5B4'u),
      uint64x2(hi: 0x9F4F2726179A2245'u, lo: 0x01D762422C946590'u),
      uint64x2(hi: 0xC722F0EF9D80AAD6'u, lo: 0x424D3AD2B7B97EF5'u),
      uint64x2(hi: 0xF8EBAD2B84E0D58B'u, lo: 0xD2E0898765A7DEB2'u),
      uint64x2(hi: 0x9B934C3B330C8577'u, lo: 0x63CC55F49F88EB2F'u),
      uint64x2(hi: 0xC2781F49FFCFA6D5'u, lo: 0x3CBF6B71C76B25FB'u),
      uint64x2(hi: 0xF316271C7FC3908A'u, lo: 0x8BEF464E3945EF7A'u),
      uint64x2(hi: 0x97EDD871CFDA3A56'u, lo: 0x97758BF0E3CBB5AC'u),
      uint64x2(hi: 0xBDE94E8E43D0C8EC'u, lo: 0x3D52EEED1CBEA317'u),
      uint64x2(hi: 0xED63A231D4C4FB27'u, lo: 0x4CA7AAA863EE4BDD'u),
      uint64x2(hi: 0x945E455F24FB1CF8'u, lo: 0x8FE8CAA93E74EF6A'u),
      uint64x2(hi: 0xB975D6B6EE39E436'u, lo: 0xB3E2FD538E122B44'u),
      uint64x2(hi: 0xE7D34C64A9C85D44'u, lo: 0x60DBBCA87196B616'u),
      uint64x2(hi: 0x90E40FBEEA1D3A4A'u, lo: 0xBC8955E946FE31CD'u),
      uint64x2(hi: 0xB51D13AEA4A488DD'u, lo: 0x6BABAB6398BDBE41'u),
      uint64x2(hi: 0xE264589A4DCDAB14'u, lo: 0xC696963C7EED2DD1'u),
      uint64x2(hi: 0x8D7EB76070A08AEC'u, lo: 0xFC1E1DE5CF543CA2'u),
      uint64x2(hi: 0xB0DE65388CC8ADA8'u, lo: 0x3B25A55F43294BCB'u),
      uint64x2(hi: 0xDD15FE86AFFAD912'u, lo: 0x49EF0EB713F39EBE'u),
      uint64x2(hi: 0x8A2DBF142DFCC7AB'u, lo: 0x6E3569326C784337'u),
      uint64x2(hi: 0xACB92ED9397BF996'u, lo: 0x49C2C37F07965404'u),
      uint64x2(hi: 0xD7E77A8F87DAF7FB'u, lo: 0xDC33745EC97BE906'u),
      uint64x2(hi: 0x86F0AC99B4E8DAFD'u, lo: 0x69A028BB3DED71A3'u),
      uint64x2(hi: 0xA8ACD7C0222311BC'u, lo: 0xC40832EA0D68CE0C'u),
      uint64x2(hi: 0xD2D80DB02AABD62B'u, lo: 0xF50A3FA490C30190'u),
      uint64x2(hi: 0x83C7088E1AAB65DB'u, lo: 0x792667C6DA79E0FA'u),
      uint64x2(hi: 0xA4B8CAB1A1563F52'u, lo: 0x577001B891185938'u),
      uint64x2(hi: 0xCDE6FD5E09ABCF26'u, lo: 0xED4C0226B55E6F86'u),
      uint64x2(hi: 0x80B05E5AC60B6178'u, lo: 0x544F8158315B05B4'u),
      uint64x2(hi: 0xA0DC75F1778E39D6'u, lo: 0x696361AE3DB1C721'u),
      uint64x2(hi: 0xC913936DD571C84C'u, lo: 0x03BC3A19CD1E38E9'u),
      uint64x2(hi: 0xFB5878494ACE3A5F'u, lo: 0x04AB48A04065C723'u),
      uint64x2(hi: 0x9D174B2DCEC0E47B'u, lo: 0x62EB0D64283F9C76'u),
      uint64x2(hi: 0xC45D1DF942711D9A'u, lo: 0x3BA5D0BD324F8394'u),
      uint64x2(hi: 0xF5746577930D6500'u, lo: 0xCA8F44EC7EE36479'u),
      uint64x2(hi: 0x9968BF6ABBE85F20'u, lo: 0x7E998B13CF4E1ECB'u),
      uint64x2(hi: 0xBFC2EF456AE276E8'u, lo: 0x9E3FEDD8C321A67E'u),
      uint64x2(hi: 0xEFB3AB16C59B14A2'u, lo: 0xC5CFE94EF3EA101E'u),
      uint64x2(hi: 0x95D04AEE3B80ECE5'u, lo: 0xBBA1F1D158724A12'u),
      uint64x2(hi: 0xBB445DA9CA61281F'u, lo: 0x2A8A6E45AE8EDC97'u),
      uint64x2(hi: 0xEA1575143CF97226'u, lo: 0xF52D09D71A3293BD'u),
      uint64x2(hi: 0x924D692CA61BE758'u, lo: 0x593C2626705F9C56'u),
      uint64x2(hi: 0xB6E0C377CFA2E12E'u, lo: 0x6F8B2FB00C77836C'u),
      uint64x2(hi: 0xE498F455C38B997A'u, lo: 0x0B6DFB9C0F956447'u),
      uint64x2(hi: 0x8EDF98B59A373FEC'u, lo: 0x4724BD4189BD5EAC'u),
      uint64x2(hi: 0xB2977EE300C50FE7'u, lo: 0x58EDEC91EC2CB657'u),
      uint64x2(hi: 0xDF3D5E9BC0F653E1'u, lo: 0x2F2967B66737E3ED'u),
      uint64x2(hi: 0x8B865B215899F46C'u, lo: 0xBD79E0D20082EE74'u),
      uint64x2(hi: 0xAE67F1E9AEC07187'u, lo: 0xECD8590680A3AA11'u),
      uint64x2(hi: 0xDA01EE641A708DE9'u, lo: 0xE80E6F4820CC9495'u),
      uint64x2(hi: 0x884134FE908658B2'u, lo: 0x3109058D147FDCDD'u),
      uint64x2(hi: 0xAA51823E34A7EEDE'u, lo: 0xBD4B46F0599FD415'u),
      uint64x2(hi: 0xD4E5E2CDC1D1EA96'u, lo: 0x6C9E18AC7007C91A'u),
      uint64x2(hi: 0x850FADC09923329E'u, lo: 0x03E2CF6BC604DDB0'u),
      uint64x2(hi: 0xA6539930BF6BFF45'u, lo: 0x84DB8346B786151C'u),
      uint64x2(hi: 0xCFE87F7CEF46FF16'u, lo: 0xE612641865679A63'u),
      uint64x2(hi: 0x81F14FAE158C5F6E'u, lo: 0x4FCB7E8F3F60C07E'u),
      uint64x2(hi: 0xA26DA3999AEF7749'u, lo: 0xE3BE5E330F38F09D'u),
      uint64x2(hi: 0xCB090C8001AB551C'u, lo: 0x5CADF5BFD3072CC5'u),
      uint64x2(hi: 0xFDCB4FA002162A63'u, lo: 0x73D9732FC7C8F7F6'u),
      uint64x2(hi: 0x9E9F11C4014DDA7E'u, lo: 0x2867E7FDDCDD9AFA'u),
      uint64x2(hi: 0xC646D63501A1511D'u, lo: 0xB281E1FD541501B8'u),
      uint64x2(hi: 0xF7D88BC24209A565'u, lo: 0x1F225A7CA91A4226'u),
      uint64x2(hi: 0x9AE757596946075F'u, lo: 0x3375788DE9B06958'u),
      uint64x2(hi: 0xC1A12D2FC3978937'u, lo: 0x0052D6B1641C83AE'u),
      uint64x2(hi: 0xF209787BB47D6B84'u, lo: 0xC0678C5DBD23A49A'u),
      uint64x2(hi: 0x9745EB4D50CE6332'u, lo: 0xF840B7BA963646E0'u),
      uint64x2(hi: 0xBD176620A501FBFF'u, lo: 0xB650E5A93BC3D898'u),
      uint64x2(hi: 0xEC5D3FA8CE427AFF'u, lo: 0xA3E51F138AB4CEBE'u),
      uint64x2(hi: 0x93BA47C980E98CDF'u, lo: 0xC66F336C36B10137'u),
      uint64x2(hi: 0xB8A8D9BBE123F017'u, lo: 0xB80B0047445D4184'u),
      uint64x2(hi: 0xE6D3102AD96CEC1D'u, lo: 0xA60DC059157491E5'u),
      uint64x2(hi: 0x9043EA1AC7E41392'u, lo: 0x87C89837AD68DB2F'u),
      uint64x2(hi: 0xB454E4A179DD1877'u, lo: 0x29BABE4598C311FB'u),
      uint64x2(hi: 0xE16A1DC9D8545E94'u, lo: 0xF4296DD6FEF3D67A'u),
      uint64x2(hi: 0x8CE2529E2734BB1D'u, lo: 0x1899E4A65F58660C'u),
      uint64x2(hi: 0xB01AE745B101E9E4'u, lo: 0x5EC05DCFF72E7F8F'u),
      uint64x2(hi: 0xDC21A1171D42645D'u, lo: 0x76707543F4FA1F73'u),
      uint64x2(hi: 0x899504AE72497EBA'u, lo: 0x6A06494A791C53A8'u),
      uint64x2(hi: 0xABFA45DA0EDBDE69'u, lo: 0x0487DB9D17636892'u),
      uint64x2(hi: 0xD6F8D7509292D603'u, lo: 0x45A9D2845D3C42B6'u),
      uint64x2(hi: 0x865B86925B9BC5C2'u, lo: 0x0B8A2392BA45A9B2'u),
      uint64x2(hi: 0xA7F26836F282B732'u, lo: 0x8E6CAC7768D7141E'u),
      uint64x2(hi: 0xD1EF0244AF2364FF'u, lo: 0x3207D795430CD926'u),
      uint64x2(hi: 0x8335616AED761F1F'u, lo: 0x7F44E6BD49E807B8'u),
      uint64x2(hi: 0xA402B9C5A8D3A6E7'u, lo: 0x5F16206C9C6209A6'u),
      uint64x2(hi: 0xCD036837130890A1'u, lo: 0x36DBA887C37A8C0F'u),
      uint64x2(hi: 0x802221226BE55A64'u, lo: 0xC2494954DA2C9789'u),
      uint64x2(hi: 0xA02AA96B06DEB0FD'u, lo: 0xF2DB9BAA10B7BD6C'u),
      uint64x2(hi: 0xC83553C5C8965D3D'u, lo: 0x6F92829494E5ACC7'u),
      uint64x2(hi: 0xFA42A8B73ABBF48C'u, lo: 0xCB772339BA1F17F9'u),
      uint64x2(hi: 0x9C69A97284B578D7'u, lo: 0xFF2A760414536EFB'u),
      uint64x2(hi: 0xC38413CF25E2D70D'u, lo: 0xFEF5138519684ABA'u),
      uint64x2(hi: 0xF46518C2EF5B8CD1'u, lo: 0x7EB258665FC25D69'u),
      uint64x2(hi: 0x98BF2F79D5993802'u, lo: 0xEF2F773FFBD97A61'u),
      uint64x2(hi: 0xBEEEFB584AFF8603'u, lo: 0xAAFB550FFACFD8FA'u),
      uint64x2(hi: 0xEEAABA2E5DBF6784'u, lo: 0x95BA2A53F983CF38'u),
      uint64x2(hi: 0x952AB45CFA97A0B2'u, lo: 0xDD945A747BF26183'u),
      uint64x2(hi: 0xBA756174393D88DF'u, lo: 0x94F971119AEEF9E4'u),
      uint64x2(hi: 0xE912B9D1478CEB17'u, lo: 0x7A37CD5601AAB85D'u),
      uint64x2(hi: 0x91ABB422CCB812EE'u, lo: 0xAC62E055C10AB33A'u),
      uint64x2(hi: 0xB616A12B7FE617AA'u, lo: 0x577B986B314D6009'u),
      uint64x2(hi: 0xE39C49765FDF9D94'u, lo: 0xED5A7E85FDA0B80B'u),
      uint64x2(hi: 0x8E41ADE9FBEBC27D'u, lo: 0x14588F13BE847307'u),
      uint64x2(hi: 0xB1D219647AE6B31C'u, lo: 0x596EB2D8AE258FC8'u),
      uint64x2(hi: 0xDE469FBD99A05FE3'u, lo: 0x6FCA5F8ED9AEF3BB'u),
      uint64x2(hi: 0x8AEC23D680043BEE'u, lo: 0x25DE7BB9480D5854'u),
      uint64x2(hi: 0xADA72CCC20054AE9'u, lo: 0xAF561AA79A10AE6A'u),
      uint64x2(hi: 0xD910F7FF28069DA4'u, lo: 0x1B2BA1518094DA04'u),
      uint64x2(hi: 0x87AA9AFF79042286'u, lo: 0x90FB44D2F05D0842'u),
      uint64x2(hi: 0xA99541BF57452B28'u, lo: 0x353A1607AC744A53'u),
      uint64x2(hi: 0xD3FA922F2D1675F2'u, lo: 0x42889B8997915CE8'u),
      uint64x2(hi: 0x847C9B5D7C2E09B7'u, lo: 0x69956135FEBADA11'u),
      uint64x2(hi: 0xA59BC234DB398C25'u, lo: 0x43FAB9837E699095'u),
      uint64x2(hi: 0xCF02B2C21207EF2E'u, lo: 0x94F967E45E03F4BB'u),
      uint64x2(hi: 0x8161AFB94B44F57D'u, lo: 0x1D1BE0EEBAC278F5'u),
      uint64x2(hi: 0xA1BA1BA79E1632DC'u, lo: 0x6462D92A69731732'u),
      uint64x2(hi: 0xCA28A291859BBF93'u, lo: 0x7D7B8F7503CFDCFE'u),
      uint64x2(hi: 0xFCB2CB35E702AF78'u, lo: 0x5CDA735244C3D43E'u),
      uint64x2(hi: 0x9DEFBF01B061ADAB'u, lo: 0x3A0888136AFA64A7'u),
      uint64x2(hi: 0xC56BAEC21C7A1916'u, lo: 0x088AAA1845B8FDD0'u),
      uint64x2(hi: 0xF6C69A72A3989F5B'u, lo: 0x8AAD549E57273D45'u),
      uint64x2(hi: 0x9A3C2087A63F6399'u, lo: 0x36AC54E2F678864B'u),
      uint64x2(hi: 0xC0CB28A98FCF3C7F'u, lo: 0x84576A1BB416A7DD'u),
      uint64x2(hi: 0xF0FDF2D3F3C30B9F'u, lo: 0x656D44A2A11C51D5'u),
      uint64x2(hi: 0x969EB7C47859E743'u, lo: 0x9F644AE5A4B1B325'u),
      uint64x2(hi: 0xBC4665B596706114'u, lo: 0x873D5D9F0DDE1FEE'u),
      uint64x2(hi: 0xEB57FF22FC0C7959'u, lo: 0xA90CB506D155A7EA'u),
      uint64x2(hi: 0x9316FF75DD87CBD8'u, lo: 0x09A7F12442D588F2'u),
      uint64x2(hi: 0xB7DCBF5354E9BECE'u, lo: 0x0C11ED6D538AEB2F'u),
      uint64x2(hi: 0xE5D3EF282A242E81'u, lo: 0x8F1668C8A86DA5FA'u),
      uint64x2(hi: 0x8FA475791A569D10'u, lo: 0xF96E017D694487BC'u),
      uint64x2(hi: 0xB38D92D760EC4455'u, lo: 0x37C981DCC395A9AC'u),
      uint64x2(hi: 0xE070F78D3927556A'u, lo: 0x85BBE253F47B1417'u),
      uint64x2(hi: 0x8C469AB843B89562'u, lo: 0x93956D7478CCEC8E'u),
      uint64x2(hi: 0xAF58416654A6BABB'u, lo: 0x387AC8D1970027B2'u),
      uint64x2(hi: 0xDB2E51BFE9D0696A'u, lo: 0x06997B05FCC0319E'u),
      uint64x2(hi: 0x88FCF317F22241E2'u, lo: 0x441FECE3BDF81F03'u),
      uint64x2(hi: 0xAB3C2FDDEEAAD25A'u, lo: 0xD527E81CAD7626C3'u),
      uint64x2(hi: 0xD60B3BD56A5586F1'u, lo: 0x8A71E223D8D3B074'u),
      uint64x2(hi: 0x85C7056562757456'u, lo: 0xF6872D5667844E49'u),
      uint64x2(hi: 0xA738C6BEBB12D16C'u, lo: 0xB428F8AC016561DB'u),
      uint64x2(hi: 0xD106F86E69D785C7'u, lo: 0xE13336D701BEBA52'u),
      uint64x2(hi: 0x82A45B450226B39C'u, lo: 0xECC0024661173473'u),
      uint64x2(hi: 0xA34D721642B06084'u, lo: 0x27F002D7F95D0190'u),
      uint64x2(hi: 0xCC20CE9BD35C78A5'u, lo: 0x31EC038DF7B441F4'u),
      uint64x2(hi: 0xFF290242C83396CE'u, lo: 0x7E67047175A15271'u),
      uint64x2(hi: 0x9F79A169BD203E41'u, lo: 0x0F0062C6E984D386'u),
      uint64x2(hi: 0xC75809C42C684DD1'u, lo: 0x52C07B78A3E60868'u),
      uint64x2(hi: 0xF92E0C3537826145'u, lo: 0xA7709A56CCDF8A82'u),
      uint64x2(hi: 0x9BBCC7A142B17CCB'u, lo: 0x88A66076400BB691'u),
      uint64x2(hi: 0xC2ABF989935DDBFE'u, lo: 0x6ACFF893D00EA435'u),
      uint64x2(hi: 0xF356F7EBF83552FE'u, lo: 0x0583F6B8C4124D43'u),
      uint64x2(hi: 0x98165AF37B2153DE'u, lo: 0xC3727A337A8B704A'u),
      uint64x2(hi: 0xBE1BF1B059E9A8D6'u, lo: 0x744F18C0592E4C5C'u),
      uint64x2(hi: 0xEDA2EE1C7064130C'u, lo: 0x1162DEF06F79DF73'u),
      uint64x2(hi: 0x9485D4D1C63E8BE7'u, lo: 0x8ADDCB5645AC2BA8'u),
      uint64x2(hi: 0xB9A74A0637CE2EE1'u, lo: 0x6D953E2BD7173692'u),
      uint64x2(hi: 0xE8111C87C5C1BA99'u, lo: 0xC8FA8DB6CCDD0437'u),
      uint64x2(hi: 0x910AB1D4DB9914A0'u, lo: 0x1D9C9892400A22A2'u),
      uint64x2(hi: 0xB54D5E4A127F59C8'u, lo: 0x2503BEB6D00CAB4B'u),
      uint64x2(hi: 0xE2A0B5DC971F303A'u, lo: 0x2E44AE64840FD61D'u),
      uint64x2(hi: 0x8DA471A9DE737E24'u, lo: 0x5CEAECFED289E5D2'u),
      uint64x2(hi: 0xB10D8E1456105DAD'u, lo: 0x7425A83E872C5F47'u),
      uint64x2(hi: 0xDD50F1996B947518'u, lo: 0xD12F124E28F77719'u),
      uint64x2(hi: 0x8A5296FFE33CC92F'u, lo: 0x82BD6B70D99AAA6F'u),
      uint64x2(hi: 0xACE73CBFDC0BFB7B'u, lo: 0x636CC64D1001550B'u),
      uint64x2(hi: 0xD8210BEFD30EFA5A'u, lo: 0x3C47F7E05401AA4E'u),
      uint64x2(hi: 0x8714A775E3E95C78'u, lo: 0x65ACFAEC34810A71'u),
      uint64x2(hi: 0xA8D9D1535CE3B396'u, lo: 0x7F1839A741A14D0D'u),
      uint64x2(hi: 0xD31045A8341CA07C'u, lo: 0x1EDE48111209A050'u),
      uint64x2(hi: 0x83EA2B892091E44D'u, lo: 0x934AED0AAB460432'u),
      uint64x2(hi: 0xA4E4B66B68B65D60'u, lo: 0xF81DA84D5617853F'u),
      uint64x2(hi: 0xCE1DE40642E3F4B9'u, lo: 0x36251260AB9D668E'u),
      uint64x2(hi: 0x80D2AE83E9CE78F3'u, lo: 0xC1D72B7C6B426019'u),
      uint64x2(hi: 0xA1075A24E4421730'u, lo: 0xB24CF65B8612F81F'u),
      uint64x2(hi: 0xC94930AE1D529CFC'u, lo: 0xDEE033F26797B627'u),
      uint64x2(hi: 0xFB9B7CD9A4A7443C'u, lo: 0x169840EF017DA3B1'u),
      uint64x2(hi: 0x9D412E0806E88AA5'u, lo: 0x8E1F289560EE864E'u),
      uint64x2(hi: 0xC491798A08A2AD4E'u, lo: 0xF1A6F2BAB92A27E2'u),
      uint64x2(hi: 0xF5B5D7EC8ACB58A2'u, lo: 0xAE10AF696774B1DB'u),
      uint64x2(hi: 0x9991A6F3D6BF1765'u, lo: 0xACCA6DA1E0A8EF29'u),
      uint64x2(hi: 0xBFF610B0CC6EDD3F'u, lo: 0x17FD090A58D32AF3'u),
      uint64x2(hi: 0xEFF394DCFF8A948E'u, lo: 0xDDFC4B4CEF07F5B0'u),
      uint64x2(hi: 0x95F83D0A1FB69CD9'u, lo: 0x4ABDAF101564F98E'u),
      uint64x2(hi: 0xBB764C4CA7A4440F'u, lo: 0x9D6D1AD41ABE37F1'u),
      uint64x2(hi: 0xEA53DF5FD18D5513'u, lo: 0x84C86189216DC5ED'u),
      uint64x2(hi: 0x92746B9BE2F8552C'u, lo: 0x32FD3CF5B4E49BB4'u),
      uint64x2(hi: 0xB7118682DBB66A77'u, lo: 0x3FBC8C33221DC2A1'u),
      uint64x2(hi: 0xE4D5E82392A40515'u, lo: 0x0FABAF3FEAA5334A'u),
      uint64x2(hi: 0x8F05B1163BA6832D'u, lo: 0x29CB4D87F2A7400E'u),
      uint64x2(hi: 0xB2C71D5BCA9023F8'u, lo: 0x743E20E9EF511012'u),
      uint64x2(hi: 0xDF78E4B2BD342CF6'u, lo: 0x914DA9246B255416'u),
      uint64x2(hi: 0x8BAB8EEFB6409C1A'u, lo: 0x1AD089B6C2F7548E'u),
      uint64x2(hi: 0xAE9672ABA3D0C320'u, lo: 0xA184AC2473B529B1'u),
      uint64x2(hi: 0xDA3C0F568CC4F3E8'u, lo: 0xC9E5D72D90A2741E'u),
      uint64x2(hi: 0x8865899617FB1871'u, lo: 0x7E2FA67C7A658892'u),
      uint64x2(hi: 0xAA7EEBFB9DF9DE8D'u, lo: 0xDDBB901B98FEEAB7'u),
      uint64x2(hi: 0xD51EA6FA85785631'u, lo: 0x552A74227F3EA565'u),
      uint64x2(hi: 0x8533285C936B35DE'u, lo: 0xD53A88958F87275F'u),
      uint64x2(hi: 0xA67FF273B8460356'u, lo: 0x8A892ABAF368F137'u),
      uint64x2(hi: 0xD01FEF10A657842C'u, lo: 0x2D2B7569B0432D85'u),
      uint64x2(hi: 0x8213F56A67F6B29B'u, lo: 0x9C3B29620E29FC73'u),
      uint64x2(hi: 0xA298F2C501F45F42'u, lo: 0x8349F3BA91B47B8F'u),
      uint64x2(hi: 0xCB3F2F7642717713'u, lo: 0x241C70A936219A73'u),
      uint64x2(hi: 0xFE0EFB53D30DD4D7'u, lo: 0xED238CD383AA0110'u),
      uint64x2(hi: 0x9EC95D1463E8A506'u, lo: 0xF4363804324A40AA'u),
      uint64x2(hi: 0xC67BB4597CE2CE48'u, lo: 0xB143C6053EDCD0D5'u),
      uint64x2(hi: 0xF81AA16FDC1B81DA'u, lo: 0xDD94B7868E94050A'u),
      uint64x2(hi: 0x9B10A4E5E9913128'u, lo: 0xCA7CF2B4191C8326'u),
      uint64x2(hi: 0xC1D4CE1F63F57D72'u, lo: 0xFD1C2F611F63A3F0'u),
      uint64x2(hi: 0xF24A01A73CF2DCCF'u, lo: 0xBC633B39673C8CEC'u),
      uint64x2(hi: 0x976E41088617CA01'u, lo: 0xD5BE0503E085D813'u),
      uint64x2(hi: 0xBD49D14AA79DBC82'u, lo: 0x4B2D8644D8A74E18'u),
      uint64x2(hi: 0xEC9C459D51852BA2'u, lo: 0xDDF8E7D60ED1219E'u),
      uint64x2(hi: 0x93E1AB8252F33B45'u, lo: 0xCABB90E5C942B503'u),
      uint64x2(hi: 0xB8DA1662E7B00A17'u, lo: 0x3D6A751F3B936243'u),
      uint64x2(hi: 0xE7109BFBA19C0C9D'u, lo: 0x0CC512670A783AD4'u),
      uint64x2(hi: 0x906A617D450187E2'u, lo: 0x27FB2B80668B24C5'u),
      uint64x2(hi: 0xB484F9DC9641E9DA'u, lo: 0xB1F9F660802DEDF6'u),
      uint64x2(hi: 0xE1A63853BBD26451'u, lo: 0x5E7873F8A0396973'u),
      uint64x2(hi: 0x8D07E33455637EB2'u, lo: 0xDB0B487B6423E1E8'u),
      uint64x2(hi: 0xB049DC016ABC5E5F'u, lo: 0x91CE1A9A3D2CDA62'u),
      uint64x2(hi: 0xDC5C5301C56B75F7'u, lo: 0x7641A140CC7810FB'u),
      uint64x2(hi: 0x89B9B3E11B6329BA'u, lo: 0xA9E904C87FCB0A9D'u),
      uint64x2(hi: 0xAC2820D9623BF429'u, lo: 0x546345FA9FBDCD44'u),
      uint64x2(hi: 0xD732290FBACAF133'u, lo: 0xA97C177947AD4095'u),
      uint64x2(hi: 0x867F59A9D4BED6C0'u, lo: 0x49ED8EABCCCC485D'u),
      uint64x2(hi: 0xA81F301449EE8C70'u, lo: 0x5C68F256BFFF5A74'u),
      uint64x2(hi: 0xD226FC195C6A2F8C'u, lo: 0x73832EEC6FFF3111'u),
      uint64x2(hi: 0x83585D8FD9C25DB7'u, lo: 0xC831FD53C5FF7EAB'u),
      uint64x2(hi: 0xA42E74F3D032F525'u, lo: 0xBA3E7CA8B77F5E55'u),
      uint64x2(hi: 0xCD3A1230C43FB26F'u, lo: 0x28CE1BD2E55F35EB'u),
      uint64x2(hi: 0x80444B5E7AA7CF85'u, lo: 0x7980D163CF5B81B3'u),
      uint64x2(hi: 0xA0555E361951C366'u, lo: 0xD7E105BCC332621F'u),
      uint64x2(hi: 0xC86AB5C39FA63440'u, lo: 0x8DD9472BF3FEFAA7'u),
      uint64x2(hi: 0xFA856334878FC150'u, lo: 0xB14F98F6F0FEB951'u),
      uint64x2(hi: 0x9C935E00D4B9D8D2'u, lo: 0x6ED1BF9A569F33D3'u),
      uint64x2(hi: 0xC3B8358109E84F07'u, lo: 0x0A862F80EC4700C8'u),
      uint64x2(hi: 0xF4A642E14C6262C8'u, lo: 0xCD27BB612758C0FA'u),
      uint64x2(hi: 0x98E7E9CCCFBD7DBD'u, lo: 0x8038D51CB897789C'u),
      uint64x2(hi: 0xBF21E44003ACDD2C'u, lo: 0xE0470A63E6BD56C3'u),
      uint64x2(hi: 0xEEEA5D5004981478'u, lo: 0x1858CCFCE06CAC74'u),
      uint64x2(hi: 0x95527A5202DF0CCB'u, lo: 0x0F37801E0C43EBC8'u),
      uint64x2(hi: 0xBAA718E68396CFFD'u, lo: 0xD30560258F54E6BA'u),
      uint64x2(hi: 0xE950DF20247C83FD'u, lo: 0x47C6B82EF32A2069'u),
      uint64x2(hi: 0x91D28B7416CDD27E'u, lo: 0x4CDC331D57FA5441'u),
      uint64x2(hi: 0xB6472E511C81471D'u, lo: 0xE0133FE4ADF8E952'u),
      uint64x2(hi: 0xE3D8F9E563A198E5'u, lo: 0x58180FDDD97723A6'u),
      uint64x2(hi: 0x8E679C2F5E44FF8F'u, lo: 0x570F09EAA7EA7648'u),
      uint64x2(hi: 0xB201833B35D63F73'u, lo: 0x2CD2CC6551E513DA'u),
      uint64x2(hi: 0xDE81E40A034BCF4F'u, lo: 0xF8077F7EA65E58D1'u),
      uint64x2(hi: 0x8B112E86420F6191'u, lo: 0xFB04AFAF27FAF782'u),
      uint64x2(hi: 0xADD57A27D29339F6'u, lo: 0x79C5DB9AF1F9B563'u),
      uint64x2(hi: 0xD94AD8B1C7380874'u, lo: 0x18375281AE7822BC'u),
      uint64x2(hi: 0x87CEC76F1C830548'u, lo: 0x8F2293910D0B15B5'u),
      uint64x2(hi: 0xA9C2794AE3A3C69A'u, lo: 0xB2EB3875504DDB22'u),
      uint64x2(hi: 0xD433179D9C8CB841'u, lo: 0x5FA60692A46151EB'u),
      uint64x2(hi: 0x849FEEC281D7F328'u, lo: 0xDBC7C41BA6BCD333'u),
      uint64x2(hi: 0xA5C7EA73224DEFF3'u, lo: 0x12B9B522906C0800'u),
      uint64x2(hi: 0xCF39E50FEAE16BEF'u, lo: 0xD768226B34870A00'u),
      uint64x2(hi: 0x81842F29F2CCE375'u, lo: 0xE6A1158300D46640'u),
      uint64x2(hi: 0xA1E53AF46F801C53'u, lo: 0x60495AE3C1097FD0'u),
      uint64x2(hi: 0xCA5E89B18B602368'u, lo: 0x385BB19CB14BDFC4'u),
      uint64x2(hi: 0xFCF62C1DEE382C42'u, lo: 0x46729E03DD9ED7B5'u),
      uint64x2(hi: 0x9E19DB92B4E31BA9'u, lo: 0x6C07A2C26A8346D1'u),
      uint64x2(hi: 0xC5A05277621BE293'u, lo: 0xC7098B7305241885'u),
      uint64x2(hi: 0xF70867153AA2DB38'u, lo: 0xB8CBEE4FC66D1EA7'u)]
  dragonbox_Assert(k >= kMin)
  dragonbox_Assert(k <= kMax)
  return pow10[k - kMin]

##  Returns whether value is divisible by 2^e2

proc multipleOfPow2*(value: uint64; e2: int32): bool {.inline.} =
  dragonbox_Assert(e2 >= 0)
  return e2 < 64 and (value and ((uint64(1) shl e2) - 1)) == 0

##  Returns whether value is divisible by 5^e5

proc multipleOfPow5*(value: uint64; e5: int32): bool {.inline.} =
  type
    MulCmp {.bycopy.} = object
      mul: uint64
      cmp: uint64

  const
    mod5 = [MulCmp(mul: 0x0000000000000001'u, cmp: 0xFFFFFFFFFFFFFFFF'u),
      MulCmp(mul: 0xCCCCCCCCCCCCCCCD'u, cmp: 0x3333333333333333'u),
      MulCmp(mul: 0x8F5C28F5C28F5C29'u, cmp: 0x0A3D70A3D70A3D70'u),
      MulCmp(mul: 0x1CAC083126E978D5'u, cmp: 0x020C49BA5E353F7C'u),
      MulCmp(mul: 0xD288CE703AFB7E91'u, cmp: 0x0068DB8BAC710CB2'u),
      MulCmp(mul: 0x5D4E8FB00BCBE61D'u, cmp: 0x0014F8B588E368F0'u),
      MulCmp(mul: 0x790FB65668C26139'u, cmp: 0x000431BDE82D7B63'u),
      MulCmp(mul: 0xE5032477AE8D46A5'u, cmp: 0x0000D6BF94D5E57A'u),
      MulCmp(mul: 0xC767074B22E90E21'u, cmp: 0x00002AF31DC46118'u),
      MulCmp(mul: 0x8E47CE423A2E9C6D'u, cmp: 0x0000089705F4136B'u),
      MulCmp(mul: 0x4FA7F60D3ED61F49'u, cmp: 0x000001B7CDFD9D7B'u),
      MulCmp(mul: 0x0FEE64690C913975'u, cmp: 0x00000057F5FF85E5'u),
      MulCmp(mul: 0x3662E0E1CF503EB1'u, cmp: 0x000000119799812D'u),
      MulCmp(mul: 0xA47A2CF9F6433FBD'u, cmp: 0x0000000384B84D09'u),
      MulCmp(mul: 0x54186F653140A659'u, cmp: 0x00000000B424DC35'u),
      MulCmp(mul: 0x7738164770402145'u, cmp: 0x0000000024075F3D'u),
      MulCmp(mul: 0xE4A4D1417CD9A041'u, cmp: 0x000000000734ACA5'u),
      MulCmp(mul: 0xC75429D9E5C5200D'u, cmp: 0x000000000170EF54'u),
      MulCmp(mul: 0xC1773B91FAC10669'u, cmp: 0x000000000049C977'u),
      MulCmp(mul: 0x26B172506559CE15'u, cmp: 0x00000000000EC1E4'u),
      MulCmp(mul: 0xD489E3A9ADDEC2D1'u, cmp: 0x000000000002F394'u),
      MulCmp(mul: 0x90E860BB892C8D5D'u, cmp: 0x000000000000971D'u),
      MulCmp(mul: 0x502E79BF1B6F4F79'u, cmp: 0x0000000000001E39'u),
      MulCmp(mul: 0xDCD618596BE30FE5'u, cmp: 0x000000000000060B'u),
      MulCmp(mul: 0x2C2AD1AB7BFA3661'u, cmp: 0x0000000000000135'u)]
  dragonbox_Assert(e5 >= 0)
  dragonbox_Assert(e5 <= 24)
  let m5: MulCmp = mod5[e5]
  return value * m5.mul <= m5.cmp

type
  FloatingDecimal64* {.bycopy.} = object
    significand*: uint64
    exponent*: int32


proc toDecimal64AsymmetricInterval*(e2: int32): FloatingDecimal64 {.inline.} =
  ##  NB:
  ##  accept_lower_endpoint = true
  ##  accept_upper_endpoint = true
  const
    P: int32 = significandSize
  ##  Compute k and beta
  let minusK: int32 = floorLog10ThreeQuartersPow2(e2)
  let betaMinus1: int32 = e2 + floorLog2Pow10(-minusK)
  ##  Compute xi and zi
  let pow10: uint64x2 = computePow10(-minusK)
  let lowerEndpoint: uint64 = (pow10.hi - (pow10.hi shr (P + 1))) shr
      (64 - P - betaMinus1)
  let upperEndpoint: uint64 = (pow10.hi + (pow10.hi shr (P + 0))) shr
      (64 - P - betaMinus1)
  ##  If we don't accept the left endpoint (but we do!) or
  ##  if the left endpoint is not an integer, increase it
  let lowerEndpointIsInteger: bool = (2 <= e2 and e2 <= 3)
  let xi: uint64 = lowerEndpoint + uint64(not lowerEndpointIsInteger)
  let zi: uint64 = upperEndpoint
  ##  Try bigger divisor
  var q: uint64 = zi div 10
  if q * 10 >= xi:
    return FloatingDecimal64(significand: q, exponent: minusK + 1)
  q = ((pow10.hi shr (64 - (P + 1) - betaMinus1)) + 1) div 2
  ##  When tie occurs, choose one of them according to the rule
  if e2 == -77:
    dec(q, ord(q mod 2 != 0))
    ##  Round to even.
  else:
    inc(q, ord(q < xi))
  return FloatingDecimal64(significand: q, exponent: minusK)

proc computeDelta*(pow10: uint64x2; betaMinus1: int32): uint32 {.inline.} =
  dragonbox_Assert(betaMinus1 >= 0)
  dragonbox_Assert(betaMinus1 <= 63)
  return cast[uint32](pow10.hi shr (64 - 1 - betaMinus1))

when defined(sizeof_Int128):
  proc mul128*(x: uint64; y: uint64): uint64x2 {.inline.} =
    ##  1 mulx
    type
      uint128T = uint128
    let p: uint128T = uint128T(x) * y
    let hi: uint64 = cast[uint64](p shr 64)
    let lo: uint64 = cast[uint64](p)
    return (hi, lo)

elif defined(vcc) and defined(cpu64):
  proc umul128(x, y: uint64, z: ptr uint64): uint64 {.importc: "_umul128", header: "<intrin.h>".}
  proc mul128*(x: uint64; y: uint64): uint64x2 {.inline.} =
    var hi: uint64 = 0
    var lo: uint64 = umul128(x, y, addr(hi))
    return uint64x2(hi: hi, lo: lo)

else:
  proc lo32*(x: uint64): uint32 {.inline.} =
    return cast[uint32](x)

  proc hi32*(x: uint64): uint32 {.inline.} =
    return cast[uint32](x shr 32)

  proc mul128*(a: uint64; b: uint64): uint64x2 {.inline.} =
    let b00: uint64 = uint64(lo32(a)) * lo32(b)
    let b01: uint64 = uint64(lo32(a)) * hi32(b)
    let b10: uint64 = uint64(hi32(a)) * lo32(b)
    let b11: uint64 = uint64(hi32(a)) * hi32(b)
    let mid1: uint64 = b10 + hi32(b00)
    let mid2: uint64 = b01 + lo32(mid1)
    let hi: uint64 = b11 + hi32(mid1) + hi32(mid2)
    let lo: uint64 = lo32(b00) or uint64(lo32(mid2)) shl 32
    return uint64x2(hi: hi, lo: lo)

##  Returns (x * y) / 2^128

proc mulShift*(x: uint64; y: uint64x2): uint64 {.inline.} =
  ##  2 mulx
  var p1: uint64x2 = mul128(x, y.hi)
  var p0: uint64x2 = mul128(x, y.lo)
  p1.lo += p0.hi
  inc(p1.hi, ord(p1.lo < p0.hi))
  return p1.hi

proc mulParity*(twoF: uint64; pow10: uint64x2; betaMinus1: int32): bool {.inline.} =
  ##  1 mulx, 1 mul
  dragonbox_Assert(betaMinus1 >= 1)
  dragonbox_Assert(betaMinus1 <= 63)
  let p01: uint64 = twoF * pow10.hi
  let p10: uint64 = mul128(twoF, pow10.lo).hi
  let mid: uint64 = p01 + p10
  return (mid and (uint64(1) shl (64 - betaMinus1))) != 0

proc isIntegralEndpoint*(twoF: uint64; e2: int32; minusK: int32): bool {.inline.} =
  if e2 < -2:
    return false
  if e2 <= 9:
    return true
  if e2 <= 86:
    return multipleOfPow5(twoF, minusK)
  return false

proc isIntegralMidpoint*(twoF: uint64; e2: int32; minusK: int32): bool {.inline.} =
  if e2 < -4:
    return multipleOfPow2(twoF, minusK - e2 + 1)
  if e2 <= 9:
    return true
  if e2 <= 86:
    return multipleOfPow5(twoF, minusK)
  return false

proc toDecimal64*(ieeeSignificand: uint64; ieeeExponent: uint64): FloatingDecimal64 {.
    inline.} =
  const
    kappa: int32 = 2
  const
    bigDivisor: uint32 = 1000
  ##  10^(kappa + 1)
  const
    smallDivisor: uint32 = 100
  ##  10^(kappa)
  ##
  ##  Step 1:
  ##  integer promotion & Schubfach multiplier calculation.
  ##
  var m2: uint64
  var e2: int32
  if ieeeExponent != 0:
    m2 = hiddenBit or ieeeSignificand
    e2 = cast[int32](ieeeExponent) - exponentBias
    if 0 <= -e2 and -e2 < significandSize and multipleOfPow2(m2, -e2):
      ##  Small integer.
      return FloatingDecimal64(significand: m2 shr -e2, exponent: 0)
    if ieeeSignificand == 0 and ieeeExponent > 1:
      ##  Shorter interval case; proceed like Schubfach.
      return toDecimal64AsymmetricInterval(e2)
  else:
    ##  Subnormal case; interval is always regular.
    m2 = ieeeSignificand
    e2 = 1 - exponentBias
  let isEven: bool = (m2 mod 2 == 0)
  let acceptLower: bool = isEven
  let acceptUpper: bool = isEven
  ##  Compute k and beta.
  let minusK: int32 = floorLog10Pow2(e2) - kappa
  let betaMinus1: int32 = e2 + floorLog2Pow10(-minusK)
  dragonbox_Assert(betaMinus1 >= 6)
  dragonbox_Assert(betaMinus1 <= 9)
  let pow10: uint64x2 = computePow10(-minusK)
  ##  Compute delta
  ##  10^kappa <= delta < 10^(kappa + 1)
  ##       100 <= delta < 1000
  let delta: uint32 = computeDelta(pow10, betaMinus1)
  dragonbox_Assert(delta >= smallDivisor)
  dragonbox_Assert(delta < bigDivisor)
  let twoFl: uint64 = 2 * m2 - 1
  let twoFc: uint64 = 2 * m2
  let twoFr: uint64 = 2 * m2 + 1
  ##  (54 bits)
  ##  Compute zi
  ##   (54 + 9 = 63 bits)
  let zi: uint64 = mulShift(twoFr shl betaMinus1, pow10)
  ##  2 mulx
  ##
  ##  Step 2:
  ##  Try larger divisor.
  ##
  var q: uint64 = zi div bigDivisor
  ##   uint64_t q = Mul128(zi, 0x83126E978D4FDF3Cu).hi >> 9; // 1 mulx
  var r: uint32 = cast[uint32](zi) - bigDivisor * cast[uint32](q)
  ##  r = zi % BigDivisor
  ##  0 <= r < 1000
  if r < delta:                  ## likely ~50% ?!
            ##  (r > deltai)
    ##  Exclude the right endpoint if necessary
    if r != 0 or acceptUpper or not isIntegralEndpoint(twoFr, e2, minusK):
      return FloatingDecimal64(significand: q, exponent: minusK + kappa + 1)
    dragonbox_Assert(q != 0)
    dec(q)
    r = bigDivisor
  elif r == delta:               ## unlikely
    ##  Compare fractional parts.
    ##  Check conditions in the order different from the paper
    ##  to take advantage of short-circuiting
    if (acceptLower and isIntegralEndpoint(twoFl, e2, minusK)) or
        mulParity(twoFl, pow10, betaMinus1):
      return FloatingDecimal64(significand: q, exponent: minusK + kappa + 1)
  else:
    discard
  ##
  ##  Step 3:
  ##  Find the significand with the smaller divisor
  ##
  q = q * 10
  ##  1 hmul
  ##  0 <= r <= 1000
  let dist: uint32 = r - (delta div 2) + (smallDivisor div 2)
  let distQ: uint32 = dist div 100
  ##  1 mul
  ##   const uint32_t dist_r = dist % 100;
  q += distQ
  ##   if /*likely*/ (dist_r == 0)
  if dist == distQ * 100:
    ##       const bool approx_y_parity = ((dist ^ (SmallDivisor / 2)) & 1) != 0;
    let approxYParity: bool = (dist and 1) != 0
    ##  Check z^(f) >= epsilon^(f)
    ##  We have either yi == zi - epsiloni or yi == (zi - epsiloni) - 1,
    ##  where yi == zi - epsiloni if and only if z^(f) >= epsilon^(f)
    ##  Since there are only 2 possibilities, we only need to care about the
    ##  parity. Also, zi and r should have the same parity since the divisor
    ##  is an even number
    if mulParity(twoFc, pow10, betaMinus1) != approxYParity:
      dec(q)
    elif q mod 2 != 0 and isIntegralMidpoint(twoFc, e2, minusK):
      dec(q)
  return FloatingDecimal64(significand: q, exponent: minusK + kappa)

# ==================================================================================================
#  ToChars
# ==================================================================================================

when false:
  template `+!`(x: cstring; offset: int): cstring = cast[cstring](cast[uint](x) + uint(offset))

  template dec(x: cstring; offset=1) = x = cast[cstring](cast[uint](x) - uint(offset))
  template inc(x: cstring; offset=1) = x = cast[cstring](cast[uint](x) + uint(offset))

  proc memset(x: cstring; ch: char; L: int) {.importc, nodecl.}
  proc memmove(a, b: cstring; L: int) {.importc, nodecl.}

proc utoa8DigitsSkipTrailingZeros*(buf: var openArray[char]; pos: int; digits: uint32): int {.inline.} =
  dragonbox_Assert(digits >= 1)
  dragonbox_Assert(digits <= 99999999'u32)
  let q: uint32 = digits div 10000
  let r: uint32 = digits mod 10000
  let qH: uint32 = q div 100
  let qL: uint32 = q mod 100
  utoa2Digits(buf, pos, qH)
  utoa2Digits(buf, pos + 2, qL)
  if r == 0:
    return trailingZeros2Digits(if qL == 0: qH else: qL) + (if qL == 0: 6 else: 4)
  else:
    let rH: uint32 = r div 100
    let rL: uint32 = r mod 100
    utoa2Digits(buf, pos + 4, rH)
    utoa2Digits(buf, pos + 6, rL)
    return trailingZeros2Digits(if rL == 0: rH else: rL) + (if rL == 0: 2 else: 0)

proc printDecimalDigitsBackwards*(buf: var openArray[char]; pos: int; output64: uint64): int {.inline.} =
  var pos = pos
  var output64 = output64
  var tz = 0
  ##  number of trailing zeros removed.
  var nd = 0
  ##  number of decimal digits processed.
  ##  At most 17 digits remaining
  if output64 >= 100000000'u64:
    let q: uint64 = output64 div 100000000'u64
    let r: uint32 = cast[uint32](output64 mod 100000000'u64)
    output64 = q
    dec(pos, 8)
    if r != 0:
      tz = utoa8DigitsSkipTrailingZeros(buf, pos, r)
      dragonbox_Assert(tz >= 0)
      dragonbox_Assert(tz <= 7)
    else:
      tz = 8
    nd = 8
  dragonbox_Assert(output64 <= high(uint32))
  var output = cast[uint32](output64)
  if output >= 10000:
    let q: uint32 = output div 10000
    let r: uint32 = output mod 10000
    output = q
    dec(pos, 4)
    if r != 0:
      let rH: uint32 = r div 100
      let rL: uint32 = r mod 100
      utoa2Digits(buf, pos, rH)
      utoa2Digits(buf, pos + 2, rL)
      if tz == nd:
        inc(tz, trailingZeros2Digits(if rL == 0: rH else: rL) +
            (if rL == 0: 2 else: 0))
    else:
      if tz == nd:
        inc(tz, 4)
      else:
        for i in 0..3: buf[pos+i] = '0'
      ##  (actually not required...)
    inc(nd, 4)
  if output >= 100:
    let q: uint32 = output div 100
    let r: uint32 = output mod 100
    output = q
    dec(pos, 2)
    utoa2Digits(buf, pos, r)
    if tz == nd:
      inc(tz, trailingZeros2Digits(r))
    inc(nd, 2)
    if output >= 100:
      let q2: uint32 = output div 100
      let r2: uint32 = output mod 100
      output = q2
      dec(pos, 2)
      utoa2Digits(buf, pos, r2)
      if tz == nd:
        inc(tz, trailingZeros2Digits(r2))
      inc(nd, 2)
  dragonbox_Assert(output >= 1)
  dragonbox_Assert(output <= 99)
  if output >= 10:
    let q: uint32 = output
    dec(pos, 2)
    utoa2Digits(buf, pos, q)
    if tz == nd:
      inc(tz, trailingZeros2Digits(q))
  else:
    let q: uint32 = output
    dragonbox_Assert(q >= 1)
    dragonbox_Assert(q <= 9)
    dec(pos)
    buf[pos] = chr(ord('0') + q)
  return tz

proc decimalLength*(v: uint64): int {.inline.} =
  dragonbox_Assert(v >= 1)
  dragonbox_Assert(v <= 99999999999999999'u64)
  if cast[uint32](v shr 32) != 0:
    if v >= 10000000000000000'u64:
      return 17
    if v >= 1000000000000000'u64:
      return 16
    if v >= 100000000000000'u64:
      return 15
    if v >= 10000000000000'u64:
      return 14
    if v >= 1000000000000'u64:
      return 13
    if v >= 100000000000'u64:
      return 12
    if v >= 10000000000'u64:
      return 11
    return 10
  let v32: uint32 = cast[uint32](v)
  if v32 >= 1000000000'u32:
    return 10
  if v32 >= 100000000'u32:
    return 9
  if v32 >= 10000000'u32:
    return 8
  if v32 >= 1000000'u32:
    return 7
  if v32 >= 100000'u32:
    return 6
  if v32 >= 10000'u32:
    return 5
  if v32 >= 1000'u32:
    return 4
  if v32 >= 100'u32:
    return 3
  if v32 >= 10'u32:
    return 2
  return 1

proc formatDigits*[T: Ordinal](buffer: var openArray[char]; pos: T; digits: uint64; decimalExponent: int;
                  forceTrailingDotZero = false): int {.inline.} =
  const
    minFixedDecimalPoint = -6
  const
    maxFixedDecimalPoint = 17
  var pos:int = pos.int
  assert(minFixedDecimalPoint <= -1, "internal error")
  assert(maxFixedDecimalPoint >= 17, "internal error")
  dragonbox_Assert(digits >= 1)
  dragonbox_Assert(digits <= 99999999999999999'u64)
  dragonbox_Assert(decimalExponent >= -999)
  dragonbox_Assert(decimalExponent <= 999)
  var numDigits = decimalLength(digits)
  let decimalPoint = numDigits + decimalExponent
  let useFixed: bool = minFixedDecimalPoint <= decimalPoint and
      decimalPoint <= maxFixedDecimalPoint
  ## Prepare the buffer.
  for i in 0..<32: buffer[pos+i] = '0'
  assert(minFixedDecimalPoint >= -30, "internal error")
  assert(maxFixedDecimalPoint <= 32, "internal error")
  var decimalDigitsPosition: int
  if useFixed:
    if decimalPoint <= 0:
      ##  0.[000]digits
      decimalDigitsPosition = 2 - decimalPoint
    else:
      ##  dig.its
      ##  digits[000]
      decimalDigitsPosition = 0
  else:
    ##  dE+123 or d.igitsE+123
    decimalDigitsPosition = 1
  var digitsEnd = pos + int(decimalDigitsPosition + numDigits)
  let tz = printDecimalDigitsBackwards(buffer, digitsEnd, digits)
  dec(digitsEnd, tz)
  dec(numDigits, tz)
  ##   decimal_exponent += tz; // => decimal_point unchanged.
  if useFixed:
    if decimalPoint <= 0:
      ##  0.[000]digits
      buffer[pos+1] = '.'
      pos = digitsEnd
    elif decimalPoint < numDigits:
      ##  dig.its
      when true: #defined(vcc) and not defined(clang):
        ##  VC does not inline the memmove call below. (Even if compiled with /arch:AVX2.)
        ##  However, memcpy will be inlined.
        var tmp = default(array[16, char])
        for i in 0..<16: tmp[i] = buffer[i+pos+decimalPoint]
        for i in 0..<16: buffer[i+pos+decimalPoint+1] = tmp[i]
      else:
        memmove(buffer +! (decimalPoint + 1), buffer +! decimalPoint, 16)
      buffer[pos+decimalPoint] = '.'
      pos = digitsEnd + 1
    else:
      ##  digits[000]
      inc(pos, decimalPoint)
      if forceTrailingDotZero:
        buffer[pos] = '.'
        buffer[pos+1] = '0'
        inc(pos, 2)
  else:
    ##  Copy the first digit one place to the left.
    buffer[pos] = buffer[pos+1]
    if numDigits == 1:
      ##  dE+123
      inc(pos)
    else:
      ##  d.igitsE+123
      buffer[pos+1] = '.'
      pos = digitsEnd
    let scientificExponent: int = decimalPoint - 1
    ##       SF_ASSERT(scientific_exponent != 0);
    buffer[pos] = 'e'
    buffer[pos+1] = if scientificExponent < 0: '-' else: '+'
    inc(pos, 2)
    let k: uint32 = cast[uint32](if scientificExponent < 0: -scientificExponent else: scientificExponent)
    if k < 10:
      buffer[pos] = chr(ord('0') + k)
      inc(pos)
    elif k < 100:
      utoa2Digits(buffer, pos, k)
      inc(pos, 2)
    else:
      let q: uint32 = k div 100
      let r: uint32 = k mod 100
      buffer[pos] = chr(ord('0') + q)
      inc(pos)
      utoa2Digits(buffer, pos, r)
      inc(pos, 2)
  return pos

proc toChars*(buffer: var openArray[char]; v: float; forceTrailingDotZero = false): int {.
    inline.} =
  var pos = 0
  let significand: uint64 = physicalSignificand(constructDouble(v))
  let exponent: uint64 = physicalExponent(constructDouble(v))
  if exponent != maxIeeeExponent:
    ##  Finite
    buffer[pos] = '-'
    inc(pos, signBit(constructDouble(v)))
    if exponent != 0 or significand != 0:
      ##  != 0
      let dec = toDecimal64(significand, exponent)
      return formatDigits(buffer, pos, dec.significand, dec.exponent.int,
                         forceTrailingDotZero)
    else:
      buffer[pos] = '0'
      buffer[pos+1] = '.'
      buffer[pos+2] = '0'
      buffer[pos+3] = ' '
      inc(pos, if forceTrailingDotZero: 3 else: 1)
      return pos
  if significand == 0:
    buffer[pos] = '-'
    inc(pos, signBit(constructDouble(v)))
    buffer[pos] = 'i'
    buffer[pos+1] = 'n'
    buffer[pos+2] = 'f'
    buffer[pos+3] = ' '
    return pos + 3
  else:
    buffer[pos] = 'n'
    buffer[pos+1] = 'a'
    buffer[pos+2] = 'n'
    buffer[pos+3] = ' '
    return pos + 3

when false:
  proc toString*(value: float): string =
    var buffer: array[dtoaMinBufferLength, char]
    let last = toChars(addr buffer, value)
    let L = cast[int](last) - cast[int](addr(buffer))
    result = newString(L)
    copyMem(addr result[0], addr buffer[0], L)

