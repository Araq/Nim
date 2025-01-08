discard """
  targets: "c"
  output: '''
1 3 6 11 20 foo
foo88
23 24foo 88
18
18
99
99
99
99 99
99 99
12 99 99
12 99 99
success
@[1, 2, 5]
click at 10,20
lost focus 1
lost focus 2
registered handler for UserEvent 1
registered handler for UserEvent 2
registered handler for UserEvent 3
registered handler for UserEvent 4
asdas
processClient end
false
baro0
foo88
23 24foo 88
foo88
23 24foo 88
11
@[1, 10, 45, 120, 210, 252, 210, 120, 45, 10, 1]
'''
joinable: false
"""


block tclosure:
  proc map(n: var openArray[int], fn: proc (x: int): int {.closure}) =
    for i in 0..n.len-1: n[i] = fn(n[i])

  proc each(n: openArray[int], fn: proc(x: int) {.closure.}) =
    for i in 0..n.len-1:
      fn(n[i])

  var myData: array[0..4, int] = [0, 1, 2, 3, 4]

  proc testA() =
    var p = 0
    map(myData, proc (x: int): int =
                  result = x + 1 shl (proc (y: int): int =
                    return y + p
                  )(0)
                  inc(p))

  testA()

  myData.each do (x: int):
    write(stdout, x)
    write(stdout, " ")

  #OUT 2 4 6 8 10

  # bug #5015

  type Mutator = proc(matched: string): string {.noSideEffect, gcsafe.}

  proc putMutated(
      MutatorCount: static[int],
      mTable: static[array[MutatorCount, Mutator]], input: string) =
    for i in 0..<MutatorCount: echo mTable[i](input)

  proc mutator0(matched: string): string =
      "foo"

  const
    mTable = [Mutator(mutator0)]

  putMutated(1, mTable, "foo")



block tclosure0:
  when true:
    # test simple closure within dummy 'main':
    proc dummy =
      proc main2(param: int) =
        var fooB = 23
        proc outer(outerParam: string) =
          var outerVar = 88
          echo outerParam, outerVar
          proc inner() =
            block Test:
              echo fooB, " ", param, outerParam, " ", outerVar
          inner()
        outer("foo")
      main2(24)

    dummy()

  when true:
    proc outer2(x:int) : proc(y:int):int =   # curry-ed application
        return proc(y:int):int = x*y

    var fn = outer2(6)  # the closure
    echo fn(3)   # it works

    var rawP = fn.rawProc()
    var rawE = fn.rawEnv()

    # A type to cast the function pointer into a nimcall
    type TimesClosure = proc(a: int, x: pointer): int {.nimcall.}

    # Call the function with its closure
    echo cast[TimesClosure](rawP)(3, rawE)

  when true:
    proc outer =
      var x, y: int = 99
      proc innerA = echo x
      proc innerB =
        echo y
        innerA()

      innerA()
      innerB()

    outer()

  when true:
    proc indirectDep =
      var x, y: int = 99
      proc innerA = echo x, " ", y
      proc innerB =
        innerA()

      innerA()
      innerB()

    indirectDep()

  when true:
    proc needlessIndirection =
      var x, y: int = 99
      proc indirection =
        var z = 12
        proc innerA = echo z, " ", x, " ", y
        proc innerB =
          innerA()

        innerA()
        innerB()
      indirection()

    needlessIndirection()






block tclosure3:
  proc main =
    const n = 30
    for iterations in 0..10_000:
      var s: seq[proc(): string {.closure.}] = @[]
      for i in 0 .. n-1:
        (proc () =
          let ii = i
          s.add(proc(): string = return $(ii*ii)))()
      for i in 0 .. n-1:
        let val = s[i]()
        if val != $(i*i): echo "bug  ", val

      if getOccupiedMem() > 5000_000: quit("still a leak!")
    echo "success"

  main()



import json, tables, sequtils
block tclosure4:
  proc run(json_params: OrderedTable) =
    let json_elems = json_params["files"].elems
    # These fail compilation.
    var files = map(json_elems, proc (x: JsonNode): string = x.str)

  let text = """{"files": ["a", "b", "c"]}"""
  run((text.parseJson).fields)



import sugar
block inference3304:
  type
    List[T] = ref object
      val: T

  proc foo[T](l: List[T]): seq[int] =
    @[1,2,3,5].filter(x => x != l.val)

  echo(foo(List[int](val: 3)))



block tcodegenerr1923:
  type
    Foo[M] = proc() : M

  proc bar[M](f : Foo[M]) =
    discard f()

  proc baz() : int = 42

  bar(baz)



block doNotation:
  type
    Button = object
    Event = object
      x, y: int

  proc onClick(x: Button, handler: proc(x: Event)) =
    handler(Event(x: 10, y: 20))

  proc onFocusLost(x: Button, handler: proc()) =
    handler()

  proc onUserEvent(x: Button, eventName: string, handler: proc) =
    echo "registered handler for ", eventName

  var b = Button()

  b.onClick do (e: Event):
    echo "click at ", e.x, ",", e.y

  b.onFocusLost do ():
    echo "lost focus 1"

  b.onFocusLost do ():
    echo "lost focus 2"

  b.onUserEvent("UserEvent 1") do ():
    discard

  onUserEvent(b, "UserEvent 2") do ():
    discard

  b.onUserEvent("UserEvent 3") do ():
    discard

  b.onUserEvent("UserEvent 4", () => echo "event 4")



import tables
block fib50:
  proc memoize(f: proc (a: int64): int64): proc (a: int64): int64 =
      var previous = initTable[int64, int64]()
      return proc(i: int64): int64 =
          if not previous.hasKey i:
              previous[i] = f(i)
          return previous[i]

  var fib: proc(a: int64): int64

  fib = memoize(proc (i: int64): int64 =
      if i == 0 or i == 1:
          return 1
      return fib(i-1) + fib(i-2)
  )

  doAssert fib(50) == 20365011074



block tflatmap:
  # bug #3995
  type
    RNG = tuple[]
    Rand[A] = (RNG) -> (A, RNG)

  proc nextInt(r: RNG): (int, RNG) =
    (1, ())

  proc flatMap[A,B](f: Rand[A], g: A -> Rand[B]): Rand[B] =
    (rng: RNG) => (
      let (a, rng2) = f(rng);
      let g1 = g(a);
      g1(rng2)
    )

  proc map[A,B](s: Rand[A], f: A -> B): Rand[B] =
    let g: A -> Rand[B] = (a: A) => ((rng: RNG) => (f(a), rng))
    flatMap(s, g)

  discard nextInt.map(i => i - i mod 2)



block tforum:
  type
    PAsyncHttpServer = ref object
      value: string
    PFutureBase = ref object
      callback: proc () {.closure.}
      value: string
      failed: bool

  proc accept(server: PAsyncHttpServer): PFutureBase =
    new(result)
    result.callback = proc () =
      discard
    server.value = "hahaha"

  proc processClient(): PFutureBase =
    new(result)

  proc serve(server: PAsyncHttpServer): PFutureBase =
    iterator serveIter(): PFutureBase {.closure.} =
      echo server.value
      while true:
        var acceptAddrFut = server.accept()
        yield acceptAddrFut
        var fut = acceptAddrFut.value

        var f = processClient()
        f.callback =
          proc () =
            echo("processClient end")
            echo(f.failed)
        yield f
    var x = serveIter
    for i in 0 .. 1:
      result = x()
      result.callback()

  discard serve(PAsyncHttpServer(value: "asdas"))



block futclosure2138:
  proc any[T](list: varargs[T], pred: (T) -> bool): bool =
    for item in list:
        if pred(item):
            result = true
            break

  proc contains(s: string, words: varargs[string]): bool =
    any(words, (word) => s.contains(word))



block tinterf:
  type
    ITest = tuple[
      setter: proc(v: int) {.closure.},
      getter1: proc(): int {.closure.},
      getter2: proc(): int {.closure.}]

  proc getInterf(): ITest =
    var shared1, shared2: int

    return (setter: proc (x: int) =
              shared1 = x
              shared2 = x + 10,
            getter1: proc (): int = result = shared1,
            getter2: proc (): int = return shared2)

  var i = getInterf()
  i.setter(56)

  doAssert i.getter1() == 56
  doAssert i.getter2() == 66



block tjester:
  type
    Future[T] = ref object
      data: T
      callback: proc () {.closure.}

  proc cbOuter(response: string) {.discardable.} =
    iterator cbIter(): Future[int] {.closure.} =
      for i in 0..7:
        proc foo(): int =
          iterator fooIter(): Future[int] {.closure.} =
            echo response, i
            yield Future[int](data: 17)
          var iterVar = fooIter
          iterVar().data
        yield Future[int](data: foo())

    var iterVar2 = cbIter
    proc cb2() {.closure.} =
      try:
        if not finished(iterVar2):
          let next = iterVar2()
          if next != nil:
            next.callback = cb2
      except:
        echo "WTF"
    cb2()

  cbOuter "baro"



block tnamedparamanonproc:
  type
    PButton = ref object
    TButtonClicked = proc(button: PButton) {.nimcall.}

  proc newButton(onClick: TButtonClicked) =
    discard

  proc main() =
    newButton(onClick = proc(b: PButton) =
      var requestomat = 12
      )

  main()



block tnestedclosure:
  proc main(param: int) =
    var foo = 23
    proc outer(outerParam: string) =
      var outerVar = 88
      echo outerParam, outerVar
      proc inner() =
        block Test:
          echo foo, " ", param, outerParam, " ", outerVar
      inner()
    outer("foo")

  # test simple closure within dummy 'main':
  proc dummy =
    proc main2(param: int) =
      var fooB = 23
      proc outer(outerParam: string) =
        var outerVar = 88
        echo outerParam, outerVar
        proc inner() =
          block Test:
            echo fooB, " ", param, outerParam, " ", outerVar
        inner()
      outer("foo")
    main2(24)

  dummy()

  main(24)

  # Jester + async triggered this bug:
  proc cbOuter() =
    var response = "hohoho"
    block:
      proc cbIter() =
        block:
          proc fooIter() =
            doAssert response == "hohoho"
          fooIter()
      cbIter()
  cbOuter()



block tnestedproc:
  proc p(x, y: int): int =
    result = x + y

  echo p((proc (): int =
            var x = 7
            return x)(),
         (proc (): int = return 4)())



block tnoclosure:
  proc pascal(n: int) =
    var row = @[1]
    for r in 1..n:
      row = zip(row & @[0], @[0] & row).mapIt(it[0] + it[1])
    echo row
  pascal(10)

block: # bug #22297
  iterator f: int {.closure.} =
    try:
      yield 12
    finally:
      return 14

  let s = f
  doAssert s() == 12
  doAssert s() == 14

# bug #19984
import std/[sets]

block:
  type
    i8 = int8
    seq8 = seq[int8]
    Cell    = seq8
    NODE    = tuple[d_in:int8,Strong:bool,link:Cell]
    PATH    = seq[NODE]

  var
    max_level : int

  var
    Seen:HashSet[NODE]
    path:PATH

  iterator Loop_next(strong_link:bool, d_in:int8, node:Cell, head:int8, 
                Seen:var HashSet[NODE], path: var PATH, level:int ) : PATH {.closure.} = 

    if level > max_level :
      return
    let GNode= len(node) > 1   # without this line, the code compiles
    
    var
      rt, ct, st : seq8
      column_type : bool

  #[ with this code commented out the compiler error does not occurs ]#
      
    st= filter(st, proc(x:int8) : bool = x notin node)
    if column_type :
      rt= @[]
      ct= filter(ct, proc(x:int8) : bool = x notin node)
    else :  # row type
      rt= filter(rt, proc(x:int8) : bool = x notin node)
      ct= @[]

  #[]#
  iterator Nice_Loop( ) : PATH {.closure.} =
    for cell in 0i8..80i8 :
      let head= cell

      for pt in  Loop_next(true,0.i8,@[cell], head,Seen,path,0) :
        yield pt

  for P in  Nice_Loop() :
    continue
