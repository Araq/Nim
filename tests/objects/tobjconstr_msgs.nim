import mobjconstr_msgs


block: # Private field has correct line info
  discard PrivateField(
    priv: "test" #[tt.Error
    ^ the field 'priv' is not accessible]#
  )
