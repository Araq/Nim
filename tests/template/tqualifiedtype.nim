# issue #19866

# Switch module import order to switch which of last two
# doAsserts fails
import mqualifiedtype1
import mqualifiedtype2

# this isn't officially supported but needed to point out the issue:
template f(moduleName: untyped): int = sizeof(`moduleName`.A)
template g(someType:   untyped): int = sizeof(someType)

# These are legitimately true.
doAssert sizeof(mqualifiedtype1.A) != sizeof(mqualifiedtype2.A)
doAssert g(mqualifiedtype1.A) != g(mqualifiedtype2.A)

# Which means that this should not be true, but is in Nim 1.6
doAssert f(`mqualifiedtype1`) != f(`mqualifiedtype2`)
doAssert f(mqualifiedtype1) != f(mqualifiedtype2)

# These should be true, but depending on import order, exactly one
# fails in Nim 1.2, 1.6 and devel.
doAssert f(`mqualifiedtype1`) == g(mqualifiedtype1.A)
doAssert f(`mqualifiedtype2`) == g(mqualifiedtype2.A)
doAssert f(mqualifiedtype1) == g(mqualifiedtype1.A)
doAssert f(mqualifiedtype2) == g(mqualifiedtype2.A)
