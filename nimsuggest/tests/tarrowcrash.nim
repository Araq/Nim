# issue #24179

import sugar

type
    Parser[T] = object
    
proc eatWhile[T](p: Parser[T], predicate: T -> bool): seq[T] =
    return @[]

proc skipWs(p: Parser[char]) =
    discard p.eatWhile((c: char) => c == 'a')
#[!]#
    
discard """
$nimsuggest --tester $file
>chk $1
chk;;skUnknown;;;;Hint;;???;;0;;-1;;">> (toplevel): import(dirty): tests/tarrowcrash.nim [Processing]";;0
chk;;skUnknown;;;;Hint;;$file;;11;;5;;"\'skipWs\' is declared but not used [XDeclaredButNotUsed]";;0
"""
