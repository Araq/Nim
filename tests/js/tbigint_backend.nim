proc jsTypeOf*[T](x: T): cstring {.importjs: "typeof(#)".}
  ## Returns the name of the JsObject's JavaScript type as a cstring.
  # xxx replace jsffi.jsTypeOf with this definition and add tests

type JsBigIntImpl {.importc: "bigint".} = int
type JsBigInt = distinct JsBigIntImpl

doAssert JsBigInt isnot int
func big*(integer: SomeInteger): JsBigInt {.importjs: "BigInt(#)".}
func big*(integer: cstring): JsBigInt {.importjs: "BigInt(#)".}
func `<=`*(x, y: JsBigInt): bool {.importjs: "(# $1 #)".}
func `==`*(x, y: JsBigInt): bool {.importjs: "(# === #)".}
func inc*(x: var JsBigInt) {.importjs: "[#][0][0]++".}
func inc2*(x: var JsBigInt) {.importjs: "#++".}
func toString*(this: JsBigInt): cstring {.importjs: "#.toString()".}
func `$`*(this: JsBigInt): string =
  $toString(this)

let z1=big"10"
let z2=big"15"
doAssert z1 == big"10"
doAssert z1 == z1
doAssert z1 != z2
var s: seq[cstring]
for i in z1 .. z2:
  s.add $i
doAssert s == @["10".cstring, "11", "12", "13", "14", "15"]
block:
  var a=big"3"
  a.inc
  doAssert a == big"4"
var z: JsBigInt
doAssert $z == "0"
doAssert z.jsTypeOf == "bigint" # would fail without codegen change
doAssert z != big(1)
doAssert z == big"0" # ditto
