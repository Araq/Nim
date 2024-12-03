  SomeNumber = concept a, type T
    a.int is int
    int.to(T) is type(a)

#[!]#
discard """
$nimsuggest --tester $file
>chk $1
chk;;skUnknown;;;;Hint;;???;;0;;-1;;">> (toplevel): import(dirty): tests/tconcept2.nim [Processing]";;0
chk;;skUnknown;;;;Error;;$file;;1;;2;;"invalid indentation";;0
chk;;skUnknown;;;;Error;;$file;;1;;15;;"the \'concept\' keyword is only valid in \'type\' sections";;0
chk;;skUnknown;;;;Error;;$file;;1;;15;;"invalid indentation";;0
chk;;skUnknown;;;;Error;;$file;;1;;15;;"expression expected, but found \'keyword concept\'";;0
chk;;skUnknown;;;;Error;;$file;;1;;2;;"\'SomeNumber\' cannot be assigned to";;0
"""
