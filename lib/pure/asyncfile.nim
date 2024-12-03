#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements asynchronous file reading and writing.
##
##   ```Nim
##   import std/[asyncfile, asyncdispatch, os]
##
##   proc main() {.async.} =
##     var file = openAsync(getTempDir() / "foobar.txt", fmReadWrite)
##     await file.write("test")
##     file.setFilePos(0)
##     let data = await file.readAll()
##     doAssert data == "test"
##     file.close()
##
##   waitFor main()
##   ```

import std/[asyncdispatch, os]

when defined(nimPreviewSlimSystem):
  import std/[assertions, syncio]
  when defined(windows) or defined(nimdoc):
    import std/widestrs

# TODO: Fix duplication introduced by PR #4683.

when defined(windows) or defined(nimdoc):
  import std/winlean
else:
  import std/posix

type
  AsyncFile* = ref object
    fd: AsyncFD
    offset: int64

when defined(windows) or defined(nimdoc):
  proc getDesiredAccess(mode: FileMode): int32 =
    case mode
    of fmRead:
      result = GENERIC_READ
    of fmWrite, fmAppend:
      result = GENERIC_WRITE
    of fmReadWrite, fmReadWriteExisting:
      result = GENERIC_READ or GENERIC_WRITE

  proc getCreationDisposition(mode: FileMode, filename: string): int32 =
    case mode
    of fmRead, fmReadWriteExisting:
      OPEN_EXISTING
    of fmReadWrite, fmWrite:
      CREATE_ALWAYS
    of fmAppend:
      OPEN_ALWAYS
else:
  proc getPosixFlags(mode: FileMode): cint =
    case mode
    of fmRead:
      result = O_RDONLY
    of fmWrite:
      result = O_WRONLY or O_CREAT or O_TRUNC
    of fmAppend:
      result = O_WRONLY or O_CREAT or O_APPEND
    of fmReadWrite:
      result = O_RDWR or O_CREAT or O_TRUNC
    of fmReadWriteExisting:
      result = O_RDWR
    result = result or O_NONBLOCK

proc getFileSize*(f: AsyncFile): int64 =
  ## Retrieves the specified file's size.
  when defined(windows) or defined(nimdoc):
    var high: DWORD
    let low = getFileSize(f.fd.Handle, addr high)
    if low == INVALID_FILE_SIZE:
      raiseOSError(osLastError())
    result = (high shl 32) or low
  else:
    let curPos = lseek(f.fd.cint, 0, SEEK_CUR)
    result = lseek(f.fd.cint, 0, SEEK_END)
    f.offset = lseek(f.fd.cint, curPos, SEEK_SET)
    assert(f.offset == curPos)

proc newAsyncFile*(fd: AsyncFD): AsyncFile =
  ## Creates `AsyncFile` with a previously opened file descriptor `fd`.
  new result
  result.fd = fd
  register(fd)

proc openAsync*(filename: string, mode = fmRead): AsyncFile =
  ## Opens a file specified by the path in `filename` using
  ## the specified FileMode `mode` asynchronously.
  when defined(windows) or defined(nimdoc):
    let flags = FILE_FLAG_OVERLAPPED or FILE_ATTRIBUTE_NORMAL
    let desiredAccess = getDesiredAccess(mode)
    let creationDisposition = getCreationDisposition(mode, filename)
    let fd = createFileW(newWideCString(filename), desiredAccess,
        FILE_SHARE_READ,
        nil, creationDisposition, flags, 0)

    if fd == INVALID_HANDLE_VALUE:
      raiseOSError(osLastError())

    result = newAsyncFile(fd.AsyncFD)

    if mode == fmAppend:
      result.offset = getFileSize(result)

  else:
    let flags = getPosixFlags(mode)
    # RW (Owner), RW (Group), R (Other)
    let perm = S_IRUSR or S_IWUSR or S_IRGRP or S_IWGRP or S_IROTH
    let fd = open(filename, flags, perm)
    if fd == -1:
      raiseOSError(osLastError())

    result = newAsyncFile(fd.AsyncFD)

proc readBuffer*(f: AsyncFile, buf: pointer, size: int): Future[int] =
  ## Read `size` bytes from the specified file asynchronously starting at
  ## the current position of the file pointer.
  ##
  ## If the file pointer is past the end of the file then zero is returned
  ## and no bytes are read into `buf`
  var retFuture = newFuture[int]("asyncfile.readBuffer")

  when defined(windows) or defined(nimdoc):
    var ol = newCustom()
    ol.data = CompletionData(fd: f.fd, cb:
      proc (fd: AsyncFD, bytesCount: DWORD, errcode: OSErrorCode) =
        if not retFuture.finished:
          if errcode == OSErrorCode(-1):
            assert bytesCount > 0
            assert bytesCount <= size
            f.offset.inc bytesCount
            retFuture.complete(bytesCount)
          else:
            if errcode.int32 == ERROR_HANDLE_EOF:
              retFuture.complete(0)
            else:
              retFuture.fail(newOSError(errcode))
    )
    ol.offset = DWORD(f.offset and 0xffffffff)
    ol.offsetHigh = DWORD(f.offset shr 32)

    # According to MSDN we're supposed to pass nil to lpNumberOfBytesRead.
    let ret = readFile(f.fd.Handle, buf, size.int32, nil,
                       cast[POVERLAPPED](ol))
    if not ret.bool:
      let err = osLastError()
      if err.int32 != ERROR_IO_PENDING:
        GC_unref(ol)
        if err.int32 == ERROR_HANDLE_EOF:
          # This happens in Windows Server 2003
          retFuture.complete(0)
        else:
          retFuture.fail(newOSError(err))
    else:
      # Request completed immediately.
      var bytesRead: DWORD
      let overlappedRes = getOverlappedResult(f.fd.Handle,
          cast[POVERLAPPED](ol), bytesRead, false.WINBOOL)
      if not overlappedRes.bool:
        let err = osLastError()
        if err.int32 == ERROR_HANDLE_EOF:
          retFuture.complete(0)
        else:
          retFuture.fail(newOSError(osLastError()))
      else:
        assert bytesRead > 0
        assert bytesRead <= size
        f.offset.inc bytesRead
        retFuture.complete(bytesRead)
  else:
    proc cb(fd: AsyncFD): bool =
      result = true
      let res = read(fd.cint, cast[cstring](buf), size.cint)
      if res < 0:
        let lastError = osLastError()
        if lastError.int32 != EAGAIN:
          retFuture.fail(newOSError(lastError))
        else:
          result = false # We still want this callback to be called.
      elif res == 0:
        # EOF
        retFuture.complete(0)
      else:
        f.offset.inc(res)
        retFuture.complete(res)

    if not cb(f.fd):
      addRead(f.fd, cb)

  return retFuture

proc read*(f: AsyncFile, size: int): Future[string] =
  ## Read `size` bytes from the specified file asynchronously starting at
  ## the current position of the file pointer. `size` should be greater than zero.
  ##
  ## If the file pointer is past the end of the file then an empty string is
  ## returned.
  assert size > 0
  var retFuture = newFuture[string]("asyncfile.read")

  when defined(windows) or defined(nimdoc):
    var buffer = alloc0(size)

    var ol = newCustom()
    ol.data = CompletionData(fd: f.fd, cb:
      proc (fd: AsyncFD, bytesCount: DWORD, errcode: OSErrorCode) =
        if not retFuture.finished:
          if errcode == OSErrorCode(-1):
            assert bytesCount > 0
            assert bytesCount <= size
            var data = newString(bytesCount)
            copyMem(addr data[0], buffer, bytesCount)
            f.offset.inc bytesCount
            retFuture.complete($data)
          else:
            if errcode.int32 == ERROR_HANDLE_EOF:
              retFuture.complete("")
            else:
              retFuture.fail(newOSError(errcode))
        if buffer != nil:
          dealloc buffer
          buffer = nil
    )
    ol.offset = DWORD(f.offset and 0xffffffff)
    ol.offsetHigh = DWORD(f.offset shr 32)

    # According to MSDN we're supposed to pass nil to lpNumberOfBytesRead.
    let ret = readFile(f.fd.Handle, buffer, size.int32, nil,
                       cast[POVERLAPPED](ol))
    if not ret.bool:
      let err = osLastError()
      if err.int32 != ERROR_IO_PENDING:
        if buffer != nil:
          dealloc buffer
          buffer = nil
        GC_unref(ol)

        if err.int32 == ERROR_HANDLE_EOF:
          # This happens in Windows Server 2003
          retFuture.complete("")
        else:
          retFuture.fail(newOSError(err))
    else:
      # Request completed immediately.
      var bytesRead: DWORD
      let overlappedRes = getOverlappedResult(f.fd.Handle,
          cast[POVERLAPPED](ol), bytesRead, false.WINBOOL)
      if not overlappedRes.bool:
        let err = osLastError()
        if err.int32 == ERROR_HANDLE_EOF:
          retFuture.complete("")
        else:
          retFuture.fail(newOSError(osLastError()))
      else:
        assert bytesRead > 0
        assert bytesRead <= size
        var data = newString(bytesRead)
        copyMem(addr data[0], buffer, bytesRead)
        f.offset.inc bytesRead
        retFuture.complete($data)
  else:
    var readBuffer = newString(size)

    proc cb(fd: AsyncFD): bool =
      result = true
      let res = read(fd.cint, addr readBuffer[0], size.cint)
      if res < 0:
        let lastError = osLastError()
        if lastError.int32 != EAGAIN:
          retFuture.fail(newOSError(lastError))
        else:
          result = false # We still want this callback to be called.
      elif res == 0:
        # EOF
        f.offset = lseek(fd.cint, 0, SEEK_CUR)
        retFuture.complete("")
      else:
        readBuffer.setLen(res)
        f.offset.inc(res)
        retFuture.complete(readBuffer)

    if not cb(f.fd):
      addRead(f.fd, cb)

  return retFuture

proc readLine*(f: AsyncFile): Future[string] {.async.} =
  ## Reads a single line from the specified file asynchronously.
  result = ""
  while true:
    var c = await read(f, 1)
    if c.len == 0:
      break
    if c[0] == '\c':
      c = await read(f, 1)
      break
    if c[0] == '\L' or c == "":
      break
    else:
      result.add(c)

proc getFilePos*(f: AsyncFile): int64 =
  ## Retrieves the current position of the file pointer that is
  ## used to read from the specified file. The file's first byte has the
  ## index zero.
  f.offset

proc setFilePos*(f: AsyncFile, pos: int64) =
  ## Sets the position of the file pointer that is used for read/write
  ## operations. The file's first byte has the index zero.
  f.offset = pos
  when not defined(windows) and not defined(nimdoc):
    let ret = lseek(f.fd.cint, pos.Off, SEEK_SET)
    if ret == -1:
      raiseOSError(osLastError())

proc readAll*(f: AsyncFile): Future[string] {.async.} =
  ## Reads all data from the specified file.
  result = ""
  while true:
    let data = await read(f, 4000)
    if data.len == 0:
      return
    result.add data

proc writeBuffer*(f: AsyncFile, buf: pointer, size: int): Future[void] =
  ## Writes `size` bytes from `buf` to the file specified asynchronously.
  ##
  ## The returned Future will complete once all data has been written to the
  ## specified file.
  var retFuture = newFuture[void]("asyncfile.writeBuffer")
  when defined(windows) or defined(nimdoc):
    var ol = newCustom()
    ol.data = CompletionData(fd: f.fd, cb:
      proc (fd: AsyncFD, bytesCount: DWORD, errcode: OSErrorCode) =
        if not retFuture.finished:
          if errcode == OSErrorCode(-1):
            assert bytesCount == size.int32
            retFuture.complete()
          else:
            retFuture.fail(newOSError(errcode))
    )
    # passing -1 here should work according to MSDN, but doesn't. For more
    # information see
    # https://stackoverflow.com/questions/33650899/does-asynchronous-file-
    #   appending-in-windows-preserve-order
    ol.offset = DWORD(f.offset and 0xffffffff)
    ol.offsetHigh = DWORD(f.offset shr 32)
    f.offset.inc(size)

    # According to MSDN we're supposed to pass nil to lpNumberOfBytesWritten.
    let ret = writeFile(f.fd.Handle, buf, size.int32, nil,
                       cast[POVERLAPPED](ol))
    if not ret.bool:
      let err = osLastError()
      if err.int32 != ERROR_IO_PENDING:
        GC_unref(ol)
        retFuture.fail(newOSError(err))
    else:
      # Request completed immediately.
      var bytesWritten: DWORD
      let overlappedRes = getOverlappedResult(f.fd.Handle,
          cast[POVERLAPPED](ol), bytesWritten, false.WINBOOL)
      if not overlappedRes.bool:
        retFuture.fail(newOSError(osLastError()))
      else:
        assert bytesWritten == size.int32
        retFuture.complete()
  else:
    var written = 0

    proc cb(fd: AsyncFD): bool =
      result = true
      let remainderSize = size - written
      var cbuf = cast[cstring](buf)
      let res = write(fd.cint, addr cbuf[written], remainderSize.cint)
      if res < 0:
        let lastError = osLastError()
        if lastError.int32 != EAGAIN:
          retFuture.fail(newOSError(lastError))
        else:
          result = false # We still want this callback to be called.
      else:
        written.inc res
        f.offset.inc res
        if res != remainderSize:
          result = false # We still have data to write.
        else:
          retFuture.complete()

    if not cb(f.fd):
      addWrite(f.fd, cb)
  return retFuture

proc write*(f: AsyncFile, data: string): Future[void] =
  ## Writes `data` to the file specified asynchronously.
  ##
  ## The returned Future will complete once all data has been written to the
  ## specified file.
  var retFuture = newFuture[void]("asyncfile.write")
  var copy = data
  when defined(windows) or defined(nimdoc):
    var buffer = alloc0(data.len)
    copyMem(buffer, copy.cstring, data.len)

    var ol = newCustom()
    ol.data = CompletionData(fd: f.fd, cb:
      proc (fd: AsyncFD, bytesCount: DWORD, errcode: OSErrorCode) =
        if not retFuture.finished:
          if errcode == OSErrorCode(-1):
            assert bytesCount == data.len.int32
            retFuture.complete()
          else:
            retFuture.fail(newOSError(errcode))
        if buffer != nil:
          dealloc buffer
          buffer = nil
    )
    ol.offset = DWORD(f.offset and 0xffffffff)
    ol.offsetHigh = DWORD(f.offset shr 32)
    f.offset.inc(data.len)

    # According to MSDN we're supposed to pass nil to lpNumberOfBytesWritten.
    let ret = writeFile(f.fd.Handle, buffer, data.len.int32, nil,
                       cast[POVERLAPPED](ol))
    if not ret.bool:
      let err = osLastError()
      if err.int32 != ERROR_IO_PENDING:
        if buffer != nil:
          dealloc buffer
          buffer = nil
        GC_unref(ol)
        retFuture.fail(newOSError(err))
    else:
      # Request completed immediately.
      var bytesWritten: DWORD
      let overlappedRes = getOverlappedResult(f.fd.Handle,
          cast[POVERLAPPED](ol), bytesWritten, false.WINBOOL)
      if not overlappedRes.bool:
        retFuture.fail(newOSError(osLastError()))
      else:
        assert bytesWritten == data.len.int32
        retFuture.complete()
  else:
    var written = 0

    proc cb(fd: AsyncFD): bool =
      result = true

      let remainderSize = data.len - written

      let res =
        if data.len == 0:
          write(fd.cint, copy.cstring, 0)
        else:
          write(fd.cint, addr copy[written], remainderSize.cint)

      if res < 0:
        let lastError = osLastError()
        if lastError.int32 != EAGAIN:
          retFuture.fail(newOSError(lastError))
        else:
          result = false # We still want this callback to be called.
      else:
        written.inc res
        f.offset.inc res
        if res != remainderSize:
          result = false # We still have data to write.
        else:
          retFuture.complete()

    if not cb(f.fd):
      addWrite(f.fd, cb)
  return retFuture

proc setFileSize*(f: AsyncFile, length: int64) =
  ## Set a file length.
  when defined(windows) or defined(nimdoc):
    var
      high = (length shr 32).DWORD
    let
      low = (length and 0xffffffff).DWORD
      status = setFilePointer(f.fd.Handle, low, addr high, 0)
      lastErr = osLastError()
    if (status == INVALID_SET_FILE_POINTER and lastErr.int32 != NO_ERROR) or
        (setEndOfFile(f.fd.Handle) == 0):
      raiseOSError(osLastError())
  else:
    # will truncate if Off is a 32-bit type!
    if ftruncate(f.fd.cint, length.Off) == -1:
      raiseOSError(osLastError())

proc close*(f: AsyncFile) =
  ## Closes the file specified.
  unregister(f.fd)
  when defined(windows) or defined(nimdoc):
    if not closeHandle(f.fd.Handle).bool:
      raiseOSError(osLastError())
  else:
    if close(f.fd.cint) == -1:
      raiseOSError(osLastError())

proc writeFromStream*(f: AsyncFile, fs: FutureStream[string]) {.async.} =
  ## Reads data from the specified future stream until it is completed.
  ## The data which is read is written to the file immediately and
  ## freed from memory.
  ##
  ## This procedure is perfect for saving streamed data to a file without
  ## wasting memory.
  while true:
    let (hasValue, value) = await fs.read()
    if hasValue:
      await f.write(value)
    else:
      break

proc readToStream*(f: AsyncFile, fs: FutureStream[string]) {.async.} =
  ## Writes data to the specified future stream as the file is read.
  while true:
    let data = await read(f, 4000)
    if data.len == 0:
      break
    await fs.write(data)

  fs.complete()
