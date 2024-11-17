block: # has generic field
  type
    Foo[T] = object of RootObj
      x: T
    Bar = object of Foo[int]

  proc foo(x: typedesc[Foo]) = discard

  foo(Bar)

block: # no generic field
  type
    Foo[T] = object of RootObj
    Bar = object of Foo[int]

  proc foo(x: typedesc[Foo]) = discard

  foo(Bar)

block: # issue #22445
  type
    MyType = ref object of RootObj
    MyChild[T] = ref object of MyType
    
  var curr = MyChild[int]()
  doAssert not(curr of MyChild[float])
  doAssert curr of MyChild[int]
  doAssert curr of MyType

block: # issue #18861, original case
  type
    Connection = ref ConnectionObj
    ConnectionObj = object of RootObj
    
    ConnectionRequest = ref ConnectionRequestObj
    ConnectionRequestObj = object of RootObj
      redis: Connection
    
    ConnectionStrBool = distinct bool
    
    ConnectionRequestT[T] = ref object of ConnectionRequest
    
    ConnectionSetRequest = ref object of ConnectionRequestT[ConnectionStrBool]
      keepttl: bool

  proc execute(req: ConnectionRequest): bool = discard
  proc execute(req: ConnectionRequestT[bool]): bool = discard
  proc execute(req: ConnectionRequestT[ConnectionStrBool]): bool = discard

  proc testExecute() =
    var connection: ConnectionSetRequest
    let repl = connection.execute()
