block: # issue #15760
  type
    Banana = object
    SpecialBanana = object
    
  proc getName(_: type Banana): string = "Banana"
  proc getName(_: type SpecialBanana): string = "SpecialBanana"

  proc x[T](): string = 
    const n = getName(T) # this one works
    result = n
    
  proc y(T: type): string =
    const n = getName(T) # this one failed to compile
    result = n

  doAssert x[SpecialBanana]() == "SpecialBanana"
  doAssert y(SpecialBanana) == "SpecialBanana"

import macros

block: # issue #23112
  type Container = object
    foo: string

  proc canBeImplicit(t: typedesc) {.compileTime.} =
    let tDesc = getType(t)
    doAssert tDesc.kind == nnkObjectTy

  static:
    canBeImplicit(Container)
