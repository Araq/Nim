# issue #24688

type
  R[T, E] = object
  A = object
  B = object

# Remove this overload to make it work
func err[T](_: type R[T, void]): R[T, void] = discard

func err(_: type R): R[A, B] = discard

discard R.err()
