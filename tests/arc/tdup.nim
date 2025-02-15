discard """
  cmd: "nim c --mm:arc --expandArc:foo --hints:off $file"
  nimout: '''
--expandArc: foo

var
  x
  :tmpD
  s
  :tmpD_1
x = Ref(id: 8)
inc:
  :tmpD = `=dup`(x)
  :tmpD
inc:
  let blitTmp = x
  blitTmp
var id_1 = 777
s = RefCustom(id_2: addr(id_1))
inc_1 :
  :tmpD_1 = `=dup_1`(s)
  :tmpD_1
inc_1 :
  let blitTmp_1 = s
  blitTmp_1
-- end of expandArc ------------------------
'''
"""

type
  Ref = ref object
    id: int

  RefCustom = object
    id: ptr int

proc `=dup`(x: RefCustom): RefCustom =
  result = RefCustom()
  result.id = x.id

proc inc(x: sink Ref) =
  inc x.id

proc inc(x: sink RefCustom) =
  inc x.id[]


proc foo =
  var x = Ref(id: 8)
  inc(x)
  inc(x)
  var id = 777
  var s = RefCustom(id: addr id)
  inc s
  inc s

foo()

proc foo2 =
  var x = Ref(id: 8)
  inc(x)
  doAssert x.id == 9
  inc(x)
  doAssert x.id == 10
  var id = 777
  var s = RefCustom(id: addr id)
  inc s
  doAssert s.id[] == 778
  inc s
  doAssert s.id[] == 779

foo2()
