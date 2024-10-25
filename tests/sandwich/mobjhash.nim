import hashes

type
  Obj* = object
    x*, y*: int
    z*: string # to be ignored for equality

proc `==`*(a, b: Obj): bool =
  a.x == b.x and a.y == b.y

proc hash*(a: Obj): Hash =
  !$(hash(a.x) !& hash(a.y))

type
  RefObj* = ref object
    x*, y*: int
    z*: string # to be ignored for equality

proc `==`*(a, b: RefObj): bool =
  a.x == b.x and a.y == b.y

proc hash*(a: RefObj): Hash =
  !$(hash(a.x) !& hash(a.y))

type
  GenericObj1*[T] = object
    x*, y*: T
    z*: string # to be ignored for equality

proc `==`*[T](a, b: GenericObj1[T]): bool =
  a.x == b.x and a.y == b.y

proc hash*[T](a: GenericObj1[T]): Hash =
  !$(hash(a.x) !& hash(a.y))

type
  GenericObj2*[T] = object
    x*, y*: T
    z*: string # to be ignored for equality

proc `==`*(a, b: GenericObj2): bool =
  a.x == b.x and a.y == b.y

proc hash*(a: GenericObj2): Hash =
  !$(hash(a.x) !& hash(a.y))

type
  GenericObj3*[T] = object
    x*, y*: T
    z*: string # to be ignored for equality
  GenericObj3Alias*[T] = GenericObj3[T]

proc `==`*[T](a, b: GenericObj3Alias[T]): bool =
  a.x == b.x and a.y == b.y

proc hash*[T](a: GenericObj3Alias[T]): Hash =
  !$(hash(a.x) !& hash(a.y))

type
  GenericObj4*[T] = object
    x*, y*: T
    z*: string # to be ignored for equality
  GenericObj4Alias*[T] = GenericObj4[T]

proc `==`*(a, b: GenericObj4): bool =
  a.x == b.x and a.y == b.y

proc hash*(a: GenericObj4): Hash =
  !$(hash(a.x) !& hash(a.y))

type
  GenericRefObj*[T] = ref object
    x*, y*: T
    z*: string # to be ignored for equality

proc `==`*[T](a, b: GenericRefObj[T]): bool =
  a.x == b.x and a.y == b.y

proc hash*[T](a: GenericRefObj[T]): Hash =
  !$(hash(a.x) !& hash(a.y))
