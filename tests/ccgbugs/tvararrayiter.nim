discard """
  targets: "c cpp"
"""

block: # issue #24274
  iterator foo[T](x: var T): var T =
    yield x

  var x: array[3, char]
  for a in foo(x):
    let b = a
  
  var y: array[3, char] = ['a', 'b', 'c']
  for a in foo(y):
    let b = a
    doAssert a[0] == 'a'
    doAssert a[1] == 'b'
    doAssert a[2] == 'c'
    doAssert b[0] == 'a'
    doAssert b[1] == 'b'
    doAssert b[2] == 'c'
