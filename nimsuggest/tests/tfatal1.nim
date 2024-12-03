{.warning: "I'm a warning!".}
{.error: "I'm an error!".}
{.fatal: "I'm a fatal error!".}
{.error: "I'm an error after fatal error!".}

#[!]#
discard """
$nimsuggest --tester $file
>chk $1
chk;;skUnknown;;;;Hint;;???;;0;;-1;;">> (toplevel): import(dirty): tests/tfatal1.nim [Processing]";;0
chk;;skUnknown;;;;Warning;;$file;;1;;9;;"I\'m a warning! [User]";;0
chk;;skUnknown;;;;Error;;$file;;2;;7;;"I\'m an error!";;0
chk;;skUnknown;;;;Error;;$file;;3;;7;;"fatal error: I\'m a fatal error!";;0
chk;;skUnknown;;;;Error;;$file;;4;;7;;"I\'m an error after fatal error!";;0
"""
