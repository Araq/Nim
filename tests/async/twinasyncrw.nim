when defined(windows):
  import asyncdispatch, nativesockets, net, strutils, os, winlean
  from stdtest/netutils import bindAvailablePort
  var msgCount = 0

  const
    swarmSize = 50
    messagesToSend = 100

  var clientCount = 0

  proc winConnect*(socket: AsyncFD, address: string, port: Port,
      domain = Domain.AF_INET): Future[void] =
    var retFuture = newFuture[void]("winConnect")
    proc cb(fd: AsyncFD): bool =
      var ret = SocketHandle(fd).getSockOptInt(cint(SOL_SOCKET), cint(SO_ERROR))
      if ret == 0:
          # We have connected.
          retFuture.complete()
          return true
      else:
          retFuture.fail(newOSError(OSErrorCode(ret)))
          return true

    var aiList = getAddrInfo(address, port, domain)
    var success = false
    var lastError: OSErrorCode = OSErrorCode(0)
    var it = aiList
    while it != nil:
      var ret = nativesockets.connect(socket.SocketHandle, it.ai_addr, it.ai_addrlen.Socklen)
      if ret == 0:
        # Request to connect completed immediately.
        success = true
        retFuture.complete()
        break
      else:
        lastError = osLastError()
        if lastError.int32 == WSAEWOULDBLOCK:
          success = true
          addWrite(socket, cb)
          break
        else:
          success = false
      it = it.ai_next

    freeAddrInfo(aiList)
    if not success:
      retFuture.fail(newOSError(lastError))
    return retFuture

  proc winRecv*(socket: AsyncFD, size: int,
             flags = {SocketFlag.SafeDisconn}): Future[string] =
    var retFuture = newFuture[string]("recv")

    var readBuffer = newString(size)

    proc cb(sock: AsyncFD): bool =
      result = true
      let res = recv(sock.SocketHandle, addr readBuffer[0], size.cint,
                     flags.toOSFlags())
      if res < 0:
        let lastError = osLastError()
        if flags.isDisconnectionError(lastError):
          retFuture.complete("")
        else:
          retFuture.fail(newOSError(lastError))
      elif res == 0:
        # Disconnected
        retFuture.complete("")
      else:
        readBuffer.setLen(res)
        retFuture.complete(readBuffer)
    # TODO: The following causes a massive slowdown.
    #if not cb(socket):
    addRead(socket, cb)
    return retFuture

  proc winRecvInto*(socket: AsyncFD, buf: cstring, size: int,
                  flags = {SocketFlag.SafeDisconn}): Future[int] =
    var retFuture = newFuture[int]("winRecvInto")

    proc cb(sock: AsyncFD): bool =
      result = true
      let res = nativesockets.recv(sock.SocketHandle, buf, size.cint,
                                   flags.toOSFlags())
      if res < 0:
        let lastError = osLastError()
        if flags.isDisconnectionError(lastError):
          retFuture.complete(0)
        else:
          retFuture.fail(newOSError(lastError))
      else:
        retFuture.complete(res)
    # TODO: The following causes a massive slowdown.
    #if not cb(socket):
    addRead(socket, cb)
    return retFuture

  proc winSend*(socket: AsyncFD, data: string,
             flags = {SocketFlag.SafeDisconn}): Future[void] =
    var retFuture = newFuture[void]("winSend")

    var written = 0

    proc cb(sock: AsyncFD): bool =
      result = true
      let netSize = data.len-written
      var d = data.cstring
      let res = nativesockets.send(sock.SocketHandle, addr d[written], netSize.cint, 0)
      if res < 0:
        let lastError = osLastError()
        if flags.isDisconnectionError(lastError):
          retFuture.complete()
        else:
          retFuture.fail(newOSError(lastError))
      else:
        written.inc(res)
        if res != netSize:
          result = false # We still have data to send.
        else:
          retFuture.complete()
    # TODO: The following causes crashes.
    #if not cb(socket):
    addWrite(socket, cb)
    return retFuture

  proc winAcceptAddr*(socket: AsyncFD, flags = {SocketFlag.SafeDisconn}):
      Future[tuple[address: string, client: AsyncFD]] =
    var retFuture = newFuture[tuple[address: string,
        client: AsyncFD]]("winAcceptAddr")
    proc cb(sock: AsyncFD): bool =
      result = true
      if not retFuture.finished:
        var sockAddress = Sockaddr()
        var addrLen = sizeof(sockAddress).Socklen
        var client = nativesockets.accept(sock.SocketHandle,
                                          cast[ptr SockAddr](addr(sockAddress)), addr(addrLen))
        if client == osInvalidSocket:
          retFuture.fail(newOSError(osLastError()))
        else:
          retFuture.complete((getAddrString(cast[ptr SockAddr](addr sockAddress)), client.AsyncFD))

    addRead(socket, cb)
    return retFuture

  proc winAccept*(socket: AsyncFD,
      flags = {SocketFlag.SafeDisconn}): Future[AsyncFD] =
    ## Accepts a new connection. Returns a future containing the client socket
    ## corresponding to that connection.
    ## The future will complete when the connection is successfully accepted.
    var retFut = newFuture[AsyncFD]("winAccept")
    var fut = winAcceptAddr(socket, flags)
    fut.callback =
      proc (future: Future[tuple[address: string, client: AsyncFD]]) =
        assert future.finished
        if future.failed:
          retFut.fail(future.error)
        else:
          retFut.complete(future.read.client)
    return retFut


  proc winRecvLine*(socket: AsyncFD): Future[string] {.async.} =
    ## Reads a line of data from ``socket``. Returned future will complete once
    ## a full line is read or an error occurs.
    ##
    ## If a full line is read ``\r\L`` is not
    ## added to ``line``, however if solely ``\r\L`` is read then ``line``
    ## will be set to it.
    ##
    ## If the socket is disconnected, ``line`` will be set to ``""``.
    ##
    ## If the socket is disconnected in the middle of a line (before ``\r\L``
    ## is read) then line will be set to ``""``.
    ## The partial line **will be lost**.
    ##
    ## **Warning**: This assumes that lines are delimited by ``\r\L``.
    ##
    ## **Note**: This procedure is mostly used for testing. You likely want to
    ## use ``asyncnet.recvLine`` instead.

    template addNLIfEmpty() =
      if result.len == 0:
        result.add("\c\L")

    result = ""
    var c = ""
    while true:
      c = await winRecv(socket, 1)
      if c.len == 0:
        return ""
      if c == "\r":
        c = await winRecv(socket, 1)
        assert c == "\l"
        addNLIfEmpty()
        return
      elif c == "\L":
        addNLIfEmpty()
        return
      add(result, c)

  proc sendMessages(client: AsyncFD) {.async.} =
    for i in 0 ..< messagesToSend:
      await winSend(client, "Message " & $i & "\c\L")

  proc launchSwarm(port: Port) {.async.} =
    for i in 0 ..< swarmSize:
      var sock = createNativeSocket()
      setBlocking(sock, false)

      await winConnect(AsyncFD(sock), "localhost", port)
      await sendMessages(AsyncFD(sock))
      discard closeSocket(sock)

  proc readMessages(client: AsyncFD) {.async.} =
    while true:
      var line = await winRecvLine(client)
      if line == "":
        closeSocket(client)
        clientCount.inc
        break
      else:
        if line.startsWith("Message "):
          msgCount.inc
        else:
          doAssert false

  proc createServer(server: SocketHandle) {.async.} =
    discard server.listen()
    while true:
      asyncCheck readMessages(await winAccept(AsyncFD(server)))

  var server = createNativeSocket()
  setBlocking(server, false)
  let port = bindAvailablePort(server)
  asyncCheck createServer(server)
  asyncCheck launchSwarm(port)
  while true:
    poll()
    if clientCount == swarmSize: break

  assert msgCount == swarmSize * messagesToSend
  doAssert msgCount == 5000
