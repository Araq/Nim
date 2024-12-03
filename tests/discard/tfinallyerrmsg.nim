discard """
  cmd: "nim check $file"
"""

block: # issue #19672
  try:
    10 #[tt.Error
    ^ expression '10' is of type 'int literal(10)' and has to be used (or discarded); start of expression here: tfinallyerrmsg.nim(5, 1)]#
  finally:
    echo "Finally block"

block: # issue #13871
  template t(body: int) =
    try:
      body
    finally:
      echo "expression"
  t: 2 #[tt.Error
     ^ expression '2' is of type 'int literal(2)' and has to be used (or discarded)]#
