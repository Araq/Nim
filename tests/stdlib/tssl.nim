discard """
  matrix: "--mm:refc; --mm:orc"
  joinable: false
  disabled: "freebsd" # see #15713
  disabled: "openbsd" # see #15713
  disabled: "netbsd" # see #15713
"""

import std/[net, nativesockets, assertions, typedthreads]

when defined(posix): import os, posix
else:
  import winlean
  const SD_SEND = 1

when not defined(ssl):
  {.error: "This test must be compiled with -d:ssl".}

const DummyData = "dummy data\n"

proc abruptShutdown(port: Port) {.thread.} =
  let clientContext = newContext(verifyMode = CVerifyNone)
  var client = newSocket(buffered = false)
  clientContext.wrapSocket(client)
  client.connect("localhost", port)

  discard client.recvLine()
  client.getFd.close()

proc notifiedShutdown(port: Port) {.thread.} =
  let clientContext = newContext(verifyMode = CVerifyNone)
  var client = newSocket(buffered = false)
  clientContext.wrapSocket(client)
  client.connect("localhost", port)

  discard client.recvLine()
  client.close()

proc main() =
  when defined(posix):
    var
      ignoreAction = Sigaction(sa_handler: SIG_IGN)
      oldSigPipeHandler: Sigaction = default(Sigaction)
    if sigemptyset(ignoreAction.sa_mask) == -1:
      raiseOSError(osLastError(), "Couldn't create an empty signal set")
    if sigaction(SIGPIPE, ignoreAction, oldSigPipeHandler) == -1:
      raiseOSError(osLastError(), "Couldn't ignore SIGPIPE")

  let serverContext = newContext(verifyMode = CVerifyNone,
                                 certFile = "tests/testdata/mycert.pem",
                                 keyFile = "tests/testdata/mycert.pem")

  block peer_close_during_write_without_shutdown:
    var server = newSocket(buffered = false)
    defer: server.close()
    serverContext.wrapSocket(server)
    server.bindAddr(address = "localhost")
    let (_, port) = server.getLocalAddr()
    server.listen()

    var clientThread: Thread[Port] = default(Thread[Port])
    createThread(clientThread, abruptShutdown, port)

    var peer: Socket = default(Socket)
    try:
      server.accept(peer)
      peer.send(DummyData)

      joinThread clientThread

      while true:
        # Send data until we get EPIPE.
        peer.send(DummyData, {})
    except OSError:
      discard
    finally:
      peer.close()

  when defined(posix):
    if sigaction(SIGPIPE, oldSigPipeHandler, nil) == -1:
      raiseOSError(osLastError(), "Couldn't restore SIGPIPE handler")

  block peer_close_before_received_shutdown:
    var server = newSocket(buffered = false)
    defer: server.close()
    serverContext.wrapSocket(server)
    server.bindAddr(address = "localhost")
    let (_, port) = server.getLocalAddr()
    server.listen()

    var clientThread: Thread[Port] = default(Thread[Port])
    createThread(clientThread, abruptShutdown, port)

    var peer: Socket = default(Socket)
    try:
      server.accept(peer)
      peer.send(DummyData)

      joinThread clientThread

      # Tell the OS to close off the write side so shutdown attempts will
      # be met with SIGPIPE.
      when defined(posix):
        discard peer.getFd.shutdown(SHUT_WR)
      else:
        discard peer.getFd.shutdown(SD_SEND)
    finally:
      peer.close()

  block peer_close_after_received_shutdown:
    var server = newSocket(buffered = false)
    defer: server.close()
    serverContext.wrapSocket(server)
    server.bindAddr(address = "localhost")
    let (_, port) = server.getLocalAddr()
    server.listen()

    var clientThread: Thread[Port] = default(Thread[Port])
    createThread(clientThread, notifiedShutdown, port)

    var peer: Socket = default(Socket)
    try:
      server.accept(peer)
      peer.send(DummyData)

      doAssert peer.recv(1024) == "" # Get the shutdown notification
      joinThread clientThread

      # Tell the OS to close off the write side so shutdown attempts will
      # be met with SIGPIPE.
      when defined(posix):
        discard peer.getFd.shutdown(SHUT_WR)
      else:
        discard peer.getFd.shutdown(SD_SEND)
    finally:
      peer.close()

when isMainModule: main()
