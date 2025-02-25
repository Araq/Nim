#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements a high-level cross-platform sockets interface.
## The procedures implemented in this module are primarily for blocking sockets.
## For asynchronous non-blocking sockets use the `asyncnet` module together
## with the `asyncdispatch` module.
##
## The first thing you will always need to do in order to start using sockets,
## is to create a new instance of the `Socket` type using the `newSocket`
## procedure.
##
## SSL
## ====
##
## In order to use the SSL procedures defined in this module, you will need to
## compile your application with the `-d:ssl` flag. See the
## `newContext<net.html#newContext%2Cstring%2Cstring%2Cstring%2Cstring>`_
## procedure for additional details.
##
##
## SSL on Windows
## ==============
##
## On Windows the SSL library checks for valid certificates.
## It uses the `cacert.pem` file for this purpose which was extracted
## from `https://curl.se/ca/cacert.pem`. Besides
## the OpenSSL DLLs (e.g. libssl-1_1-x64.dll, libcrypto-1_1-x64.dll) you
## also need to ship `cacert.pem` with your `.exe` file.
##
##
## Examples
## ========
##
## Connecting to a server
## ----------------------
##
## After you create a socket with the `newSocket` procedure, you can easily
## connect it to a server running at a known hostname (or IP address) and port.
## To do so over TCP, use the example below.

runnableExamples("-r:off"):
  let socket = newSocket()
  socket.connect("google.com", Port(80))

## For SSL, use the following example:

runnableExamples("-r:off -d:ssl"):
  let socket = newSocket()
  let ctx = newContext()
  wrapSocket(ctx, socket)
  socket.connect("google.com", Port(443))

## UDP is a connectionless protocol, so UDP sockets don't have to explicitly
## call the `connect <net.html#connect%2CSocket%2Cstring>`_ procedure. They can
## simply start sending data immediately.

runnableExamples("-r:off"):
  let socket = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
  socket.sendTo("192.168.0.1", Port(27960), "status\n")

runnableExamples("-r:off"):
  let socket = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
  let ip = parseIpAddress("192.168.0.1")
  doAssert socket.sendTo(ip, Port(27960), "status\c\l") == 8

## Creating a server
## -----------------
##
## After you create a socket with the `newSocket` procedure, you can create a
## TCP server by calling the `bindAddr` and `listen` procedures.

runnableExamples("-r:off"):
  let socket = newSocket()
  socket.bindAddr(Port(1234))
  socket.listen()

  # You can then begin accepting connections using the `accept` procedure.
  var client: Socket
  var address = ""
  while true:
    socket.acceptAddr(client, address)
    echo "Client connected from: ", address

import std/private/since

when defined(nimPreviewSlimSystem):
  import std/assertions

import std/nativesockets
import std/[os, strutils, times, sets, options, monotimes]
import std/ssl_config
export nativesockets.Port, nativesockets.`$`, nativesockets.`==`
export Domain, SockType, Protocol, IPPROTO_NONE

const useWinVersion = defined(windows) or defined(nimdoc)
const useNimNetLite = defined(nimNetLite) or defined(freertos) or defined(zephyr) or
    defined(nuttx)
const defineSsl = defined(ssl) or defined(nimdoc)

when useWinVersion:
  from std/winlean import WSAESHUTDOWN

when defineSsl:
  import std/openssl
  when not defined(nimDisableCertificateValidation):
    from std/ssl_certs import scanSSLCertificates

# Note: The enumerations are mapped to Window's constants.

when defineSsl:
  type
    Certificate* = string ## DER encoded certificate

    SslError* = object of CatchableError

    SslCVerifyMode* = enum
      CVerifyNone, CVerifyPeer, CVerifyPeerUseEnvVars

    SslProtVersion* = enum
      protSSLv2, protSSLv3, protTLSv1, protSSLv23

    SslContext* = ref object
      context*: SslCtx
      referencedData: HashSet[int]
      extraInternal: SslContextExtraInternal

    SslAcceptResult* = enum
      AcceptNoClient = 0, AcceptNoHandshake, AcceptSuccess

    SslHandshakeType* = enum
      handshakeAsClient, handshakeAsServer

    SslClientGetPskFunc* = proc(hint: string): tuple[identity: string, psk: string]

    SslServerGetPskFunc* = proc(identity: string): string

    SslContextExtraInternal = ref object of RootRef
      serverGetPskFunc: SslServerGetPskFunc
      clientGetPskFunc: SslClientGetPskFunc

else:
  type
    SslContext* = ref object # TODO: Workaround #4797.

const
  BufferSize*: int = 4000 ## size of a buffered socket's buffer
  MaxLineLength* = 1_000_000

type
  SocketImpl* = object     ## socket type
    fd: SocketHandle
    isBuffered: bool       # determines whether this socket is buffered.
    buffer: array[0..BufferSize, char]
    currPos: int           # current index in buffer
    bufLen: int            # current length of buffer
    when defineSsl:
      isSsl: bool
      sslHandle: SslPtr
      sslContext: SslContext
      sslNoHandshake: bool # True if needs handshake.
      sslHasPeekChar: bool
      sslPeekChar: char
      sslNoShutdown: bool # True if shutdown shouldn't be done.
    lastError: OSErrorCode ## stores the last error on this socket
    domain: Domain
    sockType: SockType
    protocol: Protocol

  Socket* = ref SocketImpl

  SOBool* = enum ## Boolean socket options.
    OptAcceptConn, OptBroadcast, OptDebug, OptDontRoute, OptKeepAlive,
    OptOOBInline, OptReuseAddr, OptReusePort, OptNoDelay

  ReadLineResult* = enum ## result for readLineAsync
    ReadFullLine, ReadPartialLine, ReadDisconnected, ReadNone

  TimeoutError* = object of CatchableError

  SocketFlag* {.pure.} = enum
    Peek,
    SafeDisconn ## Ensures disconnection exceptions (ECONNRESET, EPIPE etc) are not thrown.

when defined(nimHasStyleChecks):
  {.push styleChecks: off.}

type
  IpAddressFamily* {.pure.} = enum ## Describes the type of an IP address
    IPv6,                          ## IPv6 address
    IPv4                           ## IPv4 address

  IpAddress* = object                  ## stores an arbitrary IP address
    case family*: IpAddressFamily      ## the type of the IP address (IPv4 or IPv6)
    of IpAddressFamily.IPv6:
      address_v6*: array[0..15, uint8] ## Contains the IP address in bytes in
                                       ## case of IPv6
    of IpAddressFamily.IPv4:
      address_v4*: array[0..3, uint8]  ## Contains the IP address in bytes in
                                       ## case of IPv4
when defined(nimHasStyleChecks):
  {.pop.}


when defined(posix) and not defined(lwip):
  from std/posix import TPollfd, POLLIN, POLLPRI, POLLOUT, POLLWRBAND, Tnfds

  template monitorPollEvent(x: var SocketHandle, y, timeout: cint): int =
    var tpollfd: TPollfd = default(TPollfd)
    tpollfd.fd = cast[cint](x)
    tpollfd.events = y
    posix.poll(addr(tpollfd), Tnfds(1), timeout)

proc timeoutRead(fd: var SocketHandle, timeout = 500): int =
  when defined(windows) or defined(lwip):
    var fds = @[fd]
    selectRead(fds, timeout)
  else:
    monitorPollEvent(fd, POLLIN or POLLPRI, cint(timeout))

proc timeoutWrite(fd: var SocketHandle, timeout = 500): int =
  when defined(windows) or defined(lwip):
    var fds = @[fd]
    selectWrite(fds, timeout)
  else:
    monitorPollEvent(fd, POLLOUT or POLLWRBAND, cint(timeout))

proc socketError*(socket: Socket, err: int = -1, async = false,
                  lastError = (-1).OSErrorCode,
                  flags: set[SocketFlag] = {}) {.gcsafe.}

proc isDisconnectionError*(flags: set[SocketFlag],
    lastError: OSErrorCode): bool =
  ## Determines whether `lastError` is a disconnection error. Only does this
  ## if flags contains `SafeDisconn`.
  when useWinVersion:
    SocketFlag.SafeDisconn in flags and
      (lastError.int32 == WSAECONNRESET or
       lastError.int32 == WSAECONNABORTED or
       lastError.int32 == WSAENETRESET or
       lastError.int32 == WSAEDISCON or
       lastError.int32 == WSAESHUTDOWN or
       lastError.int32 == ERROR_NETNAME_DELETED)
  else:
    SocketFlag.SafeDisconn in flags and
      (lastError.int32 == ECONNRESET or
       lastError.int32 == EPIPE or
       lastError.int32 == ENETRESET)

proc toOSFlags*(socketFlags: set[SocketFlag]): cint =
  ## Converts the flags into the underlying OS representation.
  result = cint(0)
  for f in socketFlags:
    case f
    of SocketFlag.Peek:
      result = result or MSG_PEEK
    of SocketFlag.SafeDisconn: continue

proc newSocket*(fd: SocketHandle, domain: Domain = AF_INET,
    sockType: SockType = SOCK_STREAM,
    protocol: Protocol = IPPROTO_TCP, buffered = true): owned(Socket) =
  ## Creates a new socket as specified by the params.
  assert fd != osInvalidSocket
  result = Socket(
    fd: fd,
    isBuffered: buffered,
    domain: domain,
    sockType: sockType,
    protocol: protocol)
  if buffered:
    result.currPos = 0

  # Set SO_NOSIGPIPE on OS X.
  when defined(macosx) and not defined(nimdoc):
    setSockOptInt(fd, SOL_SOCKET, SO_NOSIGPIPE, 1)

proc newSocket*(domain, sockType, protocol: cint, buffered = true,
                inheritable = defined(nimInheritHandles)): owned(Socket) =
  ## Creates a new socket.
  ##
  ## The SocketHandle associated with the resulting Socket will not be
  ## inheritable by child processes by default. This can be changed via
  ## the `inheritable` parameter.
  ##
  ## If an error occurs OSError will be raised.
  let fd = createNativeSocket(domain, sockType, protocol, inheritable)
  if fd == osInvalidSocket:
    raiseOSError(osLastError())
  result = newSocket(fd, domain.Domain, sockType.SockType, protocol.Protocol,
                     buffered)

proc newSocket*(domain: Domain = AF_INET, sockType: SockType = SOCK_STREAM,
                protocol: Protocol = IPPROTO_TCP, buffered = true,
                inheritable = defined(nimInheritHandles)): owned(Socket) =
  ## Creates a new socket.
  ##
  ## The SocketHandle associated with the resulting Socket will not be
  ## inheritable by child processes by default. This can be changed via
  ## the `inheritable` parameter.
  ##
  ## If an error occurs OSError will be raised.
  let fd = createNativeSocket(domain, sockType, protocol, inheritable)
  if fd == osInvalidSocket:
    raiseOSError(osLastError())
  result = newSocket(fd, domain, sockType, protocol, buffered)

proc parseIPv4Address(addressStr: string): IpAddress =
  ## Parses IPv4 addresses
  ## Raises ValueError on errors
  var
    byteCount = 0
    currentByte: uint16 = 0
    separatorValid = false
    leadingZero = false

  result = IpAddress(family: IpAddressFamily.IPv4)

  for i in 0 .. high(addressStr):
    if addressStr[i] in strutils.Digits: # Character is a number
      if leadingZero:
        raise newException(ValueError,
          "Invalid IP address. Octal numbers are not allowed")
      currentByte = currentByte * 10 +
        cast[uint16](ord(addressStr[i]) - ord('0'))
      if currentByte == 0'u16:
        leadingZero = true
      elif currentByte > 255'u16:
        raise newException(ValueError,
          "Invalid IP Address. Value is out of range")
      separatorValid = true
    elif addressStr[i] == '.': # IPv4 address separator
      if not separatorValid or byteCount >= 3:
        raise newException(ValueError,
          "Invalid IP Address. The address consists of too many groups")
      result.address_v4[byteCount] = cast[uint8](currentByte)
      currentByte = 0
      byteCount.inc
      separatorValid = false
      leadingZero = false
    else:
      raise newException(ValueError,
        "Invalid IP Address. Address contains an invalid character")

  if byteCount != 3 or not separatorValid:
    raise newException(ValueError, "Invalid IP Address")
  result.address_v4[byteCount] = cast[uint8](currentByte)

proc parseIPv6Address(addressStr: string): IpAddress =
  ## Parses IPv6 addresses
  ## Raises ValueError on errors
  result = IpAddress(family: IpAddressFamily.IPv6)
  if addressStr.len < 2:
    raise newException(ValueError, "Invalid IP Address")

  var
    groupCount = 0
    currentGroupStart = 0
    currentShort: uint32 = 0
    separatorValid = true
    dualColonGroup = -1
    lastWasColon = false
    v4StartPos = -1
    byteCount = 0

  for i, c in addressStr:
    if c == ':':
      if not separatorValid:
        raise newException(ValueError,
          "Invalid IP Address. Address contains an invalid separator")
      if lastWasColon:
        if dualColonGroup != -1:
          raise newException(ValueError,
            "Invalid IP Address. Address contains more than one \"::\" separator")
        dualColonGroup = groupCount
        separatorValid = false
      elif i != 0 and i != high(addressStr):
        if groupCount >= 8:
          raise newException(ValueError,
            "Invalid IP Address. The address consists of too many groups")
        result.address_v6[groupCount*2] = cast[uint8](currentShort shr 8)
        result.address_v6[groupCount*2+1] = cast[uint8](currentShort and 0xFF)
        currentShort = 0
        groupCount.inc()
        if dualColonGroup != -1: separatorValid = false
      elif i == 0: # only valid if address starts with ::
        if addressStr[1] != ':':
          raise newException(ValueError,
            "Invalid IP Address. Address may not start with \":\"")
      else: # i == high(addressStr) - only valid if address ends with ::
        if addressStr[high(addressStr)-1] != ':':
          raise newException(ValueError,
            "Invalid IP Address. Address may not end with \":\"")
      lastWasColon = true
      currentGroupStart = i + 1
    elif c == '.': # Switch to parse IPv4 mode
      if i < 3 or not separatorValid or groupCount >= 7:
        raise newException(ValueError, "Invalid IP Address")
      v4StartPos = currentGroupStart
      currentShort = 0
      separatorValid = false
      break
    elif c in strutils.HexDigits:
      if c in strutils.Digits: # Normal digit
        currentShort = (currentShort shl 4) + cast[uint32](ord(c) - ord('0'))
      elif c >= 'a' and c <= 'f': # Lower case hex
        currentShort = (currentShort shl 4) + cast[uint32](ord(c) - ord('a')) + 10
      else: # Upper case hex
        currentShort = (currentShort shl 4) + cast[uint32](ord(c) - ord('A')) + 10
      if currentShort > 65535'u32:
        raise newException(ValueError,
          "Invalid IP Address. Value is out of range")
      lastWasColon = false
      separatorValid = true
    else:
      raise newException(ValueError,
        "Invalid IP Address. Address contains an invalid character")


  if v4StartPos == -1: # Don't parse v4. Copy the remaining v6 stuff
    if separatorValid: # Copy remaining data
      if groupCount >= 8:
        raise newException(ValueError,
          "Invalid IP Address. The address consists of too many groups")
      result.address_v6[groupCount*2] = cast[uint8](currentShort shr 8)
      result.address_v6[groupCount*2+1] = cast[uint8](currentShort and 0xFF)
      groupCount.inc()
  else: # Must parse IPv4 address
    var leadingZero = false
    for i, c in addressStr[v4StartPos..high(addressStr)]:
      if c in strutils.Digits: # Character is a number
        if leadingZero:
          raise newException(ValueError,
            "Invalid IP address. Octal numbers not allowed")
        currentShort = currentShort * 10 + cast[uint32](ord(c) - ord('0'))
        if currentShort == 0'u32:
          leadingZero = true
        elif currentShort > 255'u32:
          raise newException(ValueError,
            "Invalid IP Address. Value is out of range")
        separatorValid = true
      elif c == '.': # IPv4 address separator
        if not separatorValid or byteCount >= 3:
          raise newException(ValueError, "Invalid IP Address")
        result.address_v6[groupCount*2 + byteCount] = cast[uint8](currentShort)
        currentShort = 0
        byteCount.inc()
        separatorValid = false
        leadingZero = false
      else: # Invalid character
        raise newException(ValueError,
          "Invalid IP Address. Address contains an invalid character")

    if byteCount != 3 or not separatorValid:
      raise newException(ValueError, "Invalid IP Address")
    result.address_v6[groupCount*2 + byteCount] = cast[uint8](currentShort)
    groupCount += 2

  # Shift and fill zeros in case of ::
  if groupCount > 8:
    raise newException(ValueError,
      "Invalid IP Address. The address consists of too many groups")
  elif groupCount < 8: # must fill
    if dualColonGroup == -1:
      raise newException(ValueError,
        "Invalid IP Address. The address consists of too few groups")
    var toFill = 8 - groupCount # The number of groups to fill
    var toShift = groupCount - dualColonGroup # Nr of known groups after ::
    for i in 0..2*toShift-1: # shift
      result.address_v6[15-i] = result.address_v6[groupCount*2-i-1]
    for i in 0..2*toFill-1: # fill with 0s
      result.address_v6[dualColonGroup*2+i] = 0
  elif dualColonGroup != -1:
    raise newException(ValueError,
      "Invalid IP Address. The address consists of too many groups")

proc parseIpAddress*(addressStr: string): IpAddress =
  ## Parses an IP address
  ##
  ## Raises ValueError on error.
  ##
  ## For IPv4 addresses, only the strict form as
  ## defined in RFC 6943 is considered valid, see
  ## https://datatracker.ietf.org/doc/html/rfc6943#section-3.1.1.
  if addressStr.len == 0:
    raise newException(ValueError, "IP Address string is empty")
  if addressStr.contains(':'):
    return parseIPv6Address(addressStr)
  else:
    return parseIPv4Address(addressStr)

proc isIpAddress*(addressStr: string): bool {.tags: [].} =
  ## Checks if a string is an IP address
  ## Returns true if it is, false otherwise
  try:
    discard parseIpAddress(addressStr)
  except ValueError:
    return false
  return true

proc toSockAddr*(address: IpAddress, port: Port, sa: var Sockaddr_storage,
                 sl: var SockLen) =
  ## Converts `IpAddress` and `Port` to `SockAddr` and `SockLen`
  let port = htons(uint16(port))
  case address.family
  of IpAddressFamily.IPv4:
    sl = sizeof(Sockaddr_in).SockLen
    let s = cast[ptr Sockaddr_in](addr sa)
    s.sin_family = typeof(s.sin_family)(toInt(AF_INET))
    s.sin_port = port
    copyMem(addr s.sin_addr, unsafeAddr address.address_v4[0],
            sizeof(s.sin_addr))
  of IpAddressFamily.IPv6:
    sl = sizeof(Sockaddr_in6).SockLen
    let s = cast[ptr Sockaddr_in6](addr sa)
    s.sin6_family = typeof(s.sin6_family)(toInt(AF_INET6))
    s.sin6_port = port
    copyMem(addr s.sin6_addr, unsafeAddr address.address_v6[0],
            sizeof(s.sin6_addr))

proc fromSockAddrAux(sa: ptr Sockaddr_storage, sl: SockLen,
                     address: var IpAddress, port: var Port) =
  if sa.ss_family.cint == toInt(AF_INET) and sl == sizeof(Sockaddr_in).SockLen:
    address = IpAddress(family: IpAddressFamily.IPv4)
    let s = cast[ptr Sockaddr_in](sa)
    copyMem(addr address.address_v4[0], addr s.sin_addr,
            sizeof(address.address_v4))
    port = ntohs(s.sin_port).Port
  elif sa.ss_family.cint == toInt(AF_INET6) and
       sl == sizeof(Sockaddr_in6).SockLen:
    address = IpAddress(family: IpAddressFamily.IPv6)
    let s = cast[ptr Sockaddr_in6](sa)
    copyMem(addr address.address_v6[0], addr s.sin6_addr,
            sizeof(address.address_v6))
    port = ntohs(s.sin6_port).Port
  else:
    raise newException(ValueError, "Neither IPv4 nor IPv6")

proc fromSockAddr*(sa: Sockaddr_storage | SockAddr | Sockaddr_in | Sockaddr_in6,
    sl: SockLen, address: var IpAddress, port: var Port) {.inline.} =
  ## Converts `SockAddr` and `SockLen` to `IpAddress` and `Port`. Raises
  ## `ObjectConversionDefect` in case of invalid `sa` and `sl` arguments.
  fromSockAddrAux(cast[ptr Sockaddr_storage](unsafeAddr sa), sl, address, port)

when defineSsl:
  # OpenSSL >= 1.1.0 does not need explicit init.
  when not useOpenssl3:
    CRYPTO_malloc_init()
    doAssert SslLibraryInit() == 1
    SSL_load_error_strings()
    ERR_load_BIO_strings()
    OpenSSL_add_all_algorithms()

  proc sslHandle*(self: Socket): SslPtr =
    ## Retrieve the ssl pointer of `socket`.
    ## Useful for interfacing with `openssl`.
    self.sslHandle

  proc raiseSSLError*(s = "") {.raises: [SslError].}=
    ## Raises a new SSL error.
    if s != "":
      raise newException(SslError, s)
    let err = ERR_peek_last_error()
    if err == 0:
      raise newException(SslError, "No error reported.")
    var errStr = $ERR_error_string(err, nil)
    case err
    of 336032814, 336032784:
      errStr = "Please upgrade your OpenSSL library, it does not support the " &
               "necessary protocols. OpenSSL error is: " & errStr
    else:
      discard
    raise newException(SslError, errStr)

  proc getExtraData*(ctx: SslContext, index: int): RootRef =
    ## Retrieves arbitrary data stored inside SslContext.
    if index notin ctx.referencedData:
      raise newException(IndexDefect, "No data with that index.")
    let res = ctx.context.SSL_CTX_get_ex_data(index.cint)
    if cast[int](res) == 0:
      raiseSSLError()
    return cast[RootRef](res)

  proc setExtraData*(ctx: SslContext, index: int, data: RootRef) =
    ## Stores arbitrary data inside SslContext. The unique `index`
    ## should be retrieved using getSslContextExtraDataIndex.
    if index in ctx.referencedData:
      GC_unref(getExtraData(ctx, index))

    if ctx.context.SSL_CTX_set_ex_data(index.cint, cast[pointer](data)) == -1:
      raiseSSLError()

    if index notin ctx.referencedData:
      ctx.referencedData.incl(index)
    GC_ref(data)

  # https://simplestcodings.blogspot.co.uk/2010/08/secure-server-client-using-openssl-in-c.html
  proc loadCertificates(ctx: SslCtx, certFile, keyFile: string) =
    if certFile != "" and not fileExists(certFile):
      raise newException(system.IOError,
          "Certificate file could not be found: " & certFile)
    if keyFile != "" and not fileExists(keyFile):
      raise newException(system.IOError, "Key file could not be found: " & keyFile)

    if certFile != "":
      var ret = SSL_CTX_use_certificate_chain_file(ctx, certFile)
      if ret != 1:
        raiseSSLError()

    # TODO: Password? www.rtfm.com/openssl-examples/part1.pdf
    if keyFile != "":
      if SSL_CTX_use_PrivateKey_file(ctx, keyFile,
                                     SSL_FILETYPE_PEM) != 1:
        raiseSSLError()

      if SSL_CTX_check_private_key(ctx) != 1:
        raiseSSLError("Verification of private key file failed.")

  proc newContext*(protVersion = protSSLv23, verifyMode = CVerifyPeer,
                   certFile = "", keyFile = "", cipherList = CiphersIntermediate,
                   caDir = "", caFile = "", ciphersuites = CiphersModern): SslContext =
    ## Creates an SSL context.
    ##
    ## Protocol version is currently ignored by default and TLS is used.
    ## With `-d:openssl10`, only SSLv23 and TLSv1 may be used.
    ##
    ## There are three options for verify mode:
    ## `CVerifyNone`: certificates are not verified;
    ## `CVerifyPeer`: certificates are verified;
    ## `CVerifyPeerUseEnvVars`: certificates are verified and the optional
    ## environment variables SSL_CERT_FILE and SSL_CERT_DIR are also used to
    ## locate certificates
    ##
    ## The `nimDisableCertificateValidation` define overrides verifyMode and
    ## disables certificate verification globally!
    ##
    ## CA certificates will be loaded, in the following order, from:
    ##
    ## - caFile, caDir, parameters, if set
    ## - if `verifyMode` is set to `CVerifyPeerUseEnvVars`,
    ##   the SSL_CERT_FILE and SSL_CERT_DIR environment variables are used
    ## - a set of files and directories from the `ssl_certs <ssl_certs.html>`_ file.
    ##
    ## The last two parameters specify the certificate file path and the key file
    ## path, a server socket will most likely not work without these.
    ##
    ## Certificates can be generated using the following command:
    ## - `openssl req -x509 -nodes -days 365 -newkey rsa:4096 -keyout mykey.pem -out mycert.pem`
    ## or using ECDSA:
    ## - `openssl ecparam -out mykey.pem -name secp256k1 -genkey`
    ## - `openssl req -new -key mykey.pem -x509 -nodes -days 365 -out mycert.pem`
    var mtd: PSSL_METHOD
    when defined(openssl10):
      case protVersion
      of protSSLv23:
        mtd = SSLv23_method()
      of protSSLv2:
        raiseSSLError("SSLv2 is no longer secure and has been deprecated, use protSSLv23")
      of protSSLv3:
        raiseSSLError("SSLv3 is no longer secure and has been deprecated, use protSSLv23")
      of protTLSv1:
        mtd = TLSv1_method()
    else:
      mtd = TLS_method()
    if mtd == nil:
      raiseSSLError("Failed to create TLS context")
    var newCTX = SSL_CTX_new(mtd)
    if newCTX == nil:
      raiseSSLError("Failed to create TLS context")

    if newCTX.SSL_CTX_set_cipher_list(cipherList) != 1:
      raiseSSLError()
    when not defined(openssl10) and not defined(libressl):
      let sslVersion = getOpenSSLVersion()
      if sslVersion >= 0x010101000 and sslVersion != 0x020000000:
        # In OpenSSL >= 1.1.1, TLSv1.3 cipher suites can only be configured via
        # this API.
        if newCTX.SSL_CTX_set_ciphersuites(ciphersuites) != 1:
          raiseSSLError()
    # Automatically the best ECDH curve for client exchange. Without this, ECDH
    # ciphers will be ignored by the server.
    #
    # From OpenSSL >= 1.1.0, this setting is set by default and can't be
    # overridden.
    if newCTX.SSL_CTX_set_ecdh_auto(1) != 1:
      raiseSSLError()

    when defined(nimDisableCertificateValidation):
      newCTX.SSL_CTX_set_verify(SSL_VERIFY_NONE, nil)
    else:
      case verifyMode
      of CVerifyPeer, CVerifyPeerUseEnvVars:
        newCTX.SSL_CTX_set_verify(SSL_VERIFY_PEER, nil)
      of CVerifyNone:
        newCTX.SSL_CTX_set_verify(SSL_VERIFY_NONE, nil)

    if newCTX == nil:
      raiseSSLError()

    discard newCTX.SSLCTXSetMode(SSL_MODE_AUTO_RETRY)
    newCTX.loadCertificates(certFile, keyFile)

    const VerifySuccess = 1 # SSL_CTX_load_verify_locations returns 1 on success.

    when not defined(nimDisableCertificateValidation):
      if verifyMode != CVerifyNone:
        # Use the caDir and caFile parameters if set
        if caDir != "" or caFile != "":
          if newCTX.SSL_CTX_load_verify_locations(if caFile == "": nil else: caFile.cstring, if caDir == "": nil else: caDir.cstring) != VerifySuccess:
            raise newException(IOError, "Failed to load SSL/TLS CA certificate(s).")

        else:
          # Scan for certs in known locations. For CVerifyPeerUseEnvVars also scan
          # the SSL_CERT_FILE and SSL_CERT_DIR env vars
          var found = false
          let useEnvVars = (if verifyMode == CVerifyPeerUseEnvVars: true else: false)
          for fn in scanSSLCertificates(useEnvVars = useEnvVars):
            if fn.extractFilename == "":
              if newCTX.SSL_CTX_load_verify_locations(nil, cstring(fn.normalizePathEnd(false))) == VerifySuccess:
                found = true
                break
            elif newCTX.SSL_CTX_load_verify_locations(cstring(fn), nil) == VerifySuccess:
              found = true
              break
          if not found:
            raise newException(IOError, "No SSL/TLS CA certificates found.")

    result = SslContext(context: newCTX, referencedData: initHashSet[int](),
      extraInternal: new(SslContextExtraInternal))

  proc getExtraInternal(ctx: SslContext): SslContextExtraInternal =
    return ctx.extraInternal

  proc destroyContext*(ctx: SslContext) =
    ## Free memory referenced by SslContext.

    # We assume here that OpenSSL's internal indexes increase by 1 each time.
    # That means we can assume that the next internal index is the length of
    # extra data indexes.
    for i in ctx.referencedData:
      GC_unref(getExtraData(ctx, i))
    ctx.context.SSL_CTX_free()

  proc `pskIdentityHint=`*(ctx: SslContext, hint: string) =
    ## Sets the identity hint passed to server.
    ##
    ## Only used in PSK ciphersuites.
    if ctx.context.SSL_CTX_use_psk_identity_hint(hint) <= 0:
      raiseSSLError()

  proc clientGetPskFunc*(ctx: SslContext): SslClientGetPskFunc =
    return ctx.getExtraInternal().clientGetPskFunc

  proc pskClientCallback(ssl: SslPtr; hint: cstring; identity: cstring;
      max_identity_len: cuint; psk: ptr uint8;
      max_psk_len: cuint): cuint {.cdecl.} =
    let ctx = SslContext(context: ssl.SSL_get_SSL_CTX)
    let hintString = if hint == nil: "" else: $hint
    let (identityString, pskString) = (ctx.clientGetPskFunc)(hintString)
    if pskString.len.cuint > max_psk_len:
      return 0
    if identityString.len.cuint >= max_identity_len:
      return 0
    copyMem(identity, identityString.cstring, identityString.len + 1) # with the last zero byte
    copyMem(psk, pskString.cstring, pskString.len)

    return pskString.len.cuint

  proc `clientGetPskFunc=`*(ctx: SslContext, fun: SslClientGetPskFunc) =
    ## Sets function that returns the client identity and the PSK based on identity
    ## hint from the server.
    ##
    ## Only used in PSK ciphersuites.
    ctx.getExtraInternal().clientGetPskFunc = fun
    ctx.context.SSL_CTX_set_psk_client_callback(
        if fun == nil: nil else: pskClientCallback)

  proc serverGetPskFunc*(ctx: SslContext): SslServerGetPskFunc =
    return ctx.getExtraInternal().serverGetPskFunc

  proc pskServerCallback(ssl: SslCtx; identity: cstring; psk: ptr uint8;
      max_psk_len: cint): cuint {.cdecl.} =
    let ctx = SslContext(context: ssl.SSL_get_SSL_CTX)
    let pskString = (ctx.serverGetPskFunc)($identity)
    if pskString.len.cint > max_psk_len:
      return 0
    copyMem(psk, pskString.cstring, pskString.len)

    return pskString.len.cuint

  proc `serverGetPskFunc=`*(ctx: SslContext, fun: SslServerGetPskFunc) =
    ## Sets function that returns PSK based on the client identity.
    ##
    ## Only used in PSK ciphersuites.
    ctx.getExtraInternal().serverGetPskFunc = fun
    ctx.context.SSL_CTX_set_psk_server_callback(if fun == nil: nil
                                                else: pskServerCallback)

  proc getPskIdentity*(socket: Socket): string =
    ## Gets the PSK identity provided by the client.
    assert socket.isSsl
    return $(socket.sslHandle.SSL_get_psk_identity)

  proc wrapSocket*(ctx: SslContext, socket: Socket) =
    ## Wraps a socket in an SSL context. This function effectively turns
    ## `socket` into an SSL socket.
    ##
    ## This must be called on an unconnected socket; an SSL session will
    ## be started when the socket is connected.
    ##
    ## FIXME:
    ## **Disclaimer**: This code is not well tested, may be very unsafe and
    ## prone to security vulnerabilities.

    assert(not socket.isSsl)
    socket.isSsl = true
    socket.sslContext = ctx
    socket.sslHandle = SSL_new(socket.sslContext.context)
    socket.sslNoHandshake = false
    socket.sslHasPeekChar = false
    socket.sslNoShutdown = false
    if socket.sslHandle == nil:
      raiseSSLError()

    if SSL_set_fd(socket.sslHandle, socket.fd) != 1:
      raiseSSLError()

  proc checkCertName(socket: Socket, hostname: string) {.raises: [SslError], tags:[RootEffect].} =
    ## Check if the certificate Subject Alternative Name (SAN) or Subject CommonName (CN) matches hostname.
    ## Wildcards match only in the left-most label.
    ## When name starts with a dot it will be matched by a certificate valid for any subdomain
    when not defined(nimDisableCertificateValidation) and not defined(windows):
      assert socket.isSsl
      try:
        let certificate = socket.sslHandle.SSL_get_peer_certificate()
        if certificate.isNil:
          raiseSSLError("No SSL certificate found.")

        const X509_CHECK_FLAG_ALWAYS_CHECK_SUBJECT = 0x1.cuint
        # https://www.openssl.org/docs/man1.1.1/man3/X509_check_host.html
        let match = certificate.X509_check_host(hostname.cstring, hostname.len.cint,
          X509_CHECK_FLAG_ALWAYS_CHECK_SUBJECT, nil)
        # https://www.openssl.org/docs/man1.1.1/man3/SSL_get_peer_certificate.html
        X509_free(certificate)
        if match != 1:
          raiseSSLError("SSL Certificate check failed.")

      except LibraryError:
        raiseSSLError("SSL import failed")

  proc wrapConnectedSocket*(ctx: SslContext, socket: Socket,
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
    ## FIXME:
    ## **Disclaimer**: This code is not well tested, may be very unsafe and
    ## prone to security vulnerabilities.
    wrapSocket(ctx, socket)
    case handshake
    of handshakeAsClient:
      if hostname.len > 0 and not isIpAddress(hostname):
        # Discard result in case OpenSSL version doesn't support SNI, or we're
        # not using TLSv1+
        discard SSL_set_tlsext_host_name(socket.sslHandle, hostname)
      ErrClearError()
      let ret = SSL_connect(socket.sslHandle)
      socketError(socket, ret)
      when not defined(nimDisableCertificateValidation) and not defined(windows):
        # FIXME: this should be skipped on CVerifyNone
        if hostname.len > 0 and not isIpAddress(hostname):
          socket.checkCertName(hostname)
    of handshakeAsServer:
      ErrClearError()
      let ret = SSL_accept(socket.sslHandle)
      socketError(socket, ret)

  proc getPeerCertificates*(sslHandle: SslPtr): seq[Certificate] {.since: (1, 1).} =
    ## Returns the certificate chain received by the peer we are connected to
    ## through the OpenSSL connection represented by `sslHandle`.
    ## The handshake must have been completed and the certificate chain must
    ## have been verified successfully or else an empty sequence is returned.
    ## The chain is ordered from leaf certificate to root certificate.
    result = newSeq[Certificate]()
    if SSL_get_verify_result(sslHandle) != X509_V_OK:
      return
    let stack = SSL_get0_verified_chain(sslHandle)
    if stack == nil:
      return
    let length = OPENSSL_sk_num(stack)
    if length == 0:
      return
    for i in 0 .. length - 1:
      let x509 = cast[PX509](OPENSSL_sk_value(stack, i))
      result.add(i2d_X509(x509))

  proc getPeerCertificates*(socket: Socket): seq[Certificate] {.since: (1, 1).} =
    ## Returns the certificate chain received by the peer we are connected to
    ## through the given socket.
    ## The handshake must have been completed and the certificate chain must
    ## have been verified successfully or else an empty sequence is returned.
    ## The chain is ordered from leaf certificate to root certificate.
    if not socket.isSsl:
      result = newSeq[Certificate]()
    else:
      result = getPeerCertificates(socket.sslHandle)

  proc `sessionIdContext=`*(ctx: SslContext, sidCtx: string) =
    ## Sets the session id context in which a session can be reused.
    ## Used for permitting clients to reuse a session id instead of
    ## doing a new handshake.
    ##
    ## TLS clients might attempt to resume a session using the session id context,
    ## thus it must be set if verifyMode is set to CVerifyPeer or CVerifyPeerUseEnvVars,
    ## otherwise the connection will fail and SslError will be raised if resumption occurs.
    ##
    ## - Only useful if set server-side.
    ## - Should be unique per-application to prevent clients from malfunctioning.
    ## - sidCtx must be at most 32 characters in length.
    if sidCtx.len > 32:
      raiseSSLError("sessionIdContext must be shorter than 32 characters")
    SSL_CTX_set_session_id_context(ctx.context, sidCtx, sidCtx.len)

proc getSocketError*(socket: Socket): OSErrorCode =
  ## Checks `osLastError` for a valid error. If it has been reset it uses
  ## the last error stored in the socket object.
  result = osLastError()
  if result == 0.OSErrorCode:
    result = socket.lastError
  if result == 0.OSErrorCode:
    raiseOSError(result, "No valid socket error code available")

proc socketError*(socket: Socket, err: int = -1, async = false,
                  lastError = (-1).OSErrorCode,
                  flags: set[SocketFlag] = {}) =
  ## Raises an OSError based on the error code returned by `SSL_get_error`
  ## (for SSL sockets) and `osLastError` otherwise.
  ##
  ## If `async` is `true` no error will be thrown in the case when the
  ## error was caused by no data being available to be read.
  ##
  ## If `err` is not lower than 0 no exception will be raised.
  ##
  ## If `flags` contains `SafeDisconn`, no exception will be raised
  ## when the error was caused by a peer disconnection.
  when defineSsl:
    if socket.isSsl:
      if err <= 0:
        var ret = SSL_get_error(socket.sslHandle, err.cint)
        case ret
        of SSL_ERROR_ZERO_RETURN:
          raiseSSLError("TLS/SSL connection failed to initiate, socket closed prematurely.")
        of SSL_ERROR_WANT_CONNECT, SSL_ERROR_WANT_ACCEPT:
          if async:
            return
          else: raiseSSLError("Not enough data on socket.")
        of SSL_ERROR_WANT_WRITE, SSL_ERROR_WANT_READ:
          if async:
            return
          else: raiseSSLError("Not enough data on socket.")
        of SSL_ERROR_WANT_X509_LOOKUP:
          raiseSSLError("Function for x509 lookup has been called.")
        of SSL_ERROR_SYSCALL:
          # SSL shutdown must not be done if a fatal error occurred.
          socket.sslNoShutdown = true
          let osErr = osLastError()
          if not flags.isDisconnectionError(osErr):
            var errStr = "IO error has occurred "
            let sslErr = ERR_peek_last_error()
            if sslErr == 0 and err == 0:
              errStr.add "because an EOF was observed that violates the protocol"
            elif sslErr == 0 and err == -1:
              errStr.add "in the BIO layer"
            else:
              let errStr = $ERR_error_string(sslErr, nil)
              raiseSSLError(errStr & ": " & errStr)
            raiseOSError(osErr, errStr)
        of SSL_ERROR_SSL:
          # SSL shutdown must not be done if a fatal error occurred.
          socket.sslNoShutdown = true
          raiseSSLError()
        else: raiseSSLError("Unknown Error")

  if err == -1 and not (when defineSsl: socket.isSsl else: false):
    var lastE = if lastError.int == -1: getSocketError(socket) else: lastError
    if not flags.isDisconnectionError(lastE):
      if async:
        when useWinVersion:
          if lastE.int32 == WSAEWOULDBLOCK:
            return
          else: raiseOSError(lastE)
        else:
          if lastE.int32 == EAGAIN or lastE.int32 == EWOULDBLOCK:
            return
          else: raiseOSError(lastE)
      else: raiseOSError(lastE)

proc listen*(socket: Socket, backlog = SOMAXCONN) {.tags: [ReadIOEffect].} =
  ## Marks `socket` as accepting connections.
  ## `Backlog` specifies the maximum length of the
  ## queue of pending connections.
  ##
  ## Raises an OSError error upon failure.
  if nativesockets.listen(socket.fd, backlog) < 0'i32:
    raiseOSError(osLastError())

proc bindAddr*(socket: Socket, port = Port(0), address = "") {.
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
    var address2: string = ""
    address2.addQuoted address
    raiseOSError(osLastError(), "address: $# port: $#" % [address2, $port])
  freeAddrInfo(aiList)

proc acceptAddr*(server: Socket, client: var owned(Socket), address: var string,
                 flags = {SocketFlag.SafeDisconn},
                 inheritable = defined(nimInheritHandles)) {.
                 tags: [ReadIOEffect], gcsafe.} =
  ## Blocks until a connection is being made from a client. When a connection
  ## is made sets `client` to the client socket and `address` to the address
  ## of the connecting client.
  ## This function will raise OSError if an error occurs.
  ##
  ## The resulting client will inherit any properties of the server socket. For
  ## example: whether the socket is buffered or not.
  ##
  ## The SocketHandle associated with the resulting client will not be
  ## inheritable by child processes by default. This can be changed via
  ## the `inheritable` parameter.
  ##
  ## The `accept` call may result in an error if the connecting socket
  ## disconnects during the duration of the `accept`. If the `SafeDisconn`
  ## flag is specified then this error will not be raised and instead
  ## accept will be called again.
  if client.isNil:
    new(client)
  let ret = accept(server.fd, inheritable)
  let sock = ret[0]

  if sock == osInvalidSocket:
    let err = osLastError()
    if flags.isDisconnectionError(err):
      acceptAddr(server, client, address, flags, inheritable)
    raiseOSError(err)
  else:
    address = ret[1]
    client.fd = sock
    client.domain = getSockDomain(sock)
    client.isBuffered = server.isBuffered

    # Handle SSL.
    when defineSsl:
      if server.isSsl:
        # We must wrap the client sock in a ssl context.

        server.sslContext.wrapSocket(client)
        ErrClearError()
        let ret = SSL_accept(client.sslHandle)
        socketError(client, ret, false)

when false: #defineSsl:
  proc acceptAddrSSL*(server: Socket, client: var Socket,
                      address: var string): SSL_acceptResult {.
                      tags: [ReadIOEffect].} =
    ## This procedure should only be used for non-blocking **SSL** sockets.
    ## It will immediately return with one of the following values:
    ##
    ## `AcceptSuccess` will be returned when a client has been successfully
    ## accepted and the handshake has been successfully performed between
    ## `server` and the newly connected client.
    ##
    ## `AcceptNoHandshake` will be returned when a client has been accepted
    ## but no handshake could be performed. This can happen when the client
    ## connects but does not yet initiate a handshake. In this case
    ## `acceptAddrSSL` should be called again with the same parameters.
    ##
    ## `AcceptNoClient` will be returned when no client is currently attempting
    ## to connect.
    template doHandshake(): untyped =
      when defineSsl:
        if server.isSsl:
          client.setBlocking(false)
          # We must wrap the client sock in a ssl context.

          if not client.isSsl or client.sslHandle == nil:
            server.sslContext.wrapSocket(client)
          ErrClearError()
          let ret = SSL_accept(client.sslHandle)
          while ret <= 0:
            let err = SSL_get_error(client.sslHandle, ret)
            if err != SSL_ERROR_WANT_ACCEPT:
              case err
              of SSL_ERROR_ZERO_RETURN:
                raiseSSLError("TLS/SSL connection failed to initiate, socket closed prematurely.")
              of SSL_ERROR_WANT_READ, SSL_ERROR_WANT_WRITE,
                 SSL_ERROR_WANT_CONNECT, SSL_ERROR_WANT_ACCEPT:
                client.sslNoHandshake = true
                return AcceptNoHandshake
              of SSL_ERROR_WANT_X509_LOOKUP:
                raiseSSLError("Function for x509 lookup has been called.")
              of SSL_ERROR_SYSCALL, SSL_ERROR_SSL:
                raiseSSLError()
              else:
                raiseSSLError("Unknown error")
          client.sslNoHandshake = false

    if client.isSsl and client.sslNoHandshake:
      doHandshake()
      return AcceptSuccess
    else:
      acceptAddrPlain(AcceptNoClient, AcceptSuccess):
        doHandshake()

proc accept*(server: Socket, client: var owned(Socket),
             flags = {SocketFlag.SafeDisconn},
             inheritable = defined(nimInheritHandles))
            {.tags: [ReadIOEffect].} =
  ## Equivalent to `acceptAddr` but doesn't return the address, only the
  ## socket.
  ##
  ## The SocketHandle associated with the resulting client will not be
  ## inheritable by child processes by default. This can be changed via
  ## the `inheritable` parameter.
  ##
  ## The `accept` call may result in an error if the connecting socket
  ## disconnects during the duration of the `accept`. If the `SafeDisconn`
  ## flag is specified then this error will not be raised and instead
  ## accept will be called again.
  var addrDummy = ""
  acceptAddr(server, client, addrDummy, flags)

when defined(posix) and not defined(lwip):
  from std/posix import Sigset, sigwait, sigismember, sigemptyset, sigaddset,
    sigprocmask, pthread_sigmask, SIGPIPE, SIG_BLOCK, SIG_UNBLOCK

template blockSigpipe(body: untyped): untyped =
  ## Temporary block SIGPIPE within the provided code block. If SIGPIPE is
  ## raised for the duration of the code block, it will be queued and will be
  ## raised once the block ends.
  ##
  ## Within the block a `selectSigpipe()` template is provided which can be
  ## used to remove SIGPIPE from the queue. Note that if SIGPIPE is **not**
  ## raised at the time of call, it will block until SIGPIPE is raised.
  ##
  ## If SIGPIPE has already been blocked at the time of execution, the
  ## signal mask is left as-is and `selectSigpipe()` will become a no-op.
  ##
  ## For convenience, this template is also available for non-POSIX system,
  ## where `body` will be executed as-is.
  when not defined(posix) or defined(lwip):
    body
  else:
    template sigmask(how: cint, set, oset: var Sigset): untyped {.gensym.} =
      ## Alias for pthread_sigmask or sigprocmask depending on the status
      ## of --threads
      when compileOption("threads"):
        pthread_sigmask(how, set, oset)
      else:
        sigprocmask(how, set, oset)

    var oldSet, watchSet: Sigset
    if sigemptyset(oldSet) == -1:
      raiseOSError(osLastError())
    if sigemptyset(watchSet) == -1:
      raiseOSError(osLastError())

    if sigaddset(watchSet, SIGPIPE) == -1:
      raiseOSError(osLastError(), "Couldn't add SIGPIPE to Sigset")

    if sigmask(SIG_BLOCK, watchSet, oldSet) == -1:
      raiseOSError(osLastError(), "Couldn't block SIGPIPE")

    let alreadyBlocked = sigismember(oldSet, SIGPIPE) == 1

    template selectSigpipe(): untyped {.used.} =
      if not alreadyBlocked:
        var signal: cint
        let err = sigwait(watchSet, signal)
        if err != 0:
          raiseOSError(err.OSErrorCode, "Couldn't select SIGPIPE")
        assert signal == SIGPIPE

    try:
      body
    finally:
      if not alreadyBlocked:
        if sigmask(SIG_UNBLOCK, watchSet, oldSet) == -1:
          raiseOSError(osLastError(), "Couldn't unblock SIGPIPE")

proc close*(socket: Socket, flags = {SocketFlag.SafeDisconn}) =
  ## Closes a socket.
  ##
  ## If `socket` is an SSL/TLS socket, this proc will also send a closure
  ## notification to the peer. If `SafeDisconn` is in `flags`, failure to do so
  ## due to disconnections will be ignored. This is generally safe in
  ## practice. See
  ## `here <https://security.stackexchange.com/a/82044>`_ for more details.
  try:
    when defineSsl:
      if socket.isSsl and socket.sslHandle != nil:
        # Don't call SSL_shutdown if the connection has not been fully
        # established, see:
        # https://github.com/openssl/openssl/issues/710#issuecomment-253897666
        if not socket.sslNoShutdown and SSL_in_init(socket.sslHandle) == 0:
          # As we are closing the underlying socket immediately afterwards,
          # it is valid, under the TLS standard, to perform a unidirectional
          # shutdown i.e not wait for the peers "close notify" alert with a second
          # call to SSL_shutdown
          blockSigpipe:
            ErrClearError()
            let res = SSL_shutdown(socket.sslHandle)
            if res == 0:
              discard
            elif res != 1:
              let
                err = osLastError()
                sslError = SSL_get_error(socket.sslHandle, res)

              # If a close notification is received, failures outside of the
              # protocol will be returned as SSL_ERROR_ZERO_RETURN instead
              # of SSL_ERROR_SYSCALL. This fact is deduced by digging into
              # SSL_get_error() source code.
              if sslError == SSL_ERROR_ZERO_RETURN or
                 sslError == SSL_ERROR_SYSCALL:
                when defined(posix) and not defined(macosx) and
                     not defined(nimdoc):
                  if err == EPIPE.OSErrorCode:
                    # Clear the SIGPIPE that's been raised due to
                    # the disconnection.
                    selectSigpipe()
                else:
                  discard
                if not flags.isDisconnectionError(err):
                  socketError(socket, res, lastError = err, flags = flags)
              else:
                socketError(socket, res, lastError = err, flags = flags)
  finally:
    when defineSsl:
      if socket.isSsl and socket.sslHandle != nil:
        SSL_free(socket.sslHandle)
        socket.sslHandle = nil

    socket.fd.close()
    socket.fd = osInvalidSocket

when defined(posix):
  from std/posix import TCP_NODELAY
else:
  from std/winlean import TCP_NODELAY

proc toCInt*(opt: SOBool): cint =
  ## Converts a `SOBool` into its Socket Option cint representation.
  case opt
  of OptAcceptConn: SO_ACCEPTCONN
  of OptBroadcast: SO_BROADCAST
  of OptDebug: SO_DEBUG
  of OptDontRoute: SO_DONTROUTE
  of OptKeepAlive: SO_KEEPALIVE
  of OptOOBInline: SO_OOBINLINE
  of OptReuseAddr: SO_REUSEADDR
  of OptReusePort: SO_REUSEPORT
  of OptNoDelay: TCP_NODELAY

proc getSockOpt*(socket: Socket, opt: SOBool, level = SOL_SOCKET): bool {.
  tags: [ReadIOEffect].} =
  ## Retrieves option `opt` as a boolean value.
  var res = getSockOptInt(socket.fd, cint(level), toCInt(opt))
  result = res != 0

proc getLocalAddr*(socket: Socket): (string, Port) =
  ## Get the socket's local address and port number.
  ##
  ## This is high-level interface for `getsockname`:idx:.
  getLocalAddr(socket.fd, socket.domain)

when not useNimNetLite:
  proc getPeerAddr*(socket: Socket): (string, Port) =
    ## Get the socket's peer address and port number.
    ##
    ## This is high-level interface for `getpeername`:idx:.
    getPeerAddr(socket.fd, socket.domain)

proc setSockOpt*(socket: Socket, opt: SOBool, value: bool,
    level = SOL_SOCKET) {.tags: [WriteIOEffect].} =
  ## Sets option `opt` to a boolean value specified by `value`.
  runnableExamples("-r:off"):
    let socket = newSocket()
    socket.setSockOpt(OptReusePort, true)
    socket.setSockOpt(OptNoDelay, true, level = IPPROTO_TCP.cint)
  var valuei = cint(if value: 1 else: 0)
  setSockOptInt(socket.fd, cint(level), toCInt(opt), valuei)

when defined(nimdoc) or (defined(posix) and not useNimNetLite):
  proc connectUnix*(socket: Socket, path: string) =
    ## Connects to Unix socket on `path`.
    ## This only works on Unix-style systems: Mac OS X, BSD and Linux
    when not defined(nimdoc):
      var socketAddr = makeUnixAddr(path)
      if socket.fd.connect(cast[ptr SockAddr](addr socketAddr),
          (offsetOf(socketAddr, sun_path) + path.len + 1).SockLen) != 0'i32:
        raiseOSError(osLastError())

  proc bindUnix*(socket: Socket, path: string) =
    ## Binds Unix socket to `path`.
    ## This only works on Unix-style systems: Mac OS X, BSD and Linux
    when not defined(nimdoc):
      var socketAddr = makeUnixAddr(path)
      if socket.fd.bindAddr(cast[ptr SockAddr](addr socketAddr),
          (offsetOf(socketAddr, sun_path) + path.len + 1).SockLen) != 0'i32:
        raiseOSError(osLastError())

when defineSsl:
  proc gotHandshake*(socket: Socket): bool =
    ## Determines whether a handshake has occurred between a client (`socket`)
    ## and the server that `socket` is connected to.
    ##
    ## Throws SslError if `socket` is not an SSL socket.
    if socket.isSsl:
      return not socket.sslNoHandshake
    else:
      raiseSSLError("Socket is not an SSL socket.")

proc hasDataBuffered*(s: Socket): bool =
  ## Determines whether a socket has data buffered.
  result = false
  if s.isBuffered:
    result = s.bufLen > 0 and s.currPos != s.bufLen

  when defineSsl:
    if s.isSsl and not result:
      result = s.sslHasPeekChar

proc isClosed(socket: Socket): bool =
  socket.fd == osInvalidSocket

proc uniRecv(socket: Socket, buffer: pointer, size, flags: cint): int =
  ## Handles SSL and non-ssl recv in a nice package.
  ##
  ## In particular handles the case where socket has been closed properly
  ## for both SSL and non-ssl.
  result = 0
  assert(not socket.isClosed, "Cannot `recv` on a closed socket")
  when defineSsl:
    if socket.isSsl:
      ErrClearError()
      return SSL_read(socket.sslHandle, buffer, size)

  return recv(socket.fd, buffer, size, flags)

proc readIntoBuf(socket: Socket, flags: int32): int =
  result = 0
  result = uniRecv(socket, addr(socket.buffer), socket.buffer.high, flags)
  if result < 0:
    # Save it in case it gets reset (the Nim codegen occasionally may call
    # Win API functions which reset it).
    socket.lastError = osLastError()
  if result <= 0:
    socket.bufLen = 0
    socket.currPos = 0
    return result
  socket.bufLen = result
  socket.currPos = 0

template retRead(flags, readBytes: int) {.dirty.} =
  let res = socket.readIntoBuf(flags.int32)
  if res <= 0:
    if readBytes > 0:
      return readBytes
    else:
      return res

proc recv*(socket: Socket, data: pointer, size: int): int {.tags: [
    ReadIOEffect].} =
  ## Receives data from a socket.
  ##
  ## **Note**: This is a low-level function, you may be interested in the higher
  ## level versions of this function which are also named `recv`.
  if size == 0: return
  if socket.isBuffered:
    if socket.bufLen == 0:
      retRead(0'i32, 0)

    var read = 0
    while read < size:
      if socket.currPos >= socket.bufLen:
        retRead(0'i32, read)

      let chunk = min(socket.bufLen-socket.currPos, size-read)
      var d = cast[cstring](data)
      assert size-read >= chunk
      copyMem(addr(d[read]), addr(socket.buffer[socket.currPos]), chunk)
      read.inc(chunk)
      socket.currPos.inc(chunk)

    result = read
  else:
    when defineSsl:
      if socket.isSsl:
        if socket.sslHasPeekChar: # TODO: Merge this peek char mess into uniRecv
          copyMem(data, addr(socket.sslPeekChar), 1)
          socket.sslHasPeekChar = false
          if size-1 > 0:
            var d = cast[cstring](data)
            result = uniRecv(socket, addr(d[1]), cint(size-1), 0'i32) + 1
          else:
            result = 1
        else:
          result = uniRecv(socket, data, size.cint, 0'i32)
      else:
        result = recv(socket.fd, data, size.cint, 0'i32)
    else:
      result = recv(socket.fd, data, size.cint, 0'i32)
    if result < 0:
      # Save the error in case it gets reset.
      socket.lastError = osLastError()

proc waitFor(socket: Socket, waited: var Duration, timeout, size: int,
             funcName: string): int {.tags: [TimeEffect].} =
  ## determines the amount of characters that can be read. Result will never
  ## be larger than `size`. For unbuffered sockets this will be `1`.
  ## For buffered sockets it can be as big as `BufferSize`.
  ##
  ## If this function does not determine that there is data on the socket
  ## within `timeout` ms, a TimeoutError error will be raised.
  result = 1
  if size <= 0: assert false
  if timeout == -1: return size
  if socket.isBuffered and socket.bufLen != 0 and
      socket.bufLen != socket.currPos:
    result = socket.bufLen - socket.currPos
    result = min(result, size)
  else:
    if timeout - waited.inMilliseconds < 1:
      raise newException(TimeoutError, "Call to '" & funcName & "' timed out.")

    when defineSsl:
      if socket.isSsl:
        if socket.hasDataBuffered:
          # sslPeekChar is present.
          return 1
        let sslPending = SSL_pending(socket.sslHandle)
        if sslPending != 0:
          return min(sslPending, size)

    var startTime = getMonoTime()
    let selRet = if socket.hasDataBuffered: 1
      else:
        timeoutRead(socket.fd, (timeout - waited.inMilliseconds).int)
    if selRet < 0: raiseOSError(osLastError())
    if selRet != 1:
      raise newException(TimeoutError, "Call to '" & funcName & "' timed out.")
    waited += (getMonoTime() - startTime)

proc recv*(socket: Socket, data: pointer, size: int, timeout: int): int {.
  tags: [ReadIOEffect, TimeEffect].} =
  ## overload with a `timeout` parameter in milliseconds.
  var waited: Duration = default(Duration) # duration already waited

  var read = 0
  while read < size:
    let avail = waitFor(socket, waited, timeout, size-read, "recv")
    var d = cast[cstring](data)
    assert avail <= size-read
    result = recv(socket, addr(d[read]), avail)
    if result == 0: break
    if result < 0:
      return result
    inc(read, result)

  result = read

proc recv*(socket: Socket, data: var string, size: int, timeout = -1,
           flags = {SocketFlag.SafeDisconn}): int =
  ## Higher-level version of `recv`.
  ##
  ## Reads **up to** `size` bytes from `socket` into `data`.
  ##
  ## For buffered sockets this function will attempt to read all the requested
  ## data. It will read this data in `BufferSize` chunks.
  ##
  ## For unbuffered sockets this function makes no effort to read
  ## all the data requested. It will return as much data as the operating system
  ## gives it.
  ##
  ## When 0 is returned the socket's connection has been closed.
  ##
  ## This function will throw an OSError exception when an error occurs. A value
  ## lower than 0 is never returned.
  ##
  ## A timeout may be specified in milliseconds, if enough data is not received
  ## within the time specified a TimeoutError exception will be raised.
  ##
  ## .. warning:: Only the `SafeDisconn` flag is currently supported.
  data.setLen(size)
  result =
    if timeout == -1:
      recv(socket, cstring(data), size)
    else:
      recv(socket, cstring(data), size, timeout)
  if result < 0:
    data.setLen(0)
    let lastError = getSocketError(socket)
    socket.socketError(result, lastError = lastError, flags = flags)
  else:
    data.setLen(result)

proc recv*(socket: Socket, size: int, timeout = -1,
           flags = {SocketFlag.SafeDisconn}): string {.inline.} =
  ## Higher-level version of `recv` which returns a string.
  ##
  ## Reads **up to** `size` bytes from `socket` into the result.
  ##
  ## For buffered sockets this function will attempt to read all the requested
  ## data. It will read this data in `BufferSize` chunks.
  ##
  ## For unbuffered sockets this function makes no effort to read
  ## all the data requested. It will return as much data as the operating system
  ## gives it.
  ##
  ## When `""` is returned the socket's connection has been closed.
  ##
  ## This function will throw an OSError exception when an error occurs.
  ##
  ## A timeout may be specified in milliseconds, if enough data is not received
  ## within the time specified a TimeoutError exception will be raised.
  ##
  ##
  ## .. warning:: Only the `SafeDisconn` flag is currently supported.
  result = newString(size)
  discard recv(socket, result, size, timeout, flags)

proc peekChar(socket: Socket, c: var char): int {.tags: [ReadIOEffect].} =
  if socket.isBuffered:
    result = 1
    if socket.bufLen == 0 or socket.currPos > socket.bufLen-1:
      var res = socket.readIntoBuf(0'i32)
      if res <= 0:
        result = res

    c = socket.buffer[socket.currPos]
  else:
    when defineSsl:
      if socket.isSsl:
        if not socket.sslHasPeekChar:
          result = uniRecv(socket, addr(socket.sslPeekChar), 1, 0'i32)
          socket.sslHasPeekChar = true

        c = socket.sslPeekChar
        return
    result = recv(socket.fd, addr(c), 1, MSG_PEEK)

proc readLine*(socket: Socket, line: var string, timeout = -1,
               flags = {SocketFlag.SafeDisconn}, maxLength = MaxLineLength) {.
  tags: [ReadIOEffect, TimeEffect].} =
  ## Reads a line of data from `socket`.
  ##
  ## If a full line is read `\r\L` is not
  ## added to `line`, however if solely `\r\L` is read then `line`
  ## will be set to it.
  ##
  ## If the socket is disconnected, `line` will be set to `""`.
  ##
  ## An OSError exception will be raised in the case of a socket error.
  ##
  ## A timeout can be specified in milliseconds, if data is not received within
  ## the specified time a TimeoutError exception will be raised.
  ##
  ## The `maxLength` parameter determines the maximum amount of characters
  ## that can be read. The result is truncated after that.
  ##
  ## .. warning:: Only the `SafeDisconn` flag is currently supported.

  template addNLIfEmpty() =
    if line.len == 0:
      line.add("\c\L")

  template raiseSockError() {.dirty.} =
    let lastError = getSocketError(socket)
    if flags.isDisconnectionError(lastError):
      setLen(line, 0)
    socket.socketError(n, lastError = lastError, flags = flags)
    return

  var waited: Duration = default(Duration) # duration already waited

  setLen(line, 0)
  while true:
    var c: char
    discard waitFor(socket, waited, timeout, 1, "readLine")
    var n = recv(socket, addr(c), 1)
    if n < 0: raiseSockError()
    elif n == 0: setLen(line, 0); return
    if c == '\r':
      discard waitFor(socket, waited, timeout, 1, "readLine")
      n = peekChar(socket, c)
      if n > 0 and c == '\L':
        discard recv(socket, addr(c), 1)
      elif n <= 0: raiseSockError()
      addNLIfEmpty()
      return
    elif c == '\L':
      addNLIfEmpty()
      return
    add(line, c)

    # Verify that this isn't a DOS attack: #3847.
    if line.len > maxLength: break

proc recvLine*(socket: Socket, timeout = -1,
               flags = {SocketFlag.SafeDisconn},
               maxLength = MaxLineLength): string =
  ## Reads a line of data from `socket`.
  ##
  ## If a full line is read `\r\L` is not
  ## added to the result, however if solely `\r\L` is read then the result
  ## will be set to it.
  ##
  ## If the socket is disconnected, the result will be set to `""`.
  ##
  ## An OSError exception will be raised in the case of a socket error.
  ##
  ## A timeout can be specified in milliseconds, if data is not received within
  ## the specified time a TimeoutError exception will be raised.
  ##
  ## The `maxLength` parameter determines the maximum amount of characters
  ## that can be read. The result is truncated after that.
  ##
  ## .. warning:: Only the `SafeDisconn` flag is currently supported.
  result = ""
  readLine(socket, result, timeout, flags, maxLength)

proc recvFrom*[T: string | IpAddress](socket: Socket, data: var string, length: int,
               address: var T, port: var Port, flags = 0'i32): int {.
               tags: [ReadIOEffect].} =
  ## Receives data from `socket`. This function should normally be used with
  ## connection-less sockets (UDP sockets). The source address of the data
  ## packet is stored in the `address` argument as either a string or an IpAddress.
  ##
  ## If an error occurs an OSError exception will be raised. Otherwise the return
  ## value will be the length of data received.
  ##
  ## .. warning:: This function does not yet have a buffered implementation,
  ##   so when `socket` is buffered the non-buffered implementation will be
  ##   used. Therefore if `socket` contains something in its buffer this
  ##   function will make no effort to return it.
  template adaptRecvFromToDomain(sockAddress: untyped, domain: Domain) =
    var addrLen = SockLen(sizeof(sockAddress))
    result = recvfrom(socket.fd, cstring(data), length.cint, flags.cint,
                      cast[ptr SockAddr](addr(sockAddress)), addr(addrLen))

    if result != -1:
      data.setLen(result)

      when typeof(address) is string:
        address = getAddrString(cast[ptr SockAddr](addr(sockAddress)))
        when domain == AF_INET6:
          port = ntohs(sockAddress.sin6_port).Port
        else:
          port = ntohs(sockAddress.sin_port).Port
      else:
        data.setLen(result)
        sockAddress.fromSockAddr(addrLen, address, port)
    else:
      raiseOSError(osLastError())

  assert(socket.protocol != IPPROTO_TCP, "Cannot `recvFrom` on a TCP socket")
  # TODO: Buffered sockets
  data.setLen(length)

  case socket.domain
  of AF_INET6:
    var sockAddress: Sockaddr_in6
    adaptRecvFromToDomain(sockAddress, AF_INET6)
  of AF_INET:
    var sockAddress: Sockaddr_in
    adaptRecvFromToDomain(sockAddress, AF_INET)
  else:
    raise newException(ValueError, "Unknown socket address family")

proc skip*(socket: Socket, size: int, timeout = -1) =
  ## Skips `size` amount of bytes.
  ##
  ## An optional timeout can be specified in milliseconds, if skipping the
  ## bytes takes longer than specified a TimeoutError exception will be raised.
  ##
  ## Returns the number of skipped bytes.
  var waited: Duration = default(Duration) # duration already waited
  var dummy = alloc(size)
  var bytesSkipped = 0
  while bytesSkipped != size:
    let avail = waitFor(socket, waited, timeout, size-bytesSkipped, "skip")
    bytesSkipped += recv(socket, dummy, avail)
  dealloc(dummy)

proc send*(socket: Socket, data: pointer, size: int): int {.
  tags: [WriteIOEffect].} =
  ## Sends data to a socket.
  ##
  ## **Note**: This is a low-level version of `send`. You likely should use
  ## the version below.
  assert(not socket.isClosed, "Cannot `send` on a closed socket")
  when defineSsl:
    if socket.isSsl:
      ErrClearError()
      return SSL_write(socket.sslHandle, cast[cstring](data), size)

  when useWinVersion or defined(macosx):
    result = send(socket.fd, data, size.cint, 0'i32)
  else:
    when defined(solaris):
      const MSG_NOSIGNAL = 0
    result = send(socket.fd, data, size, int32(MSG_NOSIGNAL))

proc send*(socket: Socket, data: string,
           flags = {SocketFlag.SafeDisconn}, maxRetries = 100) {.tags: [WriteIOEffect].} =
  ## Sends data to a socket. Will try to send all the data by handling interrupts
  ## and incomplete writes up to `maxRetries`.
  var written = 0
  var attempts = 0
  while data.len - written > 0:
    let sent = send(socket, cstring(data), data.len)

    if sent < 0:
      let lastError = osLastError()
      let isBlockingErr =
        when defined(nimdoc):
          false
        elif useWinVersion:
          lastError.int32 == WSAEINTR or
          lastError.int32 == WSAEWOULDBLOCK
        else:
          lastError.int32 == EINTR or
          lastError.int32 == EWOULDBLOCK or
          lastError.int32 == EAGAIN

      if not isBlockingErr:
        let lastError = osLastError()
        socketError(socket, lastError = lastError, flags = flags)
      else:
        attempts.inc()
        if attempts > maxRetries:
          raiseOSError(osLastError(), "Could not send all data.")
    else:
      written.inc(sent)

template `&=`*(socket: Socket; data: typed) =
  ## an alias for 'send'.
  send(socket, data)

proc trySend*(socket: Socket, data: string): bool {.tags: [WriteIOEffect].} =
  ## Safe alternative to `send`. Does not raise an OSError when an error occurs,
  ## and instead returns `false` on failure.
  result = send(socket, cstring(data), data.len) == data.len

proc sendTo*(socket: Socket, address: string, port: Port, data: pointer,
             size: int, af: Domain = AF_INET, flags = 0'i32) {.
             tags: [WriteIOEffect].} =
  ## This proc sends `data` to the specified `address`,
  ## which may be an IP address or a hostname, if a hostname is specified
  ## this function will try each IP of that hostname. This function
  ## should normally be used with connection-less sockets (UDP sockets).
  ##
  ## If an error occurs an OSError exception will be raised.
  ##
  ## **Note:** You may wish to use the high-level version of this function
  ## which is defined below.
  ##
  ## **Note:** This proc is not available for SSL sockets.
  assert(socket.protocol != IPPROTO_TCP, "Cannot `sendTo` on a TCP socket")
  assert(not socket.isClosed, "Cannot `sendTo` on a closed socket")
  var aiList = getAddrInfo(address, port, af, socket.sockType, socket.protocol)
  # try all possibilities:
  var success = false
  var it = aiList
  var result = 0
  while it != nil:
    result = sendto(socket.fd, data, size.cint, flags.cint, it.ai_addr,
                    it.ai_addrlen.SockLen)
    if result != -1'i32:
      success = true
      break
    it = it.ai_next

  let osError = osLastError()
  freeAddrInfo(aiList)

  if not success:
    raiseOSError(osError)

proc sendTo*(socket: Socket, address: string, port: Port,
             data: string) {.tags: [WriteIOEffect].} =
  ## This proc sends `data` to the specified `address`,
  ## which may be an IP address or a hostname, if a hostname is specified
  ## this function will try each IP of that hostname.
  ##
  ## Generally for use with connection-less (UDP) sockets.
  ##
  ## If an error occurs an OSError exception will be raised.
  ##
  ## This is the high-level version of the above `sendTo` function.
  socket.sendTo(address, port, cstring(data), data.len, socket.domain)

proc sendTo*(socket: Socket, address: IpAddress, port: Port,
             data: string, flags = 0'i32): int {.
              discardable, tags: [WriteIOEffect].} =
  ## This proc sends `data` to the specified `IpAddress` and returns
  ## the number of bytes written.
  ##
  ## Generally for use with connection-less (UDP) sockets.
  ##
  ## If an error occurs an OSError exception will be raised.
  ##
  ## This is the high-level version of the above `sendTo` function.
  assert(socket.protocol != IPPROTO_TCP, "Cannot `sendTo` on a TCP socket")
  assert(not socket.isClosed, "Cannot `sendTo` on a closed socket")

  var sa: Sockaddr_storage = default(Sockaddr_storage)
  var sl: SockLen = default(SockLen)
  toSockAddr(address, port, sa, sl)
  result = sendto(socket.fd, cstring(data), data.len().cint, flags.cint,
                  cast[ptr SockAddr](addr sa), sl)

  if result == -1'i32:
    let osError = osLastError()
    raiseOSError(osError)


proc isSsl*(socket: Socket): bool =
  ## Determines whether `socket` is a SSL socket.
  when defineSsl:
    result = socket.isSsl
  else:
    result = false

proc getFd*(socket: Socket): SocketHandle = return socket.fd
  ## Returns the socket's file descriptor

when defined(zephyr) or defined(nimNetSocketExtras): # Remove in future
  proc getDomain*(socket: Socket): Domain = return socket.domain
    ## Returns the socket's domain

  proc getType*(socket: Socket): SockType = return socket.sockType
    ## Returns the socket's type

  proc getProtocol*(socket: Socket): Protocol = return socket.protocol
    ## Returns the socket's protocol

when defined(nimHasStyleChecks):
  {.push styleChecks: off.}

proc IPv4_any*(): IpAddress =
  ## Returns the IPv4 any address, which can be used to listen on all available
  ## network adapters
  result = IpAddress(
    family: IpAddressFamily.IPv4,
    address_v4: [0'u8, 0, 0, 0])

proc IPv4_loopback*(): IpAddress =
  ## Returns the IPv4 loopback address (127.0.0.1)
  result = IpAddress(
    family: IpAddressFamily.IPv4,
    address_v4: [127'u8, 0, 0, 1])

proc IPv4_broadcast*(): IpAddress =
  ## Returns the IPv4 broadcast address (255.255.255.255)
  result = IpAddress(
    family: IpAddressFamily.IPv4,
    address_v4: [255'u8, 255, 255, 255])

proc IPv6_any*(): IpAddress =
  ## Returns the IPv6 any address (::0), which can be used
  ## to listen on all available network adapters
  result = IpAddress(
    family: IpAddressFamily.IPv6,
    address_v6: [0'u8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])

proc IPv6_loopback*(): IpAddress =
  ## Returns the IPv6 loopback address (::1)
  result = IpAddress(
    family: IpAddressFamily.IPv6,
    address_v6: [0'u8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])

when defined(nimHasStyleChecks):
  {.pop.}

proc `==`*(lhs, rhs: IpAddress): bool =
  ## Compares two IpAddresses for Equality. Returns true if the addresses are equal
  if lhs.family != rhs.family: return false
  if lhs.family == IpAddressFamily.IPv4:
    for i in low(lhs.address_v4) .. high(lhs.address_v4):
      if lhs.address_v4[i] != rhs.address_v4[i]: return false
  else: # IPv6
    for i in low(lhs.address_v6) .. high(lhs.address_v6):
      if lhs.address_v6[i] != rhs.address_v6[i]: return false
  return true

proc `$`*(address: IpAddress): string =
  ## Converts an IpAddress into the textual representation
  case address.family
  of IpAddressFamily.IPv4:
    result = newStringOfCap(15)
    result.addInt address.address_v4[0]
    result.add '.'
    result.addInt address.address_v4[1]
    result.add '.'
    result.addInt address.address_v4[2]
    result.add '.'
    result.addInt address.address_v4[3]
  of IpAddressFamily.IPv6:
    result = newStringOfCap(39)
    var
      currentZeroStart = -1
      currentZeroCount = 0
      biggestZeroStart = -1
      biggestZeroCount = 0
    # Look for the largest block of zeros
    for i in 0..7:
      var isZero = address.address_v6[i*2] == 0 and address.address_v6[i*2+1] == 0
      if isZero:
        if currentZeroStart == -1:
          currentZeroStart = i
          currentZeroCount = 1
        else:
          currentZeroCount.inc()
        if currentZeroCount > biggestZeroCount:
          biggestZeroCount = currentZeroCount
          biggestZeroStart = currentZeroStart
      else:
        currentZeroStart = -1

    if biggestZeroCount == 8: # Special case ::0
      result.add("::")
    else: # Print address
      var printedLastGroup = false
      for i in 0..7:
        var word: uint16 = (cast[uint16](address.address_v6[i*2])) shl 8
        word = word or cast[uint16](address.address_v6[i*2+1])

        if biggestZeroCount != 0 and # Check if group is in skip group
          (i >= biggestZeroStart and i < (biggestZeroStart + biggestZeroCount)):
          if i == biggestZeroStart: # skip start
            result.add("::")
          printedLastGroup = false
        else:
          if printedLastGroup:
            result.add(':')
          var
            afterLeadingZeros = false
            mask = 0xF000'u16
          for j in 0'u16..3'u16:
            var val = (mask and word) shr (4'u16*(3'u16-j))
            if val != 0 or afterLeadingZeros:
              if val < 0xA:
                result.add(chr(uint16(ord('0'))+val))
              else: # val >= 0xA
                result.add(chr(uint16(ord('a'))+val-0xA))
              afterLeadingZeros = true
            mask = mask shr 4

          if not afterLeadingZeros:
            result.add '0'

          printedLastGroup = true

proc dial*(address: string, port: Port,
           protocol = IPPROTO_TCP, buffered = true): owned(Socket)
           {.tags: [ReadIOEffect, WriteIOEffect].} =
  ## Establishes connection to the specified `address`:`port` pair via the
  ## specified protocol. The procedure iterates through possible
  ## resolutions of the `address` until it succeeds, meaning that it
  ## seamlessly works with both IPv4 and IPv6.
  ## Returns Socket ready to send or receive data.
  let sockType = protocol.toSockType()

  let aiList = getAddrInfo(address, port, AF_UNSPEC, sockType, protocol)

  var fdPerDomain = default(array[low(Domain).ord..high(Domain).ord, SocketHandle])
  for i in low(fdPerDomain)..high(fdPerDomain):
    fdPerDomain[i] = osInvalidSocket
  template closeUnusedFds(domainToKeep = -1) {.dirty.} =
    for i, fd in fdPerDomain:
      if fd != osInvalidSocket and i != domainToKeep:
        fd.close()

  var success = false
  var lastError: OSErrorCode = default(OSErrorCode)
  var it = aiList
  var domain: Domain = default(Domain)
  var lastFd: SocketHandle = default(SocketHandle)
  while it != nil:
    let domainOpt = it.ai_family.toKnownDomain()
    if domainOpt.isNone:
      it = it.ai_next
      continue
    domain = domainOpt.unsafeGet()
    lastFd = fdPerDomain[ord(domain)]
    if lastFd == osInvalidSocket:
      lastFd = createNativeSocket(domain, sockType, protocol)
      if lastFd == osInvalidSocket:
        # we always raise if socket creation failed, because it means a
        # network system problem (e.g. not enough FDs), and not an unreachable
        # address.
        let err = osLastError()
        freeAddrInfo(aiList)
        closeUnusedFds()
        raiseOSError(err)
      fdPerDomain[ord(domain)] = lastFd
    if connect(lastFd, it.ai_addr, it.ai_addrlen.SockLen) == 0'i32:
      success = true
      break
    lastError = osLastError()
    it = it.ai_next
  freeAddrInfo(aiList)
  closeUnusedFds(ord(domain))

  if success:
    result = newSocket(lastFd, domain, sockType, protocol, buffered)
  elif lastError != 0.OSErrorCode:
    lastFd.close()
    result = default(Socket)
    raiseOSError(lastError)
  else:
    lastFd.close()
    raise newException(IOError, "Couldn't resolve address: " & address)

proc connect*(socket: Socket, address: string,
    port = Port(0)) {.tags: [ReadIOEffect, RootEffect].} =
  ## Connects socket to `address`:`port`. `Address` can be an IP address or a
  ## host name. If `address` is a host name, this function will try each IP
  ## of that host name. `htons` is already performed on `port` so you must
  ## not do it.
  ##
  ## If `socket` is an SSL socket a handshake will be automatically performed.
  var aiList = getAddrInfo(address, port, socket.domain)
  # try all possibilities:
  var success = false
  var lastError: OSErrorCode = default(OSErrorCode)
  var it = aiList
  while it != nil:
    if connect(socket.fd, it.ai_addr, it.ai_addrlen.SockLen) == 0'i32:
      success = true
      break
    else: lastError = osLastError()
    it = it.ai_next

  freeAddrInfo(aiList)
  if not success: raiseOSError(lastError)

  when defineSsl:
    if socket.isSsl:
      # RFC3546 for SNI specifies that IP addresses are not allowed.
      if not isIpAddress(address):
        # Discard result in case OpenSSL version doesn't support SNI, or we're
        # not using TLSv1+
        discard SSL_set_tlsext_host_name(socket.sslHandle, address)

      ErrClearError()
      let ret = SSL_connect(socket.sslHandle)
      socketError(socket, ret)
      when not defined(nimDisableCertificateValidation) and not defined(windows):
        if not isIpAddress(address):
          socket.checkCertName(address)

proc connectAsync(socket: Socket, name: string, port = Port(0),
                  af: Domain = AF_INET) {.tags: [ReadIOEffect].} =
  ## A variant of `connect` for non-blocking sockets.
  ##
  ## This procedure will immediately return, it will not block until a connection
  ## is made. It is up to the caller to make sure the connection has been established
  ## by checking (using `select`) whether the socket is writeable.
  ##
  ## **Note**: For SSL sockets, the `handshake` procedure must be called
  ## whenever the socket successfully connects to a server.
  var aiList = getAddrInfo(name, port, af)
  # try all possibilities:
  var success = false
  var lastError: OSErrorCode = default(OSErrorCode)
  var it = aiList
  while it != nil:
    var ret = connect(socket.fd, it.ai_addr, it.ai_addrlen.SockLen)
    if ret == 0'i32:
      success = true
      break
    else:
      lastError = osLastError()
      when useWinVersion:
        # Windows EINTR doesn't behave same as POSIX.
        if lastError.int32 == WSAEWOULDBLOCK:
          success = true
          break
      else:
        if lastError.int32 == EINTR or lastError.int32 == EINPROGRESS:
          success = true
          break

    it = it.ai_next

  freeAddrInfo(aiList)
  if not success: raiseOSError(lastError)

proc connect*(socket: Socket, address: string, port = Port(0),
    timeout: int) {.tags: [ReadIOEffect, WriteIOEffect, RootEffect].} =
  ## Connects to server as specified by `address` on port specified by `port`.
  ##
  ## The `timeout` parameter specifies the time in milliseconds to allow for
  ## the connection to the server to be made.
  socket.fd.setBlocking(false)

  socket.connectAsync(address, port, socket.domain)
  if timeoutWrite(socket.fd, timeout) != 1:
    raise newException(TimeoutError, "Call to 'connect' timed out.")
  else:
    let res = getSockOptInt(socket.fd, SOL_SOCKET, SO_ERROR)
    if res != 0:
      raiseOSError(OSErrorCode(res))
    when defineSsl and not defined(nimdoc):
      if socket.isSsl:
        socket.fd.setBlocking(true)
        # RFC3546 for SNI specifies that IP addresses are not allowed.
        if not isIpAddress(address):
          # Discard result in case OpenSSL version doesn't support SNI, or we're
          # not using TLSv1+
          discard SSL_set_tlsext_host_name(socket.sslHandle, address)

        ErrClearError()
        let ret = SSL_connect(socket.sslHandle)
        socketError(socket, ret)
        when not defined(nimDisableCertificateValidation):
          if not isIpAddress(address):
            socket.checkCertName(address)
  socket.fd.setBlocking(true)

proc getPrimaryIPAddr*(dest = parseIpAddress("8.8.8.8")): IpAddress =
  ## Finds the local IP address, usually assigned to eth0 on LAN or wlan0 on WiFi,
  ## used to reach an external address. Useful to run local services.
  ##
  ## No traffic is sent.
  ##
  ## Supports IPv4 and v6.
  ## Raises OSError if external networking is not set up.
  runnableExamples("-r:off"):
    echo getPrimaryIPAddr() # "192.168.1.2"
  let socket =
    if dest.family == IpAddressFamily.IPv4:
      newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    else:
      newSocket(AF_INET6, SOCK_DGRAM, IPPROTO_UDP)
  try:
    socket.connect($dest, 80.Port)
    result = socket.getLocalAddr()[0].parseIpAddress()
  finally:
    socket.close()
