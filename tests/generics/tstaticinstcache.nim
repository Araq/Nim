block: # issue #23628, simple case
  type
    Bar[T] = object

    Foo[T; C: static int] = object
      bar: Bar[Foo[T, C]]

  var f: Foo[int, 5]

block: # issue #23628, nested
  type
    Bar[T; C: static int] = object
      arr: array[C, ptr T]

    Foo[T; C: static int] = object
      bar: Bar[Foo[T, C], C]

  var f: Foo[int, 5]
  doAssert f.bar.arr.len == 5
