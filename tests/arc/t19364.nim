discard """
  cmd: '''nim c --gc:arc --expandArc:fooLeaks $file'''
  nimout: '''
--expandArc: fooLeaks

var
  tmpTuple_cursor
  a_cursor
  b_cursor
  c_cursor
tmpTuple_cursor = refTuple
a_cursor = tmpTuple_cursor[0]
b_cursor = tmpTuple_cursor[1]
c_cursor = tmpTuple_cursor[2]
-- end of expandArc ------------------------
'''
"""

func fooLeaks(refTuple: tuple[a,
                              b,
                              c: seq[float]]): float =
  result = 0.0
  let (a, b, c) = refTuple

let refset = (a: newSeq[float](25_000_000),
              b: newSeq[float](25_000_000),
              c: newSeq[float](25_000_000))

var res = newSeq[float](1_000_000)
for i in 0 .. res.high:
  res[i] = fooLeaks(refset)
