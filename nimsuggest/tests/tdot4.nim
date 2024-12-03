# Test that already used suggestions are prioritized

from system import string, echo
import fixtures/mstrutils

proc main(inp: string): string =
  # use replace here and see if it occurs in the result, it should gain
  # priority:
  result = inp.replace(" ", "a").replace("b", "c")

echo "string literal here".#[!]#

# priority still tested, but limit results to avoid failures from other output
discard """
$nimsuggest --tester --maxresults:2 $file
>sug $1
sug;;skProc;;tdot4.main;;proc (inp: string): string;;$file;;6;;5;;"";;100;;None
sug;;skFunc;;mstrutils.replace;;proc (s: string, sub: string, by: string): string{.noSideEffect, gcsafe, raises: <inferred> [].};;*fixtures/mstrutils.nim;;9;;5;;"this is a test version of strutils.replace, it simply returns `by`";;100;;None
"""

# TODO - determine appropriate behaviour for further suggest output and test it
