#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements the ability to access symbols from shared
## libraries. On POSIX this uses the `dlsym` mechanism, on
## Windows `LoadLibrary`.
##
## Examples
## ========
##
## Loading a simple C function
## ---------------------------
##
## The following example demonstrates loading a function called `greet`
## from a library that is determined at runtime based upon a language choice.
## If the library fails to load or the function `greet` is not found,
## it quits with a failure error code.
##
runnableExamples:
  type
    GreetFunction = proc (): cstring {.gcsafe, stdcall.}

  proc loadGreet(lang: string) =
    let lib =
      case lang
      of "french":
        loadLib("french.dll")
      else:
        loadLib("english.dll")
    assert lib != nil, "Error loading library"

    let greet = cast[GreetFunction](lib.symAddr("greet"))
    assert greet != nil, "Error loading 'greet' function from library"

    echo greet()

    unloadLib(lib)


import std/strutils

type
  LibHandle* = pointer ## A handle to a dynamically loaded library.

proc loadLib*(path: string, globalSymbols = false): LibHandle {.gcsafe.}
  ## Loads a library from `path`. Returns nil if the library could not
  ## be loaded.

proc loadLib*(): LibHandle {.gcsafe.}
  ## Gets the handle from the current executable. Returns nil if the
  ## library could not be loaded.

proc unloadLib*(lib: LibHandle) {.gcsafe.}
  ## Unloads the library `lib`.

proc raiseInvalidLibrary*(name: cstring) {.noinline, noreturn.} =
  ## Raises a `LibraryError` exception.
  raise newException(LibraryError, "could not find symbol: " & $name)

proc symAddr*(lib: LibHandle, name: cstring): pointer {.gcsafe.}
  ## Retrieves the address of a procedure/variable from `lib`. Returns nil
  ## if the symbol could not be found.

proc checkedSymAddr*(lib: LibHandle, name: cstring): pointer =
  ## Retrieves the address of a procedure/variable from `lib`. Raises
  ## `LibraryError` if the symbol could not be found.
  result = symAddr(lib, name)
  if result == nil: raiseInvalidLibrary(name)

proc libCandidates*(s: string, dest: var seq[string]) =
  ## Given a library name pattern `s`, write possible library names to `dest`.
  var le = strutils.find(s, '(')
  var ri = strutils.find(s, ')', le+1)
  if le >= 0 and ri > le:
    var prefix = substr(s, 0, le - 1)
    var suffix = substr(s, ri + 1)
    for middle in split(substr(s, le + 1, ri - 1), '|'):
      libCandidates(prefix & middle & suffix, dest)
  else:
    add(dest, s)

proc loadLibPattern*(pattern: string, globalSymbols = false): LibHandle =
  ## Loads a library with name matching `pattern`, similar to what the `dynlib`
  ## pragma does. Returns nil if the library could not be loaded.
  ##
  ## .. warning:: this proc uses the GC and so cannot be used to load the GC.
  result = default(LibHandle)
  var candidates = newSeq[string]()
  libCandidates(pattern, candidates)
  for c in candidates:
    result = loadLib(c, globalSymbols)
    if not result.isNil: break

when defined(posix) and not defined(nintendoswitch):
  #
  # =========================================================================
  # This is an implementation based on the dlfcn interface.
  # The dlfcn interface is available in Linux, SunOS, Solaris, IRIX, FreeBSD,
  # NetBSD, AIX 4.2, HPUX 11, and probably most other Unix flavors, at least
  # as an emulation layer on top of native functions.
  # =========================================================================
  #
  import std/posix

  proc loadLib(path: string, globalSymbols = false): LibHandle =
    let flags =
      if globalSymbols: RTLD_NOW or RTLD_GLOBAL
      else: RTLD_NOW

    dlopen(path, flags)

  proc loadLib(): LibHandle = dlopen(nil, RTLD_NOW)
  proc unloadLib(lib: LibHandle) = discard dlclose(lib)
  proc symAddr(lib: LibHandle, name: cstring): pointer = dlsym(lib, name)

elif defined(nintendoswitch):
  #
  # =========================================================================
  # Nintendo switch DevkitPro sdk does not have these. Raise an error if called.
  # =========================================================================
  #

  proc dlclose(lib: LibHandle) =
    raise newException(OSError, "dlclose not implemented on Nintendo Switch!")
  proc dlopen(path: cstring, mode: int): LibHandle =
    raise newException(OSError, "dlopen not implemented on Nintendo Switch!")
  proc dlsym(lib: LibHandle, name: cstring): pointer =
    raise newException(OSError, "dlsym not implemented on Nintendo Switch!")
  proc loadLib(path: string, global_symbols = false): LibHandle =
    raise newException(OSError, "loadLib not implemented on Nintendo Switch!")
  proc loadLib(): LibHandle =
    raise newException(OSError, "loadLib not implemented on Nintendo Switch!")
  proc unloadLib(lib: LibHandle) =
    raise newException(OSError, "unloadLib not implemented on Nintendo Switch!")
  proc symAddr(lib: LibHandle, name: cstring): pointer =
    raise newException(OSError, "symAddr not implemented on Nintendo Switch!")

elif defined(genode):
  #
  # =========================================================================
  # Not implemented for Genode without POSIX. Raise an error if called.
  # =========================================================================
  #

  template raiseErr(prc: string) =
    raise newException(OSError, prc & " not implemented, compile with POSIX support")

  proc dlclose(lib: LibHandle) =
    raiseErr(OSError, "dlclose")
  proc dlopen(path: cstring, mode: int): LibHandle =
    raiseErr(OSError, "dlopen")
  proc dlsym(lib: LibHandle, name: cstring): pointer =
    raiseErr(OSError, "dlsym")
  proc loadLib(path: string, global_symbols = false): LibHandle =
    raiseErr(OSError, "loadLib")
  proc loadLib(): LibHandle =
    raiseErr(OSError, "loadLib")
  proc unloadLib(lib: LibHandle) =
    raiseErr(OSError, "unloadLib")
  proc symAddr(lib: LibHandle, name: cstring): pointer =
    raiseErr(OSError, "symAddr")


elif defined(windows) or defined(dos):
  #
  # =======================================================================
  # Native Windows Implementation
  # =======================================================================
  #
  type
    HMODULE {.importc: "HMODULE".} = pointer
    FARPROC {.importc: "FARPROC".} = pointer

  proc FreeLibrary(lib: HMODULE) {.importc, header: "<windows.h>", stdcall.}
  proc winLoadLibrary(path: cstring): HMODULE {.
      importc: "LoadLibraryA", header: "<windows.h>", stdcall.}
  proc getProcAddress(lib: HMODULE, name: cstring): FARPROC {.
      importc: "GetProcAddress", header: "<windows.h>", stdcall.}

  proc loadLib(path: string, globalSymbols = false): LibHandle =
    result = cast[LibHandle](winLoadLibrary(path))
  proc loadLib(): LibHandle =
    result = cast[LibHandle](winLoadLibrary(nil))
  proc unloadLib(lib: LibHandle) = FreeLibrary(cast[HMODULE](lib))

  proc symAddr(lib: LibHandle, name: cstring): pointer =
    result = cast[pointer](getProcAddress(cast[HMODULE](lib), name))

else:
  {.error: "no implementation for dynlib".}
