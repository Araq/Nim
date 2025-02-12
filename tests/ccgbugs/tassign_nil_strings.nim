discard """
  matrix: "--mm:refc"
  output: "Hello"
  ccodecheck: "\\i@'a_1 = ((NimStringDesc*) NIM_NIL)'"
"""

proc main() =
  var a = "Hello"
  echo a
  a = ""
  doAssert a.len == 0

main()
