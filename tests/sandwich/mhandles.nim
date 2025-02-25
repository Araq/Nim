type
  FD* = distinct cint

type
  AnyFD* = concept fd
    close(fd)

proc close*(fd: FD) =
  discard

type
  Handle*[T: AnyFD] = object
    fd: T

proc close*[T: AnyFD](h: var Handle[T]) =
  close h.fd

proc initHandle*[T: AnyFD](fd: T): Handle[T] =
  Handle[T](fd: fd)
