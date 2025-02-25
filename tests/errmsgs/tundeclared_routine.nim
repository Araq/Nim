discard """
cmd: '''nim check --hints:off $file'''
action: reject
nimout: '''
tundeclared_routine.nim(24, 17) Error: attempting to call routine: 'myiter'
  found tundeclared_routine.myiter(a: string) [iterator declared in tundeclared_routine.nim(22, 12)]
  found tundeclared_routine.myiter() [iterator declared in tundeclared_routine.nim(23, 12)]
tundeclared_routine.nim(29, 28) Error: invalid pragma: myPragma
tundeclared_routine.nim(36, 13) Error: undeclared field: 'bar3' for type tundeclared_routine.Foo [type declared in tundeclared_routine.nim(33, 8)]
  found tundeclared_routine.bar3() [iterator declared in tundeclared_routine.nim(35, 12)]
tundeclared_routine.nim(41, 13) Error: undeclared field: 'bar4' for type tundeclared_routine.Foo [type declared in tundeclared_routine.nim(39, 8)]
tundeclared_routine.nim(44, 11) Error: undeclared identifier: 'bad5'
'''
"""





# line 20
block:
  iterator myiter(a:string): int = discard
  iterator myiter(): int = discard
  let a = myiter(1)

block:
  proc myPragma():int=discard
  iterator myPragma():int=discard
  proc myfun(a:int): int {.myPragma.} = 1
  let a = myfun(1)

block:
  type Foo = object
  var a = Foo()
  iterator bar3():int=discard
  let a2 = a.bar3

block:
  type Foo = object
  var a = Foo()
  let a2 = a.bar4

block:
  let a = bad5(1)
