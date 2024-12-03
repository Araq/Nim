discard """
$nimsuggest --tester $file
>sug $1
>sug $2
sug;;skConst;;tenum_field.BarFoo;;int literal(1);;$file;;10;;6;;"";;100;;Prefix
"""

proc something() = discard

const BarFoo = 1

type
  Foo = enum
    # Test that typing the name doesn't give suggestions
    somethi#[!]#
    # Test that the right hand side still gets suggestions
    another = BarFo#[!]#
