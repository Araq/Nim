discard """
  cmd: "nim cpp $file"
  output: '''
Ctor Foo(-1)
Destory Foo(-1)
Ctor Foo(-1)
Destory Foo(-1)
Ctor Foo(-1)
Destory Foo(-1)
Foo.x = 1
Foo.x = 2
Foo.x = -1
'''
"""

type
  Foo {.importcpp, header: "23962.h".} = object
    x: cint

proc print(f: Foo) {.importcpp.}

#also tests the right constructor is used
proc makeFoo(x: int32 = -1): Foo {.importcpp:"Foo(#)", constructor.} 

proc test =
  var xs = newSeq[Foo](3)
  xs[0].x = 1
  xs[1].x = 2
  for x in xs:
    x.print

test()