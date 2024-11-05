discard """
  matrix: "--mm:refc; --mm:orc"
  targets: "c js"
"""

import std/setutils
import std/assertions

type 
  Colors = enum
    red, green = 5, blue = 10
  Bar = enum
    bar0 = -1, bar1, bar2

template main =
  block: # toSet
    doAssert "abcbb".toSet == {'a', 'b', 'c'}
    doAssert toSet([10u8, 12, 13]) == {10u8, 12, 13}
    doAssert toSet(0u16..30) == {0u16..30}
    type A = distinct char
    doAssert [A('x')].toSet == {A('x')}

  block: # fullSet
    doAssert fullSet(Colors) == {red, green, blue}
    doAssert fullSet(char) == {0.chr..255.chr}
    doAssert fullSet(Bar) == {bar0, bar1, bar2}
    doAssert fullSet(bool) == {true, false}

  block: # complement
    doAssert {red, blue}.complement == {green}
    doAssert (complement {red, green, blue}).card == 0
    doAssert (complement {false}) == {true}
    doAssert {bar0}.complement == {bar1, bar2}
    doAssert {range[0..10](0), 1, 2, 3}.complement == {range[0..10](4), 5, 6, 7, 8, 9, 10}
    doAssert {'0'..'9'}.complement == {0.char..255.char} - {'0'..'9'}

  block: # `[]=`
    type A = enum
      a0, a1, a2, a3
    var s = {a0, a3}
    s[a0] = false
    s[a1] = false
    doAssert s == {a3}
    s[a2] = true
    s[a3] = true
    doAssert s == {a2, a3}
  
  block: # set symmetric difference (xor), https://github.com/nim-lang/RFCs/issues/554
    type T = set[range[0..15]]
    let x: T = {1, 4, 5, 8, 9}
    let y: T = {0, 2..6, 9}
    let res = symmetricDifference(x, y)
    doAssert res == {0, 1, 2, 3, 6, 8}
    doAssert res == (x + y - x * y)
    doAssert res == ((x - y) + (y - x))
    var z = x
    doAssert z == {1, 4, 5, 8, 9}
    doAssert z == x
    z.toggle(y)
    doAssert z == res
    z.toggle(y)
    doAssert z == x
    z.toggle({1, 5})
    doAssert z == {4, 8, 9}
    z.toggle({3, 8})
    doAssert z == {3, 4, 9}

main()
static: main()
