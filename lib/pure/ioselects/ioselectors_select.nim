#
#
#            Nim's Runtime Library
#        (c) Copyright 2016 Eugene Kabanov
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This module implements Posix and Windows select().

import std/[times, nativesockets]

when defined(windows):
  import std/winlean
  when defined(gcc):
    {.passl: "-lws2_32".}
  elif defined(vcc):
    {.passl: "ws2_32.lib".}
  const platformHeaders = """#include <winsock2.h>
                             #include <windows.h>"""
  const EAGAIN = WSAEWOULDBLOCK
else:
  const platformHeaders = """#include <sys/select.h>
                             #include <sys/time.h>
                             #include <sys/types.h>
                             #include <unistd.h>"""
type
  FdSet {.importc: "fd_set", header: platformHeaders, pure, final.} = object
var
  FD_SETSIZE {.importc: "FD_SETSIZE", header: platformHeaders.}: cint

proc IOFD_SET(fd: SocketHandle, fdset: ptr FdSet)
     {.cdecl, importc: "FD_SET", header: platformHeaders, inline.}
proc IOFD_CLR(fd: SocketHandle, fdset: ptr FdSet)
     {.cdecl, importc: "FD_CLR", header: platformHeaders, inline.}
proc IOFD_ZERO(fdset: ptr FdSet)
     {.cdecl, importc: "FD_ZERO", header: platformHeaders, inline.}

when defined(windows):
  proc IOFD_ISSET(fd: SocketHandle, fdset: ptr FdSet): cint
       {.stdcall, importc: "FD_ISSET", header: platformHeaders, inline.}
  proc ioselect(nfds: cint, readFds, writeFds, exceptFds: ptr FdSet,
                timeout: ptr Timeval): cint
       {.stdcall, importc: "select", header: platformHeaders.}
else:
  proc IOFD_ISSET(fd: SocketHandle, fdset: ptr FdSet): cint
       {.cdecl, importc: "FD_ISSET", header: platformHeaders, inline.}
  proc ioselect(nfds: cint, readFds, writeFds, exceptFds: ptr FdSet,
                timeout: ptr Timeval): cint
       {.cdecl, importc: "select", header: platformHeaders.}

when hasThreadSupport:
  type
    SelectorImpl[T] = object
      rSet: FdSet
      wSet: FdSet
      eSet: FdSet
      maxFD: int
      fds: ptr SharedArray[SelectorKey[T]]
      count*: int
      lock: Lock
    Selector*[T] = ptr SelectorImpl[T]
else:
  type
    SelectorImpl[T] = object
      rSet: FdSet
      wSet: FdSet
      eSet: FdSet
      maxFD: int
      fds: seq[SelectorKey[T]]
      count*: int
    Selector*[T] = ref SelectorImpl[T]

type
  SelectEventImpl = object
    rsock: SocketHandle
    wsock: SocketHandle
  SelectEvent* = ptr SelectEventImpl

when hasThreadSupport:
  template withSelectLock[T](s: Selector[T], body: untyped) =
    acquire(s.lock)
    {.locks: [s.lock].}:
      try:
        body
      finally:
        release(s.lock)
else:
  template withSelectLock[T](s: Selector[T], body: untyped) =
    body

proc newSelector*[T](): Selector[T] =
  when hasThreadSupport:
    result = cast[Selector[T]](allocShared0(sizeof(SelectorImpl[T])))
    result.fds = allocSharedArray[SelectorKey[T]](FD_SETSIZE)
    initLock result.lock
  else:
    result = Selector[T]()
    result.fds = newSeq[SelectorKey[T]](FD_SETSIZE)

  for i in 0 ..< FD_SETSIZE:
    result.fds[i].ident = InvalidIdent

  IOFD_ZERO(addr result.rSet)
  IOFD_ZERO(addr result.wSet)
  IOFD_ZERO(addr result.eSet)

proc close*[T](s: Selector[T]) =
  when hasThreadSupport:
    deallocSharedArray(s.fds)
    deallocShared(cast[pointer](s))
    deinitLock(s.lock)

when defined(windows):
  proc newSelectEvent*(): SelectEvent =
    var ssock = createNativeSocket()
    var wsock = createNativeSocket()
    var rsock: SocketHandle = INVALID_SOCKET
    var saddr = Sockaddr_in()

    saddr.sin_family = winlean.AF_INET
    saddr.sin_port = 0
    saddr.sin_addr.s_addr = INADDR_ANY
    if bindAddr(ssock, cast[ptr SockAddr](addr(saddr)),
                sizeof(saddr).SockLen) < 0'i32:
      raiseIOSelectorsError(osLastError())

    if winlean.listen(ssock, 1) != 0:
      raiseIOSelectorsError(osLastError())

    var namelen = sizeof(saddr).SockLen
    if getsockname(ssock, cast[ptr SockAddr](addr(saddr)),
                   addr(namelen)) != 0'i32:
      raiseIOSelectorsError(osLastError())

    saddr.sin_addr.s_addr = 0x0100007F
    if winlean.connect(wsock, cast[ptr SockAddr](addr(saddr)),
                       sizeof(saddr).SockLen) != 0:
      raiseIOSelectorsError(osLastError())
    namelen = sizeof(saddr).SockLen
    rsock = winlean.accept(ssock, cast[ptr SockAddr](addr(saddr)),
                           cast[ptr SockLen](addr(namelen)))
    if rsock == SocketHandle(-1):
      raiseIOSelectorsError(osLastError())

    if winlean.closesocket(ssock) != 0:
      raiseIOSelectorsError(osLastError())

    var mode = clong(1)
    if ioctlsocket(rsock, FIONBIO, addr(mode)) != 0:
      raiseIOSelectorsError(osLastError())
    mode = clong(1)
    if ioctlsocket(wsock, FIONBIO, addr(mode)) != 0:
      raiseIOSelectorsError(osLastError())

    result = cast[SelectEvent](allocShared0(sizeof(SelectEventImpl)))
    result.rsock = rsock
    result.wsock = wsock

  proc trigger*(ev: SelectEvent) =
    var data: uint64 = 1
    if winlean.send(ev.wsock, cast[pointer](addr data),
                    cint(sizeof(uint64)), 0) != sizeof(uint64):
      raiseIOSelectorsError(osLastError())

  proc close*(ev: SelectEvent) =
    let res1 = winlean.closesocket(ev.rsock)
    let res2 = winlean.closesocket(ev.wsock)
    deallocShared(cast[pointer](ev))
    if res1 != 0 or res2 != 0:
      raiseIOSelectorsError(osLastError())

else:
  proc newSelectEvent*(): SelectEvent =
    var fds: array[2, cint]
    if posix.pipe(fds) != 0:
      raiseIOSelectorsError(osLastError())
    setNonBlocking(fds[0])
    setNonBlocking(fds[1])
    result = cast[SelectEvent](allocShared0(sizeof(SelectEventImpl)))
    result.rsock = SocketHandle(fds[0])
    result.wsock = SocketHandle(fds[1])

  proc trigger*(ev: SelectEvent) =
    var data: uint64 = 1
    if posix.write(cint(ev.wsock), addr data, sizeof(uint64)) != sizeof(uint64):
      raiseIOSelectorsError(osLastError())

  proc close*(ev: SelectEvent) =
    let res1 = posix.close(cint(ev.rsock))
    let res2 = posix.close(cint(ev.wsock))
    deallocShared(cast[pointer](ev))
    if res1 != 0 or res2 != 0:
      raiseIOSelectorsError(osLastError())

proc setSelectKey[T](s: Selector[T], fd: SocketHandle, events: set[Event],
                     data: T) =
  var i = 0
  let fdi = int(fd)
  while i < FD_SETSIZE:
    if s.fds[i].ident == InvalidIdent:
      var pkey = addr(s.fds[i])
      pkey.ident = fdi
      pkey.events = events
      pkey.data = data
      break
    inc(i)
  if i >= FD_SETSIZE:
    raiseIOSelectorsError("Maximum number of descriptors is exhausted!")

proc getKey[T](s: Selector[T], fd: SocketHandle): ptr SelectorKey[T] =
  var i = 0
  let fdi = int(fd)
  while i < FD_SETSIZE:
    if s.fds[i].ident == fdi:
      result = addr(s.fds[i])
      break
    inc(i)
  doAssert(i < FD_SETSIZE,
           "Descriptor [" & $int(fd) & "] is not registered in the queue!")

proc delKey[T](s: Selector[T], fd: SocketHandle) =
  var empty: T
  var i = 0
  while i < FD_SETSIZE:
    if s.fds[i].ident == fd.int:
      s.fds[i].ident = InvalidIdent
      s.fds[i].events = {}
      s.fds[i].data = empty
      break
    inc(i)
  doAssert(i < FD_SETSIZE,
           "Descriptor [" & $int(fd) & "] is not registered in the queue!")

proc registerHandle*[T](s: Selector[T], fd: int | SocketHandle,
                        events: set[Event], data: T) =
  when not defined(windows):
    let fdi = int(fd)
  s.withSelectLock():
    s.setSelectKey(fd, events, data)
    when not defined(windows):
      if fdi > s.maxFD: s.maxFD = fdi
    if Event.Read in events:
      IOFD_SET(fd, addr s.rSet)
      inc(s.count)
    if Event.Write in events:
      IOFD_SET(fd, addr s.wSet)
      IOFD_SET(fd, addr s.eSet)
      inc(s.count)

proc registerEvent*[T](s: Selector[T], ev: SelectEvent, data: T) =
  when not defined(windows):
    let fdi = int(ev.rsock)
  s.withSelectLock():
    s.setSelectKey(ev.rsock, {Event.User}, data)
    when not defined(windows):
      if fdi > s.maxFD: s.maxFD = fdi
    IOFD_SET(ev.rsock, addr s.rSet)
    inc(s.count)

proc updateHandle*[T](s: Selector[T], fd: int | SocketHandle,
                      events: set[Event]) =
  let maskEvents = {Event.Timer, Event.Signal, Event.Process, Event.Vnode,
                    Event.User, Event.Oneshot, Event.Error}
  s.withSelectLock():
    var pkey = s.getKey(fd)
    doAssert(pkey.events * maskEvents == {})
    if pkey.events != events:
      if (Event.Read in pkey.events) and (Event.Read notin events):
        IOFD_CLR(fd, addr s.rSet)
        dec(s.count)
      if (Event.Write in pkey.events) and (Event.Write notin events):
        IOFD_CLR(fd, addr s.wSet)
        IOFD_CLR(fd, addr s.eSet)
        dec(s.count)
      if (Event.Read notin pkey.events) and (Event.Read in events):
        IOFD_SET(fd, addr s.rSet)
        inc(s.count)
      if (Event.Write notin pkey.events) and (Event.Write in events):
        IOFD_SET(fd, addr s.wSet)
        IOFD_SET(fd, addr s.eSet)
        inc(s.count)
      pkey.events = events

proc unregister*[T](s: Selector[T], fd: SocketHandle|int) =
  s.withSelectLock():
    let fd = fd.SocketHandle
    var pkey = s.getKey(fd)
    if Event.Read in pkey.events or Event.User in pkey.events:
      IOFD_CLR(fd, addr s.rSet)
      dec(s.count)
    if Event.Write in pkey.events:
      IOFD_CLR(fd, addr s.wSet)
      IOFD_CLR(fd, addr s.eSet)
      dec(s.count)
    s.delKey(fd)

proc unregister*[T](s: Selector[T], ev: SelectEvent) =
  let fd = ev.rsock
  s.withSelectLock():
    var pkey = s.getKey(fd)
    IOFD_CLR(fd, addr s.rSet)
    dec(s.count)
    s.delKey(fd)

proc selectInto*[T](s: Selector[T], timeout: int,
                    results: var openArray[ReadyKey]): int =
  var tv = Timeval()
  var ptv = addr tv
  var rset, wset, eset: FdSet

  verifySelectParams(timeout)

  if timeout != -1:
    when defined(genode) or defined(freertos) or defined(zephyr) or defined(nuttx):
      tv.tv_sec = posix.Time(timeout div 1_000)
    else:
      tv.tv_sec = timeout.int32 div 1_000
    tv.tv_usec = (timeout.int32 %% 1_000) * 1_000
  else:
    ptv = nil

  s.withSelectLock():
    rset = s.rSet
    wset = s.wSet
    eset = s.eSet

  var count = ioselect(cint(s.maxFD) + 1, addr(rset), addr(wset),
                       addr(eset), ptv)
  if count < 0:
    result = 0
    when defined(windows):
      raiseIOSelectorsError(osLastError())
    else:
      let err = osLastError()
      if cint(err) != EINTR:
        raiseIOSelectorsError(err)
  elif count == 0:
    result = 0
  else:
    var rindex = 0
    var i = 0
    var k = 0

    while (i < FD_SETSIZE) and (k < count):
      if s.fds[i].ident != InvalidIdent:
        var flag = false
        var pkey = addr(s.fds[i])
        var rkey = ReadyKey(fd: int(pkey.ident), events: {})
        let fd = SocketHandle(pkey.ident)
        if IOFD_ISSET(fd, addr rset) != 0:
          if Event.User in pkey.events:
            var data: uint64 = 0
            if recv(fd, cast[pointer](addr(data)),
                    sizeof(uint64).cint, 0) != sizeof(uint64):
              let err = osLastError()
              if cint(err) != EAGAIN:
                raiseIOSelectorsError(err)
              else:
                inc(i)
                inc(k)
                continue
            else:
              flag = true
              rkey.events = {Event.User}
          else:
            flag = true
            rkey.events = {Event.Read}
        if IOFD_ISSET(fd, addr wset) != 0:
          rkey.events.incl(Event.Write)
          if IOFD_ISSET(fd, addr eset) != 0:
            rkey.events.incl(Event.Error)
          flag = true
        if flag:
          results[rindex] = rkey
          inc(rindex)
          inc(k)
      inc(i)
    result = rindex

proc select*[T](s: Selector[T], timeout: int): seq[ReadyKey] =
  result = newSeq[ReadyKey](FD_SETSIZE)
  var count = selectInto(s, timeout, result)
  result.setLen(count)

proc flush*[T](s: Selector[T]) = discard

template isEmpty*[T](s: Selector[T]): bool =
  (s.count == 0)

proc contains*[T](s: Selector[T], fd: SocketHandle|int): bool {.inline.} =
  s.withSelectLock():
    result = false

    let fdi = int(fd)
    for i in 0..<FD_SETSIZE:
      if s.fds[i].ident == fdi:
        return true

proc getData*[T](s: Selector[T], fd: SocketHandle|int): var T =
  s.withSelectLock():
    let fdi = int(fd)
    for i in 0..<FD_SETSIZE:
      if s.fds[i].ident == fdi:
        return s.fds[i].data

proc setData*[T](s: Selector[T], fd: SocketHandle|int, data: T): bool =
  s.withSelectLock():
    let fdi = int(fd)
    var i = 0
    while i < FD_SETSIZE:
      if s.fds[i].ident == fdi:
        var pkey = addr(s.fds[i])
        pkey.data = data
        result = true
        break

template withData*[T](s: Selector[T], fd: SocketHandle|int, value,
                      body: untyped) =
  mixin withSelectLock
  s.withSelectLock():
    var value: ptr T
    let fdi = int(fd)
    var i = 0
    while i < FD_SETSIZE:
      if s.fds[i].ident == fdi:
        value = addr(s.fds[i].data)
        break
      inc(i)
    if i != FD_SETSIZE:
      body

template withData*[T](s: Selector[T], fd: SocketHandle|int, value,
                      body1, body2: untyped) =
  mixin withSelectLock
  s.withSelectLock():
    block:
      var value: ptr T
      let fdi = int(fd)
      var i = 0
      while i < FD_SETSIZE:
        if s.fds[i].ident == fdi:
          value = addr(s.fds[i].data)
          break
        inc(i)
      if i != FD_SETSIZE:
        body1
      else:
        body2


proc getFd*[T](s: Selector[T]): int =
  return -1
