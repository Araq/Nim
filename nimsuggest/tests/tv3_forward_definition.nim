proc de#[!]#mo(): int

proc de#[!]#mo(): int = 5

let a = de#[!]#mo()

discard """
$nimsuggest --v3 --tester $file
>use $1
use	skProc	tv3_forward_definition.demo	proc (): int{.noSideEffect, gcsafe, raises: <inferred> [].}	$file	1	5	""	100
def	skProc	tv3_forward_definition.demo	proc (): int{.noSideEffect, gcsafe, raises: <inferred> [].}	$file	3	5	""	100
use	skProc	tv3_forward_definition.demo	proc (): int{.noSideEffect, gcsafe, raises: <inferred> [].}	$file	5	8	""	100
>use $2
use	skProc	tv3_forward_definition.demo	proc (): int{.noSideEffect, gcsafe, raises: <inferred> [].}	$file	1	5	""	100
def	skProc	tv3_forward_definition.demo	proc (): int{.noSideEffect, gcsafe, raises: <inferred> [].}	$file	3	5	""	100
use	skProc	tv3_forward_definition.demo	proc (): int{.noSideEffect, gcsafe, raises: <inferred> [].}	$file	5	8	""	100
>declaration $1
declaration	skProc	tv3_forward_definition.demo	proc (): int{.noSideEffect, gcsafe, raises: <inferred> [].}	$file	3	5	""	100
>declaration $2
declaration	skProc	tv3_forward_definition.demo	proc (): int{.noSideEffect, gcsafe, raises: <inferred> [].}	$file	1	5	""	100
>declaration $3
declaration	skProc	tv3_forward_definition.demo	proc (): int{.noSideEffect, gcsafe, raises: <inferred> [].}	$file	1	5	""	100
"""
