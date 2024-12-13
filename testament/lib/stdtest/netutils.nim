import std/[nativesockets, asyncdispatch, os]

proc bindAvailablePort*(handle: SocketHandle, port = Port(0)): Port =
  ## See also `asynchttpserver.getPort`.
  block:
    var name: Sockaddr_in = default(Sockaddr_in)
    name.sin_family = typeof(name.sin_family)(toInt(AF_INET))
    name.sin_port = htons(uint16(port))
    name.sin_addr.s_addr = htonl(INADDR_ANY)
    if bindAddr(handle, cast[ptr SockAddr](addr(name)),
                sizeof(name).Socklen) < 0'i32:
      raiseOSError(osLastError(), $port)
  result = getLocalAddr(handle, AF_INET)[1]
