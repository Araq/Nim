# bug #22794
type O = object

proc `=destroy`(x: O) = discard
proc `=trace`(x: var O; env: pointer) = discard
proc `=copy`(a: var O; b: O) = discard
proc `=dup`(a: O): O {.nodestroy.} = a
proc `=sink`(a: var O; b: O) = discard


# bug #23316
type SomeSturct = object

proc `=destroy`(x: SomeSturct) =
  echo "SomeSturct destroyed"

# bug #23867
type ObjStr = object
  s: string

let ostr = ObjStr() # <-- nimsuggest crashes
discard ostr

type ObjSeq = object
  s: seq[int]

let oseq = ObjSeq() # <-- nimsuggest crashes
discard oseq

#[!]#
discard """
$nimsuggest --tester $file
>chk $1
chk;;skUnknown;;;;Hint;;???;;0;;-1;;">> (toplevel): import(dirty): tests/tchk2.nim [Processing]";;0
"""
