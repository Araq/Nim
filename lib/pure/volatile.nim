#
#
#            Nim's Runtime Library
#        (c) Copyright 2017 Jeff Ciesielski
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module contains code for generating volatile loads and stores,
## which are useful in embedded and systems programming.

template volatileLoad*[T](src: ptr T): T =
  ## Generates a volatile load of the value stored in the container `src`.
  ## Note that this only effects code generation on `C` like backends.
  when nimvm:
    src[]
  else:
    when defined(js):
      src[]
    else:
      result = default(T)
      {.emit: [result, " = (*(", typeof(src[]), " volatile*)", src, ");"].}

template volatileStore*[T](dest: ptr T, val: T) =
  ## Generates a volatile store into the container `dest` of the value
  ## `val`. Note that this only effects code generation on `C` like
  ## backends.
  when nimvm:
    dest[] = val
  else:
    when defined(js):
      dest[] = val
    else:
      {.emit: ["*((", typeof(dest[]), " volatile*)(", dest, ")) = ", val, ";"].}
