import strmisc, math


func main() =
  doAssert parseFloatThousandSep("0.0") == 0.0
  doAssert parseFloatThousandSep("1.0") == 1.0
  doAssert parseFloatThousandSep("-0.0") == -0.0
  doAssert parseFloatThousandSep("-1.0") == -1.0
  doAssert parseFloatThousandSep("1.000") == 1.0
  doAssert parseFloatThousandSep("1.000") == 1.0
  doAssert parseFloatThousandSep("-1.000") == -1.0
  doAssert parseFloatThousandSep("-1,222.0001") == -1222.0001
  doAssert parseFloatThousandSep("3.141592653589793") == 3.141592653589793
  doAssert parseFloatThousandSep("6.283185307179586") == 6.283185307179586
  doAssert parseFloatThousandSep("2.718281828459045") == 2.718281828459045

  doAssertRaises(ValueError): discard parseFloatThousandSep(" ", {pfDotOptional})
  doAssertRaises(ValueError): discard parseFloatThousandSep(".1.", {pfLeadingDot,pfTrailingDot})
  doAssertRaises(ValueError): discard parseFloatThousandSep("1ee9", {pfDotOptional})
  doAssertRaises(ValueError): discard parseFloatThousandSep("aNa", {pfNanInf})
  doAssertRaises(ValueError): discard parseFloatThousandSep("fnI", {pfNanInf})
  doAssertRaises(ValueError): discard parseFloatThousandSep("1,000.000,000,E,+,9,0", {pfSepAnywhere})
  for s in ["1,11", "1,1", "1,0000.000", "--", "..", "1,,000", "1..000",
    "1,000000", ",1", "1,", "1.", ".1", "10,00.0", "1,000.000ee9", "1e02.2",
    "1.0e--9", "Inf", "-Inf", "+Inf", "NaN"]:
    doAssertRaises(ValueError): discard parseFloatThousandSep(s)

  doAssert parseFloatThousandSep("10,00.0", {pfSepAnywhere}) == 1000.0
  doAssert parseFloatThousandSep("0", {pfDotOptional}) == 0.0
  doAssert parseFloatThousandSep("-0", {pfDotOptional}) == -0.0
  doAssert parseFloatThousandSep("1,111", {pfDotOptional}) == 1111.0
  doAssert parseFloatThousandSep(".1", {pfLeadingDot}) == 0.1
  doAssert parseFloatThousandSep("1.", {pfTrailingDot}) == 1.0
  doAssert parseFloatThousandSep(".1", {pfLeadingDot,pfTrailingDot}) == 0.1
  doAssert parseFloatThousandSep("1.", {pfLeadingDot,pfTrailingDot}) == 1.0
  doAssert parseFloatThousandSep("1", {pfDotOptional}) == 1.0
  doAssert parseFloatThousandSep("1.0,0,0", {pfSepAnywhere}) == 1.0
  doAssert parseFloatThousandSep(".10", {pfLeadingDot}) == 0.1
  doAssert parseFloatThousandSep("10.", {pfTrailingDot}) == 10.0
  doAssert parseFloatThousandSep("10", {pfDotOptional, pfSepAnywhere}) == 10.0
  doAssert parseFloatThousandSep("1.0,0,0,0,0,0,0,0", {pfSepAnywhere}) == 1.0
  doAssert parseFloatThousandSep("0,0,0,0,0,0,0,0.1", {pfSepAnywhere}) == 0.1
  doAssert parseFloatThousandSep("1.0e9") == 1000000000.0
  doAssert parseFloatThousandSep("1.0e-9") == 1e-09
  doAssert parseFloatThousandSep("1,000.000e9") == 1000000000000.0
  doAssert parseFloatThousandSep("1e9", {pfDotOptional}) == 1000000000.0
  doAssert parseFloatThousandSep("1.0E9") == 1000000000.0
  doAssert parseFloatThousandSep("1.0E-9") == 1e-09
  doAssert parseFloatThousandSep("Inf", {pfNanInf}) == Inf
  doAssert parseFloatThousandSep("-Inf", {pfNanInf}) == -Inf
  doAssert parseFloatThousandSep("+Inf", {pfNanInf}) == +Inf
  doAssert parseFloatThousandSep("1000.000000E+90") == 1e93
  doAssert parseFloatThousandSep("-10 000 000 000.0001", sep=' ') == -10000000000.0001
  doAssert parseFloatThousandSep("-10 000 000 000,0001", sep=' ', decimalDot = ',') == -10000000000.0001
  doAssert classify(parseFloatThousandSep("NaN", {pfNanInf})) == fcNan


main()
static: main()
