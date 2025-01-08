discard """
  targets: "c cpp"
  matrix: "--mm:arc; --mm:orc"
"""

block:
  type
    PublicKey = array[32, uint8]
    PrivateKey = array[64, uint8]

  proc ed25519_create_keypair(publicKey: ptr PublicKey; privateKey: ptr PrivateKey) =
    publicKey[][0] = uint8(88)

  type
    KeyPair = object
      public: PublicKey
      private: PrivateKey

  proc initKeyPair(): KeyPair =
    result = KeyPair()
    ed25519_create_keypair(result.public.addr, result.private.addr)

  let keys = initKeyPair()
  doAssert keys.public[0] == 88


template minIndexByIt: untyped =
  var other = 3
  other

proc bug20303() =
  var hlibs = @["hello", "world", "how", "are", "you"]
  let res = hlibs[minIndexByIt()]
  doAssert res == "are"

bug20303()

proc main() = # todo bug with templates
  block: # bug #11267
    var a: seq[char] = block: @[]
    doAssert a == @[]
    # 2
    proc b: seq[string] =
      discard
      @[]
    doAssert b() == @[]
static: main()
main()


type Obj = tuple
  value: int
  arr: seq[int]

proc bug(): seq[Obj] =
  result = @[]
  result.add (value: 0, arr: @[])
  result[^1].value = 1
  result[^1].arr.add 1

# bug #19990
let s = bug()
doAssert s[0] == (value: 1, arr: @[1])

block: # bug #21974
  type Test[T] = ref object
      values : seq[T]
      counter: int

  proc newTest[T](): Test[T] =
      result         = new(Test[T])
      result.values  = newSeq[T](16)
      result.counter = 0

  proc push[T](self: Test[T], value: T) =
      self.counter += 1
      if self.counter >= self.values.len:
          self.values.setLen(self.values.len * 2)
      self.values[self.counter - 1] = value

  proc pop[T](self: Test[T]): T =
      result         = self.values[0]
      self.values[0] = self.values[self.counter - 1] # <--- This line
      self.counter  -= 1


  type X = tuple
      priority: int
      value   : string

  var a = newTest[X]()
  a.push((1, "One"))
  doAssert a.pop.value == "One"

# bug #21987

type
  EmbeddedImage* = distinct Image
  Image = object
    len: int

proc imageCopy*(image: Image): Image {.nodestroy.}

proc `=destroy`*(x: var Image) =
  discard
proc `=sink`*(dest: var Image; source: Image) =
  `=destroy`(dest)
  wasMoved(dest)

proc `=dup`*(source: Image): Image {.nodestroy.} =
  result = imageCopy(source)

proc `=copy`*(dest: var Image; source: Image) =
  dest = imageCopy(source) # calls =sink implicitly

proc `=destroy`*(x: var EmbeddedImage) = discard

proc `=dup`*(source: EmbeddedImage): EmbeddedImage {.nodestroy.} = source

proc `=copy`*(dest: var EmbeddedImage; source: EmbeddedImage) {.nodestroy.} =
  dest = source

proc imageCopy*(image: Image): Image =
  result = image

proc main2 =
  block:
    var a = Image(len: 2).EmbeddedImage
    var b = Image(len: 1).EmbeddedImage
    b = a
    doAssert Image(a).len == 2
    doAssert Image(b).len == 2

  block:
    var a = Image(len: 2)
    var b = Image(len: 1)
    b = a
    doAssert a.len == 2
    doAssert b.len == 0

main2()

block:
  type
    TestObj = object of RootObj
      name: string
    
    TestSubObj = object of TestObj
      objname: string

  proc `=destroy`(x: TestObj) =
    `=destroy`(x.name)

  proc `=destroy`(x: TestSubObj) =
    `=destroy`(x.objname)
    `=destroy`(TestObj(x))

  proc testCase() =
    let t1 {.used.} = TestSubObj(objname: "tso1", name: "to1")

  proc main() =
    testCase()

  main()

block: # bug #23858
  type Object = object
    a: int
    b: ref int
  var x = 0
  proc fn(): auto {.cdecl.} =
    inc x
    return Object()
  discard fn()
  doAssert x == 1

block: # bug #24147
  type
    O = object of RootObj
      val: string
    OO = object of O

  proc `=copy`(dest: var O, src: O) =
      dest.val = src.val

  let oo = OO(val: "hello world")
  var ooCopy : OO
  `=copy`(ooCopy, oo)
