import "."/[mambtype1, mambtype2]
type H[K] = object
proc b(_: int) =  # slightly different, still not useful, error message if `b` generic
  proc r(): H[Y] = discard #[tt.Error
             ^ cannot instantiate H [type declared in tambtypegeneric.nim(2, 6)]
got: <typedesc[Y] | typedesc[Y]>
but expected: <K>
ambiguous identifier: 'Y' -- use one of the following:
  mambtype1.Y: Y
  mambtype2.Y: Y]#
b(0)
