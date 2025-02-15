#
#
#            Nim's Runtime Library
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This module contains headers of Ansi C procs
# and definitions of Ansi C types in Nim syntax
# All symbols are prefixed with 'c_' to avoid ambiguities

{.push hints:off, stack_trace: off, profiler: off.}

proc c_memchr*(s: pointer, c: cint, n: csize_t): pointer {.
  importc: "memchr", header: "<string.h>".}
proc c_memcmp*(a, b: pointer, size: csize_t): cint {.
  importc: "memcmp", header: "<string.h>", noSideEffect.}
proc c_memcpy*(a, b: pointer, size: csize_t): pointer {.
  importc: "memcpy", header: "<string.h>", discardable.}
proc c_memmove*(a, b: pointer, size: csize_t): pointer {.
  importc: "memmove", header: "<string.h>",discardable.}
proc c_memset*(p: pointer, value: cint, size: csize_t): pointer {.
  importc: "memset", header: "<string.h>", discardable.}
proc c_strcmp*(a, b: cstring): cint {.
  importc: "strcmp", header: "<string.h>", noSideEffect.}
proc c_strlen*(a: cstring): csize_t {.
  importc: "strlen", header: "<string.h>", noSideEffect.}
proc c_strstr*(haystack, needle: cstring): cstring {.
    importc: "strstr", header: "<string.h>", noSideEffect.}
proc c_abort*() {.
  importc: "abort", header: "<stdlib.h>", noSideEffect, noreturn.}


when defined(nimBuiltinSetjmp):
  type
    C_JmpBuf* = array[5, pointer]
elif defined(linux) and defined(amd64):
  type
    C_JmpBuf* {.importc: "jmp_buf", header: "<setjmp.h>", bycopy.} = object
        abi: array[200 div sizeof(clong), clong]
else:
  type
    C_JmpBuf* {.importc: "jmp_buf", header: "<setjmp.h>".} = object


type CSighandlerT = proc (a: cint) {.noconv.}
when defined(windows):
  const
    SIGABRT* = cint(22)
    SIGFPE* = cint(8)
    SIGILL* = cint(4)
    SIGINT* = cint(2)
    SIGSEGV* = cint(11)
    SIGTERM = cint(15)
    SIG_DFL* = cast[CSighandlerT](0)
elif defined(macosx) or defined(linux) or defined(freebsd) or
     defined(openbsd) or defined(netbsd) or defined(solaris) or
     defined(dragonfly) or defined(nintendoswitch) or defined(genode) or
     defined(aix) or hostOS == "standalone":
  const
    SIGABRT* = cint(6)
    SIGFPE* = cint(8)
    SIGILL* = cint(4)
    SIGINT* = cint(2)
    SIGSEGV* = cint(11)
    SIGTERM* = cint(15)
    SIGPIPE* = cint(13)
    SIG_DFL* = CSighandlerT(nil)
elif defined(haiku):
  const
    SIGABRT* = cint(6)
    SIGFPE* = cint(8)
    SIGILL* = cint(4)
    SIGINT* = cint(2)
    SIGSEGV* = cint(11)
    SIGTERM* = cint(15)
    SIGPIPE* = cint(7)
    SIG_DFL* = CSighandlerT(nil)
elif not defined(nimscript):
  var
    SIGINT* {.importc: "SIGINT", nodecl.}: cint
    SIGSEGV* {.importc: "SIGSEGV", nodecl.}: cint
    SIGABRT* {.importc: "SIGABRT", nodecl.}: cint
    SIGFPE* {.importc: "SIGFPE", nodecl.}: cint
    SIGILL* {.importc: "SIGILL", nodecl.}: cint
    SIG_DFL* {.importc: "SIG_DFL", nodecl.}: CSighandlerT

when defined(macosx):
  const SIGBUS* = cint(10)
elif defined(haiku):
  const SIGBUS* = cint(30)

# "nimRawSetjmp" is defined by default for certain platforms, so we need the
# "nimStdSetjmp" escape hatch with it.
when defined(nimSigSetjmp):
  proc c_longjmp*(jmpb: C_JmpBuf, retval: cint) {.
    header: "<setjmp.h>", importc: "siglongjmp".}
  proc c_setjmp*(jmpb: C_JmpBuf): cint =
    proc c_sigsetjmp(jmpb: C_JmpBuf, savemask: cint): cint {.
      header: "<setjmp.h>", importc: "sigsetjmp".}
    c_sigsetjmp(jmpb, 0)
elif defined(nimBuiltinSetjmp):
  proc c_longjmp*(jmpb: C_JmpBuf, retval: cint) =
    # Apple's Clang++ has trouble converting array names to pointers, so we need
    # to be very explicit here.
    proc c_builtin_longjmp(jmpb: ptr pointer, retval: cint) {.
      importc: "__builtin_longjmp", nodecl.}
    # The second parameter needs to be 1 and sometimes the C/C++ compiler checks it.
    c_builtin_longjmp(unsafeAddr jmpb[0], 1)
  proc c_setjmp*(jmpb: C_JmpBuf): cint =
    proc c_builtin_setjmp(jmpb: ptr pointer): cint {.
      importc: "__builtin_setjmp", nodecl.}
    c_builtin_setjmp(unsafeAddr jmpb[0])

elif defined(nimRawSetjmp) and not defined(nimStdSetjmp):
  when defined(windows):
    # No `_longjmp()` on Windows.
    proc c_longjmp*(jmpb: C_JmpBuf, retval: cint) {.
      header: "<setjmp.h>", importc: "longjmp".}
    when defined(vcc) or defined(clangcl):
      proc c_setjmp*(jmpb: C_JmpBuf): cint {.
        header: "<setjmp.h>", importc: "setjmp".}
    else:
      # The Windows `_setjmp()` takes two arguments, with the second being an
      # undocumented buffer used by the SEH mechanism for stack unwinding.
      # Mingw-w64 has been trying to get it right for years, but it's still
      # prone to stack corruption during unwinding, so we disable that by setting
      # it to NULL.
      # More details: https://github.com/status-im/nimbus-eth2/issues/3121
      when defined(nimHasStyleChecks):
        {.push styleChecks: off.}

      proc c_setjmp*(jmpb: C_JmpBuf): cint =
        proc c_setjmp_win(jmpb: C_JmpBuf, ctx: pointer): cint {.
          header: "<setjmp.h>", importc: "_setjmp".}
        c_setjmp_win(jmpb, nil)

      when defined(nimHasStyleChecks):
        {.pop.}
  else:
    proc c_longjmp*(jmpb: C_JmpBuf, retval: cint) {.
      header: "<setjmp.h>", importc: "_longjmp".}
    proc c_setjmp*(jmpb: C_JmpBuf): cint {.
      header: "<setjmp.h>", importc: "_setjmp".}
else:
  proc c_longjmp*(jmpb: C_JmpBuf, retval: cint) {.
    header: "<setjmp.h>", importc: "longjmp".}
  proc c_setjmp*(jmpb: C_JmpBuf): cint {.
    header: "<setjmp.h>", importc: "setjmp".}

proc c_signal*(sign: cint, handler: CSighandlerT): CSighandlerT {.
  importc: "signal", header: "<signal.h>", discardable.}
proc c_raise*(sign: cint): cint {.importc: "raise", header: "<signal.h>".}

type
  CFile {.importc: "FILE", header: "<stdio.h>",
          incompleteStruct.} = object
  CFilePtr* = ptr CFile ## The type representing a file handle.

# duplicated between io and ansi_c
const stdioUsesMacros = (defined(osx) or defined(freebsd) or defined(dragonfly)) and not defined(emscripten)
const stderrName = when stdioUsesMacros: "__stderrp" else: "stderr"
const stdoutName = when stdioUsesMacros: "__stdoutp" else: "stdout"
const stdinName = when stdioUsesMacros: "__stdinp" else: "stdin"

var
  cstderr* {.importc: stderrName, header: "<stdio.h>".}: CFilePtr
  cstdout* {.importc: stdoutName, header: "<stdio.h>".}: CFilePtr
  cstdin* {.importc: stdinName, header: "<stdio.h>".}: CFilePtr

proc c_fprintf*(f: CFilePtr, frmt: cstring): cint {.
  importc: "fprintf", header: "<stdio.h>", varargs, discardable.}
proc c_printf*(frmt: cstring): cint {.
  importc: "printf", header: "<stdio.h>", varargs, discardable.}

proc c_fputs*(c: cstring, f: CFilePtr): cint {.
  importc: "fputs", header: "<stdio.h>", discardable.}
proc c_fputc*(c: char, f: CFilePtr): cint {.
  importc: "fputc", header: "<stdio.h>", discardable.}

proc c_sprintf*(buf, frmt: cstring): cint {.
  importc: "sprintf", header: "<stdio.h>", varargs, noSideEffect.}
  # we use it only in a way that cannot lead to security issues

proc c_snprintf*(buf: cstring, n: csize_t, frmt: cstring): cint {.
  importc: "snprintf", header: "<stdio.h>", varargs, noSideEffect.}

when defined(zephyr) and not defined(zephyrUseLibcMalloc):
  proc c_malloc*(size: csize_t): pointer {.
    importc: "k_malloc", header: "<kernel.h>".}
  proc c_calloc*(nmemb, size: csize_t): pointer {.
    importc: "k_calloc", header: "<kernel.h>".}
  proc c_free*(p: pointer) {.
    importc: "k_free", header: "<kernel.h>".}
  proc c_realloc*(p: pointer, newsize: csize_t): pointer =
    # Zephyr's kernel malloc doesn't support realloc
    result = c_malloc(newSize)
    # match the ansi c behavior
    if not result.isNil():
      copyMem(result, p, newSize)
      c_free(p)
else:
  proc c_malloc*(size: csize_t): pointer {.
    importc: "malloc", header: "<stdlib.h>".}
  proc c_calloc*(nmemb, size: csize_t): pointer {.
    importc: "calloc", header: "<stdlib.h>".}
  proc c_free*(p: pointer) {.
    importc: "free", header: "<stdlib.h>".}
  proc c_realloc*(p: pointer, newsize: csize_t): pointer {.
    importc: "realloc", header: "<stdlib.h>".}

proc c_fwrite*(buf: pointer, size, n: csize_t, f: CFilePtr): csize_t {.
  importc: "fwrite", header: "<stdio.h>".}

proc c_fflush*(f: CFilePtr): cint {.
  importc: "fflush", header: "<stdio.h>".}

proc rawWriteString*(f: CFilePtr, s: cstring, length: int) {.compilerproc, nonReloadable, inline.} =
  # we cannot throw an exception here!
  discard c_fwrite(s, 1, cast[csize_t](length), f)
  discard c_fflush(f)

proc rawWrite*(f: CFilePtr, s: cstring) {.compilerproc, nonReloadable, inline.} =
  # we cannot throw an exception here!
  discard c_fwrite(s, 1, c_strlen(s), f)
  discard c_fflush(f)

{.pop.}
