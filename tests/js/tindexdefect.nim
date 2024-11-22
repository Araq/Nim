discard """
  outputsub: "unhandled exception: index 10000 not in 0 .. 0 [IndexDefect]"
  exitcode: 1
  joinable: false
"""

var s = ['a']
let i = 10000
let z = s[i] == 'a'
echo z
