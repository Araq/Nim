discard """
  cmd: "nim check $file"
"""

import mobjconstr_msgs


block:
  discard PrivateField(
    priv: "test" #[tt.Error
    ^ the field 'priv' is not accessible]#
  )


block:
  type
    Foo = object
      field: string
  discard Foo(
    field: "test",
    field: "test" #[tt.Error
    ^ field initialized twice: 'field']#
  )
