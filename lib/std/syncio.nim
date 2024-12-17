#
#
#            Nim's Runtime Library
#        (c) Copyright 2022 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements various synchronized I/O operations.

include system/inclrtl
import std/private/since
import std/formatfloat
when defined(windows):
  import std/widestrs

# ----------------- IO Part ------------------------------------------------
type
  CFile {.importc: "FILE", header: "<stdio.h>",
          incompleteStruct.} = object
  File* = ptr CFile ## The type representing a file handle.

  FileMode* = enum       ## The file mode when opening a file.
    fmRead,              ## Open the file for read access only.
                         ## If the file does not exist, it will not
                         ## be created.
    fmWrite,             ## Open the file for write access only.
                         ## If the file does not exist, it will be
                         ## created. Existing files will be cleared!
    fmReadWrite,         ## Open the file for read and write access.
                         ## If the file does not exist, it will be
                         ## created. Existing files will be cleared!
    fmReadWriteExisting, ## Open the file for read and write access.
                         ## If the file does not exist, it will not be
                         ## created. The existing file will not be cleared.
    fmAppend             ## Open the file for writing only; append data
                         ## at the end. If the file does not exist, it
                         ## will be created.

  FileHandle* = cint ## The type that represents an OS file handle; this is
                      ## useful for low-level file access.

  FileSeekPos* = enum ## Position relative to which seek should happen.
                      # The values are ordered so that they match with stdio
                      # SEEK_SET, SEEK_CUR and SEEK_END respectively.
    fspSet            ## Seek to absolute value
    fspCur            ## Seek relative to current position
    fspEnd            ## Seek relative to end

# text file handling:
when not defined(nimscript) and not defined(js):
  # duplicated between io and ansi_c
  const stdioUsesMacros = (defined(osx) or defined(freebsd) or defined(
      dragonfly)) and not defined(emscripten)
  const stderrName = when stdioUsesMacros: "__stderrp" else: "stderr"
  const stdoutName = when stdioUsesMacros: "__stdoutp" else: "stdout"
  const stdinName = when stdioUsesMacros: "__stdinp" else: "stdin"

  var
    stdin* {.importc: stdinName, header: "<stdio.h>".}: File
      ## The standard input stream.
    stdout* {.importc: stdoutName, header: "<stdio.h>".}: File
      ## The standard output stream.
    stderr* {.importc: stderrName, header: "<stdio.h>".}: File
      ## The standard error stream.

when defined(useStdoutAsStdmsg):
  template stdmsg*: File = stdout
else:
  template stdmsg*: File = stderr
    ## Template which expands to either stdout or stderr depending on
    ## `useStdoutAsStdmsg` compile-time switch.

when defined(windows):
  proc c_fileno(f: File): cint {.
    importc: "_fileno", header: "<stdio.h>".}
else:
  proc c_fileno(f: File): cint {.
    importc: "fileno", header: "<fcntl.h>".}

when defined(windows):
  proc c_fdopen(filehandle: cint, mode: cstring): File {.
    importc: "_fdopen", header: "<stdio.h>".}
else:
  proc c_fdopen(filehandle: cint, mode: cstring): File {.
    importc: "fdopen", header: "<stdio.h>".}
proc c_fputs(c: cstring, f: File): cint {.
  importc: "fputs", header: "<stdio.h>", tags: [WriteIOEffect].}
proc c_fgets(c: cstring, n: cint, f: File): cstring {.
  importc: "fgets", header: "<stdio.h>", tags: [ReadIOEffect].}
proc c_fgetc(stream: File): cint {.
  importc: "fgetc", header: "<stdio.h>", tags: [].}
proc c_ungetc(c: cint, f: File): cint {.
  importc: "ungetc", header: "<stdio.h>", tags: [].}
proc c_putc(c: cint, stream: File): cint {.
  importc: "putc", header: "<stdio.h>", tags: [WriteIOEffect].}
proc c_fflush(f: File): cint {.
  importc: "fflush", header: "<stdio.h>".}
proc c_fclose(f: File): cint {.
  importc: "fclose", header: "<stdio.h>".}
proc c_clearerr(f: File) {.
  importc: "clearerr", header: "<stdio.h>".}
proc c_feof(f: File): cint {.
  importc: "feof", header: "<stdio.h>".}

when not declared(c_fwrite):
  proc c_fwrite(buf: pointer, size, n: csize_t, f: File): csize_t {.
    importc: "fwrite", header: "<stdio.h>".}

# C routine that is used here:
proc c_fread(buf: pointer, size, n: csize_t, f: File): csize_t {.
  importc: "fread", header: "<stdio.h>", tags: [ReadIOEffect].}
when defined(windows):
  when not defined(amd64):
    proc c_fseek(f: File, offset: int64, whence: cint): cint {.
      importc: "fseek", header: "<stdio.h>", tags: [].}
    proc c_ftell(f: File): int64 {.
      importc: "ftell", header: "<stdio.h>", tags: [].}
  else:
    proc c_fseek(f: File, offset: int64, whence: cint): cint {.
      importc: "_fseeki64", header: "<stdio.h>", tags: [].}
    when defined(tcc):
      proc c_fsetpos(f: File, pos: var int64): int32 {.
        importc: "fsetpos", header: "<stdio.h>", tags: [].}
      proc c_fgetpos(f: File, pos: var int64): int32 {.
        importc: "fgetpos", header: "<stdio.h>", tags: [].}
      proc c_telli64(f: cint): int64 {.
        importc: "_telli64", header: "<io.h>", tags: [].}
      proc c_ftell(f: File): int64 =
        # Taken from https://pt.osdn.net/projects/mingw/scm/git/mingw-org-wsl/blobs/5.4-trunk/mingwrt/mingwex/stdio/ftelli64.c
        result = -1'i64
        var pos: int64
        if c_fgetpos(f, pos) == 0 and c_fsetpos(f, pos) == 0:
          result = c_telli64(c_fileno(f))
    else:
      proc c_ftell(f: File): int64 {.
        importc: "_ftelli64", header: "<stdio.h>", tags: [].}
else:
  proc c_fseek(f: File, offset: int64, whence: cint): cint {.
    importc: "fseeko", header: "<stdio.h>", tags: [].}
  proc c_ftell(f: File): int64 {.
    importc: "ftello", header: "<stdio.h>", tags: [].}
proc c_ferror(f: File): cint {.
  importc: "ferror", header: "<stdio.h>", tags: [].}
proc c_setvbuf(f: File, buf: pointer, mode: cint, size: csize_t): cint {.
  importc: "setvbuf", header: "<stdio.h>", tags: [].}

proc c_fprintf(f: File, frmt: cstring): cint {.
  importc: "fprintf", header: "<stdio.h>", varargs, discardable.}
proc c_fputc(c: char, f: File): cint {.
  importc: "fputc", header: "<stdio.h>".}

proc raiseEIO(msg: string) {.noinline, noreturn.} =
  raise newException(IOError, msg)

proc raiseEOF() {.noinline, noreturn.} =
  raise newException(EOFError, "EOF reached")

proc strerror(errnum: cint): cstring {.importc, header: "<string.h>".}

when not defined(nimscript):
  var
    errno {.importc, header: "<errno.h>".}: cint ## error variable
    EINTR {.importc: "EINTR", header: "<errno.h>".}: cint

proc checkErr(f: File) =
  when not defined(nimscript):
    if c_ferror(f) != 0:
      let msg = "errno: " & $errno & " `" & $strerror(errno) & "`"
      c_clearerr(f)
      raiseEIO(msg)
  else:
    # shouldn't happen
    quit(1)

{.push stackTrace: off, profiler: off.}
proc readBuffer*(f: File, buffer: pointer, len: Natural): int {.
  tags: [ReadIOEffect], benign.} =
  ## Reads `len` bytes into the buffer pointed to by `buffer`. Returns
  ## the actual number of bytes that have been read which may be less than
  ## `len` (if not as many bytes are remaining), but not greater.
  result = cast[int](c_fread(buffer, 1, cast[csize_t](len), f))
  if result != len: checkErr(f)

proc readBytes*(f: File, a: var openArray[int8|uint8], start,
    len: Natural): int {.
  tags: [ReadIOEffect], benign.} =
  ## Reads `len` bytes into the buffer `a` starting at `a[start]`. Returns
  ## the actual number of bytes that have been read which may be less than
  ## `len` (if not as many bytes are remaining), but not greater.
  result = readBuffer(f, addr(a[start]), len)

proc readChars*(f: File, a: var openArray[char]): int {.tags: [ReadIOEffect], benign.} =
  ## Reads up to `a.len` bytes into the buffer `a`. Returns
  ## the actual number of bytes that have been read which may be less than
  ## `a.len` (if not as many bytes are remaining), but not greater.
  result = readBuffer(f, addr(a[0]), a.len)

proc readChars*(f: File, a: var openArray[char], start, len: Natural): int {.
  tags: [ReadIOEffect], benign, deprecated:
    "use other `readChars` overload, possibly via: readChars(toOpenArray(buf, start, len-1))".} =
  ## Reads `len` bytes into the buffer `a` starting at `a[start]`. Returns
  ## the actual number of bytes that have been read which may be less than
  ## `len` (if not as many bytes are remaining), but not greater.
  if (start + len) > len(a):
    raiseEIO("buffer overflow: (start+len) > length of openarray buffer")
  result = readBuffer(f, addr(a[start]), len)

proc write*(f: File, c: cstring) {.tags: [WriteIOEffect], benign.} =
  ## Writes a value to the file `f`. May throw an IO exception.
  discard c_fputs(c, f)
  checkErr(f)

proc writeBuffer*(f: File, buffer: pointer, len: Natural): int {.
  tags: [WriteIOEffect], benign.} =
  ## Writes the bytes of buffer pointed to by the parameter `buffer` to the
  ## file `f`. Returns the number of actual written bytes, which may be less
  ## than `len` in case of an error.
  result = cast[int](c_fwrite(buffer, 1, cast[csize_t](len), f))
  checkErr(f)

proc writeBytes*(f: File, a: openArray[int8|uint8], start, len: Natural): int {.
  tags: [WriteIOEffect], benign.} =
  ## Writes the bytes of `a[start..start+len-1]` to the file `f`. Returns
  ## the number of actual written bytes, which may be less than `len` in case
  ## of an error.
  var x = cast[ptr UncheckedArray[int8]](a)
  result = writeBuffer(f, addr(x[int(start)]), len)

proc writeChars*(f: File, a: openArray[char], start, len: Natural): int {.
  tags: [WriteIOEffect], benign.} =
  ## Writes the bytes of `a[start..start+len-1]` to the file `f`. Returns
  ## the number of actual written bytes, which may be less than `len` in case
  ## of an error.
  var x = cast[ptr UncheckedArray[int8]](a)
  result = writeBuffer(f, addr(x[int(start)]), len)

when defined(windows):
  proc writeWindows(f: File; s: string; doRaise = false) =
    # Don't ask why but the 'printf' family of function is the only thing
    # that writes utf-8 strings reliably on Windows. At least on my Win 10
    # machine. We also enable `setConsoleOutputCP(65001)` now by default.
    # But we cannot call printf directly as the string might contain \0.
    # So we have to loop over all the sections separated by potential \0s.
    var i = int c_fprintf(f, "%s", s)
    while i < s.len:
      if s[i] == '\0':
        let w = c_fputc('\0', f)
        if w != 0:
          if doRaise: raiseEIO("cannot write string to file")
          break
        inc i
      else:
        let w = c_fprintf(f, "%s", unsafeAddr s[i])
        if w <= 0:
          if doRaise: raiseEIO("cannot write string to file")
          break
        inc i, w

proc write*(f: File, s: string) {.tags: [WriteIOEffect], benign.} =
  when defined(windows):
    writeWindows(f, s, doRaise = true)
  else:
    if writeBuffer(f, cstring(s), s.len) != s.len:
      raiseEIO("cannot write string to file")
{.pop.}

when defined(nimscript):
  when defined(windows):
    const
      IOFBF = cint(0)
      IONBF = cint(4)
  else:
    # On all systems I could find, including Linux, Mac OS X, and the BSDs
    const
      IOFBF = cint(0)
      IONBF = cint(2)
else:
  var
    IOFBF {.importc: "_IOFBF", nodecl.}: cint
    IONBF {.importc: "_IONBF", nodecl.}: cint

const SupportIoctlInheritCtl = (defined(linux) or defined(bsd)) and
                              not defined(nimscript)
when SupportIoctlInheritCtl:
  var
    FIOCLEX {.importc, header: "<sys/ioctl.h>".}: cint
    FIONCLEX {.importc, header: "<sys/ioctl.h>".}: cint

  proc c_ioctl(fd: cint, request: cint): cint {.
    importc: "ioctl", header: "<sys/ioctl.h>", varargs.}
elif defined(posix) and not defined(lwip) and not defined(nimscript):
  var
    F_GETFD {.importc, header: "<fcntl.h>".}: cint
    F_SETFD {.importc, header: "<fcntl.h>".}: cint
    FD_CLOEXEC {.importc, header: "<fcntl.h>".}: cint

  proc c_fcntl(fd: cint, cmd: cint): cint {.
    importc: "fcntl", header: "<fcntl.h>", varargs.}
elif defined(windows):
  type
    WinDWORD = culong
    WinBOOL = cint

  const HANDLE_FLAG_INHERIT = 1.WinDWORD

  proc getOsfhandle(fd: cint): int {.
    importc: "_get_osfhandle", header: "<io.h>".}

  type
    IoHandle = distinct pointer
      ## Windows' HANDLE type. Defined as an untyped pointer but is **not**
      ## one. Named like this to avoid collision with other `system` modules.

  proc setHandleInformation(hObject: IoHandle, dwMask, dwFlags: WinDWORD):
                           WinBOOL {.stdcall, dynlib: "kernel32",
                                  importc: "SetHandleInformation".}

const
  BufSize = 4000

template closeIgnoreError(f: File) =
  ## Closes the file.
  if not f.isNil:
    discard c_fclose(f)


when defined(nimPreviewCheckedClose):
  proc close*(f: File) {.tags: [], gcsafe, sideEffect.} =
    ## Closes the file.
    ##
    ## Raises an IO exception in case of an error.
    if not f.isNil:
      let x = c_fclose(f)
      if x < 0:
        checkErr(f)
else:
  proc close*(f: File) {.tags: [], gcsafe, sideEffect.} =
    ## Closes the file.
    closeIgnoreError(f)

proc readChar*(f: File): char {.tags: [ReadIOEffect].} =
  ## Reads a single character from the stream `f`. Should not be used in
  ## performance sensitive code.
  let x = c_fgetc(f)
  if x < 0:
    checkErr(f)
    raiseEOF()
  result = char(x)

proc flushFile*(f: File) {.tags: [WriteIOEffect].} =
  ## Flushes `f`'s buffer.
  discard c_fflush(f)

proc getFileHandle*(f: File): FileHandle =
  ## Returns the file handle of the file `f`. This is only useful for
  ## platform specific programming.
  ## Note that on Windows this doesn't return the Windows-specific handle,
  ## but the C library's notion of a handle, whatever that means.
  ## Use `getOsFileHandle` instead.
  c_fileno(f)

proc getOsFileHandle*(f: File): FileHandle =
  ## Returns the OS file handle of the file `f`. This is only useful for
  ## platform specific programming.
  when defined(windows):
    result = FileHandle getOsfhandle(cint getFileHandle(f))
  else:
    result = c_fileno(f)

when defined(nimdoc) or (defined(posix) and not defined(nimscript)) or defined(windows):
  proc setInheritable*(f: FileHandle, inheritable: bool): bool =
    ## Controls whether a file handle can be inherited by child processes. Returns
    ## `true` on success. This requires the OS file handle, which can be
    ## retrieved via `getOsFileHandle <#getOsFileHandle,File>`_.
    ##
    ## This procedure is not guaranteed to be available for all platforms. Test for
    ## availability with `declared() <system.html#declared,untyped>`_.
    when SupportIoctlInheritCtl:
      result = c_ioctl(f, if inheritable: FIONCLEX else: FIOCLEX) != -1
    elif defined(freertos) or defined(zephyr):
      result = true
    elif defined(posix):
      var flags = c_fcntl(f, F_GETFD)
      if flags == -1:
        return false
      flags = if inheritable: flags and not FD_CLOEXEC else: flags or FD_CLOEXEC
      result = c_fcntl(f, F_SETFD, flags) != -1
    else:
      result = setHandleInformation(cast[IoHandle](f), HANDLE_FLAG_INHERIT,
                                    inheritable.WinDWORD) != 0

proc readLine*(f: File, line: var string): bool {.tags: [ReadIOEffect],
              benign.} =
  ## Reads a line of text from the file `f` into `line`. May throw an IO
  ## exception.
  ## A line of text may be delimited by `LF` or `CRLF`. The newline
  ## character(s) are not part of the returned string. Returns `false`
  ## if the end of the file has been reached, `true` otherwise. If
  ## `false` is returned `line` contains no new data.
  result = false

  proc c_memchr(s: pointer, c: cint, n: csize_t): pointer {.
    importc: "memchr", header: "<string.h>".}

  when defined(windows):
    proc readConsole(hConsoleInput: FileHandle, lpBuffer: pointer,
                     nNumberOfCharsToRead: int32,
                     lpNumberOfCharsRead: ptr int32,
                     pInputControl: pointer): int32 {.
      importc: "ReadConsoleW", stdcall, dynlib: "kernel32".}

    proc getLastError(): int32 {.
      importc: "GetLastError", stdcall, dynlib: "kernel32", sideEffect.}

    proc formatMessageW(dwFlags: int32, lpSource: pointer,
                        dwMessageId, dwLanguageId: int32,
                        lpBuffer: pointer, nSize: int32,
                        arguments: pointer): int32 {.
      importc: "FormatMessageW", stdcall, dynlib: "kernel32".}

    proc localFree(p: pointer) {.
      importc: "LocalFree", stdcall, dynlib: "kernel32".}

    proc isatty(f: File): bool =
      when defined(posix):
        proc isatty(fildes: FileHandle): cint {.
          importc: "isatty", header: "<unistd.h>".}
      else:
        proc isatty(fildes: FileHandle): cint {.
          importc: "_isatty", header: "<io.h>".}
      result = isatty(getFileHandle(f)) != 0'i32

    # this implies the file is open
    if f.isatty:
      const numberOfCharsToRead = 2048
      var numberOfCharsRead = 0'i32
      var buffer = newWideCString(numberOfCharsToRead)
      if readConsole(getOsFileHandle(f), addr(buffer[0]),
        numberOfCharsToRead, addr(numberOfCharsRead), nil) == 0:
        var error = getLastError()
        var errorMsg: string
        var msgbuf: WideCString
        if formatMessageW(0x00000100 or 0x00001000 or 0x00000200,
                        nil, error, 0, addr(msgbuf), 0, nil) != 0'i32:
          errorMsg = $msgbuf
          if msgbuf != nil:
            localFree(cast[pointer](msgbuf))
        raiseEIO("error: " & $error & " `" & errorMsg & "`")
      # input always ends with "\r\n"
      numberOfCharsRead -= 2
      # handle Ctrl+Z as EOF
      for i in 0..<numberOfCharsRead:
        if buffer[i].uint16 == 26: #Ctrl+Z
          close(f) #has the same effect as setting EOF
          if i == 0:
            line = ""
            return false
          numberOfCharsRead = i
          break
      buffer[numberOfCharsRead] = 0.Utf16Char
      when defined(nimv2):
        line = $toWideCString(buffer)
      else:
        line = $buffer
      return(true)

  var pos = 0

  # Use the currently reserved space for a first try
  var sp = max(line.len, 80)
  line.setLen(sp)

  while true:
    # memset to \L so that we can tell how far fgets wrote, even on EOF, where
    # fgets doesn't append an \L
    for i in 0..<sp: line[pos+i] = '\L'

    var fgetsSuccess: bool
    while true:
      # fixes #9634; this pattern may need to be abstracted as a template if reused;
      # likely other io procs need this for correctness.
      fgetsSuccess = c_fgets(cast[cstring](addr line[pos]), sp.cint, f) != nil
      if fgetsSuccess: break
      when not defined(nimscript):
        if errno == EINTR:
          errno = 0
          c_clearerr(f)
          continue
      checkErr(f)
      break

    let m = c_memchr(addr line[pos], '\L'.ord, cast[csize_t](sp))
    if m != nil:
      # \l found: Could be our own or the one by fgets, in any case, we're done
      var last = cast[int](m) - cast[int](addr line[0])
      if last > 0 and line[last-1] == '\c':
        line.setLen(last-1)
        return last > 1 or fgetsSuccess
      elif last > 0 and line[last-1] == '\0':
        # We have to distinguish among three possible cases:
        # \0\l\0 => line ending in a null character.
        # \0\l\l => last line without newline, null was put there by fgets.
        #   \0\l => last line without newline, null was put there by fgets.
        if last >= pos + sp - 1 or line[last+1] != '\0': # bug #21273
          dec last
      line.setLen(last)
      return last > 0 or fgetsSuccess
    else:
      # fgets will have inserted a null byte at the end of the string.
      dec sp
    # No \l found: Increase buffer and read more
    inc pos, sp
    sp = 128 # read in 128 bytes at a time
    line.setLen(pos+sp)

proc readLine*(f: File): string {.tags: [ReadIOEffect], benign.} =
  ## Reads a line of text from the file `f`. May throw an IO exception.
  ## A line of text may be delimited by `LF` or `CRLF`. The newline
  ## character(s) are not part of the returned string.
  result = newStringOfCap(80)
  if not readLine(f, result): raiseEOF()

proc write*(f: File, i: int) {.tags: [WriteIOEffect], benign.} =
  when sizeof(int) == 8:
    if c_fprintf(f, "%lld", i) < 0: checkErr(f)
  else:
    if c_fprintf(f, "%ld", i) < 0: checkErr(f)

proc write*(f: File, i: BiggestInt) {.tags: [WriteIOEffect], benign.} =
  when sizeof(BiggestInt) == 8:
    if c_fprintf(f, "%lld", i) < 0: checkErr(f)
  else:
    if c_fprintf(f, "%ld", i) < 0: checkErr(f)

proc write*(f: File, b: bool) {.tags: [WriteIOEffect], benign.} =
  if b: write(f, "true")
  else: write(f, "false")

proc write*(f: File, r: float32) {.tags: [WriteIOEffect], benign.} =
  var buffer {.noinit.}: array[65, char]
  discard writeFloatToBuffer(buffer, r)
  if c_fprintf(f, "%s", buffer[0].addr) < 0: checkErr(f)

proc write*(f: File, r: BiggestFloat) {.tags: [WriteIOEffect], benign.} =
  var buffer {.noinit.}: array[65, char]
  discard writeFloatToBuffer(buffer, r)
  if c_fprintf(f, "%s", buffer[0].addr) < 0: checkErr(f)

proc write*(f: File, c: char) {.tags: [WriteIOEffect], benign.} =
  discard c_putc(cint(c), f)

proc write*(f: File, a: varargs[string, `$`]) {.tags: [WriteIOEffect], benign.} =
  for x in items(a): write(f, x)

proc readAllBuffer(file: File): string =
  # This proc is for File we want to read but don't know how many
  # bytes we need to read before the buffer is empty.
  result = ""
  var buffer = newString(BufSize)
  while true:
    var bytesRead = readBuffer(file, addr(buffer[0]), BufSize)
    if bytesRead == BufSize:
      result.add(buffer)
    else:
      buffer.setLen(bytesRead)
      result.add(buffer)
      break

proc rawFileSize(file: File): int64 =
  # this does not raise an error opposed to `getFileSize`
  var oldPos = c_ftell(file)
  discard c_fseek(file, 0, 2) # seek the end of the file
  result = c_ftell(file)
  discard c_fseek(file, oldPos, 0)

proc endOfFile*(f: File): bool {.tags: [], benign.} =
  ## Returns true if `f` is at the end.
  var c = c_fgetc(f)
  discard c_ungetc(c, f)
  return c < 0'i32
  #result = c_feof(f) != 0

proc readAllFile(file: File, len: int64): string =
  # We acquire the filesize beforehand and hope it doesn't change.
  # Speeds things up.
  result = newString(len)
  let bytes = readBuffer(file, addr(result[0]), len)
  if endOfFile(file):
    if bytes.int64 < len:
      result.setLen(bytes)
  else:
    # We read all the bytes but did not reach the EOF
    # Try to read it as a buffer
    result.add(readAllBuffer(file))

proc readAllFile(file: File): string =
  var len = rawFileSize(file)
  result = readAllFile(file, len)

proc readAll*(file: File): string {.tags: [ReadIOEffect], benign.} =
  ## Reads all data from the stream `file`.
  ##
  ## Raises an IO exception in case of an error. It is an error if the
  ## current file position is not at the beginning of the file.

  # Separate handling needed because we need to buffer when we
  # don't know the overall length of the File.
  when declared(stdin):
    let len = if file != stdin: rawFileSize(file) else: -1
  else:
    let len = rawFileSize(file)
  if len > 0:
    result = readAllFile(file, len)
  else:
    result = readAllBuffer(file)

proc writeLine*[Ty](f: File, x: varargs[Ty, `$`]) {.inline,
                          tags: [WriteIOEffect], benign.} =
  ## Writes the values `x` to `f` and then writes "\\n".
  ## May throw an IO exception.
  for i in items(x):
    write(f, i)
  write(f, "\n")

# interface to the C procs:

when defined(windows):
  when defined(cpp):
    proc wfopen(filename, mode: WideCString): pointer {.
      importcpp: "_wfopen((const wchar_t*)#, (const wchar_t*)#)", nodecl.}
    proc wfreopen(filename, mode: WideCString, stream: File): File {.
      importcpp: "_wfreopen((const wchar_t*)#, (const wchar_t*)#, #)", nodecl.}
  else:
    proc wfopen(filename, mode: WideCString): pointer {.
      importc: "_wfopen", nodecl.}
    proc wfreopen(filename, mode: WideCString, stream: File): File {.
      importc: "_wfreopen", nodecl.}

  proc fopen(filename, mode: cstring): pointer =
    var f = newWideCString(filename)
    var m = newWideCString(mode)
    result = wfopen(f, m)

  proc freopen(filename, mode: cstring, stream: File): File =
    var f = newWideCString(filename)
    var m = newWideCString(mode)
    result = wfreopen(f, m, stream)

else:
  proc fopen(filename, mode: cstring): pointer {.importc: "fopen", nodecl.}
  proc freopen(filename, mode: cstring, stream: File): File {.
    importc: "freopen", nodecl.}

const
  NoInheritFlag =
    # Platform specific flag for creating a File without inheritance.
    when not defined(nimInheritHandles):
      when defined(windows):
        "N"
      elif defined(linux) or defined(bsd):
        "e"
      else:
        ""
    else:
      ""
  RawFormatOpen: array[FileMode, cstring] = [
    # used for open by FileHandle, which calls `fdopen`
    cstring("rb"), "wb", "w+b", "r+b", "ab"]
  FormatOpen: array[FileMode, cstring] = [
    cstring("rb" & NoInheritFlag), "wb" & NoInheritFlag, "w+b" & NoInheritFlag,
    "r+b" & NoInheritFlag, "ab" & NoInheritFlag
  ]
    #"rt", "wt", "w+t", "r+t", "at"
    # we always use binary here as for Nim the OS line ending
    # should not be translated.

when defined(posix) and not defined(nimscript):
  when defined(linux) and defined(amd64):
    type
      Mode {.importc: "mode_t", header: "<sys/types.h>".} = cint

      # fillers ensure correct size & offsets
      Stat {.importc: "struct stat",
              header: "<sys/stat.h>", final, pure.} = object ## struct stat
        filler_1: array[24, char]
        st_mode: Mode ## Mode of file
        filler_2: array[144 - 24 - 4, char]

    proc modeIsDir(m: Mode): bool =
      ## Test for a directory.
      (m and 0o170000) == 0o40000

  else:
    type
      Mode {.importc: "mode_t", header: "<sys/types.h>".} = cint

      Stat {.importc: "struct stat",
               header: "<sys/stat.h>", final, pure.} = object ## struct stat
        st_mode: Mode ## Mode of file

    proc modeIsDir(m: Mode): bool {.importc: "S_ISDIR", header: "<sys/stat.h>".}
      ## Test for a directory.

  proc c_fstat(a1: cint, a2: var Stat): cint {.
    importc: "fstat", header: "<sys/stat.h>".}


proc open*(f: var File, filename: string,
          mode: FileMode = fmRead,
          bufSize: int = -1): bool {.tags: [], raises: [], benign.} =
  ## Opens a file named `filename` with given `mode`.
  ##
  ## Default mode is readonly. Returns true if the file could be opened.
  ## This throws no exception if the file could not be opened.
  ##
  ## The file handle associated with the resulting `File` is not inheritable.
  var p = fopen(filename.cstring, FormatOpen[mode])
  if p != nil:
    var f2 = cast[File](p)
    when defined(posix) and not defined(nimscript):
      # How `fopen` handles opening a directory is not specified in ISO C and
      # POSIX. We do not want to handle directories as regular files that can
      # be opened.
      var res {.noinit.}: Stat
      if c_fstat(getFileHandle(f2), res) >= 0'i32 and modeIsDir(res.st_mode):
        closeIgnoreError(f2)
        return false
    when not defined(nimInheritHandles) and declared(setInheritable) and
         NoInheritFlag.len == 0:
      if not setInheritable(getOsFileHandle(f2), false):
        closeIgnoreError(f2)
        return false

    result = true
    f = cast[File](p)
    if bufSize > 0 and bufSize.uint <= high(uint):
      discard c_setvbuf(f, nil, IOFBF, cast[csize_t](bufSize))
    elif bufSize == 0:
      discard c_setvbuf(f, nil, IONBF, 0)
  else:
    result = false

proc reopen*(f: File, filename: string, mode: FileMode = fmRead): bool {.
  tags: [], benign.} =
  ## Reopens the file `f` with given `filename` and `mode`. This
  ## is often used to redirect the `stdin`, `stdout` or `stderr`
  ## file variables.
  ##
  ## Default mode is readonly. Returns true if the file could be reopened.
  ##
  ## The file handle associated with `f` won't be inheritable.
  if freopen(filename.cstring, FormatOpen[mode], f) != nil:
    when not defined(nimInheritHandles) and declared(setInheritable) and
         NoInheritFlag.len == 0:
      if not setInheritable(getOsFileHandle(f), false):
        closeIgnoreError(f)
        return false
    result = true
  else:
    result = false

proc open*(f: var File, filehandle: FileHandle,
           mode: FileMode = fmRead): bool {.tags: [], raises: [], benign.} =
  ## Creates a `File` from a `filehandle` with given `mode`.
  ##
  ## Default mode is readonly. Returns true if the file could be opened.
  ##
  ## The passed file handle will no longer be inheritable.
  when not defined(nimInheritHandles) and declared(setInheritable):
    let oshandle = when defined(windows): FileHandle getOsfhandle(
        filehandle) else: filehandle
    if not setInheritable(oshandle, false):
      return false
  f = c_fdopen(filehandle, RawFormatOpen[mode])
  result = f != nil

proc open*(filename: string,
            mode: FileMode = fmRead, bufSize: int = -1): File =
  ## Opens a file named `filename` with given `mode`.
  ##
  ## Default mode is readonly. Raises an `IOError` if the file
  ## could not be opened.
  ##
  ## The file handle associated with the resulting `File` is not inheritable.
  result = default(File)
  if not open(result, filename, mode, bufSize):
    raise newException(IOError, "cannot open: " & filename)

proc setFilePos*(f: File, pos: int64, relativeTo: FileSeekPos = fspSet) {.benign, sideEffect.} =
  ## Sets the position of the file pointer that is used for read/write
  ## operations. The file's first byte has the index zero.
  if c_fseek(f, pos, cint(relativeTo)) != 0:
    raiseEIO("cannot set file position")

proc getFilePos*(f: File): int64 {.benign.} =
  ## Retrieves the current position of the file pointer that is used to
  ## read from the file `f`. The file's first byte has the index zero.
  result = c_ftell(f)
  if result < 0: raiseEIO("cannot retrieve file position")

proc getFileSize*(f: File): int64 {.tags: [ReadIOEffect], benign.} =
  ## Retrieves the file size (in bytes) of `f`.
  let oldPos = getFilePos(f)
  discard c_fseek(f, 0, 2) # seek the end of the file
  result = getFilePos(f)
  setFilePos(f, oldPos)

proc setStdIoUnbuffered*() {.tags: [], benign.} =
  ## Configures `stdin`, `stdout` and `stderr` to be unbuffered.
  when declared(stdout):
    discard c_setvbuf(stdout, nil, IONBF, 0)
  when declared(stderr):
    discard c_setvbuf(stderr, nil, IONBF, 0)
  when declared(stdin):
    discard c_setvbuf(stdin, nil, IONBF, 0)


when defined(windows) and not defined(nimscript) and not defined(js):
  # work-around C's sucking abstraction:
  # BUGFIX: stdin and stdout should be binary files!
  proc c_setmode(handle, mode: cint) {.
    importc: when defined(bcc): "setmode" else: "_setmode",
    header: "<io.h>".}
  var
    O_BINARY {.importc: "_O_BINARY", header: "<fcntl.h>".}: cint

  # we use binary mode on Windows:
  c_setmode(c_fileno(stdin), O_BINARY)
  c_setmode(c_fileno(stdout), O_BINARY)
  c_setmode(c_fileno(stderr), O_BINARY)

when defined(windows) and appType == "console" and
    not defined(nimDontSetUtf8CodePage) and not defined(nimscript):
  import std/exitprocs

  proc setConsoleOutputCP(codepage: cuint): int32 {.stdcall, dynlib: "kernel32",
    importc: "SetConsoleOutputCP".}
  proc setConsoleCP(wCodePageID: cuint): int32 {.stdcall, dynlib: "kernel32",
    importc: "SetConsoleCP".}
  proc getConsoleOutputCP(): cuint {.stdcall, dynlib: "kernel32",
    importc: "GetConsoleOutputCP".}
  proc getConsoleCP(): cuint {.stdcall, dynlib: "kernel32",
    importc: "GetConsoleCP".}

  const Utf8codepage = 65001'u32

  let
    consoleOutputCP = getConsoleOutputCP()
    consoleCP = getConsoleCP()

  proc restoreConsoleOutputCP() = discard setConsoleOutputCP(consoleOutputCP)
  proc restoreConsoleCP() = discard setConsoleCP(consoleCP)

  if consoleOutputCP != Utf8codepage:
    discard setConsoleOutputCP(Utf8codepage)
    addExitProc(restoreConsoleOutputCP)

  if consoleCP != Utf8codepage:
    discard setConsoleCP(Utf8codepage)
    addExitProc(restoreConsoleCP)

proc readFile*(filename: string): string {.tags: [ReadIOEffect], benign.} =
  ## Opens a file named `filename` for reading, calls `readAll
  ## <#readAll,File>`_ and closes the file afterwards. Returns the string.
  ## Raises an IO exception in case of an error. If you need to call
  ## this inside a compile time macro you can use `staticRead
  ## <system.html#staticRead,string>`_.
  var f: File = nil
  if open(f, filename):
    try:
      result = readAll(f)
    finally:
      close(f)
  else:
    raise newException(IOError, "cannot open: " & filename)

proc writeFile*(filename, content: string) {.tags: [WriteIOEffect], benign.} =
  ## Opens a file named `filename` for writing. Then writes the
  ## `content` completely to the file and closes the file afterwards.
  ## Raises an IO exception in case of an error.
  var f: File = nil
  if open(f, filename, fmWrite):
    try:
      f.write(content)
    finally:
      close(f)
  else:
    raise newException(IOError, "cannot open: " & filename)

proc writeFile*(filename: string, content: openArray[byte]) {.since: (1, 1).} =
  ## Opens a file named `filename` for writing. Then writes the
  ## `content` completely to the file and closes the file afterwards.
  ## Raises an IO exception in case of an error.
  var f: File = nil
  if open(f, filename, fmWrite):
    try:
      discard f.writeBuffer(unsafeAddr content[0], content.len)
    finally:
      close(f)
  else:
    raise newException(IOError, "cannot open: " & filename)

proc readLines*(filename: string, n: Natural): seq[string] =
  ## Reads `n` lines from the file named `filename`. Raises an IO exception
  ## in case of an error. Raises EOF if file does not contain at least `n` lines.
  ## Available at compile time. A line of text may be delimited by `LF` or `CRLF`.
  ## The newline character(s) are not part of the returned strings.
  var f: File = nil
  if open(f, filename):
    try:
      result = newSeq[string](n)
      for i in 0 .. n - 1:
        if not readLine(f, result[i]):
          raiseEOF()
    finally:
      close(f)
  else:
    raise newException(IOError, "cannot open: " & filename)

template readLines*(filename: string): seq[
    string] {.deprecated: "use readLines with two arguments".} =
  readLines(filename, 1)

iterator lines*(filename: string): string {.tags: [ReadIOEffect].} =
  ## Iterates over any line in the file named `filename`.
  ##
  ## If the file does not exist `IOError` is raised. The trailing newline
  ## character(s) are removed from the iterated lines. Example:
  ##
  runnableExamples:
    import std/strutils

    proc transformLetters(filename: string) =
      var buffer = ""
      for line in filename.lines:
        buffer.add(line.replace("a", "0") & '\n')
      writeFile(filename, buffer)
  var f = open(filename, bufSize = 8000)
  try:
    var res = newStringOfCap(80)
    while f.readLine(res): yield res
  finally:
    close(f)

iterator lines*(f: File): string {.tags: [ReadIOEffect].} =
  ## Iterates over any line in the file `f`.
  ##
  ## The trailing newline character(s) are removed from the iterated lines.
  ##
  runnableExamples:
    proc countZeros(filename: File): tuple[lines, zeros: int] =
      for line in filename.lines:
        for letter in line:
          if letter == '0':
            result.zeros += 1
        result.lines += 1
  var res = newStringOfCap(80)
  while f.readLine(res): yield res

template `&=`*(f: File, x: typed) =
  ## An alias for `write`.
  write(f, x)
