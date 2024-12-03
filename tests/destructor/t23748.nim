discard """
  matrix: "--gc:refc; --gc:arc"
  output: '''
hello 42
hello 42
len = 2
'''
"""

# bug #23748

type
  O = ref object
    s: string
    cb: seq[proc()]

proc push1(o: O, i: int) =
  let o = o
  echo o.s, " ", i
  o.cb.add(proc() = echo o.s, " ", i)

proc push2(o: O, i: int) =
  let o = o
  echo o.s, " ", i
  proc p() = echo o.s, " ", i
  o.cb.add(p)

let o = O(s: "hello", cb: @[])
o.push1(42)
o.push2(42)
echo "len = ", o.cb.len
