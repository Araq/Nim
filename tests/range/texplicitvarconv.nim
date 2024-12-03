# related to issue #24032

proc `++`(n: var int) =
    n += 1

type
    r = range[ 0..15 ]

var a: r = 14

++int(a) # this should be mutable

doAssert a == 15
