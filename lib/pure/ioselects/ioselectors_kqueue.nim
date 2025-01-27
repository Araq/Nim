#
#
#            Nim's Runtime Library
#        (c) Copyright 2016 Eugene Kabanov
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

#  This module implements BSD kqueue().

import std/[posix, times, kqueue, nativesockets]

const
  # Maximum number of events that can be returned.
  MAX_KQUEUE_EVENTS = 64
  # SIG_IGN and SIG_DFL declared in posix.nim as variables, but we need them
  # to be constants and GC-safe.
  SIG_DFL = cast[proc(x: cint) {.noconv,gcsafe.}](0)
  SIG_IGN = cast[proc(x: cint) {.noconv,gcsafe.}](1)

when defined(kqcache):
  const CACHE_EVENTS = true

when defined(macosx) or defined(freebsd) or defined(dragonfly):
  when defined(macosx):
    const MAX_DESCRIPTORS_ID = 29 # KERN_MAXFILESPERPROC (MacOS)
  else:
    const MAX_DESCRIPTORS_ID = 27 # KERN_MAXFILESPERPROC (FreeBSD)
  proc sysctl(name: ptr cint, namelen: cuint, oldp: pointer, oldplen: ptr csize_t,
              newp: pointer, newplen: csize_t): cint
       {.importc: "sysctl",header: """#include <sys/types.h>
                                      #include <sys/sysctl.h>""".}
elif defined(netbsd) or defined(openbsd):
  # OpenBSD and NetBSD don't have KERN_MAXFILESPERPROC, so we are using
  # KERN_MAXFILES, because KERN_MAXFILES is always bigger,
  # than KERN_MAXFILESPERPROC.
  const MAX_DESCRIPTORS_ID = 7 # KERN_MAXFILES
  proc sysctl(name: ptr cint, namelen: cuint, oldp: pointer, oldplen: ptr csize_t,
              newp: pointer, newplen: csize_t): cint
       {.importc: "sysctl",header: """#include <sys/param.h>
                                      #include <sys/sysctl.h>""".}

when hasThreadSupport:
  type
    SelectorImpl[T] = object
      kqFD: cint
      maxFD: int
      changes: ptr SharedArray[KEvent]
      fds: ptr SharedArray[SelectorKey[T]]
      count*: int
      changesLock: Lock
      changesSize: int
      changesLength: int
      sock: cint
    Selector*[T] = ptr SelectorImpl[T]
else:
  type
    SelectorImpl[T] = object
      kqFD: cint
      maxFD: int
      changes: seq[KEvent]
      fds: seq[SelectorKey[T]]
      count*: int
      sock: cint
    Selector*[T] = ref SelectorImpl[T]

type
  SelectEventImpl = object
    rfd: cint
    wfd: cint

  SelectEvent* = ptr SelectEventImpl
  # SelectEvent is declared as `ptr` to be placed in `shared memory`,
  # so you can share one SelectEvent handle between threads.

proc getUnique[T](s: Selector[T]): int {.inline.} =
  # we create duplicated handles to get unique indexes for our `fds` array.
  result = posix.fcntl(s.sock, F_DUPFD_CLOEXEC, s.sock)
  if result == -1:
    raiseIOSelectorsError(osLastError())

proc newSelector*[T](): owned(Selector[T]) =
  var maxFD = 0.cint
  var size = csize_t(sizeof(cint))
  var namearr = [1.cint, MAX_DESCRIPTORS_ID.cint]
  # Obtain maximum number of opened file descriptors for process
  if sysctl(addr(namearr[0]), 2, cast[pointer](addr maxFD), addr size,
            nil, 0) != 0:
    raiseIOSelectorsError(osLastError())

  var kqFD = kqueue()
  if kqFD < 0:
    raiseIOSelectorsError(osLastError())

  # we allocating empty socket to duplicate it handle in future, to get unique
  # indexes for `fds` array. This is needed to properly identify
  # {Event.Timer, Event.Signal, Event.Process} events.
  let usock = createNativeSocket(posix.AF_INET, posix.SOCK_STREAM,
                                 posix.IPPROTO_TCP).cint
  if usock == -1:
    let err = osLastError()
    discard posix.close(kqFD)
    raiseIOSelectorsError(err)

  when hasThreadSupport:
    result = cast[Selector[T]](allocShared0(sizeof(SelectorImpl[T])))
    result.fds = allocSharedArray[SelectorKey[T]](maxFD)
    result.changes = allocSharedArray[KEvent](MAX_KQUEUE_EVENTS)
    result.changesSize = MAX_KQUEUE_EVENTS
    initLock(result.changesLock)
  else:
    result = Selector[T]()
    result.fds = newSeq[SelectorKey[T]](maxFD)
    result.changes = newSeqOfCap[KEvent](MAX_KQUEUE_EVENTS)

  for i in 0 ..< maxFD:
    result.fds[i].ident = InvalidIdent

  result.sock = usock
  result.kqFD = kqFD
  result.maxFD = maxFD.int

proc close*[T](s: Selector[T]) =
  let res1 = posix.close(s.kqFD)
  let res2 = posix.close(s.sock)
  when hasThreadSupport:
    deinitLock(s.changesLock)
    deallocSharedArray(s.fds)
    deallocShared(cast[pointer](s))
  if res1 != 0 or res2 != 0:
    raiseIOSelectorsError(osLastError())

proc newSelectEvent*(): SelectEvent =
  var fds: array[2, cint]
  if posix.pipe(fds) != 0:
    raiseIOSelectorsError(osLastError())
  setNonBlocking(fds[0])
  setNonBlocking(fds[1])
  result = cast[SelectEvent](allocShared0(sizeof(SelectEventImpl)))
  result.rfd = fds[0]
  result.wfd = fds[1]

proc trigger*(ev: SelectEvent) =
  var data: uint64 = 1
  if posix.write(ev.wfd, addr data, sizeof(uint64)) != sizeof(uint64):
    raiseIOSelectorsError(osLastError())

proc close*(ev: SelectEvent) =
  let res1 = posix.close(ev.rfd)
  let res2 = posix.close(ev.wfd)
  deallocShared(cast[pointer](ev))
  if res1 != 0 or res2 != 0:
    raiseIOSelectorsError(osLastError())

template checkFd(s, f) =
  if f >= s.maxFD:
    raiseIOSelectorsError("Maximum number of descriptors is exhausted!")

when hasThreadSupport:
  template withChangeLock[T](s: Selector[T], body: untyped) =
    acquire(s.changesLock)
    {.locks: [s.changesLock].}:
      try:
        body
      finally:
        release(s.changesLock)
else:
  template withChangeLock(s, body: untyped) =
    body

when hasThreadSupport:
  template modifyKQueue[T](s: Selector[T], nident: uint, nfilter: cshort,
                           nflags: cushort, nfflags: cuint, ndata: int,
                           nudata: pointer) =
    mixin withChangeLock
    s.withChangeLock():
      if s.changesLength == s.changesSize:
        # if cache array is full, we allocating new with size * 2
        let newSize = s.changesSize shl 1
        let rdata = allocSharedArray[KEvent](newSize)
        copyMem(rdata, s.changes, s.changesSize * sizeof(KEvent))
        s.changesSize = newSize
      s.changes[s.changesLength] = KEvent(ident: nident,
                                          filter: nfilter, flags: nflags,
                                          fflags: nfflags, data: ndata,
                                          udata: nudata)
      inc(s.changesLength)

  when not declared(CACHE_EVENTS):
    template flushKQueue[T](s: Selector[T]) =
      mixin withChangeLock
      s.withChangeLock():
        if s.changesLength > 0:
          if kevent(s.kqFD, addr(s.changes[0]), cint(s.changesLength),
                    nil, 0, nil) == -1:
            let res = osLastError()
            if cint(res) != ENOENT: # ignore pipes whose read end is closed
              raiseIOSelectorsError(res)
          s.changesLength = 0
else:
  template modifyKQueue[T](s: Selector[T], nident: uint, nfilter: cshort,
                           nflags: cushort, nfflags: cuint, ndata: int,
                           nudata: pointer) =
    s.changes.add(KEvent(ident: nident,
                         filter: nfilter, flags: nflags,
                         fflags: nfflags, data: ndata,
                         udata: nudata))

  when not declared(CACHE_EVENTS):
    template flushKQueue[T](s: Selector[T]) =
      let length = cint(len(s.changes))
      if length > 0:
        if kevent(s.kqFD, addr(s.changes[0]), length,
                  nil, 0, nil) == -1:
          let res = osLastError()
          if cint(res) != ENOENT: # ignore pipes whose read end is closed
            raiseIOSelectorsError(res)
        s.changes.setLen(0)

proc registerHandle*[T](s: Selector[T], fd: int | SocketHandle,
                        events: set[Event], data: T) =
  let fdi = int(fd)
  s.checkFd(fdi)
  doAssert(s.fds[fdi].ident == InvalidIdent)
  s.setKey(fdi, events, 0, data)

  if events != {}:
    if Event.Read in events:
      modifyKQueue(s, uint(fdi), EVFILT_READ, EV_ADD, 0, 0, nil)
      inc(s.count)
    if Event.Write in events:
      modifyKQueue(s, uint(fdi), EVFILT_WRITE, EV_ADD, 0, 0, nil)
      inc(s.count)

    when not declared(CACHE_EVENTS):
      flushKQueue(s)

proc updateHandle*[T](s: Selector[T], fd: int | SocketHandle,
                      events: set[Event]) =
  let maskEvents = {Event.Timer, Event.Signal, Event.Process, Event.Vnode,
                    Event.User, Event.Oneshot, Event.Error}
  let fdi = int(fd)
  s.checkFd(fdi)
  var pkey = addr(s.fds[fdi])
  doAssert(pkey.ident != InvalidIdent,
           "Descriptor $# is not registered in the queue!" % $fdi)
  doAssert(pkey.events * maskEvents == {})

  if pkey.events != events:
    if (Event.Read in pkey.events) and (Event.Read notin events):
      modifyKQueue(s, fdi.uint, EVFILT_READ, EV_DELETE, 0, 0, nil)
      dec(s.count)
    if (Event.Write in pkey.events) and (Event.Write notin events):
      modifyKQueue(s, fdi.uint, EVFILT_WRITE, EV_DELETE, 0, 0, nil)
      dec(s.count)
    if (Event.Read notin pkey.events) and (Event.Read in events):
      modifyKQueue(s, fdi.uint, EVFILT_READ, EV_ADD, 0, 0, nil)
      inc(s.count)
    if (Event.Write notin pkey.events) and (Event.Write in events):
      modifyKQueue(s, fdi.uint, EVFILT_WRITE, EV_ADD, 0, 0, nil)
      inc(s.count)

    when not declared(CACHE_EVENTS):
      flushKQueue(s)

    pkey.events = events

proc registerTimer*[T](s: Selector[T], timeout: int, oneshot: bool,
                       data: T): int {.discardable.} =
  let fdi = getUnique(s)
  s.checkFd(fdi)
  doAssert(s.fds[fdi].ident == InvalidIdent)

  let events = if oneshot: {Event.Timer, Event.Oneshot} else: {Event.Timer}
  let flags: cushort = if oneshot: EV_ONESHOT or EV_ADD else: EV_ADD

  s.setKey(fdi, events, 0, data)

  # EVFILT_TIMER on Open/Net(BSD) has granularity of only milliseconds,
  # but MacOS and FreeBSD allow use `0` as `fflags` to use milliseconds
  # too
  modifyKQueue(s, fdi.uint, EVFILT_TIMER, flags, 0, cint(timeout), nil)

  when not declared(CACHE_EVENTS):
    flushKQueue(s)

  inc(s.count)
  result = fdi

proc registerSignal*[T](s: Selector[T], signal: int,
                        data: T): int {.discardable.} =
  let fdi = getUnique(s)
  s.checkFd(fdi)
  doAssert(s.fds[fdi].ident == InvalidIdent)

  s.setKey(fdi, {Event.Signal}, signal, data)
  var nmask, omask: Sigset
  discard sigemptyset(nmask)
  discard sigemptyset(omask)
  discard sigaddset(nmask, cint(signal))
  blockSignals(nmask, omask)
  # to be compatible with linux semantic we need to "eat" signals
  posix.signal(cint(signal), SIG_IGN)

  modifyKQueue(s, signal.uint, EVFILT_SIGNAL, EV_ADD, 0, 0,
               cast[pointer](fdi))

  when not declared(CACHE_EVENTS):
    flushKQueue(s)

  inc(s.count)
  result = fdi

proc registerProcess*[T](s: Selector[T], pid: int,
                         data: T): int {.discardable.} =
  let fdi = getUnique(s)
  s.checkFd(fdi)
  doAssert(s.fds[fdi].ident == InvalidIdent)

  var kflags: cushort = EV_ONESHOT or EV_ADD
  setKey(s, fdi, {Event.Process, Event.Oneshot}, pid, data)

  modifyKQueue(s, pid.uint, EVFILT_PROC, kflags, NOTE_EXIT, 0,
               cast[pointer](fdi))

  when not declared(CACHE_EVENTS):
    flushKQueue(s)

  inc(s.count)
  result = fdi

proc registerEvent*[T](s: Selector[T], ev: SelectEvent, data: T) =
  let fdi = ev.rfd.int
  doAssert(s.fds[fdi].ident == InvalidIdent, "Event is already registered in the queue!")
  setKey(s, fdi, {Event.User}, 0, data)

  modifyKQueue(s, fdi.uint, EVFILT_READ, EV_ADD, 0, 0, nil)

  when not declared(CACHE_EVENTS):
    flushKQueue(s)

  inc(s.count)

template processVnodeEvents(events: set[Event]): cuint =
  var rfflags = 0.cuint
  if events == {Event.VnodeWrite, Event.VnodeDelete, Event.VnodeExtend,
                Event.VnodeAttrib, Event.VnodeLink, Event.VnodeRename,
                Event.VnodeRevoke}:
    rfflags = NOTE_DELETE or NOTE_WRITE or NOTE_EXTEND or NOTE_ATTRIB or
              NOTE_LINK or NOTE_RENAME or NOTE_REVOKE
  else:
    if Event.VnodeDelete in events: rfflags = rfflags or NOTE_DELETE
    if Event.VnodeWrite in events: rfflags = rfflags or NOTE_WRITE
    if Event.VnodeExtend in events: rfflags = rfflags or NOTE_EXTEND
    if Event.VnodeAttrib in events: rfflags = rfflags or NOTE_ATTRIB
    if Event.VnodeLink in events: rfflags = rfflags or NOTE_LINK
    if Event.VnodeRename in events: rfflags = rfflags or NOTE_RENAME
    if Event.VnodeRevoke in events: rfflags = rfflags or NOTE_REVOKE
  rfflags

proc registerVnode*[T](s: Selector[T], fd: cint, events: set[Event], data: T) =
  let fdi = fd.int
  setKey(s, fdi, {Event.Vnode} + events, 0, data)
  var fflags = processVnodeEvents(events)

  modifyKQueue(s, fdi.uint, EVFILT_VNODE, EV_ADD or EV_CLEAR, fflags, 0, nil)

  when not declared(CACHE_EVENTS):
    flushKQueue(s)

  inc(s.count)

proc unregister*[T](s: Selector[T], fd: int|SocketHandle) =
  let fdi = int(fd)
  s.checkFd(fdi)
  var pkey = addr(s.fds[fdi])
  doAssert(pkey.ident != InvalidIdent,
           "Descriptor [" & $fdi & "] is not registered in the queue!")

  if pkey.events != {}:
    if pkey.events * {Event.Read, Event.Write} != {}:
      if Event.Read in pkey.events:
        modifyKQueue(s, uint(fdi), EVFILT_READ, EV_DELETE, 0, 0, nil)
        dec(s.count)
      if Event.Write in pkey.events:
        modifyKQueue(s, uint(fdi), EVFILT_WRITE, EV_DELETE, 0, 0, nil)
        dec(s.count)
      when not declared(CACHE_EVENTS):
        flushKQueue(s)
    elif Event.Timer in pkey.events:
      if Event.Finished notin pkey.events:
        modifyKQueue(s, uint(fdi), EVFILT_TIMER, EV_DELETE, 0, 0, nil)
        when not declared(CACHE_EVENTS):
          flushKQueue(s)
        dec(s.count)
      if posix.close(cint(pkey.ident)) != 0:
        raiseIOSelectorsError(osLastError())
    elif Event.Signal in pkey.events:
      var nmask, omask: Sigset
      let signal = cint(pkey.param)
      discard sigemptyset(nmask)
      discard sigemptyset(omask)
      discard sigaddset(nmask, signal)
      unblockSignals(nmask, omask)
      posix.signal(signal, SIG_DFL)
      modifyKQueue(s, uint(pkey.param), EVFILT_SIGNAL, EV_DELETE, 0, 0, nil)
      when not declared(CACHE_EVENTS):
        flushKQueue(s)
      dec(s.count)
      if posix.close(cint(pkey.ident)) != 0:
        raiseIOSelectorsError(osLastError())
    elif Event.Process in pkey.events:
      if Event.Finished notin pkey.events:
        modifyKQueue(s, uint(pkey.param), EVFILT_PROC, EV_DELETE, 0, 0, nil)
        when not declared(CACHE_EVENTS):
          flushKQueue(s)
        dec(s.count)
      if posix.close(cint(pkey.ident)) != 0:
        raiseIOSelectorsError(osLastError())
    elif Event.Vnode in pkey.events:
      modifyKQueue(s, uint(fdi), EVFILT_VNODE, EV_DELETE, 0, 0, nil)
      when not declared(CACHE_EVENTS):
        flushKQueue(s)
      dec(s.count)
    elif Event.User in pkey.events:
      modifyKQueue(s, uint(fdi), EVFILT_READ, EV_DELETE, 0, 0, nil)
      when not declared(CACHE_EVENTS):
        flushKQueue(s)
      dec(s.count)

  clearKey(pkey)

proc unregister*[T](s: Selector[T], ev: SelectEvent) =
  let fdi = int(ev.rfd)
  s.checkFd(fdi)
  var pkey = addr(s.fds[fdi])
  doAssert(pkey.ident != InvalidIdent, "Event is not registered in the queue!")
  doAssert(Event.User in pkey.events)
  modifyKQueue(s, uint(fdi), EVFILT_READ, EV_DELETE, 0, 0, nil)
  when not declared(CACHE_EVENTS):
    flushKQueue(s)
  clearKey(pkey)
  dec(s.count)

proc selectInto*[T](s: Selector[T], timeout: int,
                    results: var openArray[ReadyKey]): int =
  var
    tv: Timespec
    resTable: array[MAX_KQUEUE_EVENTS, KEvent]
    ptv = addr tv
    maxres = MAX_KQUEUE_EVENTS

  verifySelectParams(timeout)

  if timeout != -1:
    if timeout >= 1000:
      tv.tv_sec = posix.Time(timeout div 1_000)
      tv.tv_nsec = (timeout %% 1_000) * 1_000_000
    else:
      tv.tv_sec = posix.Time(0)
      tv.tv_nsec = timeout * 1_000_000
  else:
    ptv = nil

  if maxres > len(results):
    maxres = len(results)

  var count = 0
  when not declared(CACHE_EVENTS):
    count = kevent(s.kqFD, nil, cint(0), addr(resTable[0]), cint(maxres), ptv)
  else:
    when hasThreadSupport:
      s.withChangeLock():
        if s.changesLength > 0:
          count = kevent(s.kqFD, addr(s.changes[0]), cint(s.changesLength),
                         addr(resTable[0]), cint(maxres), ptv)
          s.changesLength = 0
        else:
          count = kevent(s.kqFD, nil, cint(0), addr(resTable[0]), cint(maxres),
                         ptv)
    else:
      let length = cint(len(s.changes))
      if length > 0:
        count = kevent(s.kqFD, addr(s.changes[0]), length,
                       addr(resTable[0]), cint(maxres), ptv)
        s.changes.setLen(0)
      else:
        count = kevent(s.kqFD, nil, cint(0), addr(resTable[0]), cint(maxres),
                       ptv)

  if count < 0:
    result = 0
    let err = osLastError()
    if cint(err) != EINTR:
      raiseIOSelectorsError(err)
  elif count == 0:
    result = 0
  else:
    var i = 0
    var k = 0 # do not delete this, because `continue` used in cycle.
    var pkey: ptr SelectorKey[T]
    while i < count:
      let kevent = addr(resTable[i])
      var rkey = ReadyKey(fd: int(kevent.ident), events: {})

      if (kevent.flags and EV_ERROR) != 0:
        rkey.events = {Event.Error}
        rkey.errorCode = OSErrorCode(kevent.data)

      case kevent.filter:
      of EVFILT_READ:
        pkey = addr(s.fds[int(kevent.ident)])
        rkey.events.incl(Event.Read)
        if Event.User in pkey.events:
          var data: uint64 = 0
          if posix.read(cint(kevent.ident), addr data,
                        sizeof(uint64)) != sizeof(uint64):
            let err = osLastError()
            if err == OSErrorCode(EAGAIN):
              # someone already consumed event data
              inc(i)
              continue
            else:
              raiseIOSelectorsError(err)
          rkey.events = {Event.User}
      of EVFILT_WRITE:
        pkey = addr(s.fds[int(kevent.ident)])
        rkey.events.incl(Event.Write)
        rkey.events = {Event.Write}
      of EVFILT_TIMER:
        pkey = addr(s.fds[int(kevent.ident)])
        if Event.Oneshot in pkey.events:
          # we will not clear key until it will be unregistered, so
          # application can obtain data, but we will decrease counter,
          # because kqueue is empty.
          dec(s.count)
          # we are marking key with `Finished` event, to avoid double decrease.
          pkey.events.incl(Event.Finished)
        rkey.events.incl(Event.Timer)
      of EVFILT_VNODE:
        pkey = addr(s.fds[int(kevent.ident)])
        rkey.events.incl(Event.Vnode)
        if (kevent.fflags and NOTE_DELETE) != 0:
          rkey.events.incl(Event.VnodeDelete)
        if (kevent.fflags and NOTE_WRITE) != 0:
          rkey.events.incl(Event.VnodeWrite)
        if (kevent.fflags and NOTE_EXTEND) != 0:
          rkey.events.incl(Event.VnodeExtend)
        if (kevent.fflags and NOTE_ATTRIB) != 0:
          rkey.events.incl(Event.VnodeAttrib)
        if (kevent.fflags and NOTE_LINK) != 0:
          rkey.events.incl(Event.VnodeLink)
        if (kevent.fflags and NOTE_RENAME) != 0:
          rkey.events.incl(Event.VnodeRename)
        if (kevent.fflags and NOTE_REVOKE) != 0:
          rkey.events.incl(Event.VnodeRevoke)
      of EVFILT_SIGNAL:
        pkey = addr(s.fds[cast[int](kevent.udata)])
        rkey.fd = cast[int](kevent.udata)
        rkey.events.incl(Event.Signal)
      of EVFILT_PROC:
        rkey.fd = cast[int](kevent.udata)
        pkey = addr(s.fds[cast[int](kevent.udata)])
        # we will not clear key, until it will be unregistered, so
        # application can obtain data, but we will decrease counter,
        # because kqueue is empty.
        dec(s.count)
        # we are marking key with `Finished` event, to avoid double decrease.
        pkey.events.incl(Event.Finished)
        rkey.events.incl(Event.Process)
      else:
        doAssert(true, "Unsupported kqueue filter in the queue!")

      if (kevent.flags and EV_EOF) != 0:
        # TODO this error handling needs to be rethought.
        # `fflags` can sometimes be `0x80000000` and thus we use 'cast'
        # here:
        if kevent.fflags != 0:
          rkey.errorCode = cast[OSErrorCode](kevent.fflags)
        else:
          # This assumes we are dealing with sockets.
          # TODO: For future-proofing it might be a good idea to give the
          #       user access to the raw `kevent`.
          rkey.errorCode = OSErrorCode(ECONNRESET)
        rkey.events.incl(Event.Error)

      results[k] = rkey
      inc(k)
      inc(i)
    result = k

proc select*[T](s: Selector[T], timeout: int): seq[ReadyKey] =
  result = newSeq[ReadyKey](MAX_KQUEUE_EVENTS)
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
    var value = addr(s.fds[fdi].data)
    body

template withData*[T](s: Selector[T], fd: SocketHandle|int, value, body1,
                      body2: untyped) =
  mixin checkFd
  let fdi = int(fd)
  s.checkFd(fdi)
  if fdi in s:
    var value = addr(s.fds[fdi].data)
    body1
  else:
    body2


proc getFd*[T](s: Selector[T]): int =
  return s.kqFD.int
