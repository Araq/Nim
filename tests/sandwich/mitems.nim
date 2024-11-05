import sets, hashes

type
  Fruit* = ref object
    id*: int

  # Generic implementation. This doesn't work
  EntGroup*[T] = ref object
    freed*: HashSet[T]

proc hash*(self: Fruit): Hash = hash(self.id)

##
## VVV The Generic implementation. This doesn't work VVV
##

proc initEntGroup*[T: Fruit](): EntGroup[T] =
  result = EntGroup[T]()
  result.freed = initHashSet[Fruit]()
  var apple = Fruit(id: 20)
  result.freed.incl(apple)

proc get*[T: Fruit](fg: EntGroup[T]): T =
  if len(fg.freed) == 0: return
  # vvv It errors here 
  # type mismatch: ([1] fg.freed: HashSet[grouptest.Fruit])
  for it in fg.freed: 
    return it

##
## VVV The Non-Generic implementation works VVV
##
type
  # Non-generic implementation. This works.
  FruitGroup* = ref object
    freed*: HashSet[Fruit]

proc initFruitGroup*(): FruitGroup =
  result = FruitGroup()
  result.freed = initHashSet[Fruit]()
  var apple = Fruit(id: 20)
  result.freed.incl(apple)

proc getNoGeneric*(fg: FruitGroup): Fruit =
  if len(fg.freed) == 0: return
  for it in fg.freed:
    return it

proc `$`*(self: Fruit): string = 
  # For echo
  if self == nil: return "Fruit()"
  return "Fruit(" & $(self.id) & ")"
