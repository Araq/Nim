#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements a low-level cross-platform sockets interface. Look
## at the `net` module for the higher-level version.

# TODO: Clean up the exports a bit and everything else in general.

import std/[os, options]
import std/private/since
import std/strbasics

when defined(nimPreviewSlimSystem):
  import std/[assertions, syncio]

when hostOS == "solaris":
  {.passl: "-lsocket -lnsl".}

const useWinVersion = defined(windows) or defined(nimdoc)
const useNimNetLite = defined(nimNetLite) or defined(freertos) or defined(zephyr) or
    defined(nuttx)

when useWinVersion:
  import std/winlean
  export WSAEWOULDBLOCK, WSAECONNRESET, WSAECONNABORTED, WSAENETRESET,
         WSANOTINITIALISED, WSAENOTSOCK, WSAEINPROGRESS, WSAEINTR,
         WSAEDISCON, ERROR_NETNAME_DELETED
else:
  import std/posix
  export fcntl, F_GETFL, O_NONBLOCK, F_SETFL, EAGAIN, EWOULDBLOCK, MSG_NOSIGNAL,
    EINTR, EINPROGRESS, ECONNRESET, EPIPE, ENETRESET, EBADF
  export Sockaddr_storage, Sockaddr_un, Sockaddr_un_path_length

export SocketHandle, Sockaddr_in, Addrinfo, INADDR_ANY, SockAddr, SockLen,
  Sockaddr_in6, Sockaddr_storage,
  recv, `==`, connect, send, accept, recvfrom, sendto,
  freeAddrInfo

when not useNimNetLite:
  export inet_ntoa

export
  SO_ERROR,
  SOL_SOCKET,
  SOMAXCONN,
  SO_ACCEPTCONN, SO_BROADCAST, SO_DEBUG, SO_DONTROUTE,
  SO_KEEPALIVE, SO_OOBINLINE, SO_REUSEADDR, SO_REUSEPORT,
  MSG_PEEK

when defined(macosx) and not defined(nimdoc):
  export SO_NOSIGPIPE

type
  Port* = distinct uint16 ## port type

  Domain* = enum ## \
    ## domain, which specifies the protocol family of the
    ## created socket. Other domains than those that are listed
    ## here are unsupported.
    AF_UNSPEC = 0, ## unspecified domain (can be detected automatically by
                   ## some procedures, such as getaddrinfo)
    AF_UNIX = 1,   ## for local socket (using a file). Unsupported on Windows.
    AF_INET = 2,   ## for network protocol IPv4 or
    AF_INET6 = when defined(macosx): 30 elif defined(windows): 23 else: 10 ## for network protocol IPv6.

  SockType* = enum     ## second argument to `socket` proc
    SOCK_STREAM = 1,   ## reliable stream-oriented service or Stream Sockets
    SOCK_DGRAM = 2,    ## datagram service or Datagram Sockets
    SOCK_RAW = 3,      ## raw protocols atop the network layer.
    SOCK_SEQPACKET = 5 ## reliable sequenced packet service

  Protocol* = enum    ## third argument to `socket` proc
    IPPROTO_TCP = 6,  ## Transmission control protocol.
    IPPROTO_UDP = 17, ## User datagram protocol.
    IPPROTO_IP,       ## Internet protocol.
    IPPROTO_IPV6,     ## Internet Protocol Version 6.
    IPPROTO_RAW,      ## Raw IP Packets Protocol. Unsupported on Windows.
    IPPROTO_ICMP      ## Internet Control message protocol.
    IPPROTO_ICMPV6    ## Internet Control message protocol for IPv6.

  Servent* = object ## information about a service
    name*: string
    aliases*: seq[string]
    port*: Port
    proto*: string

  Hostent* = object ## information about a given host
    name*: string
    aliases*: seq[string]
    addrtype*: Domain
    length*: int
    addrList*: seq[string]

const IPPROTO_NONE* = IPPROTO_IP ## Use this if your socket type requires a protocol value of zero (e.g. Unix sockets).

when useWinVersion:
  let
    osInvalidSocket* = winlean.INVALID_SOCKET

  const
    IOCPARM_MASK* = 127
    IOC_IN* = int(-2147483648)
    FIONBIO* = IOC_IN.int32 or ((sizeof(int32) and IOCPARM_MASK) shl 16) or
               (102 shl 8) or 126
    nativeAfInet = winlean.AF_INET
    nativeAfInet6 = winlean.AF_INET6

  proc ioctlsocket*(s: SocketHandle, cmd: clong,
                   argptr: ptr clong): cint {.
                   stdcall, importc: "ioctlsocket", dynlib: "ws2_32.dll".}
else:
  let
    osInvalidSocket* = posix.INVALID_SOCKET
    nativeAfInet = posix.AF_INET
    nativeAfInet6 = posix.AF_INET6
    nativeAfUnix = posix.AF_UNIX

proc `==`*(a, b: Port): bool {.borrow.}
  ## `==` for ports.

proc `$`*(p: Port): string {.borrow.}
  ## Returns the port number as a string

proc toInt*(domain: Domain): cint
  ## Converts the Domain enum to a platform-dependent `cint`.

proc toInt*(typ: SockType): cint
  ## Converts the SockType enum to a platform-dependent `cint`.

proc toInt*(p: Protocol): cint
  ## Converts the Protocol enum to a platform-dependent `cint`.

when not useWinVersion:
  proc toInt(domain: Domain): cint =
    case domain
    of AF_UNSPEC: result = posix.AF_UNSPEC.cint
    of AF_UNIX: result = posix.AF_UNIX.cint
    of AF_INET: result = posix.AF_INET.cint
    of AF_INET6: result = posix.AF_INET6.cint

  proc toKnownDomain*(family: cint): Option[Domain] =
    ## Converts the platform-dependent `cint` to the Domain or none(),
    ## if the `cint` is not known.
    result = if family == posix.AF_UNSPEC: some(Domain.AF_UNSPEC)
             elif family == posix.AF_UNIX: some(Domain.AF_UNIX)
             elif family == posix.AF_INET: some(Domain.AF_INET)
             elif family == posix.AF_INET6: some(Domain.AF_INET6)
             else: none(Domain)

  proc toInt(typ: SockType): cint =
    case typ
    of SOCK_STREAM: result = posix.SOCK_STREAM
    of SOCK_DGRAM: result = posix.SOCK_DGRAM
    of SOCK_SEQPACKET: result = posix.SOCK_SEQPACKET
    of SOCK_RAW: result = posix.SOCK_RAW

  proc toInt(p: Protocol): cint =
    case p
    of IPPROTO_TCP: result = posix.IPPROTO_TCP
    of IPPROTO_UDP: result = posix.IPPROTO_UDP
    of IPPROTO_IP: result = posix.IPPROTO_IP
    of IPPROTO_IPV6: result = posix.IPPROTO_IPV6
    of IPPROTO_RAW: result = posix.IPPROTO_RAW
    of IPPROTO_ICMP: result = posix.IPPROTO_ICMP
    of IPPROTO_ICMPV6: result = posix.IPPROTO_ICMPV6

else:
  proc toInt(domain: Domain): cint =
    result = cast[cint](uint32(ord(domain)))

  proc toKnownDomain*(family: cint): Option[Domain] =
    ## Converts the platform-dependent `cint` to the Domain or none(),
    ## if the `cint` is not known.
    result = if family == winlean.AF_UNSPEC: some(Domain.AF_UNSPEC)
             elif family == winlean.AF_INET: some(Domain.AF_INET)
             elif family == winlean.AF_INET6: some(Domain.AF_INET6)
             else: none(Domain)

  proc toInt(typ: SockType): cint =
    result = cint(ord(typ))

  proc toInt(p: Protocol): cint =
    case p
    of IPPROTO_IP:
      result = 0.cint
    of IPPROTO_ICMP:
      result = 1.cint
    of IPPROTO_TCP:
      result = 6.cint
    of IPPROTO_UDP:
      result = 17.cint
    of IPPROTO_IPV6:
      result = 41.cint
    of IPPROTO_ICMPV6:
      result = 58.cint
    else:
      result = cint(ord(p))

proc toSockType*(protocol: Protocol): SockType =
  result = case protocol
  of IPPROTO_TCP:
    SOCK_STREAM
  of IPPROTO_UDP:
    SOCK_DGRAM
  of IPPROTO_IP, IPPROTO_IPV6, IPPROTO_RAW, IPPROTO_ICMP, IPPROTO_ICMPV6:
    SOCK_RAW

proc getProtoByName*(name: string): int {.since: (1, 3, 5).} =
  ## Returns a protocol code from the database that matches the protocol `name`.
  when useWinVersion:
    let protoent = winlean.getprotobyname(name.cstring)
  else:
    let protoent = posix.getprotobyname(name.cstring)

  if protoent == nil:
    raise newException(OSError, "protocol not found: " & name)

  result = protoent.p_proto.int

proc close*(socket: SocketHandle) =
  ## Closes a socket.
  when useWinVersion:
    discard winlean.closesocket(socket)
  else:
    discard posix.close(socket)
  # TODO: These values should not be discarded. An OSError should be raised.
  # https://stackoverflow.com/questions/12463473/what-happens-if-you-call-close-on-a-bsd-socket-multiple-times

when declared(setInheritable) or defined(nimdoc):
  proc setInheritable*(s: SocketHandle, inheritable: bool): bool {.inline.} =
    ## Set whether a socket is inheritable by child processes. Returns `true`
    ## on success.
    ##
    ## This function is not implemented on all platform, test for availability
    ## with `declared() <system.html#declared,untyped>`.
    setInheritable(FileHandle s, inheritable)

proc createNativeSocket*(domain: cint, sockType: cint, protocol: cint,
                         inheritable: bool = defined(nimInheritHandles)): SocketHandle =
  ## Creates a new socket; returns `osInvalidSocket` if an error occurs.
  ##
  ## `inheritable` decides if the resulting SocketHandle can be inherited
  ## by child processes.
  ##
  ## Use this overload if one of the enums specified above does
  ## not contain what you need.
  let sockType =
    when (defined(linux) or defined(bsd)) and not defined(nimdoc):
      if inheritable: sockType and not SOCK_CLOEXEC else: sockType or SOCK_CLOEXEC
    else:
      sockType
  result = socket(domain, sockType, protocol)
  when declared(setInheritable) and not (defined(linux) or defined(bsd)):
    if not setInheritable(result, inheritable):
      close result
      return osInvalidSocket

proc createNativeSocket*(domain: Domain = AF_INET,
                         sockType: SockType = SOCK_STREAM,
                         protocol: Protocol = IPPROTO_TCP,
                         inheritable: bool = defined(nimInheritHandles)): SocketHandle =
  ## Creates a new socket; returns `osInvalidSocket` if an error occurs.
  ##
  ## `inheritable` decides if the resulting SocketHandle can be inherited
  ## by child processes.
  createNativeSocket(toInt(domain), toInt(sockType), toInt(protocol), inheritable)

proc bindAddr*(socket: SocketHandle, name: ptr SockAddr,
    namelen: SockLen): cint =
  result = bindSocket(socket, name, namelen)

proc listen*(socket: SocketHandle, backlog = SOMAXCONN): cint {.tags: [
    ReadIOEffect].} =
  ## Marks `socket` as accepting connections.
  ## `Backlog` specifies the maximum length of the
  ## queue of pending connections.
  when useWinVersion:
    result = winlean.listen(socket, cint(backlog))
  else:
    result = posix.listen(socket, cint(backlog))

proc getAddrInfo*(address: string, port: Port, domain: Domain = AF_INET,
                  sockType: SockType = SOCK_STREAM,
                  protocol: Protocol = IPPROTO_TCP): ptr AddrInfo =
  ##
  ##
  ## .. warning:: The resulting `ptr AddrInfo` must be freed using `freeAddrInfo`!
  var hints: AddrInfo = AddrInfo(
    ai_family: toInt(domain),
    ai_socktype: toInt(sockType),
    ai_protocol: toInt(protocol)
  )
  result = nil
  # OpenBSD doesn't support AI_V4MAPPED and doesn't define the macro AI_V4MAPPED.
  # FreeBSD, Haiku don't support AI_V4MAPPED but defines the macro.
  # https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=198092
  # https://dev.haiku-os.org/ticket/14323
  when not defined(freebsd) and not defined(openbsd) and not defined(netbsd) and
      not defined(android) and not defined(haiku):
    if domain == AF_INET6:
      hints.ai_flags = AI_V4MAPPED
  let socketPort = if sockType == SOCK_RAW: "" else: $port
  var gaiResult = getaddrinfo(address, socketPort.cstring, addr(hints), result)
  if gaiResult != 0'i32:
    when useWinVersion or defined(freertos) or defined(nuttx):
      raiseOSError(osLastError())
    else:
      raiseOSError(osLastError(), $gai_strerror(gaiResult))

proc ntohl*(x: uint32): uint32 =
  ## Converts 32-bit unsigned integers from network to host byte order.
  ## On machines where the host byte order is the same as network byte order,
  ## this is a no-op; otherwise, it performs a 4-byte swap operation.
  when cpuEndian == bigEndian: result = x
  else: result = (x shr 24'u32) or
                  (x shr 8'u32 and 0xff00'u32) or
                  (x shl 8'u32 and 0xff0000'u32) or
                  (x shl 24'u32)

proc ntohs*(x: uint16): uint16 =
  ## Converts 16-bit unsigned integers from network to host byte order. On
  ## machines where the host byte order is the same as network byte order,
  ## this is a no-op; otherwise, it performs a 2-byte swap operation.
  when cpuEndian == bigEndian: result = x
  else: result = (x shr 8'u16) or (x shl 8'u16)

template htonl*(x: uint32): untyped =
  ## Converts 32-bit unsigned integers from host to network byte order. On
  ## machines where the host byte order is the same as network byte order,
  ## this is a no-op; otherwise, it performs a 4-byte swap operation.
  nativesockets.ntohl(x)

template htons*(x: uint16): untyped =
  ## Converts 16-bit unsigned integers from host to network byte order.
  ## On machines where the host byte order is the same as network byte
  ## order, this is a no-op; otherwise, it performs a 2-byte swap operation.
  nativesockets.ntohs(x)

proc getSockDomain*(socket: SocketHandle): Domain =
  ## Returns the socket's domain (AF_INET or AF_INET6).
  var name: Sockaddr_in6 = default(Sockaddr_in6)
  var namelen = sizeof(name).SockLen
  if getsockname(socket, cast[ptr SockAddr](addr(name)),
                 addr(namelen)) == -1'i32:
    raiseOSError(osLastError())
  let knownDomain = toKnownDomain(name.sin6_family.cint)
  if knownDomain.isSome:
    result = knownDomain.get()
  else:
    raise newException(IOError, "Unknown socket family in getSockDomain")

when not useNimNetLite:
  proc getServByName*(name, proto: string): Servent {.tags: [ReadIOEffect].} =
    ## Searches the database from the beginning and finds the first entry for
    ## which the service name specified by `name` matches the s_name member
    ## and the protocol name specified by `proto` matches the s_proto member.
    ##
    ## On posix this will search through the `/etc/services` file.
    when useWinVersion:
      var s = winlean.getservbyname(name, proto)
    else:
      var s = posix.getservbyname(name, proto)
    if s == nil: raiseOSError(osLastError(), "Service not found.")
    result = Servent(
      name: $s.s_name,
      aliases: cstringArrayToSeq(s.s_aliases),
      port: Port(s.s_port),
      proto: $s.s_proto
    )

  proc getServByPort*(port: Port, proto: string): Servent {.tags: [ReadIOEffect].} =
    ## Searches the database from the beginning and finds the first entry for
    ## which the port specified by `port` matches the s_port member and the
    ## protocol name specified by `proto` matches the s_proto member.
    ##
    ## On posix this will search through the `/etc/services` file.
    when useWinVersion:
      var s = winlean.getservbyport(uint16(port).cint, proto)
    else:
      var s = posix.getservbyport(uint16(port).cint, proto)
    if s == nil: raiseOSError(osLastError(), "Service not found.")
    result = Servent(
      name: $s.s_name,
      aliases: cstringArrayToSeq(s.s_aliases),
      port: Port(s.s_port),
      proto: $s.s_proto
    )

  proc getHostByAddr*(ip: string): Hostent {.tags: [ReadIOEffect].} =
    ## This function will lookup the hostname of an IP Address.
    var
      addrInfo = getAddrInfo(ip, Port(0), AF_UNSPEC)
      myAddr: pointer
      addrLen = 0
      family = 0
    
    defer: freeAddrInfo(addrInfo)

    if addrInfo.ai_addr.sa_family.cint == nativeAfInet:
      family = nativeAfInet
      myAddr = addr cast[ptr Sockaddr_in](addrInfo.ai_addr).sin_addr
      addrLen = 4
    elif addrInfo.ai_addr.sa_family.cint == nativeAfInet6:
      family = nativeAfInet6
      myAddr = addr cast[ptr Sockaddr_in6](addrInfo.ai_addr).sin6_addr
      addrLen = 16
    else:
      raise newException(IOError, "Unknown socket family in `getHostByAddr()`")

    when useWinVersion:
      var s = winlean.gethostbyaddr(cast[ptr InAddr](myAddr), addrLen.cuint,
                                    cint(family))
      if s == nil: raiseOSError(osLastError())
    else:
      var s =
        when defined(android4):
          posix.gethostbyaddr(cast[cstring](myAddr), addrLen.cint,
                              cint(family))
        else:
          posix.gethostbyaddr(myAddr, addrLen.SockLen,
                              cint(family))
      if s == nil:
        raiseOSError(osLastError(), $hstrerror(h_errno))

    result = Hostent(
      name: $s.h_name,
      aliases: cstringArrayToSeq(s.h_aliases)
    )
    when useWinVersion:
      result.addrtype = Domain(s.h_addrtype)
    else:
      if s.h_addrtype == posix.AF_INET:
        result.addrtype = AF_INET
      elif s.h_addrtype == posix.AF_INET6:
        result.addrtype = AF_INET6
      else:
        raiseOSError(osLastError(), "unknown h_addrtype")
    if result.addrtype == AF_INET:
      result.addrList = @[]
      var i = 0
      while not isNil(s.h_addr_list[i]):
        var inaddrPtr = cast[ptr InAddr](s.h_addr_list[i])
        result.addrList.add($inet_ntoa(inaddrPtr[]))
        inc(i)
    else:
      let strAddrLen = when not useWinVersion: posix.INET6_ADDRSTRLEN.int
                       else: 46
      var i = 0
      while not isNil(s.h_addr_list[i]):
        var ipStr = newString(strAddrLen)
        if inet_ntop(nativeAfInet6, cast[pointer](s.h_addr_list[i]),
                     cstring(ipStr), len(ipStr).int32) == nil:
          raiseOSError(osLastError())
        when not useWinVersion:
          if posix.IN6_IS_ADDR_V4MAPPED(cast[ptr In6Addr](s.h_addr_list[i])) != 0:
            ipStr.setSlice("::ffff:".len..<strAddrLen)
        setLen(ipStr, len(cstring(ipStr)))
        result.addrList.add(ipStr)
        inc(i)
    result.length = int(s.h_length)

  proc getHostByName*(name: string): Hostent {.tags: [ReadIOEffect].} =
    ## This function will lookup the IP address of a hostname.
    when useWinVersion:
      var s = winlean.gethostbyname(name)
    else:
      var s = posix.gethostbyname(name)
    if s == nil: raiseOSError(osLastError())
    result = Hostent(
      name: $s.h_name,
      aliases: cstringArrayToSeq(s.h_aliases)
    )
    when useWinVersion:
      result.addrtype = Domain(s.h_addrtype)
    else:
      if s.h_addrtype == posix.AF_INET:
        result.addrtype = AF_INET
      elif s.h_addrtype == posix.AF_INET6:
        result.addrtype = AF_INET6
      else:
        raiseOSError(osLastError(), "unknown h_addrtype")
    if result.addrtype == AF_INET:
      result.addrList = @[]
      var i = 0
      while not isNil(s.h_addr_list[i]):
        var inaddrPtr = cast[ptr InAddr](s.h_addr_list[i])
        result.addrList.add($inet_ntoa(inaddrPtr[]))
        inc(i)
    else:
      result.addrList = cstringArrayToSeq(s.h_addr_list)
    result.length = int(s.h_length)

  proc getHostname*(): string {.tags: [ReadIOEffect].} =
    ## Returns the local hostname (not the FQDN)
    # https://tools.ietf.org/html/rfc1035#section-2.3.1
    # https://tools.ietf.org/html/rfc2181#section-11
    const size = 256
    result = newString(size)
    when useWinVersion:
      let success = winlean.gethostname(result.cstring, size)
    else:
      # Posix
      let success = posix.gethostname(result.cstring, size)
    if success != 0.cint:
      raiseOSError(osLastError())
    let x = len(cstring(result))
    result.setLen(x)

  proc getAddrString*(sockAddr: ptr SockAddr): string =
    ## Returns the string representation of address within sockAddr
    if sockAddr.sa_family.cint == nativeAfInet:
      result = $inet_ntoa(cast[ptr Sockaddr_in](sockAddr).sin_addr)
    elif sockAddr.sa_family.cint == nativeAfInet6:
      let addrLen = when not useWinVersion: posix.INET6_ADDRSTRLEN.int
                    else: 46 # it's actually 46 in both cases
      result = newString(addrLen)
      let addr6 = addr cast[ptr Sockaddr_in6](sockAddr).sin6_addr
      when not useWinVersion:
        if posix.inet_ntop(posix.AF_INET6, addr6, cast[cstring](addr result[0]),
                          result.len.int32) == nil:
          raiseOSError(osLastError())
        if posix.IN6_IS_ADDR_V4MAPPED(addr6) != 0:
          result.setSlice("::ffff:".len..<addrLen)
      else:
        if winlean.inet_ntop(winlean.AF_INET6, addr6, cast[cstring](addr result[0]),
                            result.len.int32) == nil:
          raiseOSError(osLastError())
      setLen(result, len(cstring(result)))
    else:
      when defined(posix) and not defined(nimdoc):
        if sockAddr.sa_family.cint == nativeAfUnix:
          return "unix"
      raise newException(IOError, "Unknown socket family in getAddrString")

  proc getAddrString*(sockAddr: ptr SockAddr, strAddress: var string) =
    ## Stores in `strAddress` the string representation of the address inside
    ## `sockAddr`
    ##
    ## **Note**
    ## * `strAddress` must be initialized to 46 in length.
    const length = 46
    assert(length == len(strAddress),
          "`strAddress` was not initialized correctly. 46 != `len(strAddress)`")
    if sockAddr.sa_family.cint == nativeAfInet:
      let addr4 = addr cast[ptr Sockaddr_in](sockAddr).sin_addr
      when not useWinVersion:
        if posix.inet_ntop(posix.AF_INET, addr4, cast[cstring](addr strAddress[0]),
                          strAddress.len.int32) == nil:
          raiseOSError(osLastError())
      else:
        if winlean.inet_ntop(winlean.AF_INET, addr4, cast[cstring](addr strAddress[0]),
                            strAddress.len.int32) == nil:
          raiseOSError(osLastError())
    elif sockAddr.sa_family.cint == nativeAfInet6:
      let addr6 = addr cast[ptr Sockaddr_in6](sockAddr).sin6_addr
      when not useWinVersion:
        if posix.inet_ntop(posix.AF_INET6, addr6, cast[cstring](addr strAddress[0]),
                          strAddress.len.int32) == nil:
          raiseOSError(osLastError())
        if posix.IN6_IS_ADDR_V4MAPPED(addr6) != 0:
          strAddress.setSlice("::ffff:".len..<length)
      else:
        if winlean.inet_ntop(winlean.AF_INET6, addr6, cast[cstring](addr strAddress[0]),
                            strAddress.len.int32) == nil:
          raiseOSError(osLastError())
    else:
      raise newException(IOError, "Unknown socket family in getAddrString")
    setLen(strAddress, len(cstring(strAddress)))

  when defined(posix) and not defined(nimdoc):
    proc makeUnixAddr*(path: string): Sockaddr_un =
      result = Sockaddr_un(sun_family: AF_UNIX.TSa_Family)
      if path.len >= Sockaddr_un_path_length:
        raise newException(ValueError, "socket path too long")
      copyMem(addr result.sun_path, path.cstring, path.len + 1)

  proc getSockName*(socket: SocketHandle): Port =
    ## Returns the socket's associated port number.
    var name: Sockaddr_in = default(Sockaddr_in)
    when useWinVersion:
      name.sin_family = uint16(ord(AF_INET))
    else:
      name.sin_family = TSa_Family(posix.AF_INET)
    #name.sin_port = htons(cint16(port))
    #name.sin_addr.s_addr = htonl(INADDR_ANY)
    var namelen = sizeof(name).SockLen
    if getsockname(socket, cast[ptr SockAddr](addr(name)),
                  addr(namelen)) == -1'i32:
      raiseOSError(osLastError())
    result = Port(nativesockets.ntohs(name.sin_port))

  proc getLocalAddr*(socket: SocketHandle, domain: Domain): (string, Port) =
    ## Returns the socket's local address and port number.
    ##
    ## Similar to POSIX's `getsockname`:idx:.
    result = default((string, Port))
    case domain
    of AF_INET:
      var name: Sockaddr_in = default(Sockaddr_in)
      when useWinVersion:
        name.sin_family = uint16(ord(AF_INET))
      else:
        name.sin_family = TSa_Family(posix.AF_INET)
      var namelen = sizeof(name).SockLen
      if getsockname(socket, cast[ptr SockAddr](addr(name)),
                    addr(namelen)) == -1'i32:
        raiseOSError(osLastError())
      result = ($inet_ntoa(name.sin_addr),
                Port(nativesockets.ntohs(name.sin_port)))
    of AF_INET6:
      var name: Sockaddr_in6 = default(Sockaddr_in6)
      when useWinVersion:
        name.sin6_family = uint16(ord(AF_INET6))
      else:
        name.sin6_family = TSa_Family(posix.AF_INET6)
      var namelen = sizeof(name).SockLen
      if getsockname(socket, cast[ptr SockAddr](addr(name)),
                    addr(namelen)) == -1'i32:
        raiseOSError(osLastError())
      # Cannot use INET6_ADDRSTRLEN here, because it's a C define.
      result[0] = newString(64)
      if inet_ntop(name.sin6_family.cint,
          addr name.sin6_addr, cast[cstring](addr result[0][0]), (result[0].len+1).int32).isNil:
        raiseOSError(osLastError())
      setLen(result[0], result[0].cstring.len)
      result[1] = Port(nativesockets.ntohs(name.sin6_port))
    else:
      raiseOSError(OSErrorCode(-1), "invalid socket family in getLocalAddr")

  proc getPeerAddr*(socket: SocketHandle, domain: Domain): (string, Port) =
    ## Returns the socket's peer address and port number.
    ##
    ## Similar to POSIX's `getpeername`:idx:
    result = default((string, Port))
    case domain
    of AF_INET:
      var name: Sockaddr_in = default(Sockaddr_in)
      when useWinVersion:
        name.sin_family = uint16(ord(AF_INET))
      else:
        name.sin_family = TSa_Family(posix.AF_INET)
      var namelen = sizeof(name).SockLen
      if getpeername(socket, cast[ptr SockAddr](addr(name)),
                    addr(namelen)) == -1'i32:
        raiseOSError(osLastError())
      result = ($inet_ntoa(name.sin_addr),
                Port(nativesockets.ntohs(name.sin_port)))
    of AF_INET6:
      var name: Sockaddr_in6 = default(Sockaddr_in6)
      when useWinVersion:
        name.sin6_family = uint16(ord(AF_INET6))
      else:
        name.sin6_family = TSa_Family(posix.AF_INET6)
      var namelen = sizeof(name).SockLen
      if getpeername(socket, cast[ptr SockAddr](addr(name)),
                    addr(namelen)) == -1'i32:
        raiseOSError(osLastError())
      # Cannot use INET6_ADDRSTRLEN here, because it's a C define.
      result[0] = newString(64)
      if inet_ntop(name.sin6_family.cint,
          addr name.sin6_addr, cast[cstring](addr result[0][0]), (result[0].len+1).int32).isNil:
        raiseOSError(osLastError())
      setLen(result[0], result[0].cstring.len)
      result[1] = Port(nativesockets.ntohs(name.sin6_port))
    else:
      raiseOSError(OSErrorCode(-1), "invalid socket family in getLocalAddr")

when useNimNetLite: 

  when useWinVersion:
    const
      INET_ADDRSTRLEN = 16
      INET6_ADDRSTRLEN = 46 # it's actually 46 in both cases

  proc sockAddrToStr(sa: ptr SockAddr): string {.noinit.} =
    let af_family = sa.sa_family
    var nl, v4Slice: cint
    var si_addr: ptr InAddr

    if af_family == AF_INET.TSa_Family:
      nl = INET_ADDRSTRLEN
      si_addr = cast[ptr Sockaddr_in](sa).sin_addr.addr()
    elif af_family == AF_INET6.TSa_Family:
      nl = INET6_ADDRSTRLEN
      let si6_addr = cast[ptr Sockaddr_in6](sa).sin6_addr.addr()
      si_addr = cast[ptr InAddr](si6_addr) # let's us reuse logic below 
      when defined(posix) and not defined(nimdoc) and not defined(zephyr):
        if posix.IN6_IS_ADDR_V4MAPPED(si6_addr) != 0:
          v4Slice = "::ffff:".len()
    else:
      when defined(posix) and not defined(nimdoc):
        if af_family.cint == nativeAfUnix:
          return "unix"
      return ""

    result = newString(nl)
    let namePtr = result.cstring()
    if namePtr == inet_ntop(af_family.cint, si_addr, namePtr, nl):
      result.setLen(len(namePtr))
      if v4Slice > 0: result.setSlice(v4Slice.int ..< nl.int)
    else:
      return ""

  proc sockAddrToStr(sa: var Sockaddr_in | var Sockaddr_in6): string =
    result = sockAddrToStr(cast[ptr SockAddr](unsafeAddr(sa)))

  proc getAddrString*(sockAddr: ptr SockAddr): string =
    result = sockAddrToStr(sockAddr)
    if result.len() == 0:
      raiseOSError(osLastError())

  proc getAddrString*(sockAddr: ptr SockAddr, strAddress: var string) {.noinit.} =
    strAddress = getAddrString(sockAddr)

  proc getLocalAddr*(socket: SocketHandle, domain: Domain): (string, Port) =
    ## Returns the socket's local address and port number.
    ##
    ## Similar to POSIX's `getsockname`:idx:.
    template sockGetNameOrRaiseError(socket: untyped, name: untyped) =
      var namelen = sizeof(socket).SockLen
      if getsockname(socket, cast[ptr SockAddr](addr(name)),
                    addr(namelen)) == -1'i32:
        raiseOSError(osLastError())

    case domain
    of AF_INET:
      var name = Sockaddr_in(sin_family: TSa_Family(posix.AF_INET))
      sockGetNameOrRaiseError(socket, name)
      result = (sockAddrToStr(name),
                Port(nativesockets.ntohs(name.sin_port)))
    of AF_INET6:
      var name = Sockaddr_in6(sin6_family: TSa_Family(posix.AF_INET6))
      sockGetNameOrRaiseError(socket, name)
      result = (sockAddrToStr(name),
                Port(nativesockets.ntohs(name.sin6_port)))
    else:
      raiseOSError(OSErrorCode(-1), "invalid socket family in getLocalAddr")


proc getSockOptInt*(socket: SocketHandle, level, optname: int): int {.
  tags: [ReadIOEffect].} =
  ## getsockopt for integer options.
  var res: cint = cint(0)
  var size = sizeof(res).SockLen
  if getsockopt(socket, cint(level), cint(optname),
                addr(res), addr(size)) < 0'i32:
    raiseOSError(osLastError())
  result = int(res)

proc setSockOptInt*(socket: SocketHandle, level, optname, optval: int) {.
  tags: [WriteIOEffect].} =
  ## setsockopt for integer options.
  var value = cint(optval)
  if setsockopt(socket, cint(level), cint(optname), addr(value),
                sizeof(value).SockLen) < 0'i32:
    raiseOSError(osLastError())

proc setBlocking*(s: SocketHandle, blocking: bool) =
  ## Sets blocking mode on socket.
  ##
  ## Raises OSError on error.
  when useWinVersion:
    var mode = clong(ord(not blocking)) # 1 for non-blocking, 0 for blocking
    if ioctlsocket(s, FIONBIO, addr(mode)) == -1:
      raiseOSError(osLastError())
  else: # BSD sockets
    var x: int = fcntl(s, F_GETFL, 0)
    if x == -1:
      raiseOSError(osLastError())
    else:
      var mode = if blocking: x and not O_NONBLOCK else: x or O_NONBLOCK
      if fcntl(s, F_SETFL, mode) == -1:
        raiseOSError(osLastError())

proc timeValFromMilliseconds(timeout = 500): Timeval =
  ## Converts a timeout in milliseconds to a Timeval.
  result = default(Timeval)
  if timeout != -1:
    var seconds = timeout div 1000
    when useWinVersion:
      result.tv_sec = seconds.int32
      result.tv_usec = ((timeout - seconds * 1000) * 1000).int32
    else:
      result.tv_sec = seconds.Time
      result.tv_usec = ((timeout - seconds * 1000) * 1000).Suseconds

proc createFdSet(fd: var TFdSet, s: seq[SocketHandle], m: var int) =
  FD_ZERO(fd)
  for i in items(s):
    m = max(m, int(i))
    FD_SET(i, fd)

proc pruneSocketSet(s: var seq[SocketHandle], fd: var TFdSet) =
  var i = 0
  var L = s.len
  while i < L:
    if FD_ISSET(s[i], fd) == 0'i32:
      s[i] = s[L-1]
      dec(L)
    else:
      inc(i)
  setLen(s, L)

proc selectRead*(readfds: var seq[SocketHandle], timeout = 500): int =
  ## When a socket in `readfds` is ready to be read from then a non-zero
  ## value will be returned specifying the count of the sockets which can be
  ## read from. The sockets which cannot be read from will also be removed
  ## from `readfds`.
  ##
  ## `timeout` is specified in milliseconds and `-1` can be specified for
  ## an unlimited time.
  var tv {.noinit.}: Timeval = timeValFromMilliseconds(timeout)

  var rd: TFdSet = default(TFdSet)
  var m = 0
  createFdSet((rd), readfds, m)

  if timeout != -1:
    result = int(select(cint(m+1), addr(rd), nil, nil, addr(tv)))
  else:
    result = int(select(cint(m+1), addr(rd), nil, nil, nil))

  pruneSocketSet(readfds, (rd))

proc selectWrite*(writefds: var seq[SocketHandle],
                  timeout = 500): int {.tags: [ReadIOEffect].} =
  ## When a socket in `writefds` is ready to be written to then a non-zero
  ## value will be returned specifying the count of the sockets which can be
  ## written to. The sockets which cannot be written to will also be removed
  ## from `writefds`.
  ##
  ## `timeout` is specified in milliseconds and `-1` can be specified for
  ## an unlimited time.
  var tv {.noinit.}: Timeval = timeValFromMilliseconds(timeout)

  var wr: TFdSet = default(TFdSet)
  var m = 0
  createFdSet((wr), writefds, m)

  if timeout != -1:
    result = int(select(cint(m+1), nil, addr(wr), nil, addr(tv)))
  else:
    result = int(select(cint(m+1), nil, addr(wr), nil, nil))

  pruneSocketSet(writefds, (wr))

proc accept*(fd: SocketHandle, inheritable = defined(nimInheritHandles)): (SocketHandle, string) =
  ## Accepts a new client connection.
  ##
  ## `inheritable` decides if the resulting SocketHandle can be inherited by
  ## child processes.
  ##
  ## Returns (osInvalidSocket, "") if an error occurred.
  var sockAddress: SockAddr = default(SockAddr)
  var addrLen = sizeof(sockAddress).SockLen
  var sock =
    when (defined(linux) or defined(bsd)) and not defined(nimdoc):
      accept4(fd, addr(sockAddress), addr(addrLen),
              if inheritable: 0 else: SOCK_CLOEXEC)
    else:
      accept(fd, addr(sockAddress), addr(addrLen))
  when declared(setInheritable) and not (defined(linux) or defined(bsd)):
    if not setInheritable(sock, inheritable):
      close sock
      sock = osInvalidSocket
  if sock == osInvalidSocket:
    return (osInvalidSocket, "")
  else:
    when useNimNetLite:
      var name = sockAddrToStr(addr sockAddress)
      return (sock, name)
    else:
      return (sock, $inet_ntoa(cast[Sockaddr_in](sockAddress).sin_addr))

when defined(windows):
  var wsa: WSAData
  if wsaStartup(0x0101'i16, addr wsa) != 0: raiseOSError(osLastError())
