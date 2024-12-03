import std/paths
import json as J
import std/[os,streams]#[!]#

discard """
$nimsuggest --tester $file
>highlight $1
highlight;;skModule;;1;;11;;5
highlight;;skModule;;2;;7;;4
highlight;;skModule;;3;;12;;2
highlight;;skModule;;3;;15;;7
"""
