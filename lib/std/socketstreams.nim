#
#
#            Nim's Runtime Library
#        (c) Copyright 2021 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module provides an implementation of the streams interface for sockets.
## It contains two separate implementations, a
## `ReadSocketStream <#ReadSocketStream>`_ and a
## `WriteSocketStream <#WriteSocketStream>`_.
##
## The `ReadSocketStream` only supports reading, peeking, and seeking.
## It reads into a buffer, so even by
## seeking backwards it will only read the same position a single time from the
## underlying socket. To clear the buffer and free the data read into it you
## can call `resetStream`, this will also reset the position back to 0 but
## won't do anything to the underlying socket.
##
## The `WriteSocketStream` allows both reading and writing, but it performs the
## reads on the internal buffer. So by writing to the buffer you can then read
## back what was written but without receiving anything from the socket. You
## can also set the position and overwrite parts of the buffer, and to send
## anything over the socket you need to call `flush` at which point you can't
## write anything to the buffer before the point of the flush (but it can still
## be read). Again to empty the underlying buffer you need to call
## `resetStream`.
##
## Examples
## ========
##
##   ```Nim
##   import std/socketstreams
##
##   var
##     socket = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
##     stream = newReadSocketStream(socket)
##   socket.sendTo("127.0.0.1", Port(12345), "SOME REQUEST")
##   echo stream.readLine() # Will call `recv`
##   stream.setPosition(0)
##   echo stream.readLine() # Will return the read line from the buffer
##   stream.resetStream() # Buffer is now empty, position is 0
##   echo stream.readLine() # Will call `recv` again
##   stream.close() # Closes the socket
##   ```
##
##   ```Nim
##   import std/socketstreams
##
##   var socket = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
##   socket.connect("127.0.0.1", Port(12345))
##   var sendStream = newWriteSocketStream(socket)
##   sendStream.write "NOM"
##   sendStream.setPosition(1)
##   echo sendStream.peekStr(2) # OM
##   sendStream.write "I"
##   sendStream.setPosition(0)
##   echo sendStream.readStr(3) # NIM
##   echo sendStream.getPosition() # 3
##   sendStream.flush() # This actually performs the writing to the socket
##   sendStream.setPosition(1)
##   sendStream.write "I" # Throws an error as we can't write into an already sent buffer
##   ```

import std/[net, streams]

type
  ReadSocketStream* = ref ReadSocketStreamObj
  ReadSocketStreamObj* = object of StreamObj
    data: Socket
    pos: int
    buf: seq[byte]
  WriteSocketStream* = ref WriteSocketStreamObj
  WriteSocketStreamObj* = object of ReadSocketStreamObj
    lastFlush: int

proc rsAtEnd(s: Stream): bool =
  return false

proc rsSetPosition(s: Stream, pos: int) =
  var s = ReadSocketStream(s)
  s.pos = pos

proc rsGetPosition(s: Stream): int =
  var s = ReadSocketStream(s)
  return s.pos

proc rsPeekData(s: Stream, buffer: pointer, bufLen: int): int =
  result = 0
  let s = ReadSocketStream(s)
  if bufLen > 0:
    let oldLen = s.buf.len
    s.buf.setLen(max(s.pos + bufLen, s.buf.len))
    if s.pos + bufLen > oldLen:
      result = s.data.recv(s.buf[oldLen].addr, s.buf.len - oldLen)
      if result > 0:
        result += oldLen - s.pos
    else:
      result = bufLen
    copyMem(buffer, s.buf[s.pos].addr, result)

proc rsReadData(s: Stream, buffer: pointer, bufLen: int): int =
  result = s.rsPeekData(buffer, bufLen)
  var s = ReadSocketStream(s)
  s.pos += bufLen

proc rsReadDataStr(s: Stream, buffer: var string, slice: Slice[int]): int =
  var s = ReadSocketStream(s)
  result = slice.b + 1 - slice.a
  if result > 0:
    result = s.rsReadData(buffer[slice.a].addr, result)
    inc(s.pos, result)
  else:
    result = 0

proc wsWriteData(s: Stream, buffer: pointer, bufLen: int) =
  var s = WriteSocketStream(s)
  if s.pos < s.lastFlush:
    raise newException(IOError, "Unable to write into buffer that has already been sent")
  if s.buf.len < s.pos + bufLen:
    s.buf.setLen(s.pos + bufLen)
  copyMem(s.buf[s.pos].addr, buffer, bufLen)
  s.pos += bufLen

proc wsPeekData(s: Stream, buffer: pointer, bufLen: int): int =
  var s = WriteSocketStream(s)
  result = bufLen
  if result > 0:
    if s.pos > s.buf.len or s.pos == s.buf.len or s.pos + bufLen > s.buf.len:
      raise newException(IOError, "Unable to read past end of write buffer")
    else:
      copyMem(buffer, s.buf[s.pos].addr, bufLen)

proc wsReadData(s: Stream, buffer: pointer, bufLen: int): int =
  result = s.wsPeekData(buffer, bufLen)
  var s = ReadSocketStream(s)
  s.pos += bufLen

proc wsAtEnd(s: Stream): bool =
  var s = WriteSocketStream(s)
  return s.pos == s.buf.len

proc wsFlush(s: Stream) =
  var s = WriteSocketStream(s)
  discard s.data.send(s.buf[s.lastFlush].addr, s.buf.len - s.lastFlush)
  s.lastFlush = s.buf.len

proc rsClose(s: Stream) =
  {.cast(raises: [IOError, OSError]), cast(tags: []).}: # todo fixme maybe do something?
    var s = ReadSocketStream(s)
    s.data.close()

proc newReadSocketStream*(s: Socket): owned ReadSocketStream =
  result = ReadSocketStream(data: s, pos: 0,
    closeImpl: rsClose,
    atEndImpl: rsAtEnd,
    setPositionImpl: rsSetPosition,
    getPositionImpl: rsGetPosition,
    readDataImpl: rsReadData,
    peekDataImpl: rsPeekData,
    readDataStrImpl: rsReadDataStr)

proc resetStream*(s: ReadSocketStream) =
  s.buf = @[]
  s.pos = 0

proc newWriteSocketStream*(s: Socket): owned WriteSocketStream =
  result = WriteSocketStream(data: s, pos: 0,
    closeImpl: rsClose,
    atEndImpl: wsAtEnd,
    setPositionImpl: rsSetPosition,
    getPositionImpl: rsGetPosition,
    writeDataImpl: wsWriteData,
    readDataImpl: wsReadData,
    peekDataImpl: wsPeekData,
    flushImpl: wsFlush)

proc resetStream*(s: WriteSocketStream) =
  s.buf = @[]
  s.pos = 0
  s.lastFlush = 0
