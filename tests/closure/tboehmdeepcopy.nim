discard """
  cmd: "nim c --gc:boehm $options $file"
  output: '''meep'''
  disabled: "windows"
  disabled: osx
"""

proc callit(it: proc ()) =
  it()

proc main =
  var outer = "meep"
  proc x =
    echo outer
  var y: proc()
  deepCopy(y, x)
  callit(y)

main()
