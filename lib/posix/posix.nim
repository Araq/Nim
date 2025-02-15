#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# Until std_arg!!
# done: ipc, pwd, stat, semaphore, sys/types, sys/utsname, pthread, unistd,
# statvfs, mman, time, wait, signal, nl_types, sched, spawn, select, ucontext,
# net/if, sys/socket, sys/uio, netinet/in, netinet/tcp, netdb

## This is a raw POSIX interface module. It does not not provide any
## convenience: cstrings are used instead of proper Nim strings and
## return codes indicate errors. If you want exceptions
## and a proper Nim-like interface, use the OS module or write a wrapper.
##
## For high-level wrappers specialized for Linux and BSDs see:
## `posix_utils <posix_utils.html>`_
##
## Coding conventions:
## ALL types are named the same as in the POSIX standard except that they start
## with 'T' or 'P' (if they are pointers) and without the '_t' suffix to be
## consistent with Nim conventions. If an identifier is a Nim keyword
## the \`identifier\` notation is used.
##
## This library relies on the header files of your C compiler. The
## resulting C code will just `#include <XYZ.h>` and *not* define the
## symbols declared here.

# Dead code elimination ensures that we don't accidentally generate #includes
# for files that might not exist on a specific platform! The user will get an
# error only if they actually try to use the missing declaration

when defined(nimHasStyleChecks):
  {.push styleChecks: off.}

when defined(nimPreviewSlimSystem):
  import std/syncio

# TODO these constants don't seem to be fetched from a header file for unknown
#      platforms - where do they come from and why are they here?
when false:
  const
    C_IRUSR = 0o000400 ## Read by owner.
    C_IWUSR = 0o000200 ## Write by owner.
    C_IXUSR = 0o000100 ## Execute by owner.
    C_IRGRP = 0o000040 ## Read by group.
    C_IWGRP = 0o000020 ## Write by group.
    C_IXGRP = 0o000010 ## Execute by group.
    C_IROTH = 0o000004 ## Read by others.
    C_IWOTH = 0o000002 ## Write by others.
    C_IXOTH = 0o000001 ## Execute by others.
    C_ISUID = 0o004000 ## Set user ID.
    C_ISGID = 0o002000 ## Set group ID.
    C_ISVTX = 0o001000 ## On directories, restricted deletion flag.
    C_ISDIR = 0o040000 ## Directory.
    C_ISFIFO = 0o010000 ##FIFO.
    C_ISREG = 0o100000 ## Regular file.
    C_ISBLK = 0o060000 ## Block special.
    C_ISCHR = 0o020000 ## Character special.
    C_ISCTG = 0o110000 ## Reserved.
    C_ISLNK = 0o120000 ## Symbolic link.</p>
    C_ISSOCK = 0o140000 ## Socket.

const
  MM_NULLLBL* = nil
  MM_NULLSEV* = 0
  MM_NULLMC* = 0
  MM_NULLTXT* = nil
  MM_NULLACT* = nil
  MM_NULLTAG* = nil

  STDERR_FILENO* = 2 ## File number of stderr;
  STDIN_FILENO* = 0  ## File number of stdin;
  STDOUT_FILENO* = 1 ## File number of stdout;

  DT_UNKNOWN* = 0 ## Unknown file type.
  DT_FIFO* = 1    ## Named pipe, or FIFO.
  DT_CHR* = 2     ## Character device.
  DT_DIR* = 4     ## Directory.
  DT_BLK* = 6     ## Block device.
  DT_REG* = 8     ## Regular file.
  DT_LNK* = 10    ## Symbolic link.
  DT_SOCK* = 12   ## UNIX domain socket.
  DT_WHT* = 14

# Special types
type Sighandler = proc (a: cint) {.noconv.}

const StatHasNanoseconds* = defined(linux) or defined(freebsd) or
    defined(osx) or defined(openbsd) or defined(dragonfly) or defined(haiku) ## \
  ## Boolean flag that indicates if the system supports nanosecond time
  ## resolution in the fields of `Stat`. Note that the nanosecond based fields
  ## (`Stat.st_atim`, `Stat.st_mtim` and `Stat.st_ctim`) can be accessed
  ## without checking this flag, because this module defines fallback procs
  ## when they are not available.

# Platform specific stuff

when (defined(linux) and not defined(android)) and defined(amd64):
  include posix_linux_amd64
elif defined(openbsd) and defined(amd64):
  include posix_openbsd_amd64
elif (defined(macos) or defined(macosx) or defined(bsd)) and defined(cpu64):
  include posix_macos_amd64
elif defined(nintendoswitch):
  include posix_nintendoswitch
elif defined(haiku):
  include posix_haiku
else:
  include posix_other

# There used to be this name in posix.nim a long time ago, not sure why!

when StatHasNanoseconds:
  proc st_atime*(s: Stat): Time {.inline.} =
    ## Second-granularity time of last access.
    result = s.st_atim.tv_sec
  proc st_mtime*(s: Stat): Time {.inline.} =
    ## Second-granularity time of last data modification.
    result = s.st_mtim.tv_sec
  proc st_ctime*(s: Stat): Time {.inline.} =
    ## Second-granularity time of last status change.
    result = s.st_ctim.tv_sec
else:
  proc st_atim*(s: Stat): Timespec {.inline.} =
    ## Nanosecond-granularity time of last access.
    result.tv_sec = s.st_atime
  proc st_mtim*(s: Stat): Timespec {.inline.} =
    ## Nanosecond-granularity time of last data modification.
    result.tv_sec = s.st_mtime
  proc st_ctim*(s: Stat): Timespec {.inline.} =
    ## Nanosecond-granularity time of last data modification.
    result.tv_sec = s.st_ctime

when hasAioH:
  proc aio_cancel*(a1: cint, a2: ptr Taiocb): cint {.importc, header: "<aio.h>".}
  proc aio_error*(a1: ptr Taiocb): cint {.importc, header: "<aio.h>".}
  proc aio_fsync*(a1: cint, a2: ptr Taiocb): cint {.importc, header: "<aio.h>".}
  proc aio_read*(a1: ptr Taiocb): cint {.importc, header: "<aio.h>".}
  proc aio_return*(a1: ptr Taiocb): int {.importc, header: "<aio.h>".}
  proc aio_suspend*(a1: ptr ptr Taiocb, a2: cint, a3: ptr Timespec): cint {.
                   importc, header: "<aio.h>".}
  proc aio_write*(a1: ptr Taiocb): cint {.importc, header: "<aio.h>".}
  proc lio_listio*(a1: cint, a2: ptr ptr Taiocb, a3: cint,
               a4: ptr SigEvent): cint {.importc, header: "<aio.h>".}

# arpa/inet.h
proc htonl*(a1: uint32): uint32 {.importc, header: "<arpa/inet.h>".}
proc htons*(a1: uint16): uint16 {.importc, header: "<arpa/inet.h>".}
proc ntohl*(a1: uint32): uint32 {.importc, header: "<arpa/inet.h>".}
proc ntohs*(a1: uint16): uint16 {.importc, header: "<arpa/inet.h>".}

when not defined(zephyr):
  proc inet_addr*(a1: cstring): InAddrT {.importc, header: "<arpa/inet.h>".}
  proc inet_ntoa*(a1: InAddr): cstring {.importc, header: "<arpa/inet.h>".}

proc inet_ntop*(a1: cint, a2: pointer | ptr InAddr | ptr In6Addr, a3: cstring, a4: int32): cstring {.
  importc:"(char *)$1", header: "<arpa/inet.h>".}
proc inet_pton*(a1: cint, a2: cstring, a3: pointer | ptr InAddr | ptr In6Addr): cint {.
  importc, header: "<arpa/inet.h>".}

var
  in6addr_any* {.importc, header: "<netinet/in.h>".}: In6Addr
  in6addr_loopback* {.importc, header: "<netinet/in.h>".}: In6Addr

proc IN6ADDR_ANY_INIT* (): In6Addr {.importc, header: "<netinet/in.h>".}
proc IN6ADDR_LOOPBACK_INIT* (): In6Addr {.importc, header: "<netinet/in.h>".}

# dirent.h
proc closedir*(a1: ptr DIR): cint  {.importc, header: "<dirent.h>".}
proc opendir*(a1: cstring): ptr DIR {.importc, header: "<dirent.h>", sideEffect.}
proc readdir*(a1: ptr DIR): ptr Dirent  {.importc, header: "<dirent.h>", sideEffect.}
proc readdir_r*(a1: ptr DIR, a2: ptr Dirent, a3: ptr ptr Dirent): cint  {.
                importc, header: "<dirent.h>", sideEffect.}
proc rewinddir*(a1: ptr DIR)  {.importc, header: "<dirent.h>".}
proc seekdir*(a1: ptr DIR, a2: int)  {.importc, header: "<dirent.h>".}
proc telldir*(a1: ptr DIR): int {.importc, header: "<dirent.h>".}

# dlfcn.h
proc dlclose*(a1: pointer): cint {.importc, header: "<dlfcn.h>", sideEffect.}
proc dlerror*(): cstring {.importc, header: "<dlfcn.h>", sideEffect.}
proc dlopen*(a1: cstring, a2: cint): pointer {.importc, header: "<dlfcn.h>", sideEffect.}
proc dlsym*(a1: pointer, a2: cstring): pointer {.importc, header: "<dlfcn.h>", sideEffect.}

proc creat*(a1: cstring, a2: Mode): cint {.importc, header: "<fcntl.h>", sideEffect.}
proc fcntl*(a1: cint | SocketHandle, a2: cint): cint {.varargs, importc, header: "<fcntl.h>", sideEffect.}
proc openImpl(a1: cstring, a2: cint): cint {.varargs, importc: "open", header: "<fcntl.h>", sideEffect.}
proc open*(a1: cstring, a2: cint, mode: Mode | cint = 0.Mode): cint {.inline.} =
  # prevents bug #17888
  openImpl(a1, a2, mode)

proc posix_fadvise*(a1: cint, a2, a3: Off, a4: cint): cint {.
  importc, header: "<fcntl.h>".}

proc ftruncate*(a1: cint, a2: Off): cint {.importc, header: "<unistd.h>".}
when defined(osx):              # 2001 POSIX evidently does not concern Apple
  type FStore {.importc: "fstore_t", header: "<fcntl.h>", bycopy.} = object
    fst_flags: uint32           ## IN: flags word
    fst_posmode: cint           ## IN: indicates offset field
    fst_offset,                 ## IN: start of the region
      fst_length,               ## IN: size of the region
      fst_bytesalloc: Off       ## OUT: number of bytes allocated
  var F_PEOFPOSMODE {.importc, header: "<fcntl.h>".}: cint
  var F_ALLOCATEALL {.importc, header: "<fcntl.h>".}: uint32
  var F_PREALLOCATE {.importc, header: "<fcntl.h>".}: cint
  proc posix_fallocate*(a1: cint, a2, a3: Off): cint =
    var fst = FStore(fst_flags: F_ALLOCATEALL, fst_posmode: F_PEOFPOSMODE,
                     fst_offset: a2, fst_length: a3)
    # Must also call ftruncate to match what POSIX does. Unlike posix_fallocate,
    # this can shrink files.  Could guard w/getFileSize, but caller likely knows
    # present size & has no good reason to call this unless it is growing.
    if fcntl(a1, F_PREALLOCATE, fst.addr) != cint(-1): ftruncate(a1, a2 + a3)
    else: cint(-1)
else:
  proc posix_fallocate*(a1: cint, a2, a3: Off): cint {.
    importc, header: "<fcntl.h>".}

when not defined(haiku) and not defined(openbsd):
  proc fmtmsg*(a1: int, a2: cstring, a3: cint,
              a4, a5, a6: cstring): cint {.importc, header: "<fmtmsg.h>".}

proc fnmatch*(a1, a2: cstring, a3: cint): cint {.importc, header: "<fnmatch.h>".}
proc ftw*(a1: cstring,
         a2: proc (x1: cstring, x2: ptr Stat, x3: cint): cint {.noconv.},
         a3: cint): cint {.importc, header: "<ftw.h>".}
when not (defined(linux) and defined(amd64)) and not defined(nintendoswitch):
  proc nftw*(a1: cstring,
            a2: proc (x1: cstring, x2: ptr Stat,
                      x3: cint, x4: ptr FTW): cint {.noconv.},
            a3: cint,
            a4: cint): cint {.importc, header: "<ftw.h>".}

proc glob*(a1: cstring, a2: cint,
          a3: proc (x1: cstring, x2: cint): cint {.noconv.},
          a4: ptr Glob): cint {.importc, header: "<glob.h>", sideEffect.}
  ## Filename globbing. Use `os.walkPattern() <os.html#glob_1>`_ and similar.

proc globfree*(a1: ptr Glob) {.importc, header: "<glob.h>".}

proc getgrgid*(a1: Gid): ptr Group {.importc, header: "<grp.h>".}
proc getgrnam*(a1: cstring): ptr Group {.importc, header: "<grp.h>".}
proc getgrgid_r*(a1: Gid, a2: ptr Group, a3: cstring, a4: int,
                 a5: ptr ptr Group): cint {.importc, header: "<grp.h>".}
proc getgrnam_r*(a1: cstring, a2: ptr Group, a3: cstring,
                  a4: int, a5: ptr ptr Group): cint {.
                 importc, header: "<grp.h>".}
proc getgrent*(): ptr Group {.importc, header: "<grp.h>".}
proc endgrent*() {.importc, header: "<grp.h>".}
proc setgrent*() {.importc, header: "<grp.h>".}


proc iconv_open*(a1, a2: cstring): Iconv {.importc, header: "<iconv.h>".}
proc iconv*(a1: Iconv, a2: var cstring, a3: var int, a4: var cstring,
            a5: var int): int {.importc, header: "<iconv.h>".}
proc iconv_close*(a1: Iconv): cint {.importc, header: "<iconv.h>".}

proc nl_langinfo*(a1: Nl_item): cstring {.importc, header: "<langinfo.h>".}

proc basename*(a1: cstring): cstring {.importc, header: "<libgen.h>".}
proc dirname*(a1: cstring): cstring {.importc, header: "<libgen.h>".}

proc localeconv*(): ptr Lconv {.importc, header: "<locale.h>".}
proc setlocale*(a1: cint, a2: cstring): cstring {.
                importc, header: "<locale.h>", sideEffect.}

proc strfmon*(a1: cstring, a2: int, a3: cstring): int {.varargs,
   importc, header: "<monetary.h>".}

when not (defined(nintendoswitch) or defined(macos) or defined(macosx)):
  proc mq_notify*(mqdes: Mqd, event: ptr SigEvent): cint {.
    importc, header: "<mqueue.h>".}

  proc mq_open*(name: cstring, flags: cint): Mqd {.
    varargs, importc, header: "<mqueue.h>".}

  proc mq_close*(mqdes: Mqd): cint {.importc, header: "<mqueue.h>".}

  proc mq_receive*(
    mqdes: Mqd,
    buffer: cstring,
    length: csize_t,
    priority: var cuint
  ): int {.importc, header: "<mqueue.h>".}

  proc mq_timedreceive*(
    mqdes: Mqd,
    buffer: cstring,
    length: csize_t,
    priority: cuint,
    timeout: ptr Timespec
  ): int {.importc, header: "<mqueue.h>".}

  proc mq_send*(
    mqdes: Mqd,
    buffer: cstring,
    length: csize_t,
    priority: cuint
  ): cint {.importc, header: "<mqueue.h>".}

  proc mq_timedsend*(
    mqdes: Mqd,
    buffer: cstring,
    length: csize_t,
    priority: cuint,
    timeout: ptr Timespec
  ): cint {.importc, header: "<mqueue.h>".}

  proc mq_getattr*(mqdes: Mqd, attribute: ptr MqAttr): cint {.
    importc, header: "<mqueue.h>".}

  proc mq_setattr*(mqdes: Mqd, newAttribute, oldAttribute: ptr MqAttr): cint {.
    importc, header: "<mqueue.h>".}

  proc mq_unlink*(mqdes: cstring): cint {.importc, header: "<mqueue.h>".}


proc getpwnam*(a1: cstring): ptr Passwd {.importc, header: "<pwd.h>".}
proc getpwuid*(a1: Uid): ptr Passwd {.importc, header: "<pwd.h>".}
proc getpwnam_r*(a1: cstring, a2: ptr Passwd, a3: cstring, a4: int,
                 a5: ptr ptr Passwd): cint {.importc, header: "<pwd.h>".}
proc getpwuid_r*(a1: Uid, a2: ptr Passwd, a3: cstring,
      a4: int, a5: ptr ptr Passwd): cint {.importc, header: "<pwd.h>".}
proc endpwent*() {.importc, header: "<pwd.h>".}
proc getpwent*(): ptr Passwd {.importc, header: "<pwd.h>".}
proc setpwent*() {.importc, header: "<pwd.h>".}

proc uname*(a1: var Utsname): cint {.importc, header: "<sys/utsname.h>".}

proc strerror*(errnum: cint): cstring {.importc, header: "<string.h>".}

proc pthread_atfork*(a1, a2, a3: proc () {.noconv.}): cint {.
  importc, header: "<pthread.h>".}
proc pthread_attr_destroy*(a1: ptr Pthread_attr): cint {.
  importc, header: "<pthread.h>".}
proc pthread_attr_getdetachstate*(a1: ptr Pthread_attr, a2: cint): cint {.
  importc, header: "<pthread.h>".}
proc pthread_attr_getguardsize*(a1: ptr Pthread_attr, a2: var cint): cint {.
  importc, header: "<pthread.h>".}
proc pthread_attr_getinheritsched*(a1: ptr Pthread_attr,
          a2: var cint): cint {.importc, header: "<pthread.h>".}
proc pthread_attr_getschedparam*(a1: ptr Pthread_attr,
          a2: ptr Sched_param): cint {.importc, header: "<pthread.h>".}
proc pthread_attr_getschedpolicy*(a1: ptr Pthread_attr,
          a2: var cint): cint {.importc, header: "<pthread.h>".}
proc pthread_attr_getscope*(a1: ptr Pthread_attr,
          a2: var cint): cint {.importc, header: "<pthread.h>".}
proc pthread_attr_getstack*(a1: ptr Pthread_attr,
         a2: var pointer, a3: var int): cint {.importc, header: "<pthread.h>".}
proc pthread_attr_getstackaddr*(a1: ptr Pthread_attr,
          a2: var pointer): cint {.importc, header: "<pthread.h>".}
proc pthread_attr_getstacksize*(a1: ptr Pthread_attr,
          a2: var int): cint {.importc, header: "<pthread.h>".}
proc pthread_attr_init*(a1: ptr Pthread_attr): cint {.
  importc, header: "<pthread.h>".}
proc pthread_attr_setdetachstate*(a1: ptr Pthread_attr, a2: cint): cint {.
  importc, header: "<pthread.h>".}
proc pthread_attr_setguardsize*(a1: ptr Pthread_attr, a2: int): cint {.
  importc, header: "<pthread.h>".}
proc pthread_attr_setinheritsched*(a1: ptr Pthread_attr, a2: cint): cint {.
  importc, header: "<pthread.h>".}
proc pthread_attr_setschedparam*(a1: ptr Pthread_attr,
          a2: ptr Sched_param): cint {.importc, header: "<pthread.h>".}
proc pthread_attr_setschedpolicy*(a1: ptr Pthread_attr, a2: cint): cint {.
  importc, header: "<pthread.h>".}
proc pthread_attr_setscope*(a1: ptr Pthread_attr, a2: cint): cint {.importc,
  header: "<pthread.h>".}
proc pthread_attr_setstack*(a1: ptr Pthread_attr, a2: pointer, a3: int): cint {.
  importc, header: "<pthread.h>".}
proc pthread_attr_setstackaddr*(a1: ptr Pthread_attr, a2: pointer): cint {.
  importc, header: "<pthread.h>".}
proc pthread_attr_setstacksize*(a1: ptr Pthread_attr, a2: int): cint {.
  importc, header: "<pthread.h>".}
proc pthread_barrier_destroy*(a1: ptr Pthread_barrier): cint {.
  importc, header: "<pthread.h>".}
proc pthread_barrier_init*(a1: ptr Pthread_barrier,
         a2: ptr Pthread_barrierattr, a3: cint): cint {.
         importc, header: "<pthread.h>".}
proc pthread_barrier_wait*(a1: ptr Pthread_barrier): cint {.
  importc, header: "<pthread.h>".}
proc pthread_barrierattr_destroy*(a1: ptr Pthread_barrierattr): cint {.
  importc, header: "<pthread.h>".}
proc pthread_barrierattr_getpshared*(
          a1: ptr Pthread_barrierattr, a2: var cint): cint {.
          importc, header: "<pthread.h>".}
proc pthread_barrierattr_init*(a1: ptr Pthread_barrierattr): cint {.
  importc, header: "<pthread.h>".}
proc pthread_barrierattr_setpshared*(a1: ptr Pthread_barrierattr,
  a2: cint): cint {.importc, header: "<pthread.h>".}
proc pthread_cancel*(a1: Pthread): cint {.importc, header: "<pthread.h>".}
proc pthread_cleanup_push*(a1: proc (x: pointer) {.noconv.}, a2: pointer) {.
  importc, header: "<pthread.h>".}
proc pthread_cleanup_pop*(a1: cint) {.importc, header: "<pthread.h>".}
proc pthread_cond_broadcast*(a1: ptr Pthread_cond): cint {.
  importc, header: "<pthread.h>".}
proc pthread_cond_destroy*(a1: ptr Pthread_cond): cint {.importc, header: "<pthread.h>".}
proc pthread_cond_init*(a1: ptr Pthread_cond,
          a2: ptr Pthread_condattr): cint {.importc, header: "<pthread.h>".}
proc pthread_cond_signal*(a1: ptr Pthread_cond): cint {.importc, header: "<pthread.h>".}
proc pthread_cond_timedwait*(a1: ptr Pthread_cond,
          a2: ptr Pthread_mutex, a3: ptr Timespec): cint {.importc, header: "<pthread.h>".}

proc pthread_cond_wait*(a1: ptr Pthread_cond,
          a2: ptr Pthread_mutex): cint {.importc, header: "<pthread.h>".}
proc pthread_condattr_destroy*(a1: ptr Pthread_condattr): cint {.importc, header: "<pthread.h>".}
proc pthread_condattr_getclock*(a1: ptr Pthread_condattr,
          a2: var ClockId): cint {.importc, header: "<pthread.h>".}
proc pthread_condattr_getpshared*(a1: ptr Pthread_condattr,
          a2: var cint): cint {.importc, header: "<pthread.h>".}

proc pthread_condattr_init*(a1: ptr Pthread_condattr): cint {.importc, header: "<pthread.h>".}
proc pthread_condattr_setclock*(a1: ptr Pthread_condattr,a2: ClockId): cint {.importc, header: "<pthread.h>".}
proc pthread_condattr_setpshared*(a1: ptr Pthread_condattr, a2: cint): cint {.importc, header: "<pthread.h>".}

proc pthread_create*(a1: ptr Pthread, a2: ptr Pthread_attr,
          a3: proc (x: pointer): pointer {.noconv.}, a4: pointer): cint {.importc, header: "<pthread.h>".}
proc pthread_detach*(a1: Pthread): cint {.importc, header: "<pthread.h>".}
proc pthread_equal*(a1, a2: Pthread): cint {.importc, header: "<pthread.h>".}
proc pthread_exit*(a1: pointer) {.importc, header: "<pthread.h>".}
proc pthread_getconcurrency*(): cint {.importc, header: "<pthread.h>".}
proc pthread_getcpuclockid*(a1: Pthread, a2: var ClockId): cint {.importc, header: "<pthread.h>".}
proc pthread_getschedparam*(a1: Pthread,  a2: var cint,
          a3: ptr Sched_param): cint {.importc, header: "<pthread.h>".}
proc pthread_getspecific*(a1: Pthread_key): pointer {.importc, header: "<pthread.h>".}
proc pthread_join*(a1: Pthread, a2: ptr pointer): cint {.importc, header: "<pthread.h>".}
proc pthread_key_create*(a1: ptr Pthread_key, a2: proc (x: pointer) {.noconv.}): cint {.importc, header: "<pthread.h>".}
proc pthread_key_delete*(a1: Pthread_key): cint {.importc, header: "<pthread.h>".}

proc pthread_mutex_destroy*(a1: ptr Pthread_mutex): cint {.importc, header: "<pthread.h>".}
proc pthread_mutex_getprioceiling*(a1: ptr Pthread_mutex,
         a2: var cint): cint {.importc, header: "<pthread.h>".}
proc pthread_mutex_init*(a1: ptr Pthread_mutex,
          a2: ptr Pthread_mutexattr): cint {.importc, header: "<pthread.h>".}
proc pthread_mutex_lock*(a1: ptr Pthread_mutex): cint {.importc, header: "<pthread.h>".}
proc pthread_mutex_setprioceiling*(a1: ptr Pthread_mutex,a2: cint,
          a3: var cint): cint {.importc, header: "<pthread.h>".}
proc pthread_mutex_timedlock*(a1: ptr Pthread_mutex,
          a2: ptr Timespec): cint {.importc, header: "<pthread.h>".}
proc pthread_mutex_trylock*(a1: ptr Pthread_mutex): cint {.importc, header: "<pthread.h>".}
proc pthread_mutex_unlock*(a1: ptr Pthread_mutex): cint {.importc, header: "<pthread.h>".}
proc pthread_mutexattr_destroy*(a1: ptr Pthread_mutexattr): cint {.importc, header: "<pthread.h>".}

proc pthread_mutexattr_getprioceiling*(
          a1: ptr Pthread_mutexattr, a2: var cint): cint {.importc, header: "<pthread.h>".}
proc pthread_mutexattr_getprotocol*(a1: ptr Pthread_mutexattr,
          a2: var cint): cint {.importc, header: "<pthread.h>".}
proc pthread_mutexattr_getpshared*(a1: ptr Pthread_mutexattr,
          a2: var cint): cint {.importc, header: "<pthread.h>".}
proc pthread_mutexattr_gettype*(a1: ptr Pthread_mutexattr,
          a2: var cint): cint {.importc, header: "<pthread.h>".}

proc pthread_mutexattr_init*(a1: ptr Pthread_mutexattr): cint {.importc, header: "<pthread.h>".}
proc pthread_mutexattr_setprioceiling*(a1: ptr Pthread_mutexattr, a2: cint): cint {.importc, header: "<pthread.h>".}
proc pthread_mutexattr_setprotocol*(a1: ptr Pthread_mutexattr, a2: cint): cint {.importc, header: "<pthread.h>".}
proc pthread_mutexattr_setpshared*(a1: ptr Pthread_mutexattr, a2: cint): cint {.importc, header: "<pthread.h>".}
proc pthread_mutexattr_settype*(a1: ptr Pthread_mutexattr, a2: cint): cint {.importc, header: "<pthread.h>".}

proc pthread_once*(a1: ptr Pthread_once, a2: proc () {.noconv.}): cint {.importc, header: "<pthread.h>".}

proc pthread_rwlock_destroy*(a1: ptr Pthread_rwlock): cint {.importc, header: "<pthread.h>".}
proc pthread_rwlock_init*(a1: ptr Pthread_rwlock,
          a2: ptr Pthread_rwlockattr): cint {.importc, header: "<pthread.h>".}
proc pthread_rwlock_rdlock*(a1: ptr Pthread_rwlock): cint {.importc, header: "<pthread.h>".}
proc pthread_rwlock_timedrdlock*(a1: ptr Pthread_rwlock,
          a2: ptr Timespec): cint {.importc, header: "<pthread.h>".}
proc pthread_rwlock_timedwrlock*(a1: ptr Pthread_rwlock,
          a2: ptr Timespec): cint {.importc, header: "<pthread.h>".}

proc pthread_rwlock_tryrdlock*(a1: ptr Pthread_rwlock): cint {.importc, header: "<pthread.h>".}
proc pthread_rwlock_trywrlock*(a1: ptr Pthread_rwlock): cint {.importc, header: "<pthread.h>".}
proc pthread_rwlock_unlock*(a1: ptr Pthread_rwlock): cint {.importc, header: "<pthread.h>".}
proc pthread_rwlock_wrlock*(a1: ptr Pthread_rwlock): cint {.importc, header: "<pthread.h>".}
proc pthread_rwlockattr_destroy*(a1: ptr Pthread_rwlockattr): cint {.importc, header: "<pthread.h>".}
proc pthread_rwlockattr_getpshared*(
          a1: ptr Pthread_rwlockattr, a2: var cint): cint {.importc, header: "<pthread.h>".}
proc pthread_rwlockattr_init*(a1: ptr Pthread_rwlockattr): cint {.importc, header: "<pthread.h>".}
proc pthread_rwlockattr_setpshared*(a1: ptr Pthread_rwlockattr, a2: cint): cint {.importc, header: "<pthread.h>".}

proc pthread_self*(): Pthread {.importc, header: "<pthread.h>".}
proc pthread_setcancelstate*(a1: cint, a2: var cint): cint {.importc, header: "<pthread.h>".}
proc pthread_setcanceltype*(a1: cint, a2: var cint): cint {.importc, header: "<pthread.h>".}
proc pthread_setconcurrency*(a1: cint): cint {.importc, header: "<pthread.h>".}
proc pthread_setschedparam*(a1: Pthread, a2: cint,
          a3: ptr Sched_param): cint {.importc, header: "<pthread.h>".}

proc pthread_setschedprio*(a1: Pthread, a2: cint): cint {.
  importc, header: "<pthread.h>".}
proc pthread_setspecific*(a1: Pthread_key, a2: pointer): cint {.
  importc, header: "<pthread.h>".}
proc pthread_spin_destroy*(a1: ptr Pthread_spinlock): cint {.
  importc, header: "<pthread.h>".}
proc pthread_spin_init*(a1: ptr Pthread_spinlock, a2: cint): cint {.
  importc, header: "<pthread.h>".}
proc pthread_spin_lock*(a1: ptr Pthread_spinlock): cint {.
  importc, header: "<pthread.h>".}
proc pthread_spin_trylock*(a1: ptr Pthread_spinlock): cint{.
  importc, header: "<pthread.h>".}
proc pthread_spin_unlock*(a1: ptr Pthread_spinlock): cint {.
  importc, header: "<pthread.h>".}
proc pthread_testcancel*() {.importc, header: "<pthread.h>".}


proc exitnow*(code: cint) {.importc: "_exit", header: "<unistd.h>", noreturn.}
proc access*(a1: cstring, a2: cint): cint {.importc, header: "<unistd.h>".}
proc alarm*(a1: cint): cint {.importc, header: "<unistd.h>".}
proc chdir*(a1: cstring): cint {.importc, header: "<unistd.h>".}
proc chown*(a1: cstring, a2: Uid, a3: Gid): cint {.importc, header: "<unistd.h>".}
proc close*(a1: cint | SocketHandle): cint {.importc, header: "<unistd.h>".}
proc confstr*(a1: cint, a2: cstring, a3: int): int {.importc, header: "<unistd.h>".}
proc crypt*(a1, a2: cstring): cstring {.importc, header: "<unistd.h>".}
proc ctermid*(a1: cstring): cstring {.importc, header: "<unistd.h>".}
proc dup*(a1: cint): cint {.importc, header: "<unistd.h>".}
proc dup2*(a1, a2: cint): cint {.importc, header: "<unistd.h>".}
proc encrypt*(a1: array[0..63, char], a2: cint) {.importc, header: "<unistd.h>".}

proc execl*(a1, a2: cstring): cint {.varargs, importc, header: "<unistd.h>", sideEffect.}
proc execle*(a1, a2: cstring): cint {.varargs, importc, header: "<unistd.h>", sideEffect.}
proc execlp*(a1, a2: cstring): cint {.varargs, importc, header: "<unistd.h>", sideEffect.}
proc execv*(a1: cstring, a2: cstringArray): cint {.importc, header: "<unistd.h>", sideEffect.}
proc execve*(a1: cstring, a2, a3: cstringArray): cint {.
  importc, header: "<unistd.h>", sideEffect.}
proc execvp*(a1: cstring, a2: cstringArray): cint {.importc, header: "<unistd.h>", sideEffect.}
proc execvpe*(a1: cstring, a2: cstringArray, a3: cstringArray): cint {.importc, header: "<unistd.h>", sideEffect.}
proc fchown*(a1: cint, a2: Uid, a3: Gid): cint {.importc, header: "<unistd.h>", sideEffect.}
proc fchdir*(a1: cint): cint {.importc, header: "<unistd.h>", sideEffect.}
proc fdatasync*(a1: cint): cint {.importc, header: "<unistd.h>".}
proc fork*(): Pid {.importc, header: "<unistd.h>", sideEffect.}
proc fpathconf*(a1, a2: cint): int {.importc, header: "<unistd.h>".}
proc fsync*(a1: cint): cint {.importc, header: "<unistd.h>".}
 ## synchronize a file's buffer cache to the storage device

proc getcwd*(a1: cstring, a2: int): cstring {.importc, header: "<unistd.h>", sideEffect.}
proc getuid*(): Uid {.importc, header: "<unistd.h>", sideEffect.}
 ## returns the real user ID of the calling process

proc geteuid*(): Uid {.importc, header: "<unistd.h>", sideEffect.}
 ## returns the effective user ID of the calling process

proc getgid*(): Gid {.importc, header: "<unistd.h>", sideEffect.}
 ## returns the real group ID of the calling process

proc getegid*(): Gid {.importc, header: "<unistd.h>", sideEffect.}
 ## returns the effective group ID of the calling process

proc getgroups*(a1: cint, a2: ptr array[0..255, Gid]): cint {.
  importc, header: "<unistd.h>".}
proc gethostid*(): int {.importc, header: "<unistd.h>", sideEffect.}
proc gethostname*(a1: cstring, a2: int): cint {.importc, header: "<unistd.h>", sideEffect.}
proc getlogin*(): cstring {.importc, header: "<unistd.h>", sideEffect.}
proc getlogin_r*(a1: cstring, a2: int): cint {.importc, header: "<unistd.h>", sideEffect.}

proc getopt*(a1: cint, a2: cstringArray, a3: cstring): cint {.
  importc, header: "<unistd.h>".}
proc getpgid*(a1: Pid): Pid {.importc, header: "<unistd.h>".}
proc getpgrp*(): Pid {.importc, header: "<unistd.h>".}
proc getpid*(): Pid {.importc, header: "<unistd.h>", sideEffect.}
 ## returns  the process ID (PID) of the calling process

proc getppid*(): Pid {.importc, header: "<unistd.h>", sideEffect.}
 ## returns the process ID of the parent of the calling process

proc getsid*(a1: Pid): Pid {.importc, header: "<unistd.h>", sideEffect.}
 ## returns the session ID of the calling process

proc getwd*(a1: cstring): cstring {.importc, header: "<unistd.h>".}
proc isatty*(a1: cint): cint {.importc, header: "<unistd.h>".}
proc lchown*(a1: cstring, a2: Uid, a3: Gid): cint {.importc, header: "<unistd.h>".}
proc link*(a1, a2: cstring): cint {.importc, header: "<unistd.h>".}

proc lockf*(a1, a2: cint, a3: Off): cint {.importc, header: "<unistd.h>".}
proc lseek*(a1: cint, a2: Off, a3: cint): Off {.importc, header: "<unistd.h>".}
proc nice*(a1: cint): cint {.importc, header: "<unistd.h>".}
proc pathconf*(a1: cstring, a2: cint): int {.importc, header: "<unistd.h>".}

proc pause*(): cint {.importc, header: "<unistd.h>".}
proc pclose*(a: File): cint {.importc, header: "<stdio.h>".}
proc pipe*(a: array[0..1, cint]): cint {.importc, header: "<unistd.h>".}
proc popen*(a1, a2: cstring): File {.importc, header: "<stdio.h>".}
proc pread*(a1: cint, a2: pointer, a3: int, a4: Off): int {.
  importc, header: "<unistd.h>".}
proc pwrite*(a1: cint, a2: pointer, a3: int, a4: Off): int {.
  importc, header: "<unistd.h>".}
proc read*(a1: cint, a2: pointer, a3: int): int {.importc, header: "<unistd.h>".}
when not defined(nintendoswitch):
  proc readlink*(a1, a2: cstring, a3: int): int {.importc, header: "<unistd.h>".}
proc ioctl*(f: FileHandle, device: uint): int {.importc: "ioctl",
      header: "<sys/ioctl.h>", varargs, tags: [WriteIOEffect].}
  ## A system call for device-specific input/output operations and other
  ## operations which cannot be expressed by regular system calls

proc rmdir*(a1: cstring): cint {.importc, header: "<unistd.h>".}
proc setegid*(a1: Gid): cint {.importc, header: "<unistd.h>".}
proc seteuid*(a1: Uid): cint {.importc, header: "<unistd.h>".}
proc setgid*(a1: Gid): cint {.importc, header: "<unistd.h>".}

proc setpgid*(a1, a2: Pid): cint {.importc, header: "<unistd.h>".}
proc setpgrp*(): Pid {.importc, header: "<unistd.h>".}
proc setregid*(a1, a2: Gid): cint {.importc, header: "<unistd.h>".}
proc setreuid*(a1, a2: Uid): cint {.importc, header: "<unistd.h>".}
proc setsid*(): Pid {.importc, header: "<unistd.h>".}
proc setuid*(a1: Uid): cint {.importc, header: "<unistd.h>".}
proc sleep*(a1: cint): cint {.importc, header: "<unistd.h>".}
proc swab*(a1, a2: pointer, a3: int) {.importc, header: "<unistd.h>".}
when not defined(nintendoswitch):
  proc symlink*(a1, a2: cstring): cint {.importc, header: "<unistd.h>".}
else:
  proc symlink*(a1, a2: cstring): cint = -1
proc sync*() {.importc, header: "<unistd.h>".}
proc sysconf*(a1: cint): int {.importc, header: "<unistd.h>".}
proc tcgetpgrp*(a1: cint): Pid {.importc, header: "<unistd.h>".}
proc tcsetpgrp*(a1: cint, a2: Pid): cint {.importc, header: "<unistd.h>".}
proc truncate*(a1: cstring, a2: Off): cint {.importc, header: "<unistd.h>".}
proc ttyname*(a1: cint): cstring {.importc, header: "<unistd.h>".}
proc ttyname_r*(a1: cint, a2: cstring, a3: int): cint {.
  importc, header: "<unistd.h>".}
proc ualarm*(a1, a2: Useconds): Useconds {.importc, header: "<unistd.h>".}
proc unlink*(a1: cstring): cint {.importc, header: "<unistd.h>".}
proc usleep*(a1: Useconds): cint {.importc, header: "<unistd.h>".}
proc vfork*(): Pid {.importc, header: "<unistd.h>".}
proc write*(a1: cint, a2: pointer, a3: int): int {.importc, header: "<unistd.h>".}

proc sem_close*(a1: ptr Sem): cint {.importc, header: "<semaphore.h>".}
proc sem_destroy*(a1: ptr Sem): cint {.importc, header: "<semaphore.h>".}
proc sem_getvalue*(a1: ptr Sem, a2: var cint): cint {.
  importc, header: "<semaphore.h>".}
proc sem_init*(a1: ptr Sem, a2: cint, a3: cint): cint {.
  importc, header: "<semaphore.h>".}
proc sem_open*(a1: cstring, a2: cint): ptr Sem {.
  varargs, importc, header: "<semaphore.h>".}
proc sem_post*(a1: ptr Sem): cint {.importc, header: "<semaphore.h>".}
proc sem_timedwait*(a1: ptr Sem, a2: ptr Timespec): cint {.
  importc, header: "<semaphore.h>".}
proc sem_trywait*(a1: ptr Sem): cint {.importc, header: "<semaphore.h>".}
proc sem_unlink*(a1: cstring): cint {.importc, header: "<semaphore.h>".}
proc sem_wait*(a1: ptr Sem): cint {.importc, header: "<semaphore.h>".}

proc ftok*(a1: cstring, a2: cint): Key {.importc, header: "<sys/ipc.h>".}

proc statvfs*(a1: cstring, a2: var Statvfs): cint {.
  importc, header: "<sys/statvfs.h>".}
proc fstatvfs*(a1: cint, a2: var Statvfs): cint {.
  importc, header: "<sys/statvfs.h>".}

proc chmod*(a1: cstring, a2: Mode): cint {.importc, header: "<sys/stat.h>", sideEffect.}
when defined(osx) or defined(freebsd):
  proc lchmod*(a1: cstring, a2: Mode): cint {.importc, header: "<sys/stat.h>", sideEffect.}
proc fchmod*(a1: cint, a2: Mode): cint {.importc, header: "<sys/stat.h>", sideEffect.}
proc fstat*(a1: cint, a2: var Stat): cint {.importc, header: "<sys/stat.h>", sideEffect.}
proc lstat*(a1: cstring, a2: var Stat): cint {.importc, header: "<sys/stat.h>", sideEffect.}
proc mkdir*(a1: cstring, a2: Mode): cint {.importc, header: "<sys/stat.h>", sideEffect.}
  ## Use `os.createDir() <os.html#createDir,string>`_ and similar.

proc mkfifo*(a1: cstring, a2: Mode): cint {.importc, header: "<sys/stat.h>".}
proc mknod*(a1: cstring, a2: Mode, a3: Dev): cint {.
  importc, header: "<sys/stat.h>".}
proc stat*(a1: cstring, a2: var Stat): cint {.importc, header: "<sys/stat.h>".}
proc umask*(a1: Mode): Mode {.importc, header: "<sys/stat.h>".}

proc S_ISBLK*(m: Mode): bool {.importc, header: "<sys/stat.h>".}
  ## Test for a block special file.
proc S_ISCHR*(m: Mode): bool {.importc, header: "<sys/stat.h>".}
  ## Test for a character special file.
proc S_ISDIR*(m: Mode): bool {.importc, header: "<sys/stat.h>".}
  ## Test for a directory.
proc S_ISFIFO*(m: Mode): bool {.importc, header: "<sys/stat.h>".}
  ## Test for a pipe or FIFO special file.
proc S_ISREG*(m: Mode): bool {.importc, header: "<sys/stat.h>".}
  ## Test for a regular file.
proc S_ISLNK*(m: Mode): bool {.importc, header: "<sys/stat.h>".}
  ## Test for a symbolic link.
proc S_ISSOCK*(m: Mode): bool {.importc, header: "<sys/stat.h>".}
  ## Test for a socket.

proc S_TYPEISMQ*(buf: var Stat): bool {.importc, header: "<sys/stat.h>".}
  ## Test for a message queue.
proc S_TYPEISSEM*(buf: var Stat): bool {.importc, header: "<sys/stat.h>".}
  ## Test for a semaphore.
proc S_TYPEISSHM*(buf: var Stat): bool {.importc, header: "<sys/stat.h>".}
  ## Test for a shared memory object.

proc S_TYPEISTMO*(buf: var Stat): bool {.importc, header: "<sys/stat.h>".}
  ## Test macro for a typed memory object.

proc mlock*(a1: pointer, a2: int): cint {.importc, header: "<sys/mman.h>".}
proc mlockall*(a1: cint): cint {.importc, header: "<sys/mman.h>".}
proc mmap*(a1: pointer, a2: int, a3, a4, a5: cint, a6: Off): pointer {.
  importc, header: "<sys/mman.h>".}
proc mprotect*(a1: pointer, a2: int, a3: cint): cint {.
  importc, header: "<sys/mman.h>".}
proc msync*(a1: pointer, a2: int, a3: cint): cint {.importc, header: "<sys/mman.h>".}

proc munlock*(a1: pointer, a2: int): cint {.importc, header: "<sys/mman.h>".}
proc munlockall*(): cint {.importc, header: "<sys/mman.h>".}
proc munmap*(a1: pointer, a2: int): cint {.importc, header: "<sys/mman.h>".}
proc posix_madvise*(a1: pointer, a2: int, a3: cint): cint {.
  importc, header: "<sys/mman.h>".}
proc posix_mem_offset*(a1: pointer, a2: int, a3: var Off,
           a4: var int, a5: var cint): cint {.importc, header: "<sys/mman.h>".}
when not (defined(linux) and defined(amd64)) and not defined(nintendoswitch) and
     not defined(haiku):
  proc posix_typed_mem_get_info*(a1: cint,
    a2: var Posix_typed_mem_info): cint {.importc, header: "<sys/mman.h>".}
proc posix_typed_mem_open*(a1: cstring, a2, a3: cint): cint {.
  importc, header: "<sys/mman.h>".}
proc shm_open*(a1: cstring, a2: cint, a3: Mode): cint {.
  importc, header: "<sys/mman.h>".}
proc shm_unlink*(a1: cstring): cint {.importc, header: "<sys/mman.h>".}

proc asctime*(a1: var Tm): cstring{.importc, header: "<time.h>".}

proc asctime_r*(a1: var Tm, a2: cstring): cstring {.importc, header: "<time.h>".}
proc clock*(): Clock {.importc, header: "<time.h>", sideEffect.}
proc clock_getcpuclockid*(a1: Pid, a2: var ClockId): cint {.
  importc, header: "<time.h>", sideEffect.}
proc clock_getres*(a1: ClockId, a2: var Timespec): cint {.
  importc, header: "<time.h>", sideEffect.}
proc clock_gettime*(a1: ClockId, a2: var Timespec): cint {.
  importc, header: "<time.h>", sideEffect.}
proc clock_nanosleep*(a1: ClockId, a2: cint, a3: var Timespec,
               a4: var Timespec): cint {.importc, header: "<time.h>", sideEffect.}
proc clock_settime*(a1: ClockId, a2: var Timespec): cint {.
  importc, header: "<time.h>", sideEffect.}

proc `==`*(a, b: Time): bool {.borrow.}
proc `-`*(a, b: Time): Time {.borrow.}
proc ctime*(a1: var Time): cstring {.importc, header: "<time.h>".}
proc ctime_r*(a1: var Time, a2: cstring): cstring {.importc, header: "<time.h>".}
proc difftime*(a1, a2: Time): cdouble {.importc, header: "<time.h>".}
proc getdate*(a1: cstring): ptr Tm {.importc, header: "<time.h>".}
proc gmtime*(a1: var Time): ptr Tm {.importc, header: "<time.h>".}
proc gmtime_r*(a1: var Time, a2: var Tm): ptr Tm {.importc, header: "<time.h>".}
proc localtime*(a1: var Time): ptr Tm {.importc, header: "<time.h>".}
proc localtime_r*(a1: var Time, a2: var Tm): ptr Tm {.importc, header: "<time.h>".}
proc mktime*(a1: var Tm): Time  {.importc, header: "<time.h>".}
proc timegm*(a1: var Tm): Time  {.importc, header: "<time.h>".}
proc nanosleep*(a1, a2: var Timespec): cint {.importc, header: "<time.h>", sideEffect.}
proc strftime*(a1: cstring, a2: int, a3: cstring,
           a4: var Tm): int {.importc, header: "<time.h>".}
proc strptime*(a1, a2: cstring, a3: var Tm): cstring {.importc, header: "<time.h>".}
proc time*(a1: var Time): Time {.importc, header: "<time.h>", sideEffect.}
proc timer_create*(a1: ClockId, a2: var SigEvent,
               a3: var Timer): cint {.importc, header: "<time.h>".}
proc timer_delete*(a1: Timer): cint {.importc, header: "<time.h>".}
proc timer_gettime*(a1: Timer, a2: var Itimerspec): cint {.
  importc, header: "<time.h>".}
proc timer_getoverrun*(a1: Timer): cint {.importc, header: "<time.h>".}
proc timer_settime*(a1: Timer, a2: cint, a3: var Itimerspec,
               a4: var Itimerspec): cint {.importc, header: "<time.h>".}
proc tzset*() {.importc, header: "<time.h>".}


proc wait*(a1: ptr cint): Pid {.importc, discardable, header: "<sys/wait.h>", sideEffect.}
proc waitid*(a1: cint, a2: Id, a3: var SigInfo, a4: cint): cint {.
  importc, header: "<sys/wait.h>", sideEffect.}
proc waitpid*(a1: Pid, a2: var cint, a3: cint): Pid {.
  importc, header: "<sys/wait.h>", sideEffect.}

type Rusage* {.importc: "struct rusage", header: "<sys/resource.h>",
               bycopy.} = object
  ru_utime*, ru_stime*: Timeval                       # User and system time
  ru_maxrss*, ru_ixrss*, ru_idrss*, ru_isrss*,        # memory sizes
    ru_minflt*, ru_majflt*, ru_nswap*,                # paging activity
    ru_inblock*, ru_oublock*, ru_msgsnd*, ru_msgrcv*, # IO activity
    ru_nsignals*, ru_nvcsw*, ru_nivcsw*: clong        # switching activity

proc wait4*(pid: Pid, status: ptr cint, options: cint, rusage: ptr Rusage): Pid
  {.importc, header: "<sys/wait.h>", sideEffect.}

const
  RUSAGE_SELF* = cint(0)
  RUSAGE_CHILDREN* = cint(-1)
  RUSAGE_THREAD* = cint(1)    # This one is less std; Linux, BSD agree though.

# This can only fail if `who` is invalid or `rusage` ptr is invalid.
proc getrusage*(who: cint, rusage: ptr Rusage): cint
  {.importc, header: "<sys/resource.h>", discardable.}

proc bsd_signal*(a1: cint, a2: proc (x: pointer) {.noconv.}) {.
  importc, header: "<signal.h>".}
proc kill*(a1: Pid, a2: cint): cint {.importc, header: "<signal.h>", sideEffect.}
proc killpg*(a1: Pid, a2: cint): cint {.importc, header: "<signal.h>", sideEffect.}
proc pthread_kill*(a1: Pthread, a2: cint): cint {.importc, header: "<signal.h>".}
proc pthread_sigmask*(a1: cint, a2, a3: var Sigset): cint {.
  importc, header: "<signal.h>".}
proc `raise`*(a1: cint): cint {.importc, header: "<signal.h>".}
proc sigaction*(a1: cint, a2, a3: var Sigaction): cint {.
  importc, header: "<signal.h>".}

proc sigaction*(a1: cint, a2: var Sigaction; a3: ptr Sigaction = nil): cint {.
  importc, header: "<signal.h>".}

proc sigaddset*(a1: var Sigset, a2: cint): cint {.importc, header: "<signal.h>".}
proc sigaltstack*(a1, a2: var Stack): cint {.importc, header: "<signal.h>".}
proc sigdelset*(a1: var Sigset, a2: cint): cint {.importc, header: "<signal.h>".}
proc sigemptyset*(a1: var Sigset): cint {.importc, header: "<signal.h>".}
proc sigfillset*(a1: var Sigset): cint {.importc, header: "<signal.h>".}
proc sighold*(a1: cint): cint {.importc, header: "<signal.h>".}
proc sigignore*(a1: cint): cint {.importc, header: "<signal.h>".}
proc siginterrupt*(a1, a2: cint): cint {.importc, header: "<signal.h>".}
proc sigismember*(a1: var Sigset, a2: cint): cint {.importc, header: "<signal.h>".}
proc signal*(a1: cint, a2: Sighandler) {.
  importc, header: "<signal.h>".}
proc sigpause*(a1: cint): cint {.importc, header: "<signal.h>".}
proc sigpending*(a1: var Sigset): cint {.importc, header: "<signal.h>".}
proc sigprocmask*(a1: cint, a2, a3: var Sigset): cint {.
  importc, header: "<signal.h>".}
proc sigqueue*(a1: Pid, a2: cint, a3: SigVal): cint {.
  importc, header: "<signal.h>".}
proc sigrelse*(a1: cint): cint {.importc, header: "<signal.h>".}
proc sigset*(a1: int, a2: proc (x: cint) {.noconv.}) {.
  importc, header: "<signal.h>".}
proc sigsuspend*(a1: var Sigset): cint {.importc, header: "<signal.h>".}

when defined(android):
  proc syscall(arg: clong): clong {.varargs, importc: "syscall", header: "<unistd.h>".}
  var NR_rt_sigtimedwait {.importc: "__NR_rt_sigtimedwait", header: "<sys/syscall.h>".}: clong
  var NSIGMAX {.importc: "NSIG", header: "<signal.h>".}: clong

  proc sigtimedwait*(a1: var Sigset, a2: var SigInfo, a3: var Timespec): cint =
    result = cint(syscall(NR_rt_sigtimedwait, addr(a1), addr(a2), addr(a3), NSIGMAX div 8))
else:
  proc sigtimedwait*(a1: var Sigset, a2: var SigInfo,
                     a3: var Timespec): cint {.importc, header: "<signal.h>".}

when defined(sunos) or defined(solaris):
  # The following compile time flag is needed on Illumos/Solaris to use the POSIX
  # `sigwait` implementation. See the documentation here:
  # https://docs.oracle.com/cd/E19455-01/806-5257/6je9h033k/index.html
  # https://www.illumos.org/man/2/sigwait
  {.passc: "-D_POSIX_PTHREAD_SEMANTICS".}

proc sigwait*(a1: var Sigset, a2: var cint): cint {.
  importc, header: "<signal.h>".}
proc sigwaitinfo*(a1: var Sigset, a2: var SigInfo): cint {.
  importc, header: "<signal.h>".}

when not defined(nintendoswitch):
  proc catclose*(a1: Nl_catd): cint {.importc, header: "<nl_types.h>".}
  proc catgets*(a1: Nl_catd, a2, a3: cint, a4: cstring): cstring {.
    importc, header: "<nl_types.h>".}
  proc catopen*(a1: cstring, a2: cint): Nl_catd {.
    importc, header: "<nl_types.h>".}

proc sched_get_priority_max*(a1: cint): cint {.importc, header: "<sched.h>".}
proc sched_get_priority_min*(a1: cint): cint {.importc, header: "<sched.h>".}
proc sched_getparam*(a1: Pid, a2: var Sched_param): cint {.
  importc, header: "<sched.h>".}
proc sched_getscheduler*(a1: Pid): cint {.importc, header: "<sched.h>".}
proc sched_rr_get_interval*(a1: Pid, a2: var Timespec): cint {.
  importc, header: "<sched.h>".}
proc sched_setparam*(a1: Pid, a2: var Sched_param): cint {.
  importc, header: "<sched.h>".}
proc sched_setscheduler*(a1: Pid, a2: cint, a3: var Sched_param): cint {.
  importc, header: "<sched.h>".}
proc sched_yield*(): cint {.importc, header: "<sched.h>".}

proc hstrerror*(herrnum: cint): cstring {.importc:"(char *)$1", header: "<netdb.h>".}

proc FD_CLR*(a1: cint, a2: var TFdSet) {.importc, header: "<sys/select.h>".}
proc FD_ISSET*(a1: cint | SocketHandle, a2: var TFdSet): cint {.
  importc, header: "<sys/select.h>".}
proc FD_SET*(a1: cint | SocketHandle, a2: var TFdSet) {.
  importc: "FD_SET", header: "<sys/select.h>".}
proc FD_ZERO*(a1: var TFdSet) {.importc, header: "<sys/select.h>".}

proc pselect*(a1: cint, a2, a3, a4: ptr TFdSet, a5: ptr Timespec,
         a6: var Sigset): cint  {.importc, header: "<sys/select.h>".}
proc select*(a1: cint | SocketHandle, a2, a3, a4: ptr TFdSet, a5: ptr Timeval): cint {.
             importc, header: "<sys/select.h>".}

when hasSpawnH:
  proc posix_spawn*(a1: var Pid, a2: cstring,
            a3: var Tposix_spawn_file_actions,
            a4: var Tposix_spawnattr,
            a5, a6: cstringArray): cint {.importc, header: "<spawn.h>".}
  proc posix_spawn_file_actions_addclose*(a1: var Tposix_spawn_file_actions,
            a2: cint): cint {.importc, header: "<spawn.h>".}
  proc posix_spawn_file_actions_adddup2*(a1: var Tposix_spawn_file_actions,
            a2, a3: cint): cint {.importc, header: "<spawn.h>".}
  proc posix_spawn_file_actions_addopen*(a1: var Tposix_spawn_file_actions,
            a2: cint, a3: cstring, a4: cint, a5: Mode): cint {.
            importc, header: "<spawn.h>".}
  proc posix_spawn_file_actions_destroy*(
    a1: var Tposix_spawn_file_actions): cint {.importc, header: "<spawn.h>".}
  proc posix_spawn_file_actions_init*(
    a1: var Tposix_spawn_file_actions): cint {.importc, header: "<spawn.h>".}
  proc posix_spawnattr_destroy*(a1: var Tposix_spawnattr): cint {.
    importc, header: "<spawn.h>".}
  proc posix_spawnattr_getsigdefault*(a1: var Tposix_spawnattr,
            a2: var Sigset): cint {.importc, header: "<spawn.h>".}
  proc posix_spawnattr_getflags*(a1: var Tposix_spawnattr,
            a2: var cshort): cint {.importc, header: "<spawn.h>".}
  proc posix_spawnattr_getpgroup*(a1: var Tposix_spawnattr,
            a2: var Pid): cint {.importc, header: "<spawn.h>".}
  proc posix_spawnattr_getschedparam*(a1: var Tposix_spawnattr,
            a2: var Sched_param): cint {.importc, header: "<spawn.h>".}
  proc posix_spawnattr_getschedpolicy*(a1: var Tposix_spawnattr,
            a2: var cint): cint {.importc, header: "<spawn.h>".}
  proc posix_spawnattr_getsigmask*(a1: var Tposix_spawnattr,
            a2: var Sigset): cint {.importc, header: "<spawn.h>".}

  proc posix_spawnattr_init*(a1: var Tposix_spawnattr): cint {.
    importc, header: "<spawn.h>".}
  proc posix_spawnattr_setsigdefault*(a1: var Tposix_spawnattr,
            a2: var Sigset): cint {.importc, header: "<spawn.h>".}
  proc posix_spawnattr_setflags*(a1: var Tposix_spawnattr, a2: cint): cint {.
    importc, header: "<spawn.h>".}
  proc posix_spawnattr_setpgroup*(a1: var Tposix_spawnattr, a2: Pid): cint {.
    importc, header: "<spawn.h>".}

  proc posix_spawnattr_setschedparam*(a1: var Tposix_spawnattr,
            a2: var Sched_param): cint {.importc, header: "<spawn.h>".}
  proc posix_spawnattr_setschedpolicy*(a1: var Tposix_spawnattr,
                                       a2: cint): cint {.
                                       importc, header: "<spawn.h>".}
  proc posix_spawnattr_setsigmask*(a1: var Tposix_spawnattr,
            a2: var Sigset): cint {.importc, header: "<spawn.h>".}
  proc posix_spawnp*(a1: var Pid, a2: cstring,
            a3: var Tposix_spawn_file_actions,
            a4: var Tposix_spawnattr,
            a5, a6: cstringArray): cint {.importc, header: "<spawn.h>".}

when not defined(nintendoswitch):
  proc getcontext*(a1: var Ucontext): cint {.importc, header: "<ucontext.h>".}
  proc makecontext*(a1: var Ucontext, a4: proc (){.noconv.}, a3: cint) {.
    varargs, importc, header: "<ucontext.h>".}
  proc setcontext*(a1: var Ucontext): cint {.importc, header: "<ucontext.h>".}
  proc swapcontext*(a1, a2: var Ucontext): cint {.importc, header: "<ucontext.h>".}

proc readv*(a1: cint, a2: ptr IOVec, a3: cint): int {.
  importc, header: "<sys/uio.h>".}
proc writev*(a1: cint, a2: ptr IOVec, a3: cint): int {.
  importc, header: "<sys/uio.h>".}

proc CMSG_DATA*(cmsg: ptr Tcmsghdr): cstring {.
  importc, header: "<sys/socket.h>".}

proc CMSG_NXTHDR*(mhdr: ptr Tmsghdr, cmsg: ptr Tcmsghdr): ptr Tcmsghdr {.
  importc, header: "<sys/socket.h>".}

proc CMSG_FIRSTHDR*(mhdr: ptr Tmsghdr): ptr Tcmsghdr {.
  importc, header: "<sys/socket.h>".}

proc CMSG_SPACE*(len: csize_t): csize_t {.
  importc, header: "<sys/socket.h>".}

proc CMSG_LEN*(len: csize_t): csize_t {.
  importc, header: "<sys/socket.h>".}

const
  INVALID_SOCKET* = SocketHandle(-1)

proc `==`*(x, y: SocketHandle): bool {.borrow.}

proc accept*(a1: SocketHandle, a2: ptr SockAddr, a3: ptr SockLen): SocketHandle {.
  importc, header: "<sys/socket.h>", sideEffect.}

when defined(linux) or defined(bsd) or defined(nuttx):
  proc accept4*(a1: SocketHandle, a2: ptr SockAddr, a3: ptr SockLen,
                flags: cint): SocketHandle {.importc, header: "<sys/socket.h>".}

proc bindSocket*(a1: SocketHandle, a2: ptr SockAddr, a3: SockLen): cint {.
  importc: "bind", header: "<sys/socket.h>".}
  ## is Posix's `bind`, because `bind` is a reserved word

proc connect*(a1: SocketHandle, a2: ptr SockAddr, a3: SockLen): cint {.
  importc, header: "<sys/socket.h>".}
proc getpeername*(a1: SocketHandle, a2: ptr SockAddr, a3: ptr SockLen): cint {.
  importc, header: "<sys/socket.h>".}
proc getsockname*(a1: SocketHandle, a2: ptr SockAddr, a3: ptr SockLen): cint {.
  importc, header: "<sys/socket.h>".}

proc getsockopt*(a1: SocketHandle, a2, a3: cint, a4: pointer, a5: ptr SockLen): cint {.
  importc, header: "<sys/socket.h>".}

proc listen*(a1: SocketHandle, a2: cint): cint {.
  importc, header: "<sys/socket.h>", sideEffect.}
proc recv*(a1: SocketHandle, a2: pointer, a3: int, a4: cint): int {.
  importc, header: "<sys/socket.h>", sideEffect.}
proc recvfrom*(a1: SocketHandle, a2: pointer, a3: int, a4: cint,
        a5: ptr SockAddr, a6: ptr SockLen): int {.
  importc, header: "<sys/socket.h>", sideEffect.}
proc recvmsg*(a1: SocketHandle, a2: ptr Tmsghdr, a3: cint): int {.
  importc, header: "<sys/socket.h>", sideEffect.}
proc send*(a1: SocketHandle, a2: pointer, a3: int, a4: cint): int {.
  importc, header: "<sys/socket.h>", sideEffect.}
proc sendmsg*(a1: SocketHandle, a2: ptr Tmsghdr, a3: cint): int {.
  importc, header: "<sys/socket.h>", sideEffect.}
proc sendto*(a1: SocketHandle, a2: pointer, a3: int, a4: cint, a5: ptr SockAddr,
             a6: SockLen): int {.
  importc, header: "<sys/socket.h>", sideEffect.}
proc setsockopt*(a1: SocketHandle, a2, a3: cint, a4: pointer, a5: SockLen): cint {.
  importc, header: "<sys/socket.h>".}
proc shutdown*(a1: SocketHandle, a2: cint): cint {.
  importc, header: "<sys/socket.h>".}
proc socket*(a1, a2, a3: cint): SocketHandle {.
  importc, header: "<sys/socket.h>".}
proc sockatmark*(a1: cint): cint {.
  importc, header: "<sys/socket.h>".}
proc socketpair*(a1, a2, a3: cint, a4: var array[0..1, cint]): cint {.
  importc, header: "<sys/socket.h>".}

proc if_nametoindex*(a1: cstring): cint {.importc, header: "<net/if.h>".}
proc if_indextoname*(a1: cint, a2: cstring): cstring {.
  importc, header: "<net/if.h>".}
proc if_nameindex*(): ptr Tif_nameindex {.importc, header: "<net/if.h>".}
proc if_freenameindex*(a1: ptr Tif_nameindex) {.importc, header: "<net/if.h>".}

proc IN6_IS_ADDR_UNSPECIFIED* (a1: ptr In6Addr): cint {.
  importc, header: "<netinet/in.h>".}
  ## Unspecified address.
proc IN6_IS_ADDR_LOOPBACK* (a1: ptr In6Addr): cint {.
  importc, header: "<netinet/in.h>".}
  ## Loopback address.
proc IN6_IS_ADDR_MULTICAST* (a1: ptr In6Addr): cint {.
  importc, header: "<netinet/in.h>".}
  ## Multicast address.
proc IN6_IS_ADDR_LINKLOCAL* (a1: ptr In6Addr): cint {.
  importc, header: "<netinet/in.h>".}
  ## Unicast link-local address.
proc IN6_IS_ADDR_SITELOCAL* (a1: ptr In6Addr): cint {.
  importc, header: "<netinet/in.h>".}
  ## Unicast site-local address.
when defined(lwip):
  proc IN6_IS_ADDR_V4MAPPED*(ipv6_address: ptr In6Addr): cint =
    var bits32: ptr array[4, uint32] = cast[ptr array[4, uint32]](ipv6_address)
    return (bits32[1] == 0'u32 and bits32[2] == htonl(0x0000FFFF)).cint
else:
  proc IN6_IS_ADDR_V4MAPPED* (a1: ptr In6Addr): cint {.
    importc, header: "<netinet/in.h>".}
    ## IPv4 mapped address.

proc IN6_IS_ADDR_V4COMPAT* (a1: ptr In6Addr): cint {.
  importc, header: "<netinet/in.h>".}
  ## IPv4-compatible address.
proc IN6_IS_ADDR_MC_NODELOCAL* (a1: ptr In6Addr): cint {.
  importc, header: "<netinet/in.h>".}
  ## Multicast node-local address.
proc IN6_IS_ADDR_MC_LINKLOCAL* (a1: ptr In6Addr): cint {.
  importc, header: "<netinet/in.h>".}
  ## Multicast link-local address.
proc IN6_IS_ADDR_MC_SITELOCAL* (a1: ptr In6Addr): cint {.
  importc, header: "<netinet/in.h>".}
  ## Multicast site-local address.
proc IN6_IS_ADDR_MC_ORGLOCAL* (a1: ptr In6Addr): cint {.
  importc, header: "<netinet/in.h>".}
  ## Multicast organization-local address.
proc IN6_IS_ADDR_MC_GLOBAL* (a1: ptr In6Addr): cint {.
  importc, header: "<netinet/in.h>".}
  ## Multicast global address.

proc endhostent*() {.importc, header: "<netdb.h>".}
proc endnetent*() {.importc, header: "<netdb.h>".}
proc endprotoent*() {.importc, header: "<netdb.h>".}
proc endservent*() {.importc, header: "<netdb.h>".}
proc freeAddrInfo*(a1: ptr AddrInfo) {.importc: "freeaddrinfo", header: "<netdb.h>".}

proc gai_strerror*(a1: cint): cstring {.importc:"(char *)$1", header: "<netdb.h>".}

proc getaddrinfo*(a1, a2: cstring, a3: ptr AddrInfo,
                  a4: var ptr AddrInfo): cint {.importc, header: "<netdb.h>".}

when not defined(android4):
  proc gethostbyaddr*(a1: pointer, a2: SockLen, a3: cint): ptr Hostent {.
                      importc, header: "<netdb.h>".}
else:
  proc gethostbyaddr*(a1: cstring, a2: cint, a3: cint): ptr Hostent {.
                      importc, header: "<netdb.h>".}
proc gethostbyname*(a1: cstring): ptr Hostent {.importc, header: "<netdb.h>".}
proc gethostent*(): ptr Hostent {.importc, header: "<netdb.h>".}

proc getnameinfo*(a1: ptr SockAddr, a2: SockLen,
                  a3: cstring, a4: SockLen, a5: cstring,
                  a6: SockLen, a7: cint): cint {.importc, header: "<netdb.h>".}

proc getnetbyaddr*(a1: int32, a2: cint): ptr Tnetent {.importc, header: "<netdb.h>".}
proc getnetbyname*(a1: cstring): ptr Tnetent {.importc, header: "<netdb.h>".}
proc getnetent*(): ptr Tnetent {.importc, header: "<netdb.h>".}

proc getprotobyname*(a1: cstring): ptr Protoent {.importc, header: "<netdb.h>".}
proc getprotobynumber*(a1: cint): ptr Protoent {.importc, header: "<netdb.h>".}
proc getprotoent*(): ptr Protoent {.importc, header: "<netdb.h>".}

proc getservbyname*(a1, a2: cstring): ptr Servent {.importc, header: "<netdb.h>".}
proc getservbyport*(a1: cint, a2: cstring): ptr Servent {.
  importc, header: "<netdb.h>".}
proc getservent*(): ptr Servent {.importc, header: "<netdb.h>".}

proc sethostent*(a1: cint) {.importc, header: "<netdb.h>".}
proc setnetent*(a1: cint) {.importc, header: "<netdb.h>".}
proc setprotoent*(a1: cint) {.importc, header: "<netdb.h>".}
proc setservent*(a1: cint) {.importc, header: "<netdb.h>".}

when not defined(lwip):
  # Linux and Haiku emulate SVR4, which used unsigned long.
  # Meanwhile, BSD derivatives had used unsigned int; we will use this
  # for the else case, because it is more widely cloned than SVR4's
  # behavior.
  when defined(linux) or defined(haiku):
    type
      Tnfds* {.importc: "nfds_t", header: "<poll.h>".} = culong
  elif defined(zephyr):
    type
      Tnfds* = distinct cint
  else:
    type
      Tnfds* {.importc: "nfds_t", header: "<poll.h>".} = cuint

  proc poll*(a1: ptr TPollfd, a2: Tnfds, a3: cint): cint {.
    importc, header: "<poll.h>", sideEffect.}

proc realpath*(name, resolved: cstring): cstring {.
  importc: "realpath", header: "<stdlib.h>".}

proc mkstemp*(tmpl: cstring): cint {.importc, header: "<stdlib.h>", sideEffect.}
  ## Creates a unique temporary file.
  ##
  ## .. warning:: The `tmpl` argument is written to by `mkstemp` and thus
  ##   can't be a string literal. If in doubt make a copy of the cstring before
  ##   passing it in.

proc mkstemps*(tmpl: cstring, suffixlen: int): cint {.importc, header: "<stdlib.h>", sideEffect.}
  ## Creates a unique temporary file.
  ##
  ## .. warning:: The `tmpl` argument is written to by `mkstemps` and thus
  ##   can't be a string literal. If in doubt make a copy of the cstring before
  ##   passing it in.

proc mkdtemp*(tmpl: cstring): pointer {.importc, header: "<stdlib.h>", sideEffect.}

when defined(linux) or defined(bsd) or defined(osx):
  proc mkostemp*(tmpl: cstring, oflags: cint): cint {.importc, header: "<stdlib.h>", sideEffect.}
  proc mkostemps*(tmpl: cstring, suffixlen: cint, oflags: cint): cint {.importc, header: "<stdlib.h>", sideEffect.}

  proc posix_memalign*(memptr: pointer, alignment: csize_t, size: csize_t): cint {.importc, header: "<stdlib.h>".}

proc utimes*(path: cstring, times: ptr array[2, Timeval]): int {.
  importc: "utimes", header: "<sys/time.h>", sideEffect.}
  ## Sets file access and modification times.
  ##
  ## Pass the filename and an array of times to set the access and modification
  ## times respectively. If you pass nil as the array both attributes will be
  ## set to the current time.
  ##
  ## Returns zero on success.
  ##
  ## For more information read https://www.unix.com/man-page/posix/3/utimes/.

proc handle_signal(sig: cint, handler: proc (a: cint) {.noconv.}) {.importc: "signal", header: "<signal.h>".}

template onSignal*(signals: varargs[cint], body: untyped) =
  ## Setup code to be executed when Unix signals are received. The
  ## currently handled signal is injected as `sig` into the calling
  ## scope.
  ##
  ## Example:
  ##   ```Nim
  ##   from std/posix import SIGINT, SIGTERM, onSignal
  ##   onSignal(SIGINT, SIGTERM):
  ##     echo "bye from signal ", sig
  ##   ```

  for s in signals:
    handle_signal(s,
      proc (signal: cint) {.noconv.} =
        let sig {.inject.} = signal
        body
    )

type
  RLimit* {.importc: "struct rlimit",
            header: "<sys/resource.h>", pure, final.} = object
    rlim_cur*: int
    rlim_max*: int
  ## The getrlimit() and setrlimit() system calls get and set resource limits respectively.
  ## Each resource has an associated soft and hard limit, as defined by the RLimit structure

proc setrlimit*(resource: cint, rlp: var RLimit): cint {.
  importc: "setrlimit", header: "<sys/resource.h>".}
  ## The setrlimit() system calls sets resource limits.

proc getrlimit*(resource: cint, rlp: var RLimit): cint {.
  importc: "getrlimit", header: "<sys/resource.h>".}
  ## The getrlimit() system call gets resource limits.

when defined(nimHasStyleChecks):
  {.pop.} # {.push styleChecks: off.}
