# issue #24076

when defined(macosx) or defined(freebsd) or defined(openbsd) or defined(netbsd):
  import std/posix
  proc uid(x: uint32): Uid = Uid(x)
  var y: uint32
  let myUid = geteuid()
  discard myUid == uid(y)
