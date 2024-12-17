discard """
  output: "All tests passed!"
"""
import selectors

const hasThreadSupport = compileOption("threads")

template processTest(t, x: untyped) =
  #stdout.write(t)
  #stdout.flushFile()
  if not x: echo(t & " FAILED\r\n")

when not defined(windows):
  import os, posix, nativesockets

  when ioselSupportedPlatform:
    import osproc

  proc socket_notification_test(): bool =
    proc create_test_socket(): SocketHandle =
      var sock = posix.socket(posix.AF_INET, posix.SOCK_STREAM,
                              posix.IPPROTO_TCP)
      var x: int = fcntl(sock, F_GETFL, 0)
      if x == -1: raiseOSError(osLastError())
      else:
        var mode = x or O_NONBLOCK
        if fcntl(sock, F_SETFL, mode) == -1:
          raiseOSError(osLastError())
      result = sock

    var client_message = "SERVER HELLO =>"
    var server_message = "CLIENT HELLO"
    var buffer : array[128, char]

    var selector = newSelector[int]()
    var client_socket = create_test_socket()
    var server_socket = create_test_socket()

    var option : int32 = 1
    if setsockopt(server_socket, cint(SOL_SOCKET), cint(SO_REUSEADDR),
                  addr(option), sizeof(option).SockLen) < 0:
      raiseOSError(osLastError())

    var aiList = getAddrInfo("0.0.0.0", Port(13337))
    if bindAddr(server_socket, aiList.ai_addr,
                aiList.ai_addrlen.Socklen) < 0'i32:
      freeAddrInfo(aiList)
      raiseOSError(osLastError())
    if server_socket.listen() == -1:
      raiseOSError(osLastError())
    freeAddrInfo(aiList)

    aiList = getAddrInfo("127.0.0.1", Port(13337))
    discard posix.connect(client_socket, aiList.ai_addr,
                          aiList.ai_addrlen.Socklen)

    registerHandle(selector, server_socket, {Event.Read}, 0)
    registerHandle(selector, client_socket, {Event.Write}, 0)

    freeAddrInfo(aiList)

    # make sure both sockets are selected
    var nevs = 0
    while nevs < 2:
      nevs += selector.select(100).len

    var sockAddress: SockAddr
    var addrLen = sizeof(sockAddress).Socklen
    var server2_socket = accept(server_socket,
                                cast[ptr SockAddr](addr(sockAddress)),
                                addr(addrLen))
    assert(server2_socket != osInvalidSocket)
    selector.registerHandle(server2_socket, {Event.Read}, 0)

    if posix.send(client_socket, addr(client_message[0]),
                  len(client_message), 0) == -1:
      raiseOSError(osLastError())

    selector.updateHandle(client_socket, {Event.Read})

    var rc2 = selector.select(100)
    assert(len(rc2) == 1)

    var read_count = posix.recv(server2_socket, addr buffer[0], 128, 0)
    if read_count == -1:
      raiseOSError(osLastError())

    assert(read_count == len(client_message))
    var test1 = true
    for i in 0..<read_count:
      if client_message[i] != buffer[i]:
        test1 = false
        break
    assert(test1)

    selector.updateHandle(server2_socket, {Event.Write})
    var rc3 = selector.select(0)
    assert(len(rc3) == 1)
    if posix.send(server2_socket, addr(server_message[0]),
                  len(server_message), 0) == -1:
      raiseOSError(osLastError())
    selector.updateHandle(server2_socket, {Event.Read})

    var rc4 = selector.select(100)
    assert(len(rc4) == 1)
    read_count = posix.recv(client_socket, addr(buffer[0]), 128, 0)
    if read_count == -1:
      raiseOSError(osLastError())

    assert(read_count == len(server_message))
    var test2 = true
    for i in 0..<read_count:
      if server_message[i] != buffer[i]:
        test2 = false
        break
    assert(test2)

    selector.unregister(server_socket)
    selector.unregister(server2_socket)
    selector.unregister(client_socket)
    discard posix.close(server_socket)
    discard posix.close(server2_socket)
    discard posix.close(client_socket)
    assert(selector.isEmpty())
    close(selector)
    result = true

  proc event_notification_test(): bool =
    var selector = newSelector[int]()
    var event = newSelectEvent()
    selector.registerEvent(event, 1)
    var rc0 = selector.select(0)
    event.trigger()
    var rc1 = selector.select(0)
    event.trigger()
    var rc2 = selector.select(0)
    var rc3 = selector.select(0)
    assert(len(rc0) == 0 and len(rc1) == 1 and len(rc2) == 1 and len(rc3) == 0)
    var ev1 = selector.getData(rc1[0].fd)
    var ev2 = selector.getData(rc2[0].fd)
    assert(ev1 == 1 and ev2 == 1)
    selector.unregister(event)
    event.close()
    assert(selector.isEmpty())
    selector.close()
    result = true

  when ioselSupportedPlatform:
    proc timer_notification_test(): bool =
      var selector = newSelector[int]()
      var timer = selector.registerTimer(100, false, 0)
      var rc1 = selector.select(10000)
      var rc2 = selector.select(10000)
      # if this flakes, see tests/m14634.nim
      assert len(rc1) == 1 and len(rc2) == 1, $(len(rc1), len(rc2))
      selector.unregister(timer)
      discard selector.select(0)
      selector.registerTimer(100, true, 0)
      var rc4 = selector.select(10000)
      var rc5 = selector.select(1000) # this will be an actual wait, keep it small
      assert len(rc4) == 1 and len(rc5) == 0, $(len(rc4), len(rc5))
      assert(selector.isEmpty())
      selector.close()
      result = true

    proc process_notification_test(): bool =
      var selector = newSelector[int]()
      var process2 = startProcess("sleep", "", ["2"], nil,
                           {poStdErrToStdOut, poUsePath})
      discard startProcess("sleep", "", ["1"], nil,
                           {poStdErrToStdOut, poUsePath})

      selector.registerProcess(process2.processID, 0)
      var rc1 = selector.select(1500)
      var rc2 = selector.select(1500)
      var r = len(rc1) + len(rc2)
      assert(r == 1)
      result = true

    proc signal_notification_test(): bool =
      var sigset1n, sigset1o, sigset2n, sigset2o: Sigset
      var pid = posix.getpid()

      discard sigemptyset(sigset1n)
      discard sigemptyset(sigset1o)
      discard sigemptyset(sigset2n)
      discard sigemptyset(sigset2o)

      when hasThreadSupport:
        if pthread_sigmask(SIG_BLOCK, sigset1n, sigset1o) == -1:
          raiseOSError(osLastError())
      else:
        if sigprocmask(SIG_BLOCK, sigset1n, sigset1o) == -1:
          raiseOSError(osLastError())

      var selector = newSelector[int]()
      var s1 = selector.registerSignal(SIGUSR1, 1)
      var s2 = selector.registerSignal(SIGUSR2, 2)
      var s3 = selector.registerSignal(SIGTERM, 3)
      discard selector.select(0)
      discard posix.kill(pid, SIGUSR1)
      discard posix.kill(pid, SIGUSR2)
      discard posix.kill(pid, SIGTERM)
      var rc = selector.select(0)
      var cd0 = selector.getData(rc[0].fd)
      var cd1 = selector.getData(rc[1].fd)
      var cd2 = selector.getData(rc[2].fd)
      selector.unregister(s1)
      selector.unregister(s2)
      selector.unregister(s3)

      when hasThreadSupport:
        if pthread_sigmask(SIG_BLOCK, sigset2n, sigset2o) == -1:
          raiseOSError(osLastError())
      else:
        if sigprocmask(SIG_BLOCK, sigset2n, sigset2o) == -1:
          raiseOSError(osLastError())

      assert(len(rc) == 3)
      assert(cd0 + cd1 + cd2 == 6, $(cd0 + cd1 + cd2)) # 1 + 2 + 3
      assert(equalMem(addr sigset1o, addr sigset2o, sizeof(Sigset)))
      assert(selector.isEmpty())
      result = true

  when defined(macosx) or defined(freebsd) or defined(openbsd) or
       defined(netbsd):

    proc rename(frompath: cstring, topath: cstring): cint
       {.importc: "rename", header: "<stdio.h>".}

    proc createFile(name: string): cint =
      result = posix.open(cstring(name), posix.O_CREAT or posix.O_RDWR)
      if result == -1:
        raiseOsError(osLastError())

    proc writeFile(name: string, data: string) =
      let fd = posix.open(cstring(name), posix.O_APPEND or posix.O_RDWR)
      if fd == -1:
        raiseOsError(osLastError())
      let length = len(data).cint
      if posix.write(fd, cast[pointer](addr data[0]),
                     len(data).cint) != length:
        raiseOsError(osLastError())
      if posix.close(fd) == -1:
        raiseOsError(osLastError())

    proc closeFile(fd: cint) =
      if posix.close(fd) == -1:
        raiseOsError(osLastError())

    proc removeFile(name: string) =
      let err = posix.unlink(cstring(name))
      if err == -1:
        raiseOsError(osLastError())

    proc createDir(name: string) =
      let err = posix.mkdir(cstring(name), 0x1FF)
      if err == -1:
        raiseOsError(osLastError())

    proc removeDir(name: string) =
      let err = posix.rmdir(cstring(name))
      if err == -1:
        raiseOsError(osLastError())

    proc chmodPath(name: string, mode: cint) =
      let err = posix.chmod(cstring(name), Mode(mode))
      if err == -1:
        raiseOsError(osLastError())

    proc renameFile(names: string, named: string) =
      let err = rename(cstring(names), cstring(named))
      if err == -1:
        raiseOsError(osLastError())

    proc symlink(names: string, named: string) =
      let err = posix.symlink(cstring(names), cstring(named))
      if err == -1:
        raiseOsError(osLastError())

    proc openWatch(name: string): cint =
      result = posix.open(cstring(name), posix.O_RDONLY)
      if result == -1:
        raiseOsError(osLastError())

    const
      testDirectory = "/tmp/kqtest"

    type
      valType = object
        fd: cint
        events: set[Event]

    proc vnode_test(): bool =
      proc validate(test: openArray[ReadyKey],
                    check: openArray[valType]): bool =
        result = false
        if len(test) == len(check):
          for checkItem in check:
            result = false
            for testItem in test:
              if testItem.fd == checkItem.fd and
                 checkItem.events <= testItem.events:
                result = true
                break
            if not result:
              break

      var res: seq[ReadyKey]
      var selector = newSelector[int]()
      var events = {Event.VnodeWrite, Event.VnodeDelete, Event.VnodeExtend,
                    Event.VnodeAttrib, Event.VnodeLink, Event.VnodeRename,
                    Event.VnodeRevoke}

      result = true
      discard posix.unlink(testDirectory)

      createDir(testDirectory)
      var dirfd = posix.open(cstring(testDirectory), posix.O_RDONLY)
      if dirfd == -1:
        raiseOsError(osLastError())

      selector.registerVnode(dirfd, events, 1)
      discard selector.select(0)

      # chmod testDirectory to 0777
      chmodPath(testDirectory, 0x1FF)
      res = selector.select(0)
      doAssert(len(res) == 1)
      doAssert(len(selector.select(0)) == 0)
      doAssert(res[0].fd == dirfd and
               {Event.Vnode, Event.VnodeAttrib} <= res[0].events)

      # create subdirectory
      createDir(testDirectory & "/test")
      res = selector.select(0)
      doAssert(len(res) == 1)
      doAssert(len(selector.select(0)) == 0)
      doAssert(res[0].fd == dirfd and
               {Event.Vnode, Event.VnodeWrite,
                Event.VnodeLink} <= res[0].events)

      # open test directory for watching
      var testfd = openWatch(testDirectory & "/test")
      selector.registerVnode(testfd, events, 2)
      doAssert(len(selector.select(0)) == 0)

      # rename test directory
      renameFile(testDirectory & "/test", testDirectory & "/renamed")
      res = selector.select(0)
      doAssert(len(res) == 2)
      doAssert(len(selector.select(0)) == 0)
      doAssert(validate(res,
                 [valType(fd: dirfd, events: {Event.Vnode, Event.VnodeWrite}),
                  valType(fd: testfd,
                          events: {Event.Vnode, Event.VnodeRename})])
              )

      # remove test directory
      removeDir(testDirectory & "/renamed")
      res = selector.select(0)
      doAssert(len(res) == 2)
      doAssert(len(selector.select(0)) == 0)
      doAssert(validate(res,
                 [valType(fd: dirfd, events: {Event.Vnode, Event.VnodeWrite,
                                              Event.VnodeLink}),
                  valType(fd: testfd,
                          events: {Event.Vnode, Event.VnodeDelete})])
              )
      # create file new test file
      testfd = createFile(testDirectory & "/testfile")
      res = selector.select(0)
      doAssert(len(res) == 1)
      doAssert(len(selector.select(0)) == 0)
      doAssert(res[0].fd == dirfd and
               {Event.Vnode, Event.VnodeWrite} <= res[0].events)

      # close new test file
      closeFile(testfd)
      doAssert(len(selector.select(0)) == 0)
      doAssert(len(selector.select(0)) == 0)

      # chmod test file with 0666
      chmodPath(testDirectory & "/testfile", 0x1B6)
      doAssert(len(selector.select(0)) == 0)

      testfd = openWatch(testDirectory & "/testfile")
      selector.registerVnode(testfd, events, 1)
      discard selector.select(0)

      # write data to test file
      writeFile(testDirectory & "/testfile", "TESTDATA")
      res = selector.select(0)
      doAssert(len(res) == 1)
      doAssert(len(selector.select(0)) == 0)
      doAssert(res[0].fd == testfd and
              {Event.Vnode, Event.VnodeWrite,
               Event.VnodeExtend} <= res[0].events)

      # symlink test file
      symlink(testDirectory & "/testfile", testDirectory & "/testlink")
      res = selector.select(0)
      doAssert(len(res) == 1)
      doAssert(len(selector.select(0)) == 0)
      doAssert(res[0].fd == dirfd and
               {Event.Vnode, Event.VnodeWrite} <= res[0].events)

      # remove test file
      removeFile(testDirectory & "/testfile")
      res = selector.select(0)
      doAssert(len(res) == 2)
      doAssert(len(selector.select(0)) == 0)
      doAssert(validate(res,
                [valType(fd: testfd, events: {Event.Vnode, Event.VnodeDelete}),
                 valType(fd: dirfd, events: {Event.Vnode, Event.VnodeWrite})])
              )

      # remove symlink
      removeFile(testDirectory & "/testlink")
      res = selector.select(0)
      doAssert(len(res) == 1)
      doAssert(len(selector.select(0)) == 0)
      doAssert(res[0].fd == dirfd and
               {Event.Vnode, Event.VnodeWrite} <= res[0].events)

      # remove testDirectory
      removeDir(testDirectory)
      res = selector.select(0)
      doAssert(len(res) == 1)
      doAssert(len(selector.select(0)) == 0)
      doAssert(res[0].fd == dirfd and
               {Event.Vnode, Event.VnodeDelete} <= res[0].events)

  proc pipe_test(): bool =
    # closing the read end of a pipe will result in it automatically
    # being removed from the kqueue; make sure no exception is raised
    var s = newSelector[int]()
    var fds: array[2, cint]
    discard pipe(fds)
    s.registerHandle(fds[1], {Write}, 0)
    discard close(fds[0])
    let res = s.select(-1)
    doAssert(res.len == 1)
    s.unregister(fds[1])
    discard close(fds[1])
    return true

  when hasThreadSupport:

    var counter = 0

    proc event_wait_thread(event: SelectEvent) {.thread.} =
      var selector = newSelector[int]()
      selector.registerEvent(event, 1)
      var rc = selector.select(1000)
      if len(rc) == 1:
        inc(counter)
      selector.unregister(event)
      assert(selector.isEmpty())

    proc mt_event_test(): bool =
      var
        thr: array[0..7, Thread[SelectEvent]]
      var selector = newSelector[int]()
      var sock = createNativeSocket()
      var event = newSelectEvent()
      for i in 0..high(thr):
        createThread(thr[i], event_wait_thread, event)
      selector.registerHandle(sock, {Event.Read}, 1)
      discard selector.select(500)
      selector.unregister(sock)
      event.trigger()
      joinThreads(thr)
      assert(counter == 1)
      result = true

  processTest("Socket notification test...", socket_notification_test())
  processTest("User event notification test...", event_notification_test())
  when hasThreadSupport:
    processTest("Multithreaded user event notification test...",
                mt_event_test())
  when ioselSupportedPlatform:
    processTest("Timer notification test...", timer_notification_test())
    processTest("Process notification test...", process_notification_test())
    processTest("Signal notification test...", signal_notification_test())
  when defined(macosx) or defined(freebsd) or defined(openbsd) or
       defined(netbsd):
    processTest("File notification test...", vnode_test())
    processTest("Pipe test...", pipe_test())
  echo("All tests passed!")
else:
  import nativesockets, winlean, os, osproc

  proc socket_notification_test(): bool =
    proc create_test_socket(): SocketHandle =
      var sock = createNativeSocket()
      setBlocking(sock, false)
      result = sock

    var client_message = "SERVER HELLO =>"
    var server_message = "CLIENT HELLO"
    var buffer : array[128, char]

    var selector = newSelector[int]()
    var client_socket = create_test_socket()
    var server_socket = create_test_socket()

    selector.registerHandle(server_socket, {Event.Read}, 0)
    selector.registerHandle(client_socket, {Event.Write}, 0)

    var option : int32 = 1
    if setsockopt(server_socket, cint(SOL_SOCKET), cint(SO_REUSEADDR),
                  addr(option), sizeof(option).SockLen) < 0:
      raiseOSError(osLastError())

    var aiList = getAddrInfo("0.0.0.0", Port(13337))
    if bindAddr(server_socket, aiList.ai_addr,
                aiList.ai_addrlen.Socklen) < 0'i32:
      freeAddrInfo(aiList)
      raiseOSError(osLastError())
    discard server_socket.listen()
    freeAddrInfo(aiList)

    aiList = getAddrInfo("127.0.0.1", Port(13337))
    discard connect(client_socket, aiList.ai_addr,
                    aiList.ai_addrlen.Socklen)
    freeAddrInfo(aiList)
    # for some reason Windows select doesn't return both
    # descriptors from first call, so we need to make 2 calls
    var n = 0
    var rcm = selector.select(1000)
    while n < 10 and len(rcm) < 2:
      sleep(1000)
      rcm = selector.select(1000)
      inc(n)

    assert(len(rcm) == 2)

    var sockAddress = SockAddr()
    var addrLen = sizeof(sockAddress).Socklen
    var server2_socket = accept(server_socket,
                                cast[ptr SockAddr](addr(sockAddress)),
                                addr(addrLen))
    assert(server2_socket != osInvalidSocket)
    selector.registerHandle(server2_socket, {Event.Read}, 0)

    if send(client_socket, cast[pointer](addr(client_message[0])),
            cint(len(client_message)), 0) == -1:
      raiseOSError(osLastError())

    selector.updateHandle(client_socket, {Event.Read})

    var rc2 = selector.select(1000)
    assert(len(rc2) == 1)

    var read_count = recv(server2_socket, addr buffer[0], 128, 0)
    if read_count == -1:
      raiseOSError(osLastError())

    assert(read_count == len(client_message))
    var test1 = true
    for i in 0..<read_count:
      if client_message[i] != buffer[i]:
        test1 = false
        break
    assert(test1)

    if send(server2_socket, cast[pointer](addr(server_message[0])),
                  cint(len(server_message)), 0) == -1:
      raiseOSError(osLastError())

    var rc3 = selector.select(0)
    assert(len(rc3) == 1)
    read_count = recv(client_socket, addr(buffer[0]), 128, 0)
    if read_count == -1:
      raiseOSError(osLastError())

    assert(read_count == len(server_message))
    var test2 = true
    for i in 0..<read_count:
      if server_message[i] != buffer[i]:
        test2 = false
        break
    assert(test2)

    selector.unregister(server_socket)
    selector.unregister(server2_socket)
    selector.unregister(client_socket)
    close(server_socket)
    close(server2_socket)
    close(client_socket)
    assert(selector.isEmpty())
    close(selector)
    result = true

  proc event_notification_test(): bool =
    var selector = newSelector[int]()
    var event = newSelectEvent()
    selector.registerEvent(event, 1)
    discard selector.select(0)
    event.trigger()
    var rc1 = selector.select(0)
    event.trigger()
    var rc2 = selector.select(0)
    var rc3 = selector.select(0)
    assert(len(rc1) == 1 and len(rc2) == 1 and len(rc3) == 0)
    var ev1 = selector.getData(rc1[0].fd)
    var ev2 = selector.getData(rc2[0].fd)
    assert(ev1 == 1 and ev2 == 1)
    selector.unregister(event)
    event.close()
    assert(selector.isEmpty())
    selector.close()
    result = true

  when hasThreadSupport:
    var counter = 0

    proc event_wait_thread(event: SelectEvent) {.thread.} =
      var selector = newSelector[int]()
      selector.registerEvent(event, 1)
      var rc = selector.select(1500)
      if len(rc) == 1:
        inc(counter)
      selector.unregister(event)
      assert(selector.isEmpty())

    proc mt_event_test(): bool =
      var thr: array[0..7, Thread[SelectEvent]]
      var event = newSelectEvent()
      for i in 0..high(thr):
        createThread(thr[i], event_wait_thread, event)
      event.trigger()
      joinThreads(thr)
      assert(counter == 1)
      result = true

  processTest("Socket notification test...", socket_notification_test())
  processTest("User event notification test...", event_notification_test())
  when hasThreadSupport:
    processTest("Multithreaded user event notification test...",
                 mt_event_test())
  echo("All tests passed!")
