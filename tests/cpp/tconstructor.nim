discard """
  targets: "cpp"
  cmd: "nim cpp $file"
  output: '''
1
0
123
0
123
___
0
777
10
123
0
777
10
123
()
'''
"""

{.emit:"""/*TYPESECTION*/
struct CppClass {
  int x;
  int y;
  CppClass(int inX, int inY) {
    this->x = inX;
    this->y = inY;
  }
  //CppClass() = default;
};
""".}

type  CppClass* {.importcpp, inheritable.} = object
  x: int32
  y: int32

proc makeCppClass(x, y: int32): CppClass {.importcpp: "CppClass(@)", constructor.}
#test globals are init with the constructor call
var shouldCompile {.used.} = makeCppClass(1, 2)

proc newCpp*[T](): ptr T {.importcpp:"new '*0()".}

#creation
type NimClassNoNarent* = object
  x: int32

proc makeNimClassNoParent(x:int32): NimClassNoNarent {. constructor.} =
  result.x = x
  discard

let nimClassNoParent = makeNimClassNoParent(1)
echo nimClassNoParent.x #acess to this just fine. Notice the field will appear last because we are dealing with constructor calls here

var nimClassNoParentDef {.used.}: NimClassNoNarent  #test has a default constructor. 

#inheritance 
type NimClass* = object of CppClass

proc makeNimClass(x:int32): NimClass {. constructor:"NimClass('1 #1) : CppClass(0, #1) ".} =
  result.x = x

#optinially define the default constructor so we get rid of the cpp warn and we can declare the obj (note: default constructor of 'tyObject_NimClass__apRyyO8cfRsZtsldq1rjKA' is implicitly deleted because base class 'CppClass' has no default constructor)
proc makeCppClass(): NimClass {. constructor: "NimClass() : CppClass(0, 0) ".} = 
  result.x = 1

let nimClass = makeNimClass(1)
var nimClassDef {.used.}: NimClass  #since we explictly defined the default constructor we can declare the obj

#bug: 22662
type
  BugClass* = object
    x: int          # Not initialized

proc makeBugClass(): BugClass {.constructor.} =
  discard

proc main =
  for i in 0 .. 1:
    var n = makeBugClass()
    echo n.x
    n.x = 123
    echo n.x

main()
#bug:
echo "___"
type
  NimClassWithDefault = object
    x: int
    y = 777
    case kind: bool = true
    of true:
      z: int = 10
    else: discard

proc makeNimClassWithDefault(): NimClassWithDefault {.constructor.} =
  result = NimClassWithDefault()

proc init =
  for i in 0 .. 1:
    var n = makeNimClassWithDefault()
    echo n.x
    echo n.y
    echo n.z
    n.x = 123
    echo n.x

init()

#tests that the ctor is not declared with nodecl. 
#nodelc also prevents the creation of a default one when another is created.
type Foo {.exportc.} = object

proc makeFoo(): Foo {.used, constructor, nodecl.} = discard

echo $Foo()

type Boo = object
proc `=copy`(dest: var Boo; src: Boo) = discard

proc makeBoo(): Boo {.constructor.} = Boo()
proc makeBoo2(): Boo  = Boo()

block:
  proc main =
    var b = makeBoo()
    var b2 = makeBoo2()

  main()

block: # bug #24658
  type
    A {.importcpp: "A".} = object

  proc a(something: ptr cint = nil): A {.cdecl, constructor, importcpp: "A(@)".}
