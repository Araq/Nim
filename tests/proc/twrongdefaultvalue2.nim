# issue #22888

proc dummy*[T: SomeNumber](a: T, b: T = 2.5): T = #[tt.Error
                                        ^ type mismatch: got <float64> but expected 'int']#
  result = a

echo dummy(2)
