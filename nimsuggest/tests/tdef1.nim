discard """
$nimsuggest --tester $file
>def $1
def;;skProc;;tdef1.hello;;proc (): string{.noSideEffect, gcsafe, raises: <inferred> [].};;$file;;11;;5;;"Return hello";;100
>def $2
def;;skProc;;tdef1.hello;;proc (): string{.noSideEffect, gcsafe, raises: <inferred> [].};;$file;;11;;5;;"Return hello";;100
>def $2
def;;skProc;;tdef1.hello;;proc (): string{.noSideEffect, gcsafe, raises: <inferred> [].};;$file;;11;;5;;"Return hello";;100
"""

proc hel#[!]#lo(): string =
  ## Return hello
  "Hello"

hel#[!]#lo()

# v uncompleted id for sug (13,2)
he
