import asyncdispatch, asyncnet, nativesockets, net, strutils, os

var msgCount = 0

const
  swarmSize = 40
  messagesToSend = 50

var clientCount = 0

proc sendMessages(client: AsyncFD) {.async.} =
  for i in 0 ..< messagesToSend:
    await send(client, "Message " & $i & "\c\L")

proc launchSwarm(port: Port) {.async.} =
  for i in 0 ..< swarmSize:
    var sock = createAsyncNativeSocket()

    await connect(sock, "localhost", port)
    await sendMessages(sock)
    closeSocket(sock)

proc readMessages(client: AsyncFD) {.async.} =
  # wrapping the AsyncFd into a AsyncSocket object
  var sockObj = newAsyncSocket(client)
  var (ipaddr, port) = sockObj.getPeerAddr()
  doAssert ipaddr == "127.0.0.1"
  (ipaddr, port) = sockObj.getLocalAddr()
  doAssert ipaddr == "127.0.0.1"
  while true:
    var line = await recvLine(sockObj)
    if line == "":
      closeSocket(client)
      clientCount.inc
      break
    else:
      if line.startswith("Message "):
        msgCount.inc
      else:
        doAssert false

proc bindAvailablePort(port: Port): (AsyncFD, Port) =
  var server = createAsyncNativeSocket()
  block:
    var name: Sockaddr_in
    name.sin_family = typeof(name.sin_family)(toInt(AF_INET))
    name.sin_port = htons(uint16(port))
    name.sin_addr.s_addr = htonl(INADDR_ANY)
    if bindAddr(server.SocketHandle, cast[ptr SockAddr](addr(name)),
                sizeof(name).Socklen) < 0'i32:
      raiseOSError(osLastError())
  let port = getLocalAddr(server.SocketHandle, AF_INET)[1]
  result = (server, port)

proc createServer(server: AsyncFD) {.async.} =
  discard server.SocketHandle.listen()
  while true:
    asyncCheck readMessages(await accept(server))

let (server, port) = bindAvailablePort(0.Port)
asyncCheck createServer(server)
asyncCheck launchSwarm(port)
while true:
  poll()
  if clientCount == swarmSize: break

assert msgCount == swarmSize * messagesToSend
doAssert msgCount == 2000
