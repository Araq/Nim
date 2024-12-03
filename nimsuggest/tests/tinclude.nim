# import that has an include:
# * def calls must work into and out of includes
# * outline calls on the import must show included members
import fixtures/minclude_import

proc go() =
  discard create().say()

go()

discard """
$nimsuggest --tester $file
>def $path/tinclude.nim:7:14
def;;skProc;;minclude_import.create;;proc (greeting: string, subject: string): Greet{.noSideEffect, gcsafe, raises: <inferred> [].};;*fixtures/minclude_include.nim;;3;;5;;"";;100
>def $path/fixtures/minclude_include.nim:3:71
def;;skType;;minclude_types.Greet;;Greet;;*fixtures/minclude_types.nim;;4;;2;;"";;100
>def $path/fixtures/minclude_include.nim:3:71
def;;skType;;minclude_types.Greet;;Greet;;*fixtures/minclude_types.nim;;4;;2;;"";;100
>outline $path/fixtures/minclude_import.nim
outline;;skProc;;minclude_import.say;;*fixtures/minclude_import.nim;;7;;5;;"";;100
outline;;skProc;;minclude_import.create;;*fixtures/minclude_include.nim;;3;;5;;"";;100
outline;;skProc;;minclude_import.say;;*fixtures/minclude_import.nim;;13;;5;;"";;100
"""

# TODO test/fix if the first `def` is not first or repeated we get no results
