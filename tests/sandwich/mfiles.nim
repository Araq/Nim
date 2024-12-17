import mhandles

type
  File* = ref object
    handle: Handle[FD]

proc close*[T: File](f: T) =
  f.handle.close()

proc newFile*(fd: FD): File =
  File(handle: initHandle(FD -1))
