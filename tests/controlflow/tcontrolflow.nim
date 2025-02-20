discard """
  output: '''
10
true true
true false
false true
false false
i == 2
'''
"""


block tbreak:
  var
    x = false
    run = true

  while run:
    run = false
    block myblock:
      if true:
        break myblock
      echo "leaving myblock"
    x = true
  doAssert(x)

  # bug #1418
  iterator foo: int =
    for x in 0 .. 9:
      for y in [10,20,30,40,50,60,70,80,90]:
        yield x + y

  for p in foo():
    echo p
    break

  iterator permutations: int =
    yield 10

  for p in permutations():
    break

  # regression:
  proc main =
    for x in [true, false]:
      for y in [true, false]:
        echo x, " ", y

  main()



block tcontinue:
  var i = 0
  while i < 400:

    if i == 10: break
    elif i == 3:
      inc i
      continue
    inc i

  var f = "failure"
  var j = 0
  while j < 300:
    for x in 0..34:
      if j < 300: continue
      if x == 10:
        echo "failure: should never happen"
        break
    f = "came here"
    break

  if i == 10:
    doAssert f == "came here"
  else:
    echo "failure"



block tnestif:
  var
      x, y: int
  x = 2
  if x == 0:
      write(stdout, "i == 0")
      if y == 0:
          writeLine(stdout, x)
      else:
          writeLine(stdout, y)
  elif x == 1:
      writeLine(stdout, "i == 1")
  elif x == 2:
      writeLine(stdout, "i == 2")
  else:
      writeLine(stdout, "looks like Python")
  #OUT i == 2

# bug https://github.com/nim-lang/RFCs/issues/451
for i in 1..2: # works
  break

block: # works
  for i in 1..2:
    break

block: # works
  block:
    discard 12 + 3
  for i in 1..2:
    break

block named: # works
  if true:
    break named
  doAssert false, "not reached"

block:
  iterator p(a: openArray[char]): int =
    if a.len != 0:
      if a[0] != '/':
        discard
  for t in p(""): discard
