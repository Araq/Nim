# issue #24076

when defined(macosx) or defined(freebsd) or defined(openbsd) or defined(netbsd):
  import std/posix
  proc uid(x: uint32): Uid = Uid(x)
  var y: uint32
  let myUid = geteuid()
  discard myUid == uid(y)
  proc dev(x: uint32): Dev = Dev(x)
  let myDev = 1.Dev
  discard myDev == dev(y)
  proc nlink(x: uint32): Nlink = Nlink(x)
  let myNlink = 1.Nlink
  discard myNlink == nlink(y)
