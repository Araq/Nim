discard """
  errormsg: "cannot convert 256 to int8"
  line: 9
"""

# issue #23177

var x: int8
x = 256
echo x # 0
