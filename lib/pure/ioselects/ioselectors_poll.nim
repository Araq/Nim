#
#
#            Nim's Runtime Library
#        (c) Copyright 2016 Eugene Kabanov
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This module implements Posix poll().

import std/[posix, times]

# Maximum number of events that can be returned
const MAX_POLL_EVENTS = 64

const hasEventFds = defined(zephyr) or defined(nimPollHasEventFds)

when hasEventFds:
  proc eventfd(count: cuint, flags: cint): cint
     {.cdecl, importc: "eventfd", header: "<sys/eventfd.h>".}

when hasThreadSupport:
  type
    SelectorImpl[T] = object
      maxFD : int
      pollcnt: int
      fds: ptr SharedArray[SelectorKey[T]]
      pollfds: ptr SharedArray[TPollFd]
      count*: int
      lock: Lock
    Selector*[T] = ptr SelectorImpl[T]
else:
  type
    SelectorImpl[T] = object
      maxFD : int
      pollcnt: int
      fds: seq[SelectorKey[T]]
      pollfds: seq[TPollFd]
      count*: int
    Selector*[T] = ref SelectorImpl[T]

type
  SelectEventImpl = object
    rfd: cint
    wfd: cint
  SelectEvent* = ptr SelectEventImpl

when hasThreadSupport:
  template withPollLock[T](s: Selector[T], body: untyped) =
    acquire(s.lock)
    {.locks: [s.lock].}:
      try:
        body
      finally:
        release(s.lock)
else:
  template withPollLock(s, body: untyped) =
    body

proc newSelector*[T](): Selector[T] =
  var maxFD = maxDescriptors()

  when hasThreadSupport:
    result = cast[Selector[T]](allocShared0(sizeof(SelectorImpl[T])))
    result.maxFD = maxFD
    result.fds = allocSharedArray[SelectorKey[T]](maxFD)
    result.pollfds = allocSharedArray[TPollFd](maxFD)
    initLock(result.lock)
  else:
    result = Selector[T]()
    result.maxFD = maxFD
    result.fds = newSeq[SelectorKey[T]](maxFD)
    result.pollfds = newSeq[TPollFd](maxFD)

  for i in 0 ..< maxFD:
    result.fds[i].ident = InvalidIdent

proc close*[T](s: Selector[T]) =
  when hasThreadSupport:
    deinitLock(s.lock)
    deallocSharedArray(s.fds)
    deallocSharedArray(s.pollfds)
    deallocShared(cast[pointer](s))

template pollAdd[T](s: Selector[T], sock: cint, events: set[Event]) =
  withPollLock(s):
    var pollev: cshort = 0
    if Event.Read in events: pollev = pollev or POLLIN
    if Event.Write in events: pollev = pollev or POLLOUT
    s.pollfds[s.pollcnt].fd = cint(sock)
    s.pollfds[s.pollcnt].events = pollev
    inc(s.count)
    inc(s.pollcnt)

template pollUpdate[T](s: Selector[T], sock: cint, events: set[Event]) =
  withPollLock(s):
    var i = 0
    var pollev: cshort = 0
    if Event.Read in events: pollev = pollev or POLLIN
    if Event.Write in events: pollev = pollev or POLLOUT

    while i < s.pollcnt:
      if s.pollfds[i].fd == sock:
        s.pollfds[i].events = pollev
        break
      inc(i)
    doAssert(i < s.pollcnt,
             "Descriptor [" & $sock & "] is not registered in the queue!")

template pollRemove[T](s: Selector[T], sock: cint) =
  withPollLock(s):
    var i = 0
    while i < s.pollcnt:
      if s.pollfds[i].fd == sock:
        if i == s.pollcnt - 1:
          s.pollfds[i].fd = 0
          s.pollfds[i].events = 0
          s.pollfds[i].revents = 0
        else:
          while i < (s.pollcnt - 1):
            s.pollfds[i].fd = s.pollfds[i + 1].fd
            s.pollfds[i].events = s.pollfds[i + 1].events
            inc(i)
        break
      inc(i)
    dec(s.pollcnt)
    dec(s.count)

template checkFd(s, f) =
  if f >= s.maxFD:
    raiseIOSelectorsError("Maximum number of descriptors is exhausted!")

proc registerHandle*[T](s: Selector[T], fd: int | SocketHandle,
                        events: set[Event], data: T) =
  var fdi = int(fd)
  s.checkFd(fdi)
  doAssert(s.fds[fdi].ident == InvalidIdent)
  setKey(s, fdi, events, 0, data)
  if events != {}: s.pollAdd(fdi.cint, events)

proc updateHandle*[T](s: Selector[T], fd: int | SocketHandle,
                      events: set[Event]) =
  let maskEvents = {Event.Timer, Event.Signal, Event.Process, Event.Vnode,
                    Event.User, Event.Oneshot, Event.Error}
  let fdi = int(fd)
  s.checkFd(fdi)
  var pkey = addr(s.fds[fdi])
  doAssert(pkey.ident != InvalidIdent,
           "Descriptor [" & $fdi & "] is not registered in the queue!")
  doAssert(pkey.events * maskEvents == {})

  if pkey.events != events:
    if pkey.events == {}:
      s.pollAdd(fd.cint, events)
    else:
      if events != {}:
        s.pollUpdate(fd.cint, events)
      else:
        s.pollRemove(fd.cint)
    pkey.events = events

proc registerEvent*[T](s: Selector[T], ev: SelectEvent, data: T) =
  var fdi = int(ev.rfd)
  doAssert(s.fds[fdi].ident == InvalidIdent, "Event is already registered in the queue!")
  var events = {Event.User}
  setKey(s, fdi, events, 0, data)
  events.incl(Event.Read)
  s.pollAdd(fdi.cint, events)

proc unregister*[T](s: Selector[T], fd: int|SocketHandle) =
  let fdi = int(fd)
  s.checkFd(fdi)
  var pkey = addr(s.fds[fdi])
  doAssert(pkey.ident != InvalidIdent,
           "Descriptor [" & $fdi & "] is not registered in the queue!")
  pkey.ident = InvalidIdent
  if pkey.events != {}:
    pkey.events = {}
    s.pollRemove(fdi.cint)

proc unregister*[T](s: Selector[T], ev: SelectEvent) =
  let fdi = int(ev.rfd)
  s.checkFd(fdi)
  var pkey = addr(s.fds[fdi])
  doAssert(pkey.ident != InvalidIdent, "Event is not registered in the queue!")
  doAssert(Event.User in pkey.events)
  pkey.ident = InvalidIdent
  pkey.events = {}
  s.pollRemove(fdi.cint)

proc newSelectEvent*(): SelectEvent =
  when not hasEventFds: 
    var fds: array[2, cint]
    if posix.pipe(fds) != 0:
      raiseIOSelectorsError(osLastError())
    setNonBlocking(fds[0])
    setNonBlocking(fds[1])
    result = cast[SelectEvent](allocShared0(sizeof(SelectEventImpl)))
    result.rfd = fds[0]
    result.wfd = fds[1]
  else: 
    let fdci = eventfd(0, posix.O_NONBLOCK)
    if fdci == -1:
      raiseIOSelectorsError(osLastError())
    result = cast[SelectEvent](allocShared0(sizeof(SelectEventImpl)))
    result.rfd = fdci
    result.wfd = fdci

proc trigger*(ev: SelectEvent) =
  var data: uint64 = 1
  if posix.write(ev.wfd, addr data, sizeof(uint64)) != sizeof(uint64):
    raiseIOSelectorsError(osLastError())

proc close*(ev: SelectEvent) =
  let res1 = posix.close(ev.rfd)
  let res2 = 
    when  hasEventFds: 0
    else: posix.close(ev.wfd)

  deallocShared(cast[pointer](ev))
  if res1 != 0 or res2 != 0:
    raiseIOSelectorsError(osLastError())

proc selectInto*[T](s: Selector[T], timeout: int,
                    results: var openArray[ReadyKey]): int =
  var maxres = MAX_POLL_EVENTS
  if maxres > len(results):
    maxres = len(results)

  verifySelectParams(timeout)

  s.withPollLock():
    let count = posix.poll(addr(s.pollfds[0]), Tnfds(s.pollcnt), cint(timeout))
    if count < 0:
      result = 0
      let err = osLastError()
      if cint(err) != EINTR:
        raiseIOSelectorsError(err)
    elif count == 0:
      result = 0
    else:
      var i = 0
      var k = 0
      var rindex = 0
      while (i < s.pollcnt) and (k < count) and (rindex < maxres):
        let revents = s.pollfds[i].revents
        if revents != 0:
          let fd = s.pollfds[i].fd
          var pkey = addr(s.fds[fd])
          var rkey = ReadyKey(fd: int(fd), events: {})

          if (revents and POLLIN) != 0:
            rkey.events.incl(Event.Read)
            if Event.User in pkey.events:
              var data: uint64 = 0
              if posix.read(fd, addr data, sizeof(uint64)) != sizeof(uint64):
                let err = osLastError()
                if err != OSErrorCode(EAGAIN):
                  raiseIOSelectorsError(err)
                else:
                  # someone already consumed event data
                  inc(i)
                  continue
              rkey.events = {Event.User}
          if (revents and POLLOUT) != 0:
            rkey.events.incl(Event.Write)
          if (revents and POLLERR) != 0 or (revents and POLLHUP) != 0 or
             (revents and POLLNVAL) != 0:
            rkey.events.incl(Event.Error)
          results[rindex] = rkey
          s.pollfds[i].revents = 0
          inc(rindex)
          inc(k)
        inc(i)
      result = k

proc select*[T](s: Selector[T], timeout: int): seq[ReadyKey] =
  result = newSeq[ReadyKey](MAX_POLL_EVENTS)
  let count = selectInto(s, timeout, result)
  result.setLen(count)

template isEmpty*[T](s: Selector[T]): bool =
  (s.count == 0)

proc contains*[T](s: Selector[T], fd: SocketHandle|int): bool {.inline.} =
  return s.fds[fd.int].ident != InvalidIdent

proc getData*[T](s: Selector[T], fd: SocketHandle|int): var T =
  let fdi = int(fd)
  s.checkFd(fdi)
  if fdi in s:
    result = s.fds[fdi].data

proc setData*[T](s: Selector[T], fd: SocketHandle|int, data: T): bool =
  let fdi = int(fd)
  s.checkFd(fdi)
  if fdi in s:
    s.fds[fdi].data = data
    result = true

template withData*[T](s: Selector[T], fd: SocketHandle|int, value,
                        body: untyped) =
  mixin checkFd
  let fdi = int(fd)
  s.checkFd(fdi)
  if fdi in s:
    var value = addr(s.getData(fdi))
    body

template withData*[T](s: Selector[T], fd: SocketHandle|int, value, body1,
                        body2: untyped) =
  mixin checkFd
  let fdi = int(fd)
  s.checkFd(fdi)
  if fdi in s:
    var value = addr(s.getData(fdi))
    body1
  else:
    body2


proc getFd*[T](s: Selector[T]): int =
  return -1
