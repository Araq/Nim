discard """
disabled: "arm64"
cmd: "nim c --mm:arc -u:nimPreviewNonVarDestructor $file"
output: "y"
"""

# TODO: fixme: investigate why it failed with non-var destructors

{.passC: "-march=native".}

proc isAlignedCheck(p: pointer, alignment: int) = 
  doAssert (cast[uint](p) and uint(alignment - 1)) == 0

proc isAlignedCheck[T](p: ref T, alignment: int) = 
  isAlignedCheck(cast[pointer](p), alignment)

type
  m256d {.importc: "__m256d", header: "immintrin.h".} = object

proc set1(x: float): m256d {.importc: "_mm256_set1_pd", header: "immintrin.h".}
func `+`(a,b: m256d): m256d {.importc: "_mm256_add_pd", header: "immintrin.h".}
proc `$`(a: m256d): string =  
  result = $(cast[ptr float](a.addr)[])


var res: seq[seq[m256d]]

for _ in 1..1000:
  var x = newSeq[m256d](1)
  x[0] = set1(1.0) # test if operation causes segfault
  isAlignedCheck(x[0].addr, alignof(m256d))
  res.add x

var res2: seq[m256d]
for i in 1..10000:
  res2.setLen(res2.len + 1) # check if realloc works
  isAlignedCheck(res2[0].addr, alignof(m256d))  

proc lambdaGen(a, b: float, z: ref m256d) : auto =
  var x1 = new(m256d)
  var x2 = new(m256d)
  isAlignedCheck(x1, alignof(m256d))
  isAlignedCheck(x2, alignof(m256d))
  x1[] = set1(2.0 + a)  
  x2[] = set1(-23.0 - b)
  let capturingLambda = proc(x: ref m256d): ref m256d =
    var cc = new(m256d)
    var bb = new(m256d)
    isAlignedCheck(x1, alignof(m256d))
    isAlignedCheck(x2, alignof(m256d))
    isAlignedCheck(cc, alignof(m256d))
    isAlignedCheck(bb, alignof(m256d))
    isAlignedCheck(z, alignof(m256d))
        
    cc[] = x1[] + x1[] + z[]
    bb[] = x2[] + set1(12.5) + z[]
    
    result = new(m256d)
    isAlignedCheck(result, alignof(m256d))
    result[] = cc[] + bb[] + x[]
    
  return capturingLambda

var xx = new(m256d)
xx[] = set1(10)
isAlignedCheck(xx, alignOf(m256d))

let f1 = lambdaGen(2.0 , 2.221, xx)
let f2 = lambdaGen(-1.226 , 3.5, xx)
isAlignedCheck(f1(xx), alignOf(m256d))
isAlignedCheck(f2(xx), alignOf(m256d))


#-----------------------------------------------------------------------------

type
  MyAligned = object of RootObj
    a{.align: 128.}: float


var f: MyAligned
isAlignedCheck(f.addr, MyAligned.alignOf)

var fref = new(MyAligned)
isAlignedCheck(fref, MyAligned.alignOf)

var fs: seq[MyAligned]
var fr: seq[RootRef]

for i in 0..1000:
  fs.add MyAligned()
  isAlignedCheck(fs[^1].addr, MyAligned.alignOf)
  fs[^1].a = i.float

  fr.add new(MyAligned)
  isAlignedCheck(fr[^1], MyAligned.alignOf)
  ((ref MyAligned)fr[^1])[].a = i.float

for i in 0..1000:
  doAssert(fs[i].a == i.float)
  doAssert(((ref MyAligned)fr[i]).a == i.float)


proc lambdaTest2(a: MyAligned, z: ref MyAligned): auto =
  var x1: MyAligned = default(MyAligned)
  x1.a = a.a + z.a  
  var x2: MyAligned = default(MyAligned)
  x2.a = a.a - z.a
  let capturingLambda = proc(x: MyAligned): MyAligned =
    result = default(MyAligned)
    var cc: MyAligned = default(MyAligned)
    var bb: MyAligned = default(MyAligned)
    isAlignedCheck(x1.addr, MyAligned.alignOf)
    isAlignedCheck(x2.addr, MyAligned.alignOf)
    isAlignedCheck(cc.addr, MyAligned.alignOf)
    isAlignedCheck(bb.addr, MyAligned.alignOf)
    isAlignedCheck(z, MyAligned.alignOf)

    cc.a = x1.a + x1.a + z.a
    bb.a = x2.a - z.a
    
    isAlignedCheck(result.addr, MyAligned.alignOf)
    result.a = cc.a + bb.a + x2.a

  return capturingLambda


let q1 = lambdaTest2(MyAligned(a: 1.0), (ref MyAligned)(a: 2.0))
let q2 = lambdaTest2(MyAligned( a: -1.0), (ref MyAligned)(a: -2.0))

isAlignedCheck(rawEnv(q1), MyAligned.alignOf)
isAlignedCheck(rawEnv(q2), MyAligned.alignOf)
discard q1(MyAligned(a: 1.0))
discard q2(MyAligned(a: -1.0))


#-----------------------------------------------------------------------------

block:
  var s: seq[seq[MyAligned]]
  for len in 0..128:
    s.add newSeq[MyAligned](len)
    for i in 0..<len:
      s[^1][i] = MyAligned(a: 1.0)

    if len > 0:
      isAlignedCheck(s[^1][0].addr, MyAligned.alignOf)
  
echo "y"
