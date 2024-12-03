discard """
  cmd: "nim c --mm:arc $file"
  errormsg: "'=copy' is not available for type <Obj>; requires a copy because it's not the last read of 'chan[]'; routine: test"
"""

# bug #22218
type Obj[T] = object
  v: T

proc `=copy`[T](
    dest: var Obj[T],
    source: Obj[T]
  ) {.error: "A channel cannot be copied".}

from system/ansi_c import c_calloc

proc test() =
    var v: bool = true
    var chan = cast[ptr Obj[int]](c_calloc(1, csize_t sizeof(Obj[int])))
    var copy = chan[]

    echo chan.v
    echo v

test()