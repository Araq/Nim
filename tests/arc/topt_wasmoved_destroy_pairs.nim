discard """
  output: ''''''
  cmd: '''nim c --gc:arc --expandArc:main --expandArc:tfor --hint:Performance:off $file'''
  nimout: '''
--expandArc: main

var
  a
  b
  x
x = f()
if cond:
  add(a):
    let blitTmp = x
    blitTmp
else:
  add(b):
    let blitTmp_1 = x
    blitTmp_1
`=destroy`(b)
`=destroy`(a)
-- end of expandArc ------------------------
--expandArc: tfor

var
  a
  b
  x
try:
  x = f()
  block :tmp:
    var i_cursor
    mixin inc
    var i_1 = 0
    block :tmp_1:
      while i_1 < 4:
        var :tmpD
        i_cursor = i_1
        if i_cursor == 2:
          return
        add(a):
          :tmpD = `=dup`(x)
          :tmpD
        inc i_1, 1
  if cond:
    add(a):
      let blitTmp = x
      `=wasMoved`(x)
      blitTmp
  else:
    add(b):
      let blitTmp_1 = x
      `=wasMoved`(x)
      blitTmp_1
finally:
  `=destroy`(x)
  `=destroy_1`(b)
  `=destroy_1`(a)
-- end of expandArc ------------------------
'''
"""

proc f(): seq[int] =
  @[1, 2, 3]

proc main(cond: bool) =
  var a, b: seq[seq[int]] = @[]
  var x = f()
  if cond:
    a.add x
  else:
    b.add x

# all paths move 'x' so no wasMoved(x); destroy(x) pair should be left in the
# AST.

main(false)


proc tfor(cond: bool) =
  var a, b: seq[seq[int]] = @[]

  var x = f()

  for i in 0 ..< 4:
    if i == 2: return
    a.add x

  if cond:
    a.add x
  else:
    b.add x

tfor(false)
