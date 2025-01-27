#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module provides a stream interface and two implementations thereof:
## the `FileStream <#FileStream>`_ and the `StringStream <#StringStream>`_
## which implement the stream interface for Nim file objects (`File`) and
## strings.
##
## Other modules may provide other implementations for this standard
## stream interface.
##
## .. warning:: Due to the use of `pointer`, the `readData`, `peekData` and
## `writeData` interfaces are not available on the compile-time VM, and must
## be cast from a `ptr string` on the JS backend. However, `readDataStr` is
## available generally in place of `readData`.
##
## Basic usage
## ===========
##
## The basic flow of using this module is:
##
## 1. Open input stream
## 2. Read or write stream
## 3. Close stream
##
## StringStream example
## --------------------
##
##   ```Nim
##   import std/streams
##
##   var strm = newStringStream("""The first line
##   the second line
##   the third line""")
##
##   var line = ""
##
##   while strm.readLine(line):
##     echo line
##
##   # Output:
##   # The first line
##   # the second line
##   # the third line
##
##   strm.close()
##   ```
##
## FileStream example
## ------------------
##
## Write file stream example:
##
##   ```Nim
##   import std/streams
##
##   var strm = newFileStream("somefile.txt", fmWrite)
##   var line = ""
##
##   if not isNil(strm):
##     strm.writeLine("The first line")
##     strm.writeLine("the second line")
##     strm.writeLine("the third line")
##     strm.close()
##
##   # Output (somefile.txt):
##   # The first line
##   # the second line
##   # the third line
##   ```
##
## Read file stream example:
##
##   ```Nim
##   import std/streams
##
##   var strm = newFileStream("somefile.txt", fmRead)
##   var line = ""
##
##   if not isNil(strm):
##     while strm.readLine(line):
##       echo line
##     strm.close()
##
##   # Output:
##   # The first line
##   # the second line
##   # the third line
##   ```
##
## See also
## ========
## * `asyncstreams module <asyncstreams.html>`_
## * `io module <syncio.html>`_ for `FileMode enum <syncio.html#FileMode>`_

import std/private/since

when defined(nimPreviewSlimSystem):
  import std/syncio
  export FileMode

proc newEIO(msg: string): owned(ref IOError) =
  new(result)
  result.msg = msg

type
  Stream* = ref StreamObj
    ## All procedures of this module use this type.
    ## Procedures don't directly use `StreamObj <#StreamObj>`_.
  StreamObj* = object of RootObj
    ## Stream interface that supports writing or reading.
    ##
    ## **Note:**
    ## * That these fields here shouldn't be used directly.
    ##   They are accessible so that a stream implementation can override them.
    closeImpl*: proc (s: Stream)
      {.nimcall, raises: [IOError, OSError], tags: [WriteIOEffect], gcsafe.}
    atEndImpl*: proc (s: Stream): bool
      {.nimcall, raises: [Defect, IOError, OSError], tags: [], gcsafe.}
    setPositionImpl*: proc (s: Stream, pos: int)
      {.nimcall, raises: [Defect, IOError, OSError], tags: [], gcsafe.}
    getPositionImpl*: proc (s: Stream): int
      {.nimcall, raises: [Defect, IOError, OSError], tags: [], gcsafe.}

    readDataStrImpl*: proc (s: Stream, buffer: var string, slice: Slice[int]): int
      {.nimcall, raises: [Defect, IOError, OSError], tags: [ReadIOEffect], gcsafe.}

    readLineImpl*: proc(s: Stream, line: var string): bool
      {.nimcall, raises: [Defect, IOError, OSError], tags: [ReadIOEffect], gcsafe.}

    readDataImpl*: proc (s: Stream, buffer: pointer, bufLen: int): int
      {.nimcall, raises: [Defect, IOError, OSError], tags: [ReadIOEffect], gcsafe.}
    peekDataImpl*: proc (s: Stream, buffer: pointer, bufLen: int): int
      {.nimcall, raises: [Defect, IOError, OSError], tags: [ReadIOEffect], gcsafe.}
    writeDataImpl*: proc (s: Stream, buffer: pointer, bufLen: int)
      {.nimcall, raises: [Defect, IOError, OSError], tags: [WriteIOEffect], gcsafe.}

    flushImpl*: proc (s: Stream)
      {.nimcall, raises: [Defect, IOError, OSError], tags: [WriteIOEffect], gcsafe.}

proc flush*(s: Stream) =
  ## Flushes the buffers that the stream `s` might use.
  ##
  ## This procedure causes any unwritten data for that stream to be delivered
  ## to the host environment to be written to the file.
  ##
  ## See also:
  ## * `close proc <#close,Stream>`_
  runnableExamples:
    from std/os import removeFile

    var strm = newFileStream("somefile.txt", fmWrite)

    doAssert "Before write:" & readFile("somefile.txt") == "Before write:"
    strm.write("hello")
    doAssert "After  write:" & readFile("somefile.txt") == "After  write:"

    strm.flush()
    doAssert "After  flush:" & readFile("somefile.txt") == "After  flush:hello"
    strm.write("HELLO")
    strm.flush()
    doAssert "After  flush:" & readFile("somefile.txt") == "After  flush:helloHELLO"

    strm.close()
    doAssert "After  close:" & readFile("somefile.txt") == "After  close:helloHELLO"
    removeFile("somefile.txt")

  if not isNil(s.flushImpl): s.flushImpl(s)

proc close*(s: Stream) =
  ## Closes the stream `s`.
  ##
  ## See also:
  ## * `flush proc <#flush,Stream>`_
  runnableExamples:
    block:
      let strm = newStringStream("The first line\nthe second line\nthe third line")
      ## do something...
      strm.close()

    block:
      let strm = newFileStream("amissingfile.txt")
      # deferring works even if newFileStream fails
      defer: strm.close()
      if not isNil(strm):
        ## do something...

  if not isNil(s) and not isNil(s.closeImpl):
    s.closeImpl(s)

proc atEnd*(s: Stream): bool =
  ## Checks if more data can be read from `s`. Returns ``true`` if all data has
  ## been read.
  runnableExamples:
    var strm = newStringStream("The first line\nthe second line\nthe third line")
    var line = ""
    doAssert strm.atEnd() == false
    while strm.readLine(line):
      discard
    doAssert strm.atEnd() == true
    strm.close()

  result = s.atEndImpl(s)

proc setPosition*(s: Stream, pos: int) =
  ## Sets the position `pos` of the stream `s`.
  runnableExamples:
    var strm = newStringStream("The first line\nthe second line\nthe third line")
    strm.setPosition(4)
    doAssert strm.readLine() == "first line"
    strm.setPosition(0)
    doAssert strm.readLine() == "The first line"
    strm.close()

  s.setPositionImpl(s, pos)

proc getPosition*(s: Stream): int =
  ## Retrieves the current position in the stream `s`.
  runnableExamples:
    var strm = newStringStream("The first line\nthe second line\nthe third line")
    doAssert strm.getPosition() == 0
    discard strm.readLine()
    doAssert strm.getPosition() == 15
    strm.close()

  result = s.getPositionImpl(s)

proc readData*(s: Stream, buffer: pointer, bufLen: int): int =
  ## Low level proc that reads data into an untyped `buffer` of `bufLen` size.
  ##
  ## **JS note:** `buffer` is treated as a ``ptr string`` and written to between
  ## ``0..<bufLen``.
  runnableExamples:
    var strm = newStringStream("abcde")
    var buffer: array[6, char]
    doAssert strm.readData(addr(buffer), 1024) == 5
    doAssert buffer == ['a', 'b', 'c', 'd', 'e', '\x00']
    doAssert strm.atEnd() == true
    strm.close()

  result = s.readDataImpl(s, buffer, bufLen)

proc readDataStr*(s: Stream, buffer: var string, slice: Slice[int]): int =
  ## Low level proc that reads data into a string ``buffer`` at ``slice``.
  runnableExamples:
    var strm = newStringStream("abcde")
    var buffer = "12345"
    doAssert strm.readDataStr(buffer, 0..3) == 4
    doAssert buffer == "abcd5"
    strm.close()

  if s.readDataStrImpl != nil:
    result = s.readDataStrImpl(s, buffer, slice)
  else:
    # fallback
    when declared(prepareMutation):
      # buffer might potentially be a CoW literal with ARC
      prepareMutation(buffer)
    result = s.readData(addr buffer[slice.a], slice.b + 1 - slice.a)

template jsOrVmBlock(caseJsOrVm, caseElse: untyped): untyped =
  when nimvm:
    block:
      caseJsOrVm
  else:
    block:
      when defined(js) or defined(nimscript):
        # nimscript has to be here to avoid semantic checking of caseElse
        caseJsOrVm
      else:
        caseElse

when (NimMajor, NimMinor) >= (1, 3) or not defined(js):
  proc readAll*(s: Stream): string =
    ## Reads all available data.
    runnableExamples:
      var strm = newStringStream("The first line\nthe second line\nthe third line")
      doAssert strm.readAll() == "The first line\nthe second line\nthe third line"
      doAssert strm.atEnd() == true
      strm.close()

    const bufferSize = 1024
    result = ""
    jsOrVmBlock:
      var buffer2 = newString(bufferSize)
      while true:
        let readBytes = readDataStr(s, buffer2, 0..<bufferSize)
        if readBytes == 0:
          break
        let prevLen = result.len
        result.setLen(prevLen + readBytes)
        result[prevLen..<prevLen+readBytes] = buffer2[0..<readBytes]
        if readBytes < bufferSize:
          break
    do: # not JS or VM
      var buffer {.noinit.}: array[bufferSize, char]
      while true:
        let readBytes = readData(s, addr(buffer[0]), bufferSize)
        if readBytes == 0:
          break
        let prevLen = result.len
        result.setLen(prevLen + readBytes)
        copyMem(addr(result[prevLen]), addr(buffer[0]), readBytes)
        if readBytes < bufferSize:
          break

proc peekData*(s: Stream, buffer: pointer, bufLen: int): int =
  ## Low level proc that reads data into an untyped `buffer` of `bufLen` size
  ## without moving stream position.
  ##
  ## **JS note:** `buffer` is treated as a ``ptr string`` and written to between
  ## ``0..<bufLen``.
  runnableExamples:
    var strm = newStringStream("abcde")
    var buffer: array[6, char]
    doAssert strm.peekData(addr(buffer), 1024) == 5
    doAssert buffer == ['a', 'b', 'c', 'd', 'e', '\x00']
    doAssert strm.atEnd() == false
    strm.close()

  result = s.peekDataImpl(s, buffer, bufLen)

proc writeData*(s: Stream, buffer: pointer, bufLen: int) =
  ## Low level proc that writes an untyped `buffer` of `bufLen` size
  ## to the stream `s`.
  ##
  ## **JS note:** `buffer` is treated as a ``ptr string`` and read between
  ## ``0..<bufLen``.
  runnableExamples:
    ## writeData
    var strm = newStringStream("")
    var buffer = ['a', 'b', 'c', 'd', 'e']
    strm.writeData(addr(buffer), sizeof(buffer))
    doAssert strm.atEnd() == true
    ## readData
    strm.setPosition(0)
    var buffer2: array[6, char]
    doAssert strm.readData(addr(buffer2), sizeof(buffer2)) == 5
    doAssert buffer2 == ['a', 'b', 'c', 'd', 'e', '\x00']
    strm.close()

  s.writeDataImpl(s, buffer, bufLen)

proc write*[T](s: Stream, x: T) =
  ## Generic write procedure. Writes `x` to the stream `s`. Implementation:
  ##
  ## **Note:** Not available for JS backend. Use `write(Stream, string)
  ## <#write,Stream,string>`_ for now.
  ##
  ##   ```Nim
  ##   s.writeData(s, unsafeAddr(x), sizeof(x))
  ##   ```
  runnableExamples:
    var strm = newStringStream("")
    strm.write("abcde")
    strm.setPosition(0)
    doAssert strm.readAll() == "abcde"
    strm.close()

  writeData(s, unsafeAddr(x), sizeof(x))

proc write*(s: Stream, x: string) =
  ## Writes the string `x` to the stream `s`. No length field or
  ## terminating zero is written.
  runnableExamples:
    var strm = newStringStream("")
    strm.write("THE FIRST LINE")
    strm.setPosition(0)
    doAssert strm.readLine() == "THE FIRST LINE"
    strm.close()

  when nimvm:
    writeData(s, cstring(x), x.len)
  else:
    if x.len > 0:
      when defined(js):
        var x = x
        writeData(s, addr(x), x.len)
      else:
        writeData(s, cstring(x), x.len)

proc write*(s: Stream, args: varargs[string, `$`]) =
  ## Writes one or more strings to the the stream. No length fields or
  ## terminating zeros are written.
  runnableExamples:
    var strm = newStringStream("")
    strm.write(1, 2, 3, 4)
    strm.setPosition(0)
    doAssert strm.readLine() == "1234"
    strm.close()

  for str in args: write(s, str)

proc writeLine*(s: Stream, args: varargs[string, `$`]) =
  ## Writes one or more strings to the the stream `s` followed
  ## by a new line. No length field or terminating zero is written.
  runnableExamples:
    var strm = newStringStream("")
    strm.writeLine(1, 2)
    strm.writeLine(3, 4)
    strm.setPosition(0)
    doAssert strm.readAll() == "12\n34\n"
    strm.close()

  for str in args: write(s, str)
  write(s, "\n")

proc read*[T](s: Stream, result: var T) =
  ## Generic read procedure. Reads `result` from the stream `s`.
  ##
  ## **Note:** Not available for JS backend. Use `readStr <#readStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream("012")
    ## readInt
    var i: int8
    strm.read(i)
    doAssert i == 48
    ## readData
    var buffer: array[2, char]
    strm.read(buffer)
    doAssert buffer == ['1', '2']
    strm.close()

  if readData(s, addr(result), sizeof(T)) != sizeof(T):
    raise newEIO("cannot read from stream")

proc peek*[T](s: Stream, result: var T) =
  ## Generic peek procedure. Peeks `result` from the stream `s`.
  ##
  ## **Note:** Not available for JS backend. Use `peekStr <#peekStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream("012")
    ## peekInt
    var i: int8
    strm.peek(i)
    doAssert i == 48
    ## peekData
    var buffer: array[2, char]
    strm.peek(buffer)
    doAssert buffer == ['0', '1']
    strm.close()

  if peekData(s, addr(result), sizeof(T)) != sizeof(T):
    raise newEIO("cannot read from stream")

proc readChar*(s: Stream): char =
  ## Reads a char from the stream `s`.
  ##
  ## Raises `IOError` if an error occurred.
  ## Returns '\\0' as an EOF marker.
  runnableExamples:
    var strm = newStringStream("12\n3")
    doAssert strm.readChar() == '1'
    doAssert strm.readChar() == '2'
    doAssert strm.readChar() == '\n'
    doAssert strm.readChar() == '3'
    doAssert strm.readChar() == '\x00'
    strm.close()
  result = '\0'
  jsOrVmBlock:
    var str = " "
    if readDataStr(s, str, 0..0) != 1: result = '\0'
    else: result = str[0]
  do:
    if readData(s, addr(result), sizeof(result)) != 1: result = '\0'

proc peekChar*(s: Stream): char =
  ## Peeks a char from the stream `s`. Raises `IOError` if an error occurred.
  ## Returns '\\0' as an EOF marker.
  runnableExamples:
    var strm = newStringStream("12\n3")
    doAssert strm.peekChar() == '1'
    doAssert strm.peekChar() == '1'
    discard strm.readAll()
    doAssert strm.peekChar() == '\x00'
    strm.close()

  result = '\0'
  when defined(js):
    var str = " "
    if peekData(s, addr(str), sizeof(result)) != 1: result = '\0'
    else: result = str[0]
  else:
    if peekData(s, addr(result), sizeof(result)) != 1: result = '\0'

proc readBool*(s: Stream): bool =
  ## Reads a bool from the stream `s`.
  ##
  ## A bool is one byte long and it is `true` for every non-zero
  ## (`0000_0000`) value.
  ## Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `readStr <#readStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(true)
    strm.write(false)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.readBool() == true
    doAssert strm.readBool() == false
    doAssertRaises(IOError): discard strm.readBool()
    strm.close()

  var t: byte = byte(0)
  read(s, t)
  result = t != 0.byte

proc peekBool*(s: Stream): bool =
  ## Peeks a bool from the stream `s`.
  ##
  ## A bool is one byte long and it is `true` for every non-zero
  ## (`0000_0000`) value.
  ## Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `peekStr <#peekStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(true)
    strm.write(false)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.peekBool() == true
    ## not false
    doAssert strm.peekBool() == true
    doAssert strm.readBool() == true
    doAssert strm.peekBool() == false
    strm.close()

  var t: byte = byte(0)
  peek(s, t)
  result = t != 0.byte

proc readInt8*(s: Stream): int8 =
  ## Reads an int8 from the stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `readStr <#readStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(1'i8)
    strm.write(2'i8)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.readInt8() == 1'i8
    doAssert strm.readInt8() == 2'i8
    doAssertRaises(IOError): discard strm.readInt8()
    strm.close()
  result = int8(0)
  read(s, result)

proc peekInt8*(s: Stream): int8 =
  ## Peeks an int8 from the stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `peekStr <#peekStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(1'i8)
    strm.write(2'i8)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.peekInt8() == 1'i8
    ## not 2'i8
    doAssert strm.peekInt8() == 1'i8
    doAssert strm.readInt8() == 1'i8
    doAssert strm.peekInt8() == 2'i8
    strm.close()
  result = int8(0)
  peek(s, result)

proc readInt16*(s: Stream): int16 =
  ## Reads an int16 from the stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `readStr <#readStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(1'i16)
    strm.write(2'i16)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.readInt16() == 1'i16
    doAssert strm.readInt16() == 2'i16
    doAssertRaises(IOError): discard strm.readInt16()
    strm.close()
  result = int16(0)
  read(s, result)

proc peekInt16*(s: Stream): int16 =
  ## Peeks an int16 from the stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `peekStr <#peekStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(1'i16)
    strm.write(2'i16)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.peekInt16() == 1'i16
    ## not 2'i16
    doAssert strm.peekInt16() == 1'i16
    doAssert strm.readInt16() == 1'i16
    doAssert strm.peekInt16() == 2'i16
    strm.close()
  result = int16(0)
  peek(s, result)

proc readInt32*(s: Stream): int32 =
  ## Reads an int32 from the stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `readStr <#readStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(1'i32)
    strm.write(2'i32)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.readInt32() == 1'i32
    doAssert strm.readInt32() == 2'i32
    doAssertRaises(IOError): discard strm.readInt32()
    strm.close()
  result = int32(0)
  read(s, result)

proc peekInt32*(s: Stream): int32 =
  ## Peeks an int32 from the stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `peekStr <#peekStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(1'i32)
    strm.write(2'i32)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.peekInt32() == 1'i32
    ## not 2'i32
    doAssert strm.peekInt32() == 1'i32
    doAssert strm.readInt32() == 1'i32
    doAssert strm.peekInt32() == 2'i32
    strm.close()
  result = int32(0)
  peek(s, result)

proc readInt64*(s: Stream): int64 =
  ## Reads an int64 from the stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `readStr <#readStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(1'i64)
    strm.write(2'i64)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.readInt64() == 1'i64
    doAssert strm.readInt64() == 2'i64
    doAssertRaises(IOError): discard strm.readInt64()
    strm.close()
  result = int64(0)
  read(s, result)

proc peekInt64*(s: Stream): int64 =
  ## Peeks an int64 from the stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `peekStr <#peekStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(1'i64)
    strm.write(2'i64)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.peekInt64() == 1'i64
    ## not 2'i64
    doAssert strm.peekInt64() == 1'i64
    doAssert strm.readInt64() == 1'i64
    doAssert strm.peekInt64() == 2'i64
    strm.close()
  result = int64(0)
  peek(s, result)

proc readUint8*(s: Stream): uint8 =
  ## Reads an uint8 from the stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `readStr <#readStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(1'u8)
    strm.write(2'u8)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.readUint8() == 1'u8
    doAssert strm.readUint8() == 2'u8
    doAssertRaises(IOError): discard strm.readUint8()
    strm.close()
  result = uint8(0)
  read(s, result)

proc peekUint8*(s: Stream): uint8 =
  ## Peeks an uint8 from the stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `peekStr <#peekStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(1'u8)
    strm.write(2'u8)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.peekUint8() == 1'u8
    ## not 2'u8
    doAssert strm.peekUint8() == 1'u8
    doAssert strm.readUint8() == 1'u8
    doAssert strm.peekUint8() == 2'u8
    strm.close()
  result = uint8(0)
  peek(s, result)

proc readUint16*(s: Stream): uint16 =
  ## Reads an uint16 from the stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `readStr <#readStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(1'u16)
    strm.write(2'u16)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.readUint16() == 1'u16
    doAssert strm.readUint16() == 2'u16
    doAssertRaises(IOError): discard strm.readUint16()
    strm.close()
  result = uint16(0)
  read(s, result)

proc peekUint16*(s: Stream): uint16 =
  ## Peeks an uint16 from the stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `peekStr <#peekStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(1'u16)
    strm.write(2'u16)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.peekUint16() == 1'u16
    ## not 2'u16
    doAssert strm.peekUint16() == 1'u16
    doAssert strm.readUint16() == 1'u16
    doAssert strm.peekUint16() == 2'u16
    strm.close()
  result = uint16(0)
  peek(s, result)

proc readUint32*(s: Stream): uint32 =
  ## Reads an uint32 from the stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `readStr <#readStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(1'u32)
    strm.write(2'u32)
    strm.flush()
    strm.setPosition(0)

    ## get data
    doAssert strm.readUint32() == 1'u32
    doAssert strm.readUint32() == 2'u32
    doAssertRaises(IOError): discard strm.readUint32()
    strm.close()
  result = uint32(0)
  read(s, result)

proc peekUint32*(s: Stream): uint32 =
  ## Peeks an uint32 from the stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `peekStr <#peekStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(1'u32)
    strm.write(2'u32)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.peekUint32() == 1'u32
    ## not 2'u32
    doAssert strm.peekUint32() == 1'u32
    doAssert strm.readUint32() == 1'u32
    doAssert strm.peekUint32() == 2'u32
    strm.close()
  result = uint32(0)
  peek(s, result)

proc readUint64*(s: Stream): uint64 =
  ## Reads an uint64 from the stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `readStr <#readStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(1'u64)
    strm.write(2'u64)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.readUint64() == 1'u64
    doAssert strm.readUint64() == 2'u64
    doAssertRaises(IOError): discard strm.readUint64()
    strm.close()
  result = uint64(0)
  read(s, result)

proc peekUint64*(s: Stream): uint64 =
  ## Peeks an uint64 from the stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `peekStr <#peekStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(1'u64)
    strm.write(2'u64)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.peekUint64() == 1'u64
    ## not 2'u64
    doAssert strm.peekUint64() == 1'u64
    doAssert strm.readUint64() == 1'u64
    doAssert strm.peekUint64() == 2'u64
    strm.close()
  result = uint64(0)
  peek(s, result)

proc readFloat32*(s: Stream): float32 =
  ## Reads a float32 from the stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `readStr <#readStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(1'f32)
    strm.write(2'f32)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.readFloat32() == 1'f32
    doAssert strm.readFloat32() == 2'f32
    doAssertRaises(IOError): discard strm.readFloat32()
    strm.close()
  result = 0.0
  read(s, result)

proc peekFloat32*(s: Stream): float32 =
  ## Peeks a float32 from the stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `peekStr <#peekStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(1'f32)
    strm.write(2'f32)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.peekFloat32() == 1'f32
    ## not 2'f32
    doAssert strm.peekFloat32() == 1'f32
    doAssert strm.readFloat32() == 1'f32
    doAssert strm.peekFloat32() == 2'f32
    strm.close()
  result = 0.0
  peek(s, result)

proc readFloat64*(s: Stream): float64 =
  ## Reads a float64 from the stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `readStr <#readStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(1'f64)
    strm.write(2'f64)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.readFloat64() == 1'f64
    doAssert strm.readFloat64() == 2'f64
    doAssertRaises(IOError): discard strm.readFloat64()
    strm.close()
  result = 0.0
  read(s, result)

proc peekFloat64*(s: Stream): float64 =
  ## Peeks a float64 from the stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** Not available for JS backend. Use `peekStr <#peekStr,Stream,int>`_ for now.
  runnableExamples:
    var strm = newStringStream()
    ## setup for reading data
    strm.write(1'f64)
    strm.write(2'f64)
    strm.flush()
    strm.setPosition(0)
    ## get data
    doAssert strm.peekFloat64() == 1'f64
    ## not 2'f64
    doAssert strm.peekFloat64() == 1'f64
    doAssert strm.readFloat64() == 1'f64
    doAssert strm.peekFloat64() == 2'f64
    strm.close()
  result = 0.0
  peek(s, result)

proc readStrPrivate(s: Stream, length: int, str: var string) =
  if length > len(str): setLen(str, length)
  var L: int
  when nimvm:
    L = readDataStr(s, str, 0..length-1)
  else:
    when defined(js):
      L = readData(s, addr(str), length)
    else:
      L = readData(s, cstring(str), length)
  if L != len(str): setLen(str, L)

proc readStr*(s: Stream, length: int, str: var string) {.since: (1, 3).} =
  ## Reads a string of length `length` from the stream `s`. Raises `IOError` if
  ## an error occurred.
  readStrPrivate(s, length, str)

proc readStr*(s: Stream, length: int): string =
  ## Reads a string of length `length` from the stream `s`. Raises `IOError` if
  ## an error occurred.
  runnableExamples:
    var strm = newStringStream("abcde")
    doAssert strm.readStr(2) == "ab"
    doAssert strm.readStr(2) == "cd"
    doAssert strm.readStr(2) == "e"
    doAssert strm.readStr(2) == ""
    strm.close()
  result = newString(length)
  readStrPrivate(s, length, result)

proc peekStrPrivate(s: Stream, length: int, str: var string) =
  if length > len(str): setLen(str, length)
  when defined(js):
    let L = peekData(s, addr(str), length)
  else:
    let L = peekData(s, cstring(str), length)
  if L != len(str): setLen(str, L)

proc peekStr*(s: Stream, length: int, str: var string) {.since: (1, 3).} =
  ## Peeks a string of length `length` from the stream `s`. Raises `IOError` if
  ## an error occurred.
  peekStrPrivate(s, length, str)

proc peekStr*(s: Stream, length: int): string =
  ## Peeks a string of length `length` from the stream `s`. Raises `IOError` if
  ## an error occurred.
  runnableExamples:
    var strm = newStringStream("abcde")
    doAssert strm.peekStr(2) == "ab"
    ## not "cd
    doAssert strm.peekStr(2) == "ab"
    doAssert strm.readStr(2) == "ab"
    doAssert strm.peekStr(2) == "cd"
    strm.close()
  result = newString(length)
  peekStrPrivate(s, length, result)

proc readLine*(s: Stream, line: var string): bool =
  ## Reads a line of text from the stream `s` into `line`. `line` must not be
  ## ``nil``! May throw an IO exception.
  ##
  ## A line of text may be delimited by ``LF`` or ``CRLF``.
  ## The newline character(s) are not part of the returned string.
  ## Returns ``false`` if the end of the file has been reached, ``true``
  ## otherwise. If ``false`` is returned `line` contains no new data.
  ##
  ## See also:
  ## * `readLine(Stream) proc <#readLine,Stream>`_
  ## * `peekLine(Stream) proc <#peekLine,Stream>`_
  ## * `peekLine(Stream, string) proc <#peekLine,Stream,string>`_
  runnableExamples:
    var strm = newStringStream("The first line\nthe second line\nthe third line")
    var line = ""
    doAssert strm.readLine(line) == true
    doAssert line == "The first line"
    doAssert strm.readLine(line) == true
    doAssert line == "the second line"
    doAssert strm.readLine(line) == true
    doAssert line == "the third line"
    doAssert strm.readLine(line) == false
    doAssert line == ""
    strm.close()

  if s.readLineImpl != nil:
    result = s.readLineImpl(s, line)
  else:
    # fallback
    line.setLen(0)
    while true:
      var c = readChar(s)
      if c == '\c':
        c = readChar(s)
        break
      elif c == '\L': break
      elif c == '\0':
        if line.len > 0: break
        else: return false
      line.add(c)
    result = true

proc peekLine*(s: Stream, line: var string): bool =
  ## Peeks a line of text from the stream `s` into `line`. `line` must not be
  ## ``nil``! May throw an IO exception.
  ##
  ## A line of text may be delimited by ``CR``, ``LF`` or
  ## ``CRLF``. The newline character(s) are not part of the returned string.
  ## Returns ``false`` if the end of the file has been reached, ``true``
  ## otherwise. If ``false`` is returned `line` contains no new data.
  ##
  ## See also:
  ## * `readLine(Stream) proc <#readLine,Stream>`_
  ## * `readLine(Stream, string) proc <#readLine,Stream,string>`_
  ## * `peekLine(Stream) proc <#peekLine,Stream>`_
  runnableExamples:
    var strm = newStringStream("The first line\nthe second line\nthe third line")
    var line = ""
    doAssert strm.peekLine(line) == true
    doAssert line == "The first line"
    doAssert strm.peekLine(line) == true
    ## not "the second line"
    doAssert line == "The first line"
    doAssert strm.readLine(line) == true
    doAssert line == "The first line"
    doAssert strm.peekLine(line) == true
    doAssert line == "the second line"
    strm.close()

  let pos = getPosition(s)
  defer: setPosition(s, pos)
  result = readLine(s, line)

proc readLine*(s: Stream): string =
  ## Reads a line from a stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** This is not very efficient.
  ##
  ## See also:
  ## * `readLine(Stream, string) proc <#readLine,Stream,string>`_
  ## * `peekLine(Stream) proc <#peekLine,Stream>`_
  ## * `peekLine(Stream, string) proc <#peekLine,Stream,string>`_
  runnableExamples:
    var strm = newStringStream("The first line\nthe second line\nthe third line")
    doAssert strm.readLine() == "The first line"
    doAssert strm.readLine() == "the second line"
    doAssert strm.readLine() == "the third line"
    doAssertRaises(IOError): discard strm.readLine()
    strm.close()

  result = ""
  if s.atEnd:
    raise newEIO("cannot read from stream")
  while true:
    var c = readChar(s)
    if c == '\c':
      c = readChar(s)
      break
    if c == '\L' or c == '\0':
      break
    else:
      result.add(c)

proc peekLine*(s: Stream): string =
  ## Peeks a line from a stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:** This is not very efficient.
  ##
  ## See also:
  ## * `readLine(Stream) proc <#readLine,Stream>`_
  ## * `readLine(Stream, string) proc <#readLine,Stream,string>`_
  ## * `peekLine(Stream, string) proc <#peekLine,Stream,string>`_
  runnableExamples:
    var strm = newStringStream("The first line\nthe second line\nthe third line")
    doAssert strm.peekLine() == "The first line"
    ## not "the second line"
    doAssert strm.peekLine() == "The first line"
    doAssert strm.readLine() == "The first line"
    doAssert strm.peekLine() == "the second line"
    strm.close()

  let pos = getPosition(s)
  defer: setPosition(s, pos)
  result = readLine(s)

iterator lines*(s: Stream): string =
  ## Iterates over every line in the stream.
  ## The iteration is based on ``readLine``.
  ##
  ## See also:
  ## * `readLine(Stream) proc <#readLine,Stream>`_
  ## * `readLine(Stream, string) proc <#readLine,Stream,string>`_
  runnableExamples:
    var strm = newStringStream("The first line\nthe second line\nthe third line")
    var lines: seq[string]
    for line in strm.lines():
      lines.add line
    doAssert lines == @["The first line", "the second line", "the third line"]
    strm.close()

  var line: string = ""
  while s.readLine(line):
    yield line

type
  StringStream* = ref StringStreamObj
    ## A stream that encapsulates a string.
  StringStreamObj* = object of StreamObj
    ## A string stream object.
    data*: string ## A string data.
                  ## This is updated when called `writeLine` etc.
    pos: int

when (NimMajor, NimMinor) < (1, 3) and defined(js):
  proc ssAtEnd(s: Stream): bool {.compileTime.} =
    var s = StringStream(s)
    return s.pos >= s.data.len

  proc ssSetPosition(s: Stream, pos: int) {.compileTime.} =
    var s = StringStream(s)
    s.pos = clamp(pos, 0, s.data.len)

  proc ssGetPosition(s: Stream): int {.compileTime.} =
    var s = StringStream(s)
    return s.pos

  proc ssReadDataStr(s: Stream, buffer: var string, slice: Slice[int]): int {.compileTime.} =
    var s = StringStream(s)
    result = min(slice.b + 1 - slice.a, s.data.len - s.pos)
    if result > 0:
      buffer[slice.a..<slice.a+result] = s.data[s.pos..<s.pos+result]
      inc(s.pos, result)
    else:
      result = 0

  proc ssClose(s: Stream) {.compileTime.} =
    var s = StringStream(s)
    s.data = ""

  proc newStringStream*(s: string = ""): owned StringStream {.compileTime.} =
    new(result)
    result.data = s
    result.pos = 0
    result.closeImpl = ssClose
    result.atEndImpl = ssAtEnd
    result.setPositionImpl = ssSetPosition
    result.getPositionImpl = ssGetPosition
    result.readDataStrImpl = ssReadDataStr

  proc readAll*(s: Stream): string {.compileTime.} =
    const bufferSize = 1024
    var bufferr: string
    bufferr.setLen(bufferSize)
    while true:
      let readBytes = readDataStr(s, bufferr, 0..<bufferSize)
      if readBytes == 0:
        break
      let prevLen = result.len
      result.setLen(prevLen + readBytes)
      result[prevLen..<prevLen+readBytes] = bufferr[0..<readBytes]
      if readBytes < bufferSize:
        break

else: # after 1.3 or JS not defined
  proc ssAtEnd(s: Stream): bool =
    var s = StringStream(s)
    return s.pos >= s.data.len

  proc ssSetPosition(s: Stream, pos: int) =
    var s = StringStream(s)
    s.pos = clamp(pos, 0, s.data.len)

  proc ssGetPosition(s: Stream): int =
    var s = StringStream(s)
    return s.pos

  proc ssReadDataStr(s: Stream, buffer: var string, slice: Slice[int]): int =
    var s = StringStream(s)
    when nimvm:
      discard
    else:
      when declared(prepareMutation):
        prepareMutation(buffer) # buffer might potentially be a CoW literal with ARC
    result = min(slice.b + 1 - slice.a, s.data.len - s.pos)
    if result > 0:
      jsOrVmBlock:
        buffer[slice.a..<slice.a+result] = s.data[s.pos..<s.pos+result]
      do:
        copyMem(unsafeAddr buffer[slice.a], addr s.data[s.pos], result)
      inc(s.pos, result)
    else:
      result = 0

  proc ssReadData(s: Stream, buffer: pointer, bufLen: int): int =
    var s = StringStream(s)
    result = min(bufLen, s.data.len - s.pos)
    if result > 0:
      when defined(js):
        try:
          cast[ptr string](buffer)[][0..<result] = s.data[s.pos..<s.pos+result]
        except:
          raise newException(Defect, "could not read string stream, " &
            "did you use a non-string buffer pointer?", getCurrentException())
      elif not defined(nimscript):
        copyMem(buffer, addr(s.data[s.pos]), result)
      inc(s.pos, result)
    else:
      result = 0

  proc ssPeekData(s: Stream, buffer: pointer, bufLen: int): int =
    var s = StringStream(s)
    result = min(bufLen, s.data.len - s.pos)
    if result > 0:
      when defined(js):
        try:
          cast[ptr string](buffer)[][0..<result] = s.data[s.pos..<s.pos+result]
        except:
          raise newException(Defect, "could not peek string stream, " &
            "did you use a non-string buffer pointer?", getCurrentException())
      elif not defined(nimscript):
        copyMem(buffer, addr(s.data[s.pos]), result)
    else:
      result = 0

  proc ssWriteData(s: Stream, buffer: pointer, bufLen: int) =
    var s = StringStream(s)
    if bufLen <= 0:
      return
    if s.pos + bufLen > s.data.len:
      setLen(s.data, s.pos + bufLen)
    when defined(js):
      try:
        s.data[s.pos..<s.pos+bufLen] = cast[ptr string](buffer)[][0..<bufLen]
      except:
        raise newException(Defect, "could not write to string stream, " &
          "did you use a non-string buffer pointer?", getCurrentException())
    elif not defined(nimscript):
      copyMem(addr(s.data[s.pos]), buffer, bufLen)
    inc(s.pos, bufLen)

  proc ssClose(s: Stream) =
    var s = StringStream(s)
    s.data = ""

  proc newStringStream*(s: sink string = ""): owned StringStream =
    ## Creates a new stream from the string `s`.
    ##
    ## See also:
    ## * `newFileStream proc <#newFileStream,File>`_ creates a file stream from
    ##   opened File.
    ## * `newFileStream proc <#newFileStream,string,FileMode,int>`_  creates a
    ##   file stream from the file name and the mode.
    ## * `openFileStream proc <#openFileStream,string,FileMode,int>`_ creates a
    ##   file stream from the file name and the mode.
    runnableExamples:
      var strm = newStringStream("The first line\nthe second line\nthe third line")
      doAssert strm.readLine() == "The first line"
      doAssert strm.readLine() == "the second line"
      doAssert strm.readLine() == "the third line"
      strm.close()

    new(result)
    result.data = s
    when nimvm:
      discard
    else:
      when declared(prepareMutation):
        prepareMutation(result.data) # Allows us to mutate using `addr` logic like `copyMem`, otherwise it errors.
    result.pos = 0
    result.closeImpl = ssClose
    result.atEndImpl = ssAtEnd
    result.setPositionImpl = ssSetPosition
    result.getPositionImpl = ssGetPosition
    result.readDataStrImpl = ssReadDataStr
    when nimvm:
      discard
    else:
      result.readDataImpl = ssReadData
      result.peekDataImpl = ssPeekData
      result.writeDataImpl = ssWriteData

type
  FileStream* = ref FileStreamObj
    ## A stream that encapsulates a `File`.
    ##
    ## **Note:** Not available for JS backend.
  FileStreamObj* = object of Stream
    ## A file stream object.
    ##
    ## **Note:** Not available for JS backend.
    f: File

proc fsClose(s: Stream) =
  if FileStream(s).f != nil:
    close(FileStream(s).f)
    FileStream(s).f = nil
proc fsFlush(s: Stream) = flushFile(FileStream(s).f)
proc fsAtEnd(s: Stream): bool = return endOfFile(FileStream(s).f)
proc fsSetPosition(s: Stream, pos: int) = setFilePos(FileStream(s).f, pos)
proc fsGetPosition(s: Stream): int = return int(getFilePos(FileStream(s).f))

proc fsReadData(s: Stream, buffer: pointer, bufLen: int): int =
  result = readBuffer(FileStream(s).f, buffer, bufLen)

proc fsReadDataStr(s: Stream, buffer: var string, slice: Slice[int]): int =
  result = readBuffer(FileStream(s).f, addr buffer[slice.a], slice.b + 1 - slice.a)

proc fsPeekData(s: Stream, buffer: pointer, bufLen: int): int =
  let pos = fsGetPosition(s)
  defer: fsSetPosition(s, pos)
  result = readBuffer(FileStream(s).f, buffer, bufLen)

proc fsWriteData(s: Stream, buffer: pointer, bufLen: int) =
  if writeBuffer(FileStream(s).f, buffer, bufLen) != bufLen:
    raise newEIO("cannot write to stream")

proc fsReadLine(s: Stream, line: var string): bool =
  result = readLine(FileStream(s).f, line)

proc newFileStream*(f: File): owned FileStream =
  ## Creates a new stream from the file `f`.
  ##
  ## **Note:** Not available for JS backend.
  ##
  ## See also:
  ## * `newStringStream proc <#newStringStream,string>`_ creates a new stream
  ##   from string.
  ## * `newFileStream proc <#newFileStream,string,FileMode,int>`_ is the same
  ##   as using `open proc <syncio.html#open,File,string,FileMode,int>`_
  ##   on Examples.
  ## * `openFileStream proc <#openFileStream,string,FileMode,int>`_ creates a
  ##   file stream from the file name and the mode.
  runnableExamples:
    ## Input (somefile.txt):
    ## The first line
    ## the second line
    ## the third line
    var f: File
    if open(f, "somefile.txt", fmRead, -1):
      var strm = newFileStream(f)
      var line = ""
      while strm.readLine(line):
        echo line
      ## Output:
      ## The first line
      ## the second line
      ## the third line
      strm.close()

  new(result)
  result.f = f
  result.closeImpl = fsClose
  result.atEndImpl = fsAtEnd
  result.setPositionImpl = fsSetPosition
  result.getPositionImpl = fsGetPosition
  result.readDataStrImpl = fsReadDataStr
  result.readDataImpl = fsReadData
  result.readLineImpl = fsReadLine
  result.peekDataImpl = fsPeekData
  result.writeDataImpl = fsWriteData
  result.flushImpl = fsFlush

proc newFileStream*(filename: string, mode: FileMode = fmRead,
    bufSize: int = -1): owned FileStream =
  ## Creates a new stream from the file named `filename` with the mode `mode`.
  ##
  ## If the file cannot be opened, `nil` is returned. See the `io module
  ## <syncio.html>`_ for a list of available `FileMode enums <syncio.html#FileMode>`_.
  ##
  ## **Note:**
  ## * **This function returns nil in case of failure.**
  ##   To prevent unexpected behavior and ensure proper error handling,
  ##   use `openFileStream proc <#openFileStream,string,FileMode,int>`_
  ##   instead.
  ## * Not available for JS backend.
  ##
  ## See also:
  ## * `newStringStream proc <#newStringStream,string>`_ creates a new stream
  ##   from string.
  ## * `newFileStream proc <#newFileStream,File>`_ creates a file stream from
  ##   opened File.
  ## * `openFileStream proc <#openFileStream,string,FileMode,int>`_ creates a
  ##   file stream from the file name and the mode.
  runnableExamples:
    from std/os import removeFile
    var strm = newFileStream("somefile.txt", fmWrite)
    if not isNil(strm):
      strm.writeLine("The first line")
      strm.writeLine("the second line")
      strm.writeLine("the third line")
      strm.close()
      ## Output (somefile.txt)
      ## The first line
      ## the second line
      ## the third line
      removeFile("somefile.txt")

  var f: File = default(File)
  if open(f, filename, mode, bufSize): result = newFileStream(f)
  else: result = nil

proc openFileStream*(filename: string, mode: FileMode = fmRead,
    bufSize: int = -1): owned FileStream =
  ## Creates a new stream from the file named `filename` with the mode `mode`.
  ## If the file cannot be opened, an IO exception is raised.
  ##
  ## **Note:** Not available for JS backend.
  ##
  ## See also:
  ## * `newStringStream proc <#newStringStream,string>`_ creates a new stream
  ##   from string.
  ## * `newFileStream proc <#newFileStream,File>`_ creates a file stream from
  ##   opened File.
  ## * `newFileStream proc <#newFileStream,string,FileMode,int>`_  creates a
  ##   file stream from the file name and the mode.
  runnableExamples:
    try:
      ## Input (somefile.txt):
      ## The first line
      ## the second line
      ## the third line
      var strm = openFileStream("somefile.txt")
      echo strm.readLine()
      ## Output:
      ## The first line
      strm.close()
    except:
      stderr.write getCurrentExceptionMsg()

  var f: File = default(File)
  if open(f, filename, mode, bufSize):
    return newFileStream(f)
  else:
    raise newEIO("cannot open file stream: " & filename)

when false:
  type
    FileHandleStream* = ref FileHandleStreamObj
    FileHandleStreamObj* = object of Stream
      handle*: FileHandle
      pos: int

  proc newEOS(msg: string): ref OSError =
    new(result)
    result.msg = msg

  proc hsGetPosition(s: FileHandleStream): int =
    return s.pos

  when defined(windows):
    # do not import windows as this increases compile times:
    discard
  else:
    import std/posix

    proc hsSetPosition(s: FileHandleStream, pos: int) =
      discard lseek(s.handle, pos, SEEK_SET)

    proc hsClose(s: FileHandleStream) = discard close(s.handle)
    proc hsAtEnd(s: FileHandleStream): bool =
      var pos = hsGetPosition(s)
      var theEnd = lseek(s.handle, 0, SEEK_END)
      result = pos >= theEnd
      hsSetPosition(s, pos) # set position back

    proc hsReadData(s: FileHandleStream, buffer: pointer, bufLen: int): int =
      result = posix.read(s.handle, buffer, bufLen)
      inc(s.pos, result)

    proc hsPeekData(s: FileHandleStream, buffer: pointer, bufLen: int): int =
      result = posix.read(s.handle, buffer, bufLen)

    proc hsWriteData(s: FileHandleStream, buffer: pointer, bufLen: int) =
      if posix.write(s.handle, buffer, bufLen) != bufLen:
        raise newEIO("cannot write to stream")
      inc(s.pos, bufLen)

  proc newFileHandleStream*(handle: FileHandle): owned FileHandleStream =
    new(result)
    result.handle = handle
    result.pos = 0
    result.close = hsClose
    result.atEnd = hsAtEnd
    result.setPosition = hsSetPosition
    result.getPosition = hsGetPosition
    result.readData = hsReadData
    result.peekData = hsPeekData
    result.writeData = hsWriteData

  proc newFileHandleStream*(filename: string,
                            mode: FileMode): owned FileHandleStream =
    when defined(windows):
      discard
    else:
      var flags: cint
      case mode
      of fmRead: flags = posix.O_RDONLY
      of fmWrite: flags = O_WRONLY or int(O_CREAT)
      of fmReadWrite: flags = O_RDWR or int(O_CREAT)
      of fmReadWriteExisting: flags = O_RDWR
      of fmAppend: flags = O_WRONLY or int(O_CREAT) or O_APPEND
      static: raiseAssert "unreachable" # handle bug #17888
      var handle = open(filename, flags)
      if handle < 0: raise newEOS("posix.open() call failed")
    result = newFileHandleStream(handle)
