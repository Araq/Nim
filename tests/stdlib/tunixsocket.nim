import std/[assertions, net, os, osproc]

# XXX: Make this test run on Windows too when we add support for Unix sockets on Windows
when defined(posix) and not defined(nimNetLite):
  const nim = getCurrentCompilerExe()
  let
    dir = currentSourcePath().parentDir()
    serverPath = dir / "unixsockettest"

  let (_, err) = execCmdEx(nim & " c " & quoteShell(dir / "unixsockettest.nim"))
  doAssert err == 0

  let svproc = startProcess(serverPath, workingDir = dir)
  doAssert svproc.running()
  # Wait for the server to open the socket and listen from it
  sleep(400)

  block unixSocketSendRecv:
    let
      unixSocketPath = dir / "usox"
      socket = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_NONE)

    socket.connectUnix(unixSocketPath)
    # for a blocking Unix socket this should never fail
    socket.send("data sent through the socket\c\l", maxRetries = 0)
    var resp: string
    socket.readLine(resp)
    doAssert resp == "Hello from server"

    socket.send("bye\c\l")
    socket.readLine(resp)
    doAssert resp == "bye"
    socket.close()

  svproc.close()
