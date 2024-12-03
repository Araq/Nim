discard """
  targets: "cpp"
  cmd: "nim cpp $file"
  output: '''
2
false
hello foo
hello boo
hello boo
FunctorSupport!
static
static
destructing
destructing
'''
"""
proc print(s: cstring) {.importcpp:"printf(@)", header:"<stdio.h>".}

type
  Doo  {.exportc.} = object
    test: int

proc memberProc(f: Doo) {.exportc, member.} = 
  echo $f.test

proc destructor(f: Doo) {.member: "~'1()", used.} = 
  print "destructing\n"

proc `==`(self, other: Doo): bool {.member:"operator==('2 const & #2) const -> '0"} = 
  self.test == other.test

let doo = Doo(test: 2)
doo.memberProc()
echo doo == Doo(test: 1)

#virtual
proc newCpp*[T](): ptr T {.importcpp:"new '*0()".}
type 
  Foo {.exportc.} = object of RootObj
  FooPtr = ptr Foo
  Boo = object of Foo
  BooPtr = ptr Boo

proc salute(self: FooPtr) {.member: "virtual $1()".} = 
  echo "hello foo"

proc salute(self: BooPtr) {.member: "virtual $1()".} =
  echo "hello boo"

let foo = newCpp[Foo]()
let boo = newCpp[Boo]()
let booAsFoo = cast[FooPtr](newCpp[Boo]())  

foo.salute()
boo.salute()
booAsFoo.salute()

type
  NimFunctor = object
    discard
proc invoke(f: NimFunctor, n:int) {.member:"operator ()('2 #2)" .} = 
  echo "FunctorSupport!"

{.experimental: "callOperator".}
proc `()`(f: NimFunctor, n:int) {.importcpp:"#(@)" .} 
NimFunctor()(1)

#static
proc staticProc(self: FooPtr) {.member: "static $1()".} = 
  echo "static"

proc importedStaticProc() {.importcpp:"Foo::staticProc()".}

foo.staticProc()
importedStaticProc()
