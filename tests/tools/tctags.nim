discard """
  cmd: '''nim ctags --stdout $file'''
  nimout: '''
Foo
hello
`$$`
'''
  action: "compile"
"""

type
  Foo = object

proc hello() = discard

proc `$`(x: Foo): string = "foo"
