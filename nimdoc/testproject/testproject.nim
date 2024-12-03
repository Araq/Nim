## Basic usage
## ===========
##
## Encoding data
## -------------
##
## Apart from strings you can also encode lists of integers or characters:

## Decoding data
## -------------
##


import subdir / subdir_b / utils

## This is the top level module.
runnableExamples:
  import subdir / subdir_b / utils
  doAssert bar(3, 4) == 7
  foo(enumValueA, enumValueB)
  # bug #11078
  for x in "xx": discard


var someVariable*: bool ## This should be visible.

when true:
  ## top2
  runnableExamples:
    discard "in top2"
  ## top2 after

runnableExamples:
  discard "in top3"
## top3 after

const
  C_A* = 0x7FF0000000000000'f64
  C_B* = 0o377'i8
  C_C* = 0o277'i8
  C_D* = 0o177777'i16

proc bar*[T](a, b: T): T =
  result = a + b

proc baz*[T](a, b: T): T {.deprecated.} =
  ## This is deprecated without message.
  result = a + b

proc buzz*[T](a, b: T): T {.deprecated: "since v0.20".} =
  ## This is deprecated with a message.
  result = a + b

type
  FooBuzz* {.deprecated: "FooBuzz msg".} = int

using f: FooBuzz

proc bar*(f) = # `f` should be expanded to `f: FooBuzz`
  discard

import std/macros

var aVariable*: array[1, int]

# bug #9432
aEnum()
bEnum()
fromUtilsGen()

proc isValid*[T](x: T): bool = x.len > 0

when true:
  # these cases appear redundant but they're actually (almost) all different at
  # AST level and needed to ensure docgen keeps working, e.g. because of issues
  # like D20200526T163511
  type
    Foo* = enum
      enumValueA2

  proc z1*(): Foo =
    ## cz1
    Foo.default

  proc z2*() =
    ## cz2
    runnableExamples:
      discard "in cz2"

  proc z3*() =
    ## cz3

  proc z4*() =
    ## cz4
    discard

when true:
  # tests for D20200526T163511
  proc z5*(): int =
    ## cz5
    return 1

  proc z6*(): int =
    ## cz6
    1

  template z6t*(): int =
    ## cz6t
    1

  proc z7*(): int =
    ## cz7
    result = 1

  proc z8*(): int =
    ## cz8
    block:
      discard
      1+1

when true:
  # interleaving 0 or more runnableExamples and doc comments, issue #9227
  proc z9*() =
    runnableExamples: doAssert 1 + 1 == 2

  proc z10*() =
    runnableExamples "-d:foobar":
      discard 1
    ## cz10

  proc z11*() =
    runnableExamples:
      discard 1
    discard

  proc z12*(): int =
    runnableExamples:
      discard 1
    12

  proc z13*() =
    ## cz13
    runnableExamples:
      discard

  proc baz*() = discard

  proc bazNonExported() =
    ## out (not exported)
    runnableExamples:
      # BUG: this currently this won't be run since not exported
      # but probably should
      doAssert false
  if false: bazNonExported() # silence XDeclaredButNotUsed

  proc z17*() =
    # BUG: a comment before 1st doc comment currently doesn't prevent
    # doc comment from being docgen'd; probably should be fixed
    ## cz17
    ## rest
    runnableExamples:
      discard 1
    ## rest
    # this comment separates docgen'd doc comments
    ## out

when true: # capture non-doc comments correctly even before 1st token
  proc p1*() =
    ## cp1
    runnableExamples: doAssert 1 == 1 # regular comments work here
    ## c4
    runnableExamples:
      # c5 regular comments before 1st token work
      # regular comment
      #[
      nested regular comment
      ]#
      doAssert 2 == 2 # c8
      ## this is a non-nested doc comment

      ##[
      this is a nested doc comment
      ]##
      discard "c9"
      # also work after
    # this should be out

when true: # issue #14485
  proc addfBug14485*() =
    ## Some proc
    runnableExamples:
      discard "foo() = " & $[1]
      #[
      0: let's also add some broken html to make sure this won't break in future
      1: </span>
      2: </span>
      3: </span
      4: </script>
      5: </script
      6: </script
      7: end of broken html
      ]#

when true: # procs without `=` (using comment field)
  proc c_printf*(frmt: cstring): cint {.importc: "printf", header: "<stdio.h>", varargs, discardable.}
    ## the c printf.
    ## etc.

  proc c_nonexistent*(frmt: cstring): cint {.importc: "nonexistent", header: "<stdio.h>", varargs, discardable.}

when true: # tests RST inside comments
  proc low*[T: Ordinal|enum|range](x: T): T {.magic: "Low", noSideEffect.}
    ## Returns the lowest possible value of an ordinal value `x`. As a special
    ## semantic rule, `x` may also be a type identifier.
    ##
    ## See also:
    ## * `low2(T) <#low2,T>`_
    ##
    ## .. code-block:: Nim
    ##  low(2) # => -9223372036854775808

  proc low2*[T: Ordinal|enum|range](x: T): T {.magic: "Low", noSideEffect.} =
    ## Returns the lowest possible value of an ordinal value `x`. As a special
    ## semantic rule, `x` may also be a type identifier.
    ##
    ## See also:
    ## * `low(T) <#low,T>`_
    ##
    ## .. code-block:: Nim
    ##  low2(2) # => -9223372036854775808
    runnableExamples:
      discard "in low2"

when true: # multiline string litterals
  proc tripleStrLitTest*() =
    runnableExamples("--hint:XDeclaredButNotUsed:off"):
      ## mullitline string litterals are tricky as their indentation can span
      ## below that of the runnableExamples
      let s1a = """
should appear at indent 0
  at indent 2
at indent 0
"""
      # make sure this works too
      let s1b = """start at same line
  at indent 2
at indent 0
""" # comment after
      let s2 = """sandwich """
      let s3 = """"""
      when false:
        let s5 = """
        in s5 """

      let s3b = ["""
%!? #[...] # inside a multiline ...
""", "foo"]

      ## make sure handles trailing spaces
      let s4 = """ 
"""

      let s5 = """ x
"""
      let s6 = """ ""
"""
      let s7 = """"""""""
      let s8 = ["""""""""", """
  """ ]
      discard
      # should be in
    # should be out

when true: # methods; issue #14691
  type Moo = object
  method method1*(self: Moo) {.base.} =
    ## foo1
  method method2*(self: Moo): int {.base.} =
    ## foo2
    result = 1
  method method3*(self: Moo): int {.base.} =
    ## foo3
    1

when true: # iterators
  iterator iter1*(n: int): int =
    ## foo1
    for i in 0..<n:
      yield i
  iterator iter2*(n: int): int =
    ## foo2
    runnableExamples:
      discard # bar
    yield 0

when true: # (most) macros
  macro bar*(): untyped =
    result = newStmtList()

  macro z16*() =
    runnableExamples: discard 1
    ## cz16
    ## after
    runnableExamples:
      doAssert 2 == 1 + 1
    # BUG: we should probably render `cz16\nafter` by keeping newline instead or
    # what it currently renders as: `cz16 after`

  macro z18*(): int =
    ## cz18
    newLit 0

when true: # (most) templates
  template foo*(a, b: SomeType) =
    ## This does nothing
    ##
    discard

  template myfn*() =
    runnableExamples:
      import std/strutils
      ## issue #8871 preserve formatting
      ## line doc comment
      # bar
      doAssert "'foo" == "'foo"
      ##[
      foo
      bar
      ]##

      doAssert: not "foo".startsWith "ba"
      block:
        discard 0xff # elu par cette crapule
      # should be in
    ## should be still in

    # out
    ## out

  template z14*() =
    ## cz14
    runnableExamples:
      discard

  template z15*() =
    ## cz15
    runnableExamples:
      discard
    runnableExamples: discard 3
    runnableExamples: discard 4
    ## ok5
    ## ok5b
    runnableExamples: assert true
    runnableExamples: discard 1

    ## in or out?
    discard 8
    ## out

when true: # issue #14473
  import std/[sequtils]
  template doit(): untyped =
    ## doit
    ## return output only
    toSeq(["D20210427T172228"]) # make it searcheable at least until we figure out a way to avoid echo
  echo doit() # using doAssert or similar to avoid echo would "hide" the original bug

when true: # issue #14846
  import asyncdispatch
  proc asyncFun1*(): Future[int] {.async.} =
    ## ok1
    result = 1
  proc asyncFun2*() {.async.} = discard
  proc asyncFun3*() {.async.} =
    runnableExamples:
      discard
    ## ok1
    discard
    ## should be out
    discard

when true:
  template testNimDocTrailingExample*() =
    # this must be last entry in this file, it checks against a bug (that got fixed)
    # where runnableExamples would not show if there was not at least 2 "\n" after
    # the last character of runnableExamples
    runnableExamples:
      discard 2

when true: # issue #15702
  type
    Shapes* = enum
      ## Some shapes.
      Circle,     ## A circle
      Triangle,   ## A three-sided shape
      Rectangle   ## A four-sided shape

when true: # issue #15184
  proc anything* =
    ##
    ##  There is no block quote after blank lines at the beginning.
  discard

type T19396* = object # bug #19396
   a*: int
   b: float

template somePragma*() {.pragma.}
  ## Just some annotation

type # bug #21483
   MyObject* = object
      someString*: string ## This is a string
      annotated* {.somePragma.}: string ## This is an annotated string

type
  AnotherObject* = object
    case x*: bool
    of true:
      y*: proc (x: string)
    of false:
      hidden: string
