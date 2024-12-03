template fooBar1() {.pragma.}
proc fooBar2() = discard
macro fooBar3(x: untyped) = discard
{.pragma: fooBar4 fooBar3.}

proc test1() {.fooBar#[!]#.} = discard

var test2 {.fooBar#[!]#.} = 9

type
  Person {.fooBar#[!]#.} = object
    hello {.fooBar#[!]#.}: string
  Callback = proc () {.fooBar#[!]#.}

# Check only macros/templates/pragmas are suggested
discard """
$nimsuggest --tester $file
>sug $1
sug;;skTemplate;;fooBar4;;;;$file;;4;;8;;"";;100;;Prefix
sug;;skTemplate;;tsug_pragmas.fooBar1;;template ();;$file;;1;;9;;"";;100;;Prefix
sug;;skMacro;;tsug_pragmas.fooBar3;;macro (x: untyped){.noSideEffect, gcsafe, raises: <inferred> [].};;$file;;3;;6;;"";;50;;Prefix
>sug $2
sug;;skTemplate;;fooBar4;;;;$file;;4;;8;;"";;100;;Prefix
sug;;skTemplate;;tsug_pragmas.fooBar1;;template ();;$file;;1;;9;;"";;100;;Prefix
sug;;skMacro;;tsug_pragmas.fooBar3;;macro (x: untyped){.noSideEffect, gcsafe, raises: <inferred> [].};;$file;;3;;6;;"";;50;;Prefix
>sug $3
sug;;skTemplate;;fooBar4;;;;$file;;4;;8;;"";;100;;Prefix
sug;;skTemplate;;tsug_pragmas.fooBar1;;template ();;$file;;1;;9;;"";;100;;Prefix
sug;;skMacro;;tsug_pragmas.fooBar3;;macro (x: untyped){.noSideEffect, gcsafe, raises: <inferred> [].};;$file;;3;;6;;"";;50;;Prefix
>sug $4
sug;;skTemplate;;fooBar4;;;;$file;;4;;8;;"";;100;;Prefix
sug;;skTemplate;;tsug_pragmas.fooBar1;;template ();;$file;;1;;9;;"";;100;;Prefix
sug;;skMacro;;tsug_pragmas.fooBar3;;macro (x: untyped){.noSideEffect, gcsafe, raises: <inferred> [].};;$file;;3;;6;;"";;50;;Prefix
>sug $5
sug;;skTemplate;;fooBar4;;;;$file;;4;;8;;"";;100;;Prefix
sug;;skTemplate;;tsug_pragmas.fooBar1;;template ();;$file;;1;;9;;"";;100;;Prefix
sug;;skMacro;;tsug_pragmas.fooBar3;;macro (x: untyped){.noSideEffect, gcsafe, raises: <inferred> [].};;$file;;3;;6;;"";;50;;Prefix
"""


