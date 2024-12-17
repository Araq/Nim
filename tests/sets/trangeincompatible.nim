block: # issue #20142
  let
    s1: set['a' .. 'g'] = {'a', 'e'}
    s2: set['a' .. 'g'] = {'b', 'c', 'd', 'f'} # this works fine
    s3 = {'b', 'c', 'd', 'f'}

  doAssert s1 != s2
  doAssert s1 == {range['a'..'g'] 'a', 'e'}
  doAssert s2 == {range['a'..'g'] 'b', 'c', 'd', 'f'}
  # literal conversion:
  doAssert s1 == {'a', 'e'}
  doAssert s2 == {'b', 'c', 'd', 'f'}
  doAssert s3 == {'b', 'c', 'd', 'f'}
  doAssert not compiles(s1 == s3)
  doAssert not compiles(s2 == s3)
  # can't convert literal 'z', overload match fails
  doAssert not compiles(s1 == {'a', 'z'})

block: # issue #18396
  var s1: set[char] = {'a', 'b'}
  var s2: set['a'..'z'] = {'a', 'b'}
  doAssert s1 == {'a', 'b'}
  doAssert s2 == {range['a'..'z'] 'a', 'b'}
  doAssert s2 == {'a', 'b'}
  doAssert not compiles(s1 == s2)

block: # issue #16270
  var s1: set[char] = {'a', 'b'}
  var s2: set['a'..'z'] = {'a', 'c'}
  doAssert not (compiles do: s2 = s2 + s1)
  s2 = s2 + {'a', 'b'}
  doAssert s2 == {'a', 'b', 'c'}
