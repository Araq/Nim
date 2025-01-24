import "."/[mambtype1, mambtype2]
type H[K] = object
proc b(_: int) =  # slightly different, still not useful, error message if `b` generic
  proc r(): H[Y] = discard #[tt.Error
             ^ cannot instantiate H [type declared in tambtypegeneric.nim(2, 6)]
got: <mambtype1.Y: typedesc[Y] | mambtype2.Y: typedesc[Y]>
but expected: <K>]#
b(0)
