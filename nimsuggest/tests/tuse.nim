# basic tests for use

# bug #58
proc someOtherProc() =
  discard

someOtherProc()

proc #[!]#someProc*() =
  discard

#[!]#someProc()

discard """
$nimsuggest --tester $file
>use $1
def;;skProc;;tuse.someProc;;proc (){.noSideEffect, gcsafe, raises: <inferred> [].};;$file;;9;;5;;"";;100
use;;skProc;;tuse.someProc;;proc (){.noSideEffect, gcsafe, raises: <inferred> [].};;$file;;12;;0;;"";;100
>use $2
def;;skProc;;tuse.someProc;;proc (){.noSideEffect, gcsafe, raises: <inferred> [].};;$file;;9;;5;;"";;100
use;;skProc;;tuse.someProc;;proc (){.noSideEffect, gcsafe, raises: <inferred> [].};;$file;;12;;0;;"";;100
"""
