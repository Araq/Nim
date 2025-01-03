discard """
  errormsg: "conversion from int literal(3) to range 0..1(int) is invalid"
  line: 9
"""

# Note: merge in tinvalidarrayaccess.nim pending https://github.com/nim-lang/Nim/issues/9906

let a = [1,2]
echo a[3]

