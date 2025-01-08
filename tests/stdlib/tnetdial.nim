discard """
  cmd: "nim c --threads:on $file"
  exitcode: 0
  output: "OK"
"""

import os, net, nativesockets, asyncdispatch
import std/[assertions, typedthreads]

## Test for net.dial

const port = Port(28431)

proc initIPv6Server(hostname: string, port: Port): AsyncFD =
  let fd = createNativeSocket(AF_INET6)
  setSockOptInt(fd, SOL_SOCKET, SO_REUSEADDR, 1)
  var aiList = getAddrInfo(hostname, port, AF_INET6)
  if bindAddr(fd, aiList.ai_addr, aiList.ai_addrlen.SockLen) < 0'i32:
    freeAddrInfo(aiList)
    raiseOSError(osLastError())
  freeAddrInfo(aiList)
  if listen(fd) != 0:
    raiseOSError(osLastError())
  setBlocking(fd, false)

  var serverFd = fd.AsyncFD
  register(serverFd)
  result = serverFd

# Since net.dial is synchronous, we use main thread to setup server,
# and dial to it from another thread.

proc testThread() {.thread.} =
  let fd = net.dial("::1", port)
  var s = newString(5)
  doAssert fd.recv(addr s[0], 5) == 5
  if s == "Hello":
    echo "OK"
  fd.close()

proc test() =
  let serverFd = initIPv6Server("::1", port)
  var t: Thread[void] = default(Thread[void])
  createThread(t, testThread)

  var done = false

  serverFd.accept().callback = proc(fut: Future[AsyncFD]) =
    serverFd.closeSocket()
    if not fut.failed:
      let fd = fut.read()
      fd.send("Hello").callback = proc() =
        fd.closeSocket()
        done = true

  while not done:
    poll()

  joinThread(t)

# this would cause #13132 `for i in 0..<10000: test()`
test()
