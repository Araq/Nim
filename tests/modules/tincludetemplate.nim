# issue #12539

template includePath(n: untyped) = include ../modules/n # But `include n` works
includePath(mincludetemplate)
doAssert foo == 123
