discard """
  errormsg: "conversion from int literal(2) to range 0..1(int) is invalid"
  line: 18
"""
block:
  try:
    let a = @[1,2]
    echo a[3]
  except Exception as e:
    doAssert e.msg == "index 3 not in 0 .. 1"
      # note: this is not being tested, because the CT error happens before

block:
  type TTestArr = array[0..1, int16]
  var f: TTestArr
  f[0] = 30
  f[1] = 40
  f[2] = 50
  f[3] = 60

  echo(repr(f))
