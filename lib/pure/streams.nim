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
## strings. Other modules may provide other implementations for this standard
## stream interface.
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
## It is here that an implementation example with
## `StringStream <#StringStream>`_.
##
## StringStream example
## --------------------
##
## Step 1: Open input stream:
## ^^^^^^^^^^^^^^^^^^^^^^^^^^
##
## Open StringStream. For more information on `"""The first line..."""`,
## see `Triple quoted string literals <manual.html#lexical-analysis-triple-quoted-string-literals>`_ .
##
## .. code-block:: Nim
##
##  import streams
##
##  var strm = newStringStream("""The first line
##  the second line
##  the third line""")
##
## Step 2: Read stream
## ^^^^^^^^^^^^^^^^^^^
##
## Read stream. `readLine proc <#readLine,Stream,TaintedString>`_ reads a line
## of text from the stream. In this example, read three times and exit the loop.
##
## .. code-block:: Nim
##
##  var line = ""
##
##  while strm.readLine(line):
##    echo line
##  
##  # Output:
##  # The first line
##  # The second line
##  # The third line
##
## Step 3: Close stream
## ^^^^^^^^^^^^^^^^^^^^
##
## Close stream. Call `close proc <#close,Stream>`_ or
## `flush proc <#flush,Stream>`_ if save data that written in the file
## stream to file.
##
## .. code-block:: Nim
##
##  strm.close()
##
## You can use `defer statement <manual.html#exception-handling-defer-statement>`_ 
## to close stream. defer statement is available with procedure. But defer
## statement is not available with Top-level.
## 
## defer statement example is here:
##
## .. code-block:: Nim
##
##  defer: strm.close()
##
## Similarly, it is here that an implementation example with
## `FileStream <#FileStream>`_.
##
## FileStream example
## ------------------
##
## Read file stream example:
##
## .. code-block:: Nim
##
##  import streams
##
##  var strm = newFileStream("somefile.txt", fmRead)
##  var line = ""
##
##  if not isNil(strm):
##    while strm.readLine(line):
##      echo line
##    strm.close()
##
##  # Output:
##  # The first line
##  # the second line
##  # the third line
##
## Write file stream example:
##
## .. code-block:: Nim
##
##  import streams
##
##  var strm = newFileStream("somefile.txt", fmWrite)
##  var line = ""
##
##  if not isNil(strm):
##    strm.writeLine("The first line")
##    strm.writeLine("the second line")
##    strm.writeLine("the third line")
##    strm.close()
## 
##  # Output (somefile.txt):
##  # The first line
##  # the second line
##  # the third line
##
## See also
## ========
## * `FileMode enum <io.html#FileMode>`_ is available FileMode

include "system/inclrtl"

proc newEIO(msg: string): owned(ref IOError) =
  new(result)
  result.msg = msg

type
  Stream* = ref StreamObj
    ## A stream.
    ## All procedures of this module use this type.
    ## Procedures don't directly use `StreamObj <#StreamObj>`_.
  StreamObj* = object of RootObj
    ## Stream interface that supports writing or reading.
    ## 
    ## **Note:**
    ## * That these fields here shouldn't be used directly.
    ##   They are accessible so that a stream implementation can override them.
    closeImpl*: proc (s: Stream)
      {.nimcall, raises: [Exception, IOError, OSError], tags: [WriteIOEffect], gcsafe.}
    atEndImpl*: proc (s: Stream): bool
      {.nimcall, raises: [Defect, IOError, OSError], tags: [], gcsafe.}
    setPositionImpl*: proc (s: Stream, pos: int)
      {.nimcall, raises: [Defect, IOError, OSError], tags: [], gcsafe.}
    getPositionImpl*: proc (s: Stream): int
      {.nimcall, raises: [Defect, IOError, OSError], tags: [], gcsafe.}

    readDataStrImpl*: proc (s: Stream, buffer: var string, slice: Slice[int]): int
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
  ## This procedure causes any unwritten data for that stream to be delivered
  ## to the host environment to be written to the file.
  ##
  ## See also:
  ## * `close proc <#close,Stream>`_
  runnableExamples:
    from os import removeFile

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
    var strm = newStringStream("The first line\nthe second line\nthe third line")
    ## do something...
    strm.close()
  if not isNil(s.closeImpl): s.closeImpl(s)

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
    result = s.readData(addr buffer[0], buffer.len)

when not defined(js):
  proc readAll*(s: Stream): string =
    ## Reads all available data.
    ##
    ## **Note:**
    ## * Not available this when backend is js
    runnableExamples:
      var strm = newStringStream("The first line\nthe second line\nthe third line")
      doAssert strm.readAll() == "The first line\nthe second line\nthe third line"
      doAssert strm.atEnd() == true
      strm.close()
    const bufferSize = 1024
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
  ## .. code-block:: Nim
  ##
  ##     s.writeData(s, addr(x), sizeof(x))
  runnableExamples:
    var strm = newStringStream("")
    strm.write("abcde")
    strm.setPosition(0)
    doAssert strm.readAll() == "abcde"
    strm.close()
  var y: T
  shallowCopy(y, x)
  writeData(s, addr(y), sizeof(y))

proc write*(s: Stream, x: string) =
  ## Writes the string `x` to the the stream `s`. No length field or
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
    if x.len > 0: writeData(s, cstring(x), x.len)

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
  ## Reads a char from the stream `s`. Raises `IOError` if an error occurred.
  ## Returns '\\0' as an EOF marker.
  runnableExamples:
    var strm = newStringStream("12\n3")
    doAssert strm.readChar() == '1'
    doAssert strm.readChar() == '2'
    doAssert strm.readChar() == '\n'
    doAssert strm.readChar() == '3'
    doAssert strm.readChar() == '\x00'
    strm.close()
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
  if peekData(s, addr(result), sizeof(result)) != 1: result = '\0'

proc readBool*(s: Stream): bool =
  ## Reads a bool from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("12")
    doAssert strm.readBool()
    doAssert strm.readBool()
    ## strm.readBool() --> raise IOError
    strm.close()
  read(s, result)

proc peekBool*(s: Stream): bool =
  ## Peeks a bool from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("12")
    doAssert strm.peekBool()
    doAssert strm.peekBool()
    doAssert strm.peekBool()
    strm.close()
  peek(s, result)

proc readInt8*(s: Stream): int8 =
  ## Reads an int8 from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("12")
    doAssert strm.readInt8() == 49
    doAssert strm.readInt8() == 50
    ## strm.readInt8() --> raise IOError
    strm.close()
  read(s, result)

proc peekInt8*(s: Stream): int8 =
  ## Peeks an int8 from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("12")
    doAssert strm.peekInt8() == 49
    doAssert strm.peekInt8() == 49
    doAssert strm.peekInt8() == 49
    strm.close()
  peek(s, result)

proc readInt16*(s: Stream): int16 =
  ## Reads an int16 from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("001020")
    doAssert strm.readInt16() == 12336
    doAssert strm.readInt16() == 12337
    doAssert strm.readInt16() == 12338
    ## strm.readInt16() --> raise IOError
    strm.close()
  read(s, result)

proc peekInt16*(s: Stream): int16 =
  ## Peeks an int16 from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("001020")
    doAssert strm.peekInt16() == 12336
    doAssert strm.peekInt16() == 12336
    doAssert strm.peekInt16() == 12336
    doAssert strm.peekInt16() == 12336
    strm.close()
  peek(s, result)

proc readInt32*(s: Stream): int32 =
  ## Reads an int32 from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("000010002000")
    doAssert strm.readInt32() == 808464432
    doAssert strm.readInt32() == 808464433
    doAssert strm.readInt32() == 808464434
    ## strm.readInt32() --> raise IOError
    strm.close()
  read(s, result)

proc peekInt32*(s: Stream): int32 =
  ## Peeks an int32 from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("000010002000")
    doAssert strm.peekInt32() == 808464432
    doAssert strm.peekInt32() == 808464432
    doAssert strm.peekInt32() == 808464432
    doAssert strm.peekInt32() == 808464432
    strm.close()
  peek(s, result)

proc readInt64*(s: Stream): int64 =
  ## Reads an int64 from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("000000001000000020000000")
    doAssert strm.readInt64() == 3472328296227680304
    doAssert strm.readInt64() == 3472328296227680305
    doAssert strm.readInt64() == 3472328296227680306
    ## strm.readInt64() --> raise IOError
    strm.close()
  read(s, result)

proc peekInt64*(s: Stream): int64 =
  ## Peeks an int64 from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("000000001000000020000000")
    doAssert strm.peekInt64() == 3472328296227680304
    doAssert strm.peekInt64() == 3472328296227680304
    doAssert strm.peekInt64() == 3472328296227680304
    strm.close()
  peek(s, result)

proc readUint8*(s: Stream): uint8 =
  ## Reads an uint8 from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("012")
    doAssert strm.readUint8() == 48
    doAssert strm.readUint8() == 49
    doAssert strm.readUint8() == 50
    ## strm.readUint8() --> raies IOError
    strm.close()
  read(s, result)

proc peekUint8*(s: Stream): uint8 =
  ## Peeks an uint8 from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("012")
    doAssert strm.peekUint8() == 48
    doAssert strm.peekUint8() == 48
    doAssert strm.peekUint8() == 48
    strm.close()
  peek(s, result)

proc readUint16*(s: Stream): uint16 =
  ## Reads an uint16 from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("001020")
    doAssert strm.readUint16() == 12336
    doAssert strm.readUint16() == 12337
    doAssert strm.readUint16() == 12338
    ## strm.readUint16() --> raise IOError
    strm.close()
  read(s, result)

proc peekUint16*(s: Stream): uint16 =
  ## Peeks an uint16 from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("001020")
    doAssert strm.peekUint16() == 12336
    doAssert strm.peekUint16() == 12336
    doAssert strm.peekUint16() == 12336
    doAssert strm.peekUint16() == 12336
    strm.close()
  peek(s, result)

proc readUint32*(s: Stream): uint32 =
  ## Reads an uint32 from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("000010002000")
    doAssert strm.readUint32() == 808464432
    doAssert strm.readUint32() == 808464433
    doAssert strm.readUint32() == 808464434
    ## strm.readUint32() --> raise IOError
    strm.close()
  read(s, result)

proc peekUint32*(s: Stream): uint32 =
  ## Peeks an uint32 from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("000010002000")
    doAssert strm.peekUint32() == 808464432
    doAssert strm.peekUint32() == 808464432
    doAssert strm.peekUint32() == 808464432
    doAssert strm.peekUint32() == 808464432
    strm.close()
  peek(s, result)

proc readUint64*(s: Stream): uint64 =
  ## Reads an uint64 from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("000000001000000020000000")
    doAssert strm.readUint64() == 3472328296227680304'u64
    doAssert strm.readUint64() == 3472328296227680305'u64
    doAssert strm.readUint64() == 3472328296227680306'u64
    ## strm.readUint64() --> raise IOError
    strm.close()
  read(s, result)

proc peekUint64*(s: Stream): uint64 =
  ## Peeks an uint64 from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("000000001000000020000000")
    doAssert strm.peekUint64() == 3472328296227680304'u64
    doAssert strm.peekUint64() == 3472328296227680304'u64
    doAssert strm.peekUint64() == 3472328296227680304'u64
    strm.close()
  peek(s, result)

proc readFloat32*(s: Stream): float32 =
  ## Reads a float32 from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("000010002000")
    doAssert strm.readFloat32() == 0.00000000064096905560973027604632'f32
    doAssert strm.readFloat32() == 0.00000000064096911112088150730415'f32
    doAssert strm.readFloat32() == 0.00000000064096916663203273856197'f32
    ## strm.readFloat32() --> raise IOError
    strm.close()
  read(s, result)

proc peekFloat32*(s: Stream): float32 =
  ## Peeks a float32 from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("000010002000")
    doAssert strm.peekFloat32() == 0.00000000064096905560973027604632'f32
    doAssert strm.peekFloat32() == 0.00000000064096905560973027604632'f32
    doAssert strm.peekFloat32() == 0.00000000064096905560973027604632'f32
    doAssert strm.peekFloat32() == 0.00000000064096905560973027604632'f32
    strm.close()
  peek(s, result)

proc readFloat64*(s: Stream): float64 =
  ## Reads a float64 from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("000000001000000020000000")
    echo strm.readFloat64()
    echo strm.readFloat64()
    echo strm.readFloat64()
    # issues #11056
    # doAssert strm.readFloat64() == 1.39804328609528886042614983922832e-76'f64
    # doAssert strm.readFloat64() == 1.39804328609528916724449142033623e-76'f64
    # doAssert strm.readFloat64() == 1.39804328609528947406283300144414e-76'f64
    ## strm.readFloat64() --> raise IOError
    strm.close()
  read(s, result)

proc peekFloat64*(s: Stream): float64 =
  ## Peeks a float64 from the stream `s`. Raises `IOError` if an error occurred.
  runnableExamples:
    var strm = newStringStream("000000001000000020000000")
    echo strm.peekFloat64()
    echo strm.peekFloat64()
    echo strm.peekFloat64()
    echo strm.peekFloat64()
    # issues #11056
    # doAssert strm.peekFloat64() == 1.39804328609528886042614983922832e-76'f64
    # doAssert strm.peekFloat64() == 1.39804328609528886042614983922832e-76'f64
    # doAssert strm.peekFloat64() == 1.39804328609528886042614983922832e-76'f64
    # doAssert strm.peekFloat64() == 1.39804328609528886042614983922832e-76'f64
    strm.close()
  peek(s, result)

proc readStr*(s: Stream, length: int): TaintedString =
  ## Reads a string of length `length` from the stream `s`. Raises `IOError` if
  ## an error occurred.
  runnableExamples:
    var strm = newStringStream("abcde")
    doAssert strm.readStr(2) == "ab"
    doAssert strm.readStr(2) == "cd"
    doAssert strm.readStr(2) == "e"
    doAssert strm.readStr(2) == ""
    strm.close()
  result = newString(length).TaintedString
  var L = readData(s, cstring(result), length)
  if L != length: setLen(result.string, L)

proc peekStr*(s: Stream, length: int): TaintedString =
  ## Peeks a string of length `length` from the stream `s`. Raises `IOError` if
  ## an error occurred.
  runnableExamples:
    var strm = newStringStream("abcde")
    doAssert strm.peekStr(2) == "ab"
    doAssert strm.peekStr(2) == "ab"
    doAssert strm.peekStr(2) == "ab"
    doAssert strm.peekStr(2) == "ab"
    strm.close()
  result = newString(length).TaintedString
  var L = peekData(s, cstring(result), length)
  if L != length: setLen(result.string, L)

proc readLine*(s: Stream, line: var TaintedString): bool =
  ## Reads a line of text from the stream `s` into `line`. `line` must not be
  ## ``nil``! May throw an IO exception.
  ## A line of text may be delimited by ``LF`` or ``CRLF``.
  ## The newline character(s) are not part of the returned string.
  ## Returns ``false`` if the end of the file has been reached, ``true``
  ## otherwise. If ``false`` is returned `line` contains no new data.
  ##
  ## See also:
  ## * `readLine(Stream) proc <#readLine,Stream>`_
  ## * `peekLine(Stream) proc <#peekLine,Stream>`_
  ## * `peekLine(Stream, TaintedString) proc <#peekLine,Stream,TaintedString>`_
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
  line.string.setLen(0)
  while true:
    var c = readChar(s)
    if c == '\c':
      c = readChar(s)
      break
    elif c == '\L': break
    elif c == '\0':
      if line.len > 0: break
      else: return false
    line.string.add(c)
  result = true

proc peekLine*(s: Stream, line: var TaintedString): bool =
  ## Peeks a line of text from the stream `s` into `line`. `line` must not be
  ## ``nil``! May throw an IO exception.
  ## A line of text may be delimited by ``CR``, ``LF`` or
  ## ``CRLF``. The newline character(s) are not part of the returned string.
  ## Returns ``false`` if the end of the file has been reached, ``true``
  ## otherwise. If ``false`` is returned `line` contains no new data.
  ##
  ## See also:
  ## * `readLine(Stream) proc <#readLine,Stream>`_
  ## * `readLine(Stream, TaintedString) proc <#readLine,Stream,TaintedString>`_
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

proc readLine*(s: Stream): TaintedString =
  ## Reads a line from a stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:**
  ## * This is not very efficient.
  ##
  ## See also:
  ## * `readLine(Stream, TaintedString) proc <#readLine,Stream,TaintedString>`_
  ## * `peekLine(Stream) proc <#peekLine,Stream>`_
  ## * `peekLine(Stream, TaintedString) proc <#peekLine,Stream,TaintedString>`_
  runnableExamples:
    var strm = newStringStream("The first line\nthe second line\nthe third line")
    
    doAssert strm.readLine() == "The first line"
    doAssert strm.readLine() == "the second line"
    doAssert strm.readLine() == "the third line"
    ## strm.readLine() --> raise IOError
    
    strm.close()
  result = TaintedString""
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
      result.string.add(c)

proc peekLine*(s: Stream): TaintedString =
  ## Peeks a line from a stream `s`. Raises `IOError` if an error occurred.
  ##
  ## **Note:**
  ## * This is not very efficient.
  ##
  ## See also:
  ## * `readLine(Stream) proc <#readLine,Stream>`_
  ## * `readLine(Stream, TaintedString) proc <#readLine,Stream,TaintedString>`_
  ## * `peekLine(Stream, TaintedString) proc <#peekLine,Stream,TaintedString>`_
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

iterator lines*(s: Stream): TaintedString =
  ## Iterates over every line in the stream.
  ## The iteration is based on ``readLine``.
  ##
  ## See also:
  ## * `readLine(Stream) proc <#readLine,Stream>`_
  ## * `readLine(Stream, TaintedString) proc <#readLine,Stream,TaintedString>`_
  runnableExamples:
    var strm = newStringStream("The first line\nthe second line\nthe third line")
    var lines: seq[string]
    
    for line in strm.lines():
      lines.add line
    
    doAssert lines == @["The first line", "the second line", "the third line"]
    
    strm.close()
  var line: TaintedString
  while s.readLine(line):
    yield line

when not defined(js):

  type
    StringStream* = ref StringStreamObj
      ## A stream that encapsulates a string
      ##
      ## **Note:**
      ## * Not available this when backend is js
    StringStreamObj* = object of StreamObj
      ## A string stream object.
      ##
      ## **Note:**
      ## * Not available this when backend is js
      data*: string ## A string data.
                    ## This is updated when called `writeLine` etc.
      pos: int

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
    result = min(slice.b + 1 - slice.a, s.data.len - s.pos)
    if result > 0:
      when nimvm:
        for i in 0 ..< result: # sorry, but no fast string splicing on the vm.
          buffer[slice.a + i] = s.data[s.pos + i]
      else:
        copyMem(unsafeAddr buffer[slice.a], addr s.data[s.pos], result)
      inc(s.pos, result)
    else:
      result = 0

  proc ssReadData(s: Stream, buffer: pointer, bufLen: int): int =
    var s = StringStream(s)
    result = min(bufLen, s.data.len - s.pos)
    if result > 0:
      copyMem(buffer, addr(s.data[s.pos]), result)
      inc(s.pos, result)
    else:
      result = 0

  proc ssPeekData(s: Stream, buffer: pointer, bufLen: int): int =
    var s = StringStream(s)
    result = min(bufLen, s.data.len - s.pos)
    if result > 0:
      copyMem(buffer, addr(s.data[s.pos]), result)
    else:
      result = 0

  proc ssWriteData(s: Stream, buffer: pointer, bufLen: int) =
    var s = StringStream(s)
    if bufLen <= 0:
      return
    if s.pos + bufLen > s.data.len:
      setLen(s.data, s.pos + bufLen)
    copyMem(addr(s.data[s.pos]), buffer, bufLen)
    inc(s.pos, bufLen)

  proc ssClose(s: Stream) =
    var s = StringStream(s)
    when defined(nimNoNilSeqs):
      s.data = ""
    else:
      s.data = nil

  proc newStringStream*(s: string = ""): owned StringStream =
    ## Creates a new stream from the string `s`.
    ##
    ## **Note:**
    ## * Not available this when backend is js
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
    result.pos = 0
    result.closeImpl = ssClose
    result.atEndImpl = ssAtEnd
    result.setPositionImpl = ssSetPosition
    result.getPositionImpl = ssGetPosition
    result.readDataImpl = ssReadData
    result.peekDataImpl = ssPeekData
    result.writeDataImpl = ssWriteData
    result.readDataStrImpl = ssReadDataStr

  type
    FileStream* = ref FileStreamObj
      ## A stream that encapsulates a `File`
      ##
      ## **Note:**
      ## * Not available this when backend is js
    FileStreamObj* = object of Stream
      ## A file stream object.
      ##
      ## **Note:**
      ## * Not available this when backend is js
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

  proc newFileStream*(f: File): owned FileStream =
    ## Creates a new stream from the file `f`.
    ##
    ## **Note:**
    ## * Not available this when backend is js
    ##
    ## See also:
    ## * `newStringStream proc <#newStringStream,string>`_ creates a new stream
    ##   from string.
    ## * `newFileStream proc <#newFileStream,string,FileMode,int>`_ is the same
    ##   as using `open proc <system.html#open,File,string,FileMode,int>`_
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
    result.peekDataImpl = fsPeekData
    result.writeDataImpl = fsWriteData
    result.flushImpl = fsFlush

  proc newFileStream*(filename: string, mode: FileMode = fmRead, bufSize: int = -1): owned FileStream =
    ## Creates a new stream from the file named `filename` with the mode `mode`.
    ## If the file cannot be opened, nil is returned. See the `io
    ## <io.html>`_ module for a list of available FileMode enums.
    ##
    ## **Note:**
    ## * **This function returns nil in case of failure.**
    ##   To prevent unexpected behavior and ensure proper error handling,
    ##   use `openFileStream proc <#openFileStream,string,FileMode,int>`_
    ##   instead.
    ## * Not available this when backend is js
    ##
    ## See also:
    ## * `newStringStream proc <#newStringStream,string>`_ creates a new stream
    ##   from string.
    ## * `newFileStream proc <#newFileStream,File>`_ creates a file stream from
    ##   opened File.
    ## * `openFileStream proc <#openFileStream,string,FileMode,int>`_ creates a
    ##   file stream from the file name and the mode.
    runnableExamples:
      from os import removeFile
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
    var f: File
    if open(f, filename, mode, bufSize): result = newFileStream(f)

  proc openFileStream*(filename: string, mode: FileMode = fmRead, bufSize: int = -1): owned FileStream =
    ## Creates a new stream from the file named `filename` with the mode `mode`.
    ## If the file cannot be opened, an IO exception is raised.
    ##
    ## **Note:**
    ## * Not available this when backend is js
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
    var f: File
    if open(f, filename, mode, bufSize):
      return newFileStream(f)
    else:
      raise newEIO("cannot open file")

when true:
  discard
else:
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
    import posix

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
      of fmRead:              flags = posix.O_RDONLY
      of fmWrite:             flags = O_WRONLY or int(O_CREAT)
      of fmReadWrite:         flags = O_RDWR or int(O_CREAT)
      of fmReadWriteExisting: flags = O_RDWR
      of fmAppend:            flags = O_WRONLY or int(O_CREAT) or O_APPEND
      var handle = open(filename, flags)
      if handle < 0: raise newEOS("posix.open() call failed")
    result = newFileHandleStream(handle)

when isMainModule and defined(testing):
  var ss = newStringStream("The quick brown fox jumped over the lazy dog.\nThe lazy dog ran")
  assert(ss.getPosition == 0)
  assert(ss.peekStr(5) == "The q")
  assert(ss.getPosition == 0) # haven't moved
  assert(ss.readStr(5) == "The q")
  assert(ss.getPosition == 5) # did move
  assert(ss.peekLine() == "uick brown fox jumped over the lazy dog.")
  assert(ss.getPosition == 5) # haven't moved
  var str = newString(100)
  assert(ss.peekLine(str))
  assert(str == "uick brown fox jumped over the lazy dog.")
  assert(ss.getPosition == 5) # haven't moved
