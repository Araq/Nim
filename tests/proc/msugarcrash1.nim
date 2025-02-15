import std/options

type
  Address* = object
    port*: int

  Node* = ref object
    address*: Option[Address]
