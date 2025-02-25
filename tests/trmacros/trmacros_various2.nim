discard """
output: '''
0
-2
48
hel
lo
my awesome concat
'''
"""


block tnoalias2:
  # bug #206
  template optimizeOut{testFunc(a, b)}(a: int, b: int{alias}): untyped = 0

  proc testFunc(a, b: int): int = result = a + b
  var testVar = 1
  echo testFunc(testVar, testVar)


  template ex{a = b + c}(a : int{noalias}, b, c : int) =
    a = b
    inc a, b
    echo "came here"

  var x = 5
  x = x + x



block tpartial:
  proc p(x, y: int; cond: bool): int =
    result = if cond: x + y else: x - y

  template optPTrue{p(x, y, true)}(x, y): untyped = x - y
  template optPFalse{p(x, y, false)}(x, y): untyped = x + y

  echo p(2, 4, true)



block tpatterns:
  template optZero{x+x}(x: int): int = x*3
  template andthen{`*`(x,3)}(x: int): int = x*4
  template optSubstr1{x = substr(x, a, b)}(x: string, a, b: int) = setlen(x, b+1)

  var y = 12
  echo y+y

  var s: array[0..2, string]
  s[0] = "hello"
  s[0] = substr(s[0], 0, 2)

  echo s[0]

  # Test varargs matching
  proc someVarargProc(k: varargs[string]) = doAssert(false) # this should not get called
  template someVarargProcSingleArg{someVarargProc([a])}(a: string) = echo a
  someVarargProc("lo")



block tstar:
  var
    calls = 0

  proc `&&`(s: varargs[string]): string =
    result = s[0]
    for i in 1..len(s)-1: result.add s[i]
    inc calls

  template optConc{ `&&` * a }(a: string): string =
    {.noRewrite.}:
      &&a

  let space = " "
  echo "my" && (space & "awe" && "some " ) && "concat"

  # check that it's been optimized properly:
  doAssert calls == 1

# bug #7524
template in_to_out(typIn, typOut: typedesc) =
  proc to_out(x: typIn{lit}): typOut = result = ord(x)

# Generating the proc via template doesn't work
in_to_out(char, int)

# This works
proc to_out2(x: char{lit}): int = result = ord(x)
