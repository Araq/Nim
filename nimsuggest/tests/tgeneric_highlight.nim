newSeq[int]()
system.newSeq[int]()#[!]#
offsetOf[int]()

discard """
$nimsuggest --tester $file
>highlight $1
highlight;;skType;;1;;7;;3
highlight;;skProc;;1;;0;;6
highlight;;skType;;2;;14;;3
highlight;;skProc;;2;;7;;6
highlight;;skType;;3;;9;;3
"""
