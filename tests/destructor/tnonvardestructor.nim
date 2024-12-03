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

proc `=destroy`*(x: Image) =
  discard

proc `=sink`*(dest: var Image; source: Image) =
  `=destroy`(dest)
  wasMoved(dest)

proc `=dup`*(source: Image): Image {.nodestroy.} =
  result = imageCopy(source)

proc `=copy`*(dest: var Image; source: Image) =
  dest = imageCopy(source) # calls =sink implicitly

proc `=destroy`*(x: EmbeddedImage) = discard

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

type
  Edge = object
    neighbor {.cursor.}: Node

  NodeObj = object
    neighbors: seq[Edge]
    label: string
    visited: bool
  Node = ref NodeObj

  Graph = object
    nodes: seq[Node]

proc `=destroy`(x: NodeObj) =
  `=destroy`(x.neighbors)
  `=destroy`(x.label)

proc addNode(self: var Graph; label: string): Node =
  self.nodes.add(Node(label: label))
  result = self.nodes[^1]

proc addEdge(self: Graph; source, neighbor: Node) =
  source.neighbors.add(Edge(neighbor: neighbor))

block:
  proc main =
    var graph: Graph
    let nodeA = graph.addNode("a")
    let nodeB = graph.addNode("b")
    let nodeC = graph.addNode("c")

    graph.addEdge(nodeA, neighbor = nodeB)
    graph.addEdge(nodeA, neighbor = nodeC)

  main()

block:
  type RefObj = ref object

  proc `[]`(val: static[int]) = # works with different name/overload or without static arg
    discard

  template noRef(T: typedesc): typedesc = # works without template indirection
    typeof(default(T)[])

  proc `=destroy`(x: noRef(RefObj)) =
    discard

  proc foo =
    var x = new RefObj
    doAssert $(x[]) == "()"

  # bug #11705
  foo()

block: # bug #22197
  type
    H5IdObj = object
    H5Id = ref H5IdObj

    FileID = distinct H5Id

    H5GroupObj = object
      file_id: FileID
    H5Group = ref H5GroupObj

  ## This would make it work!
  #proc `=destroy`*(x: FileID) = `=destroy`(cast[H5Id](x))
  ## If this does not exist, it also works!
  proc newFileID(): FileID = FileID(H5Id())

  proc `=destroy`(grp: H5GroupObj) =
    ## Closes the group and resets all references to nil.
    if cast[pointer](grp.fileId) != nil:
      `=destroy`(grp.file_id)

  var grp = H5Group()
  reset(grp.file_id)
  reset(grp)

import std/tables

block: # bug #22286
  type
    A = object
    B = object
      a: A
    C = object
      b: B

  proc `=destroy`(self: A) =
    echo "destroyed"

  proc `=destroy`(self: C) =
    `=destroy`(self.b)

  var c = C()

block: # https://forum.nim-lang.org/t/10642
  type AObj = object
    name: string
    tableField: Table[string, string]

  proc `=destroy`(x: AObj) =
    `=destroy`(x.name)
    `=destroy`(x.tableField)
