# tests v3

type
  Foo* = ref object of RootObj
    bar*: string

proc test(f: Foo) =
  echo f.ba#[!]#r

#[!]#

discard """
$nimsuggest --v3 --tester $file
>use $1
def	skField	tv3.Foo.bar	string	$file	5	4	""	100
use	skField	tv3.Foo.bar	string	$file	8	9	""	100
>def $1
def	skField	tv3.Foo.bar	string	$file	5	4	""	100
>sug $1
sug	skField	bar	string	$file	5	4	""	100	Prefix
>globalSymbols test
def	skProc	tv3.test	proc (f: Foo){.gcsafe, raises: <inferred> [].}	$file	7	5	""	100
>globalSymbols Foo
def	skType	tv3.Foo	Foo	$file	4	2	""	100
>def $2
>use $2
"""
