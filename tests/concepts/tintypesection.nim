# issues with concepts in type section types

block: # issue #22839
  type
    Comparable = concept
      proc `<`(a, b: Self): bool
    
    # Works with this.
    # Comparable = concept a
    #   `<`(a, a) is bool
    
    # Doesn't work with the new style concept.
    Node[T: Comparable] = object
      data: T
      next: ref Node[T]

  var x: Node[int]
  type NotComparable = object
  doAssert not (compiles do:
    var y: Node[NotComparable])
  proc `<`(a, b: NotComparable): bool = false
  var z: Node[NotComparable]
