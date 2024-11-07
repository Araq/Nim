discard """
  exitcode: 0
  output: ""
  matrix: "; -d:nimInheritHandles; --mm:refc"
  joinable: false
"""

import os, osproc, strutils, nativesockets, net, selectors, memfiles,
       asyncdispatch, asyncnet

import std/[assertions, syncio]

when defined(windows):
  import winlean

  # Note: Windows 10-only API
  proc compareObjectHandles(first, second: Handle): WINBOOL
                           {.stdcall, dynlib: "kernelbase",
                             importc: "CompareObjectHandles".}
else:
  import posix

proc leakCheck(f: AsyncFD | int | FileHandle | SocketHandle, msg: string,
               expectLeak = defined(nimInheritHandles)) =
  var args = @[$f.int, msg, $expectLeak]

  when defined(windows):
    var refFd: Handle = default(Handle)
    # NOTE: This function shouldn't be used to duplicate sockets,
    #       as this function may mess with the socket internal refcounting.
    #       but due to the lack of type segmentation in the stdlib for
    #       Windows (AsyncFD can be a file or a socket), we will have to
    #       settle with this.
    #
    #       Now, as a poor solution for the refcounting problem, we just
    #       simply let the duplicated handle leak. This should not interfere
    #       with the test since new handles can't occupy the slot held by
    #       the leaked ones.
    if duplicateHandle(getCurrentProcess(), f.Handle,
                       getCurrentProcess(), addr refFd,
                       0, 1, DUPLICATE_SAME_ACCESS) == 0:
      raiseOSError osLastError(), "Couldn't create the reference handle"
    args.add $refFd

  discard startProcess(
    getAppFilename(),
    args = args,
    options = {poParentStreams}
  ).waitForExit

proc isValidHandle(f: int): bool =
  ## Check if a handle is valid. Requires OS-native handles.
  when defined(windows):
    var flags: DWORD = default(DWORD)
    result = getHandleInformation(f.Handle, addr flags) != 0
  else:
    result = fcntl(f.cint, F_GETFD) != -1

proc main() =
  if paramCount() == 0:
    # Parent process
    let f = syncio.open("__test_fdleak", fmReadWrite)
    defer: close f

    leakCheck(f.getOsFileHandle, "system.open()")

    doAssert f.reopen("__test_fdleak2", fmReadWrite), "reopen failed"

    leakCheck(f.getOsFileHandle, "reopen")

    let sock = createNativeSocket()
    defer: close sock
    leakCheck(sock, "createNativeSocket()")
    if sock.setInheritable(not defined(nimInheritHandles)):
      leakCheck(sock, "createNativeSocket()", not defined(nimInheritHandles))
    else:
      raiseOSError osLastError()

    let server = newSocket()
    defer: close server
    server.bindAddr(address = "127.0.0.1")
    server.listen()
    let (_, port) = server.getLocalAddr

    leakCheck(server.getFd, "newSocket()")

    let client = newSocket()
    defer: close client
    client.connect("127.0.0.1", port)

    var input: Socket = default(Socket)
    server.accept(input)

    leakCheck(input.getFd, "accept()")

    # ioselectors_select doesn't support returning a handle.
    when not defined(windows):
      let selector = newSelector[int]()
      leakCheck(selector.getFd, "selector()", false)

    var mf = memfiles.open("__test_fdleak3", fmReadWrite, newFileSize = 1)
    defer: close mf
    when defined(windows):
      leakCheck(mf.mapHandle, "memfiles.open().mapHandle", false)
    else:
      leakCheck(mf.handle, "memfiles.open().handle", false)

    let sockAsync = createAsyncNativeSocket()
    defer: closeSocket sockAsync
    leakCheck(sockAsync, "createAsyncNativeSocket()")
    if sockAsync.setInheritable(not defined(nimInheritHandles)):
      leakCheck(sockAsync, "createAsyncNativeSocket()", not defined(nimInheritHandles))
    else:
      raiseOSError osLastError()

    let serverAsync = newAsyncSocket()
    defer: close serverAsync
    serverAsync.bindAddr(address = "127.0.0.1")
    serverAsync.listen()
    let (_, portAsync) = serverAsync.getLocalAddr

    leakCheck(serverAsync.getFd, "newAsyncSocket()")

    let clientAsync = newAsyncSocket()
    defer: close clientAsync
    waitFor clientAsync.connect("127.0.0.1", portAsync)

    let inputAsync = waitFor serverAsync.accept()

    leakCheck(inputAsync.getFd, "accept() async")
  else:
    let
      fd = parseInt(paramStr 1)
      expectLeak = parseBool(paramStr 3)
      msg = (if expectLeak: "not " else: "") & "leaked " & paramStr 2
    let validHandle =
      when defined(windows):
        # On Windows, due to the use of winlean, causes the program to open
        # a handle to the various dlls that's loaded. This handle might
        # collide with the handle sent for testing.
        #
        # As a walkaround, we pass an another handle that's purposefully leaked
        # as a reference so that we can verify whether the "leaked" handle
        # is the right one.
        let refFd = parseInt(paramStr 4)
        fd.isValidHandle and compareObjectHandles(fd, refFd) != 0
      else:
        fd.isValidHandle
    if expectLeak xor validHandle:
      echo msg

when isMainModule: main()
