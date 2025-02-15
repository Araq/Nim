#
#
#            Nim's Runtime Library
#        (c) Copyright 2017 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements a high-level asynchronous sockets API based on the
## asynchronous dispatcher defined in the `asyncdispatch` module.
##
## Asynchronous IO in Nim
## ======================
##
## Async IO in Nim consists of multiple layers (from highest to lowest):
##
## * `asyncnet` module
##
## * Async await
##
## * `asyncdispatch` module (event loop)
##
## * `selectors` module
##
## Each builds on top of the layers below it. The selectors module is an
## abstraction for the various system `select()` mechanisms such as epoll or
## kqueue. If you wish you can use it directly, and some people have done so
## `successfully <https://goran.krampe.se/2014/10/25/nim-socketserver/>`_.
## But you must be aware that on Windows it only supports
## `select()`.
##
## The async dispatcher implements the proactor pattern and also has an
## implementation of IOCP. It implements the proactor pattern for other
## OS' via the selectors module. Futures are also implemented here, and
## indeed all the procedures return a future.
##
## The final layer is the async await transformation. This allows you to
## write asynchronous code in a synchronous style and works similar to
## C#'s await. The transformation works by converting any async procedures
## into an iterator.
##
## This is all single threaded, fully non-blocking and does give you a
## lot of control. In theory you should be able to work with any of these
## layers interchangeably (as long as you only care about non-Windows
## platforms).
##
## For most applications using `asyncnet` is the way to go as it builds
## over all the layers, providing some extra features such as buffering.
##
## SSL
## ===
##
## SSL can be enabled by compiling with the `-d:ssl` flag.
##
## You must create a new SSL context with the `newContext` function defined
## in the `net` module. You may then call `wrapSocket` on your socket using
## the newly created SSL context to get an SSL socket.
##
## Examples
## ========
##
## Chat server
## -----------
##
## The following example demonstrates a simple chat server.
##
##   ```Nim
##   import std/[asyncnet, asyncdispatch]
##
##   var clients {.threadvar.}: seq[AsyncSocket]
##
##   proc processClient(client: AsyncSocket) {.async.} =
##     while true:
##       let line = await client.recvLine()
##       if line.len == 0: break
##       for c in clients:
##         await c.send(line & "\c\L")
##
##   proc serve() {.async.} =
##     clients = @[]
##     var server = newAsyncSocket()
##     server.setSockOpt(OptReuseAddr, true)
##     server.bindAddr(Port(12345))
##     server.listen()
##
##     while true:
##       let client = await server.accept()
##       clients.add client
##
##       asyncCheck processClient(client)
##
##   asyncCheck serve()
##   runForever()
##   ```

import std/private/since

when defined(nimPreviewSlimSystem):
  import std/[assertions, syncio]

import std/[asyncdispatch, nativesockets, net, os]

export SOBool

# TODO: Remove duplication introduced by PR #4683.

const defineSsl = defined(ssl) or defined(nimdoc)
const useNimNetLite = defined(nimNetLite) or defined(freertos) or defined(zephyr) or
    defined(nuttx)

when defineSsl:
  import std/openssl

type
  # TODO: I would prefer to just do:
  # AsyncSocket* {.borrow: `.`.} = distinct Socket. But that doesn't work.
  AsyncSocketDesc = object
    fd: SocketHandle
    closed: bool     ## determines whether this socket has been closed
    isBuffered: bool ## determines whether this socket is buffered.
    buffer: array[0..BufferSize, char]
    currPos: int     # current index in buffer
    bufLen: int      # current length of buffer
    isSsl: bool
    when defineSsl:
      sslHandle: SslPtr
      sslContext: SslContext
      bioIn: BIO
      bioOut: BIO
      sslNoShutdown: bool
    domain: Domain
    sockType: SockType
    protocol: Protocol
  AsyncSocket* = ref AsyncSocketDesc

proc newAsyncSocket*(fd: AsyncFD, domain: Domain = AF_INET,
                     sockType: SockType = SOCK_STREAM,
                     protocol: Protocol = IPPROTO_TCP,
                     buffered = true,
                     inheritable = defined(nimInheritHandles)): owned(AsyncSocket) =
  ## Creates a new `AsyncSocket` based on the supplied params.
  ##
  ## The supplied `fd`'s non-blocking state will be enabled implicitly.
  ##
  ## If `inheritable` is false (the default), the supplied `fd` will not
  ## be inheritable by child processes.
  ##
  ## **Note**: This procedure will **NOT** register `fd` with the global
  ## async dispatcher. You need to do this manually. If you have used
  ## `newAsyncNativeSocket` to create `fd` then it's already registered.
  assert fd != osInvalidSocket.AsyncFD
  new(result)
  result.fd = fd.SocketHandle
  fd.SocketHandle.setBlocking(false)
  if not fd.SocketHandle.setInheritable(inheritable):
    raiseOSError(osLastError())
  result.isBuffered = buffered
  result.domain = domain
  result.sockType = sockType
  result.protocol = protocol
  if buffered:
    result.currPos = 0

proc newAsyncSocket*(domain: Domain = AF_INET, sockType: SockType = SOCK_STREAM,
                     protocol: Protocol = IPPROTO_TCP, buffered = true,
                     inheritable = defined(nimInheritHandles)): owned(AsyncSocket) =
  ## Creates a new asynchronous socket.
  ##
  ## This procedure will also create a brand new file descriptor for
  ## this socket.
  ##
  ## If `inheritable` is false (the default), the new file descriptor will not
  ## be inheritable by child processes.
  let fd = createAsyncNativeSocket(domain, sockType, protocol, inheritable)
  if fd.SocketHandle == osInvalidSocket:
    raiseOSError(osLastError())
  result = newAsyncSocket(fd, domain, sockType, protocol, buffered, inheritable)

proc getLocalAddr*(socket: AsyncSocket): (string, Port) =
  ## Get the socket's local address and port number.
  ##
  ## This is high-level interface for `getsockname`:idx:.
  getLocalAddr(socket.fd, socket.domain)

when not useNimNetLite:
  proc getPeerAddr*(socket: AsyncSocket): (string, Port) =
    ## Get the socket's peer address and port number.
    ##
    ## This is high-level interface for `getpeername`:idx:.
    getPeerAddr(socket.fd, socket.domain)

proc newAsyncSocket*(domain, sockType, protocol: cint,
                     buffered = true,
                     inheritable = defined(nimInheritHandles)): owned(AsyncSocket) =
  ## Creates a new asynchronous socket.
  ##
  ## This procedure will also create a brand new file descriptor for
  ## this socket.
  ##
  ## If `inheritable` is false (the default), the new file descriptor will not
  ## be inheritable by child processes.
  let fd = createAsyncNativeSocket(domain, sockType, protocol, inheritable)
  if fd.SocketHandle == osInvalidSocket:
    raiseOSError(osLastError())
  result = newAsyncSocket(fd, Domain(domain), SockType(sockType),
                          Protocol(protocol), buffered, inheritable)

when defineSsl:
  proc getSslError(socket: AsyncSocket, err: cint): cint =
    assert socket.isSsl
    assert err < 0
    var ret = SSL_get_error(socket.sslHandle, err.cint)
    case ret
    of SSL_ERROR_ZERO_RETURN:
      raiseSSLError("TLS/SSL connection failed to initiate, socket closed prematurely.")
    of SSL_ERROR_WANT_CONNECT, SSL_ERROR_WANT_ACCEPT:
      return ret
    of SSL_ERROR_WANT_WRITE, SSL_ERROR_WANT_READ:
      return ret
    of SSL_ERROR_WANT_X509_LOOKUP:
      raiseSSLError("Function for x509 lookup has been called.")
    of SSL_ERROR_SYSCALL, SSL_ERROR_SSL:
      socket.sslNoShutdown = true
      raiseSSLError()
    else: raiseSSLError("Unknown Error")

  proc sendPendingSslData(socket: AsyncSocket,
      flags: set[SocketFlag]) {.async.} =
    let len = bioCtrlPending(socket.bioOut)
    if len > 0:
      var data = newString(len)
      let read = bioRead(socket.bioOut, cast[cstring](addr data[0]), len)
      assert read != 0
      if read < 0:
        raiseSSLError()
      data.setLen(read)
      await socket.fd.AsyncFD.send(data, flags)

  proc appeaseSsl(socket: AsyncSocket, flags: set[SocketFlag],
                  sslError: cint): owned(Future[bool]) {.async.} =
    ## Returns `true` if `socket` is still connected, otherwise `false`.
    result = true
    case sslError
    of SSL_ERROR_WANT_WRITE:
      await sendPendingSslData(socket, flags)
    of SSL_ERROR_WANT_READ:
      var data = await recv(socket.fd.AsyncFD, BufferSize, flags)
      let length = len(data)
      if length > 0:
        let ret = bioWrite(socket.bioIn, cast[cstring](addr data[0]), length.cint)
        if ret < 0:
          raiseSSLError()
      elif length == 0:
        # connection not properly closed by remote side or connection dropped
        SSL_set_shutdown(socket.sslHandle, SSL_RECEIVED_SHUTDOWN)
        result = false
    else:
      raiseSSLError("Cannot appease SSL.")

  template sslLoop(socket: AsyncSocket, flags: set[SocketFlag],
                   op: untyped) =
    var opResult {.inject.} = -1.cint
    while opResult < 0:
      ErrClearError()
      # Call the desired operation.
      opResult = op
      let err =
        if opResult < 0:
          getSslError(socket, opResult.cint)
        else:
          SSL_ERROR_NONE
      # Send any remaining pending SSL data.
      await sendPendingSslData(socket, flags)

      # If the operation failed, try to see if SSL has some data to read
      # or write.
      if opResult < 0:
        let fut = appeaseSsl(socket, flags, err.cint)
        yield fut
        if not fut.read():
          # Socket disconnected.
          if SocketFlag.SafeDisconn in flags:
            opResult = 0.cint
            break
          else:
            raiseSSLError("Socket has been disconnected")

proc dial*(address: string, port: Port, protocol = IPPROTO_TCP,
           buffered = true): owned(Future[AsyncSocket]) {.async.} =
  ## Establishes connection to the specified `address`:`port` pair via the
  ## specified protocol. The procedure iterates through possible
  ## resolutions of the `address` until it succeeds, meaning that it
  ## seamlessly works with both IPv4 and IPv6.
  ## Returns AsyncSocket ready to send or receive data.
  let asyncFd = await asyncdispatch.dial(address, port, protocol)
  let sockType = protocol.toSockType()
  let domain = getSockDomain(asyncFd.SocketHandle)
  result = newAsyncSocket(asyncFd, domain, sockType, protocol, buffered)

proc connect*(socket: AsyncSocket, address: string, port: Port) {.async.} =
  ## Connects `socket` to server at `address:port`.
  ##
  ## Returns a `Future` which will complete when the connection succeeds
  ## or an error occurs.
  await connect(socket.fd.AsyncFD, address, port, socket.domain)
  if socket.isSsl:
    when defineSsl:
      if not isIpAddress(address):
        # Set the SNI address for this connection. This call can fail if
        # we're not using TLSv1+.
        discard SSL_set_tlsext_host_name(socket.sslHandle, address)

      let flags = {SocketFlag.SafeDisconn}
      sslSetConnectState(socket.sslHandle)
      sslLoop(socket, flags, sslDoHandshake(socket.sslHandle))

template readInto(buf: pointer, size: int, socket: AsyncSocket,
                  flags: set[SocketFlag]): int =
  ## Reads **up to** `size` bytes from `socket` into `buf`. Note that
  ## this is a template and not a proc.
  assert(not socket.closed, "Cannot `recv` on a closed socket")
  var res = 0
  if socket.isSsl:
    when defineSsl:
      # SSL mode.
      sslLoop(socket, flags,
        sslRead(socket.sslHandle, cast[cstring](buf), size.cint))
      res = opResult
  else:
    # Not in SSL mode.
    res = await asyncdispatch.recvInto(socket.fd.AsyncFD, buf, size, flags)
  res

template readIntoBuf(socket: AsyncSocket,
    flags: set[SocketFlag]): int =
  var size = readInto(addr socket.buffer[0], BufferSize, socket, flags)
  socket.currPos = 0
  socket.bufLen = size
  size

proc recvInto*(socket: AsyncSocket, buf: pointer, size: int,
           flags = {SocketFlag.SafeDisconn}): owned(Future[int]) {.async.} =
  ## Reads **up to** `size` bytes from `socket` into `buf`.
  ##
  ## For buffered sockets this function will attempt to read all the requested
  ## data. It will read this data in `BufferSize` chunks.
  ##
  ## For unbuffered sockets this function makes no effort to read
  ## all the data requested. It will return as much data as the operating system
  ## gives it.
  ##
  ## If socket is disconnected during the
  ## recv operation then the future may complete with only a part of the
  ## requested data.
  ##
  ## If socket is disconnected and no data is available
  ## to be read then the future will complete with a value of `0`.
  if socket.isBuffered:
    let originalBufPos = socket.currPos

    if socket.bufLen == 0:
      let res = socket.readIntoBuf(flags - {SocketFlag.Peek})
      if res == 0:
        return 0

    var read = 0
    var cbuf = cast[cstring](buf)
    while read < size:
      if socket.currPos >= socket.bufLen:
        if SocketFlag.Peek in flags:
          # We don't want to get another buffer if we're peeking.
          break
        let res = socket.readIntoBuf(flags - {SocketFlag.Peek})
        if res == 0:
          break

      let chunk = min(socket.bufLen-socket.currPos, size-read)
      copyMem(addr(cbuf[read]), addr(socket.buffer[socket.currPos]), chunk)
      read.inc(chunk)
      socket.currPos.inc(chunk)

    if SocketFlag.Peek in flags:
      # Restore old buffer cursor position.
      socket.currPos = originalBufPos
    result = read
  else:
    result = readInto(buf, size, socket, flags)

proc recv*(socket: AsyncSocket, size: int,
           flags = {SocketFlag.SafeDisconn}): owned(Future[string]) {.async.} =
  ## Reads **up to** `size` bytes from `socket`.
  ##
  ## For buffered sockets this function will attempt to read all the requested
  ## data. It will read this data in `BufferSize` chunks.
  ##
  ## For unbuffered sockets this function makes no effort to read
  ## all the data requested. It will return as much data as the operating system
  ## gives it.
  ##
  ## If socket is disconnected during the
  ## recv operation then the future may complete with only a part of the
  ## requested data.
  ##
  ## If socket is disconnected and no data is available
  ## to be read then the future will complete with a value of `""`.
  if socket.isBuffered:
    result = newString(size)
    when not defined(nimSeqsV2):
      shallow(result)
    let originalBufPos = socket.currPos

    if socket.bufLen == 0:
      let res = socket.readIntoBuf(flags - {SocketFlag.Peek})
      if res == 0:
        result.setLen(0)
        return

    var read = 0
    while read < size:
      if socket.currPos >= socket.bufLen:
        if SocketFlag.Peek in flags:
          # We don't want to get another buffer if we're peeking.
          break
        let res = socket.readIntoBuf(flags - {SocketFlag.Peek})
        if res == 0:
          break

      let chunk = min(socket.bufLen-socket.currPos, size-read)
      copyMem(addr(result[read]), addr(socket.buffer[socket.currPos]), chunk)
      read.inc(chunk)
      socket.currPos.inc(chunk)

    if SocketFlag.Peek in flags:
      # Restore old buffer cursor position.
      socket.currPos = originalBufPos
    result.setLen(read)
  else:
    result = newString(size)
    let read = readInto(addr result[0], size, socket, flags)
    result.setLen(read)

proc send*(socket: AsyncSocket, buf: pointer, size: int,
            flags = {SocketFlag.SafeDisconn}) {.async.} =
  ## Sends `size` bytes from `buf` to `socket`. The returned future will complete once all
  ## data has been sent.
  assert socket != nil
  assert(not socket.closed, "Cannot `send` on a closed socket")
  if socket.isSsl:
    when defineSsl:
      sslLoop(socket, flags,
              sslWrite(socket.sslHandle, cast[cstring](buf), size.cint))
      await sendPendingSslData(socket, flags)
  else:
    await send(socket.fd.AsyncFD, buf, size, flags)

proc send*(socket: AsyncSocket, data: string,
           flags = {SocketFlag.SafeDisconn}) {.async.} =
  ## Sends `data` to `socket`. The returned future will complete once all
  ## data has been sent.
  assert socket != nil
  if socket.isSsl:
    when defineSsl:
      var copy = data
      sslLoop(socket, flags,
        sslWrite(socket.sslHandle, cast[cstring](addr copy[0]), copy.len.cint))
      await sendPendingSslData(socket, flags)
  else:
    await send(socket.fd.AsyncFD, data, flags)

proc acceptAddr*(socket: AsyncSocket, flags = {SocketFlag.SafeDisconn},
                 inheritable = defined(nimInheritHandles)):
      owned(Future[tuple[address: string, client: AsyncSocket]]) =
  ## Accepts a new connection. Returns a future containing the client socket
  ## corresponding to that connection and the remote address of the client.
  ##
  ## If `inheritable` is false (the default), the resulting client socket will
  ## not be inheritable by child processes.
  ##
  ## The future will complete when the connection is successfully accepted.
  var retFuture = newFuture[tuple[address: string, client: AsyncSocket]]("asyncnet.acceptAddr")
  var fut = acceptAddr(socket.fd.AsyncFD, flags, inheritable)
  fut.callback =
    proc (future: Future[tuple[address: string, client: AsyncFD]]) =
      assert future.finished
      if future.failed:
        retFuture.fail(future.readError)
      else:
        let resultTup = (future.read.address,
                         newAsyncSocket(future.read.client, socket.domain,
                         socket.sockType, socket.protocol, socket.isBuffered, inheritable))
        retFuture.complete(resultTup)
  return retFuture

proc accept*(socket: AsyncSocket,
    flags = {SocketFlag.SafeDisconn}): owned(Future[AsyncSocket]) =
  ## Accepts a new connection. Returns a future containing the client socket
  ## corresponding to that connection.
  ## If `inheritable` is false (the default), the resulting client socket will
  ## not be inheritable by child processes.
  ## The future will complete when the connection is successfully accepted.
  var retFut = newFuture[AsyncSocket]("asyncnet.accept")
  var fut = acceptAddr(socket, flags)
  fut.callback =
    proc (future: Future[tuple[address: string, client: AsyncSocket]]) =
      assert future.finished
      if future.failed:
        retFut.fail(future.readError)
      else:
        retFut.complete(future.read.client)
  return retFut

proc recvLineInto*(socket: AsyncSocket, resString: FutureVar[string],
    flags = {SocketFlag.SafeDisconn}, maxLength = MaxLineLength) {.async.} =
  ## Reads a line of data from `socket` into `resString`.
  ##
  ## If a full line is read `\r\L` is not
  ## added to `line`, however if solely `\r\L` is read then `line`
  ## will be set to it.
  ##
  ## If the socket is disconnected, `line` will be set to `""`.
  ##
  ## If the socket is disconnected in the middle of a line (before `\r\L`
  ## is read) then line will be set to `""`.
  ## The partial line **will be lost**.
  ##
  ## The `maxLength` parameter determines the maximum amount of characters
  ## that can be read. `resString` will be truncated after that.
  ##
  ## .. warning:: The `Peek` flag is not yet implemented.
  ##
  ## .. warning:: `recvLineInto` on unbuffered sockets assumes that the protocol uses `\r\L` to delimit a new line.
  assert SocketFlag.Peek notin flags ## TODO:
  result = newFuture[void]("asyncnet.recvLineInto")

  # TODO: Make the async transformation check for FutureVar params and complete
  # them when the result future is completed.
  # Can we replace the result future with the FutureVar?

  template addNLIfEmpty(): untyped =
    if resString.mget.len == 0:
      resString.mget.add("\c\L")

  if socket.isBuffered:
    if socket.bufLen == 0:
      let res = socket.readIntoBuf(flags)
      if res == 0:
        resString.complete()
        return

    var lastR = false
    while true:
      if socket.currPos >= socket.bufLen:
        let res = socket.readIntoBuf(flags)
        if res == 0:
          resString.mget.setLen(0)
          resString.complete()
          return

      case socket.buffer[socket.currPos]
      of '\r':
        lastR = true
        addNLIfEmpty()
      of '\L':
        addNLIfEmpty()
        socket.currPos.inc()
        resString.complete()
        return
      else:
        if lastR:
          socket.currPos.inc()
          resString.complete()
          return
        else:
          resString.mget.add socket.buffer[socket.currPos]
      socket.currPos.inc()

      # Verify that this isn't a DOS attack: #3847.
      if resString.mget.len > maxLength: break
  else:
    var c = ""
    while true:
      c = await recv(socket, 1, flags)
      if c.len == 0:
        resString.mget.setLen(0)
        resString.complete()
        return
      if c == "\r":
        c = await recv(socket, 1, flags) # Skip \L
        assert c == "\L"
        addNLIfEmpty()
        resString.complete()
        return
      elif c == "\L":
        addNLIfEmpty()
        resString.complete()
        return
      resString.mget.add c

      # Verify that this isn't a DOS attack: #3847.
      if resString.mget.len > maxLength: break
  resString.complete()

proc recvLine*(socket: AsyncSocket,
    flags = {SocketFlag.SafeDisconn},
    maxLength = MaxLineLength): owned(Future[string]) {.async.} =
  ## Reads a line of data from `socket`. Returned future will complete once
  ## a full line is read or an error occurs.
  ##
  ## If a full line is read `\r\L` is not
  ## added to `line`, however if solely `\r\L` is read then `line`
  ## will be set to it.
  ##
  ## If the socket is disconnected, `line` will be set to `""`.
  ##
  ## If the socket is disconnected in the middle of a line (before `\r\L`
  ## is read) then line will be set to `""`.
  ## The partial line **will be lost**.
  ##
  ## The `maxLength` parameter determines the maximum amount of characters
  ## that can be read. The result is truncated after that.
  ##
  ## .. warning:: The `Peek` flag is not yet implemented.
  ##
  ## .. warning:: `recvLine` on unbuffered sockets assumes that the protocol uses `\r\L` to delimit a new line.
  assert SocketFlag.Peek notin flags ## TODO:

  # TODO: Optimise this
  var resString = newFutureVar[string]("asyncnet.recvLine")
  resString.mget() = ""
  await socket.recvLineInto(resString, flags, maxLength)
  result = resString.mget()

proc listen*(socket: AsyncSocket, backlog = SOMAXCONN) {.tags: [
    ReadIOEffect].} =
  ## Marks `socket` as accepting connections.
  ## `Backlog` specifies the maximum length of the
  ## queue of pending connections.
  ##
  ## Raises an OSError error upon failure.
  if listen(socket.fd, backlog) < 0'i32: raiseOSError(osLastError())

proc bindAddr*(socket: AsyncSocket, port = Port(0), address = "") {.
  tags: [ReadIOEffect].} =
  ## Binds `address`:`port` to the socket.
  ##
  ## If `address` is "" then ADDR_ANY will be bound.
  var realaddr = address
  if realaddr == "":
    case socket.domain
    of AF_INET6: realaddr = "::"
    of AF_INET: realaddr = "0.0.0.0"
    else:
      raise newException(ValueError,
        "Unknown socket address family and no address specified to bindAddr")

  var aiList = getAddrInfo(realaddr, port, socket.domain)
  if bindAddr(socket.fd, aiList.ai_addr, aiList.ai_addrlen.SockLen) < 0'i32:
    freeAddrInfo(aiList)
    raiseOSError(osLastError())
  freeAddrInfo(aiList)

proc hasDataBuffered*(s: AsyncSocket): bool {.since: (1, 5).} =
  ## Determines whether an AsyncSocket has data buffered.
  # xxx dedup with std/net
  s.isBuffered and s.bufLen > 0 and s.currPos != s.bufLen

when defined(posix) and not useNimNetLite:

  proc connectUnix*(socket: AsyncSocket, path: string): owned(Future[void]) =
    ## Binds Unix socket to `path`.
    ## This only works on Unix-style systems: Mac OS X, BSD and Linux
    when not defined(nimdoc):
      let retFuture = newFuture[void]("connectUnix")
      result = retFuture

      proc cb(fd: AsyncFD): bool =
        let ret = SocketHandle(fd).getSockOptInt(cint(SOL_SOCKET), cint(SO_ERROR))
        if ret == 0:
          retFuture.complete()
          return true
        elif ret == EINTR:
          return false
        else:
          retFuture.fail(newOSError(OSErrorCode(ret)))
          return true

      var socketAddr = makeUnixAddr(path)
      let ret = socket.fd.connect(cast[ptr SockAddr](addr socketAddr),
                        (offsetOf(socketAddr, sun_path) + path.len + 1).SockLen)
      if ret == 0:
        # Request to connect completed immediately.
        retFuture.complete()
      else:
        let lastError = osLastError()
        if lastError.int32 == EINTR or lastError.int32 == EINPROGRESS:
          addWrite(AsyncFD(socket.fd), cb)
        else:
          retFuture.fail(newOSError(lastError))

  proc bindUnix*(socket: AsyncSocket, path: string) {.
    tags: [ReadIOEffect].} =
    ## Binds Unix socket to `path`.
    ## This only works on Unix-style systems: Mac OS X, BSD and Linux
    when not defined(nimdoc):
      var socketAddr = makeUnixAddr(path)
      if socket.fd.bindAddr(cast[ptr SockAddr](addr socketAddr),
          (offsetOf(socketAddr, sun_path) + path.len + 1).SockLen) != 0'i32:
        raiseOSError(osLastError())

elif defined(nimdoc):

  proc connectUnix*(socket: AsyncSocket, path: string): owned(Future[void]) =
    ## Binds Unix socket to `path`.
    ## This only works on Unix-style systems: Mac OS X, BSD and Linux
    discard

  proc bindUnix*(socket: AsyncSocket, path: string) =
    ## Binds Unix socket to `path`.
    ## This only works on Unix-style systems: Mac OS X, BSD and Linux
    discard

proc close*(socket: AsyncSocket) =
  ## Closes the socket.
  if socket.closed: return

  defer:
    socket.fd.AsyncFD.closeSocket()
    socket.closed = true # TODO: Add extra debugging checks for this.

  when defineSsl:
    if socket.isSsl:
      let res =
        # Don't call SSL_shutdown if the connection has not been fully
        # established, see:
        # https://github.com/openssl/openssl/issues/710#issuecomment-253897666
        if not socket.sslNoShutdown and SSL_in_init(socket.sslHandle) == 0:
          ErrClearError()
          SSL_shutdown(socket.sslHandle)
        else:
          0
      SSL_free(socket.sslHandle)
      if res == 0:
        discard
      elif res != 1:
        raiseSSLError()

when defineSsl:
  proc sslHandle*(self: AsyncSocket): SslPtr =
    ## Retrieve the ssl pointer of `socket`.
    ## Useful for interfacing with `openssl`.
    self.sslHandle
  
  proc wrapSocket*(ctx: SslContext, socket: AsyncSocket) =
    ## Wraps a socket in an SSL context. This function effectively turns
    ## `socket` into an SSL socket.
    ##
    ## **Disclaimer**: This code is not well tested, may be very unsafe and
    ## prone to security vulnerabilities.
    socket.isSsl = true
    socket.sslContext = ctx
    socket.sslHandle = SSL_new(socket.sslContext.context)
    if socket.sslHandle == nil:
      raiseSSLError()

    socket.bioIn = bioNew(bioSMem())
    socket.bioOut = bioNew(bioSMem())
    sslSetBio(socket.sslHandle, socket.bioIn, socket.bioOut)

    socket.sslNoShutdown = true

  proc wrapConnectedSocket*(ctx: SslContext, socket: AsyncSocket,
                            handshake: SslHandshakeType,
                            hostname: string = "") =
    ## Wraps a connected socket in an SSL context. This function effectively
    ## turns `socket` into an SSL socket.
    ## `hostname` should be specified so that the client knows which hostname
    ## the server certificate should be validated against.
    ##
    ## This should be called on a connected socket, and will perform
    ## an SSL handshake immediately.
    ##
    ## **Disclaimer**: This code is not well tested, may be very unsafe and
    ## prone to security vulnerabilities.
    wrapSocket(ctx, socket)

    case handshake
    of handshakeAsClient:
      if hostname.len > 0 and not isIpAddress(hostname):
        # Set the SNI address for this connection. This call can fail if
        # we're not using TLSv1+.
        discard SSL_set_tlsext_host_name(socket.sslHandle, hostname)
      sslSetConnectState(socket.sslHandle)
    of handshakeAsServer:
      sslSetAcceptState(socket.sslHandle)

  proc getPeerCertificates*(socket: AsyncSocket): seq[Certificate] {.since: (1, 1).} =
    ## Returns the certificate chain received by the peer we are connected to
    ## through the given socket.
    ## The handshake must have been completed and the certificate chain must
    ## have been verified successfully or else an empty sequence is returned.
    ## The chain is ordered from leaf certificate to root certificate.
    if not socket.isSsl:
      result = newSeq[Certificate]()
    else:
      result = getPeerCertificates(socket.sslHandle)

proc getSockOpt*(socket: AsyncSocket, opt: SOBool, level = SOL_SOCKET): bool {.
  tags: [ReadIOEffect].} =
  ## Retrieves option `opt` as a boolean value.
  var res = getSockOptInt(socket.fd, cint(level), toCInt(opt))
  result = res != 0

proc setSockOpt*(socket: AsyncSocket, opt: SOBool, value: bool,
    level = SOL_SOCKET) {.tags: [WriteIOEffect].} =
  ## Sets option `opt` to a boolean value specified by `value`.
  var valuei = cint(if value: 1 else: 0)
  setSockOptInt(socket.fd, cint(level), toCInt(opt), valuei)

proc isSsl*(socket: AsyncSocket): bool =
  ## Determines whether `socket` is a SSL socket.
  socket.isSsl

proc getFd*(socket: AsyncSocket): SocketHandle =
  ## Returns the socket's file descriptor.
  return socket.fd

proc isClosed*(socket: AsyncSocket): bool =
  ## Determines whether the socket has been closed.
  return socket.closed

proc sendTo*(socket: AsyncSocket, address: string, port: Port, data: string,
             flags = {SocketFlag.SafeDisconn}): owned(Future[void])
            {.async, since: (1, 3).} =
  ## This proc sends `data` to the specified `address`, which may be an IP
  ## address or a hostname. If a hostname is specified this function will try
  ## each IP of that hostname. The returned future will complete once all data
  ## has been sent.
  ##
  ## If an error occurs an OSError exception will be raised.
  ##
  ## This proc is normally used with connectionless sockets (UDP sockets).
  assert(socket.protocol != IPPROTO_TCP,
         "Cannot `sendTo` on a TCP socket. Use `send` instead")
  assert(not socket.closed, "Cannot `sendTo` on a closed socket")

  let aiList = getAddrInfo(address, port, socket.domain, socket.sockType,
                           socket.protocol)

  var
    it = aiList
    success = false
    lastException: ref Exception = nil

  while it != nil:
    let fut = sendTo(socket.fd.AsyncFD, cstring(data), len(data), it.ai_addr,
                     it.ai_addrlen.SockLen, flags)

    yield fut

    if not fut.failed:
      success = true

      break

    lastException = fut.readError()

    it = it.ai_next

  freeAddrInfo(aiList)

  if not success:
    if lastException != nil:
      raise lastException
    else:
      raise newException(IOError, "Couldn't resolve address: " & address)

proc recvFrom*(socket: AsyncSocket, data: FutureVar[string], size: int,
               address: FutureVar[string], port: FutureVar[Port],
               flags = {SocketFlag.SafeDisconn}): owned(Future[int])
              {.async, since: (1, 3).} =
  ## Receives a datagram data from `socket` into `data`, which must be at
  ## least of size `size`. The address and port of datagram's sender will be
  ## stored into `address` and `port`, respectively. Returned future will
  ## complete once one datagram has been received, and will return size of
  ## packet received.
  ##
  ## If an error occurs an OSError exception will be raised.
  ##
  ## This proc is normally used with connectionless sockets (UDP sockets).
  ##
  ## **Notes**
  ## * `data` must be initialized to the length of `size`.
  ## * `address` must be initialized to 46 in length.
  template adaptRecvFromToDomain(domain: Domain) =
    var lAddr = sizeof(sAddr).SockLen

    result = await recvFromInto(AsyncFD(getFd(socket)), cstring(data.mget()), size,
                                cast[ptr SockAddr](addr sAddr), addr lAddr,
                                flags)

    data.mget().setLen(result)
    data.complete()

    getAddrString(cast[ptr SockAddr](addr sAddr), address.mget())

    address.complete()

    when domain == AF_INET6:
      port.complete(ntohs(sAddr.sin6_port).Port)
    else:
      port.complete(ntohs(sAddr.sin_port).Port)

  assert(socket.protocol != IPPROTO_TCP,
         "Cannot `recvFrom` on a TCP socket. Use `recv` or `recvInto` instead")
  assert(not socket.closed, "Cannot `recvFrom` on a closed socket")
  assert(size == len(data.mget()),
         "`data` was not initialized correctly. `size` != `len(data.mget())`")
  assert(46 == len(address.mget()),
         "`address` was not initialized correctly. 46 != `len(address.mget())`")

  case socket.domain
  of AF_INET6:
    var sAddr: Sockaddr_in6 = default(Sockaddr_in6)
    adaptRecvFromToDomain(AF_INET6)
  of AF_INET:
    var sAddr: Sockaddr_in = default(Sockaddr_in)
    adaptRecvFromToDomain(AF_INET)
  else:
    raise newException(ValueError, "Unknown socket address family")

proc recvFrom*(socket: AsyncSocket, size: int,
               flags = {SocketFlag.SafeDisconn}):
              owned(Future[tuple[data: string, address: string, port: Port]])
              {.async, since: (1, 3).} =
  ## Receives a datagram data from `socket`, which must be at least of size
  ## `size`. Returned future will complete once one datagram has been received
  ## and will return tuple with: data of packet received; and address and port
  ## of datagram's sender.
  ##
  ## If an error occurs an OSError exception will be raised.
  ##
  ## This proc is normally used with connectionless sockets (UDP sockets).
  var
    data = newFutureVar[string]()
    address = newFutureVar[string]()
    port = newFutureVar[Port]()

  data.mget().setLen(size)
  address.mget().setLen(46)

  let read = await recvFrom(socket, data, size, address, port, flags)

  result = (data.mget(), address.mget(), port.mget())

when not defined(testing) and isMainModule:
  type
    TestCases = enum
      HighClient, LowClient, LowServer

  const test = HighClient

  when test == HighClient:
    proc main() {.async.} =
      var sock = newAsyncSocket()
      await sock.connect("irc.freenode.net", Port(6667))
      while true:
        let line = await sock.recvLine()
        if line == "":
          echo("Disconnected")
          break
        else:
          echo("Got line: ", line)
    asyncCheck main()
  elif test == LowClient:
    var sock = newAsyncSocket()
    var f = connect(sock, "irc.freenode.net", Port(6667))
    f.callback =
      proc (future: Future[void]) =
        echo("Connected in future!")
        for i in 0 .. 50:
          var recvF = recv(sock, 10)
          recvF.callback =
            proc (future: Future[string]) =
              echo("Read ", future.read.len, ": ", future.read.repr)
  elif test == LowServer:
    var sock = newAsyncSocket()
    sock.bindAddr(Port(6667))
    sock.listen()
    proc onAccept(future: Future[AsyncSocket]) =
      let client = future.read
      echo "Accepted ", client.fd.cint
      var t = send(client, "test\c\L")
      t.callback =
        proc (future: Future[void]) =
          echo("Send")
          client.close()

      var f = accept(sock)
      f.callback = onAccept

    var f = accept(sock)
    f.callback = onAccept
  runForever()
