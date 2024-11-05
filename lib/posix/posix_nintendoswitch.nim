#
#
#            Nim's Runtime Library
#        (c) Copyright 2018 Joey Yakimowich-Payne
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# To be included from posix.nim!

const
  hasSpawnH = true
  hasAioH = false

type
  DIR* {.importc: "DIR", header: "<dirent.h>",
          incompleteStruct.} = object

const SIG_HOLD* = cast[Sighandler](2)

type
  SocketHandle* = distinct cint # The type used to represent socket descriptors

type
  Time* {.importc: "time_t", header: "<time.h>".} = distinct clong

  Timespec* {.importc: "struct timespec",
               header: "<time.h>", final, pure.} = object ## struct timespec
    tv_sec*: Time  ## Seconds.
    tv_nsec*: clong  ## Nanoseconds.

  Dirent* {.importc: "struct dirent",
            header: "<dirent.h>", final, pure.} = object ## dirent_t struct
    d_ino*: Ino
    d_type*: int8  # uint8 really!
    d_name*: array[256, cchar]

  Tflock* {.importc: "struct flock", final, pure,
            header: "<fcntl.h>".} = object ## flock type
    l_type*: cshort   ## Type of lock; F_RDLCK, F_WRLCK, F_UNLCK.
    l_whence*: cshort ## Flag for starting offset.
    l_start*: Off     ## Relative offset in bytes.
    l_len*: Off       ## Size; if 0 then until EOF.
    l_pid*: Pid      ## Process ID of the process holding the lock;
                      ## returned with F_GETLK.

  # no struct FTW on linux

  Glob* {.importc: "glob_t", header: "<glob.h>",
           final, pure.} = object ## glob_t
    gl_pathc*: cint          ## Count of paths matched by pattern.
    gl_matchc*: cint          ## Count of paths matching pattern
    gl_offs*: cint           ## Slots to reserve at the beginning of gl_pathv.
    gl_flags*: cint
    gl_pathv*: cstringArray ## Pointer to a list of matched pathnames.
    gl_errfunc*: pointer
    gl_closedir*: pointer
    gl_readdir*: pointer
    gl_opendir*: pointer
    gl_lstat*: pointer
    gl_stat*: pointer

  Group* {.importc: "struct group", header: "<grp.h>",
            final, pure.} = object ## struct group
    gr_name*: cstring     ## The name of the group.
    gr_passwd*: cstring
    gr_gid*: Gid         ## Numerical group ID.
    gr_mem*: cstringArray ## Pointer to a null-terminated array of character
                          ## pointers to member names.

  Iconv* {.importc: "iconv_t", header: "<iconv.h>".} = pointer
     ## Identifies the conversion from one codeset to another.

  Lconv* {.importc: "struct lconv", header: "<locale.h>", final,
            pure.} = object
    decimal_point*: cstring
    thousands_sep*: cstring
    grouping*: cstring
    int_curr_symbol*: cstring
    currency_symbol*: cstring
    mon_decimal_point*: cstring
    mon_thousands_sep*: cstring
    mon_grouping*: cstring
    positive_sign*: cstring
    negative_sign*: cstring
    int_frac_digits*: char
    frac_digits*: char
    p_cs_precedes*: char
    p_sep_by_space*: char
    n_cs_precedes*: char
    n_sep_by_space*: char
    p_sign_posn*: char
    n_sign_posn*: char
    int_n_cs_precedes*: char
    int_n_sep_by_space*: char
    int_n_sign_posn*: char
    int_p_cs_precedes*: char
    int_p_sep_by_space*: char
    int_p_sign_posn*: char

  Passwd* {.importc: "struct passwd", header: "<pwd.h>",
             final, pure.} = object ## struct passwd
    pw_name*: cstring   ## User's login name.
    pw_passwd*: cstring
    pw_uid*: Uid        ## Numerical user ID.
    pw_gid*: Gid        ## Numerical group ID.
    pw_comment*: cstring
    pw_gecos*: cstring
    pw_dir*: cstring    ## Initial working directory.
    pw_shell*: cstring  ## Program to use as shell.

  Blkcnt* {.importc: "blkcnt_t", header: "<sys/types.h>".} = clong
    ## used for file block counts
  Blksize* {.importc: "blksize_t", header: "<sys/types.h>".} = clong
    ## used for block sizes
  Clock* {.importc: "clock_t", header: "<sys/types.h>".} = clong
  ClockId* {.importc: "clockid_t", header: "<sys/types.h>".} = cint
  Dev* {.importc: "dev_t", header: "<sys/types.h>".} = culong
  Fsblkcnt* {.importc: "fsblkcnt_t", header: "<sys/types.h>".} = culong
  Fsfilcnt* {.importc: "fsfilcnt_t", header: "<sys/types.h>".} = culong
  Gid* {.importc: "gid_t", header: "<sys/types.h>".} = cuint
  Id* {.importc: "id_t", header: "<sys/types.h>".} = cuint
  Ino* {.importc: "ino_t", header: "<sys/types.h>".} = culong
  Key* {.importc: "key_t", header: "<sys/types.h>".} = cint
  Mode* {.importc: "mode_t", header: "<sys/types.h>".} = uint16
  Nlink* {.importc: "nlink_t", header: "<sys/types.h>".} = culong
  Off* {.importc: "off_t", header: "<sys/types.h>".} = clong
  Pid* {.importc: "pid_t", header: "<sys/types.h>".} = cint
  Pthread_attr* {.importc: "pthread_attr_t", header: "<sys/types.h>",
                  pure, final.} = object
    abi: array[56 div sizeof(clong), clong]

  Pthread_barrier* {.importc: "pthread_barrier_t",
                      header: "<sys/types.h>", pure, final.} = object
    abi: array[32 div sizeof(clong), clong]
  Pthread_barrierattr* {.importc: "pthread_barrierattr_t",
                          header: "<sys/types.h>", pure, final.} = object
    abi: array[4 div sizeof(cint), cint]

  Pthread_cond* {.importc: "pthread_cond_t", header: "<sys/types.h>",
                  pure, final.} = object
    abi: array[48 div sizeof(clonglong), clonglong]
  Pthread_condattr* {.importc: "pthread_condattr_t",
                       header: "<sys/types.h>", pure, final.} = object
    abi: array[4 div sizeof(cint), cint]
  Pthread_key* {.importc: "pthread_key_t", header: "<sys/types.h>".} = cuint
  Pthread_mutex* {.importc: "pthread_mutex_t", header: "<sys/types.h>",
                   pure, final.} = object
    abi: array[48 div sizeof(clong), clong]
  Pthread_mutexattr* {.importc: "pthread_mutexattr_t",
                        header: "<sys/types.h>", pure, final.} = object
    abi: array[4 div sizeof(cint), cint]
  Pthread_once* {.importc: "pthread_once_t", header: "<sys/types.h>".} = cint
  Pthread_rwlock* {.importc: "pthread_rwlock_t",
                     header: "<sys/types.h>", pure, final.} = object
    abi: array[56 div sizeof(clong), clong]
  Pthread_rwlockattr* {.importc: "pthread_rwlockattr_t",
                         header: "<sys/types.h>".} = object
    abi: array[8 div sizeof(clong), clong]
  Pthread_spinlock* {.importc: "pthread_spinlock_t",
                       header: "<sys/types.h>".} = cint
  Pthread* {.importc: "pthread_t", header: "<sys/types.h>".} = culong
  Suseconds* {.importc: "suseconds_t", header: "<sys/types.h>".} = clong
  #Ttime* {.importc: "time_t", header: "<sys/types.h>".} = int
  Timer* {.importc: "timer_t", header: "<sys/types.h>".} = pointer
  Uid* {.importc: "uid_t", header: "<sys/types.h>".} = cuint
  Useconds* {.importc: "useconds_t", header: "<sys/types.h>".} = cuint

  Utsname* {.importc: "struct utsname",
              header: "<sys/utsname.h>",
              final, pure.} = object ## struct utsname
    sysname*,      ## Name of this implementation of the operating system.
      nodename*,   ## Name of this node within the communications
                   ## network to which this node is attached, if any.
      release*,    ## Current release level of this implementation.
      version*,    ## Current version level of this release.
      machine*,    ## Name of the hardware type on which the
                   ## system is running.
      domainname*: array[65, char]

  Sem* {.importc: "sem_t", header: "<semaphore.h>", final, pure.} = object
    abi: array[32 div sizeof(clong), clong]

  Stat* {.importc: "struct stat",
           header: "<sys/stat.h>", final, pure.} = object ## struct stat
    st_dev*: Dev          ## Device ID of device containing file.
    st_ino*: Ino          ## File serial number.
    st_mode*: Mode        ## Mode of file (see below).
    st_nlink*: Nlink      ## Number of hard links to the file.
    st_uid*: Uid          ## User ID of file.
    st_gid*: Gid          ## Group ID of file.
    st_rdev*: Dev         ## Device ID (if file is character or block special).
    st_size*: Off         ## For regular files, the file size in bytes.
                           ## For symbolic links, the length in bytes of the
                           ## pathname contained in the symbolic link.
                           ## For a shared memory object, the length in bytes.
                           ## For a typed memory object, the length in bytes.
                           ## For other file types, the use of this field is
                           ## unspecified.
    when StatHasNanoseconds:
      st_atim*: Timespec  ## Time of last access.
      pad1: clong
      st_mtim*: Timespec  ## Time of last data modification.
      pad2: clong
      st_ctim*: Timespec  ## Time of last status change.
      pad3: clong
    else:
      st_atime*: Time     ## Time of last access.
      pad1: clong
      st_mtime*: Time     ## Time of last data modification.
      pad2: clong
      st_ctime*: Time     ## Time of last status change.
      pad3: clong
    st_blksize*: Blksize   ## A file system-specific preferred I/O block size
                           ## for this object. In some file system types, this
                           ## may vary from file to file.
    st_blocks*: Blkcnt     ## Number of blocks allocated for this object.
    reserved: array[2, clong]



  Statvfs* {.importc: "struct statvfs", header: "<sys/statvfs.h>",
              final, pure.} = object ## struct statvfs
    f_bsize*: culong        ## File system block size.
    f_frsize*: culong       ## Fundamental file system block size.
    f_blocks*: Fsblkcnt  ## Total number of blocks on file system
                         ## in units of f_frsize.
    f_bfree*: Fsblkcnt   ## Total number of free blocks.
    f_bavail*: Fsblkcnt  ## Number of free blocks available to
                         ## non-privileged process.
    f_files*: Fsfilcnt   ## Total number of file serial numbers.
    f_ffree*: Fsfilcnt   ## Total number of free file serial numbers.
    f_favail*: Fsfilcnt  ## Number of file serial numbers available to
                         ## non-privileged process.
    f_fsid*: culong         ## File system ID.
    f_flag*: culong         ## Bit mask of f_flag values.
    f_namemax*: culong      ## Maximum filename length.

  # No Posix_typed_mem_info

  Tm* {.importc: "struct tm", header: "<time.h>",
         final, pure.} = object ## struct tm
    tm_sec*: cint   ## Seconds [0,60].
    tm_min*: cint   ## Minutes [0,59].
    tm_hour*: cint  ## Hour [0,23].
    tm_mday*: cint  ## Day of month [1,31].
    tm_mon*: cint   ## Month of year [0,11].
    tm_year*: cint  ## Years since 1900.
    tm_wday*: cint  ## Day of week [0,6] (Sunday =0).
    tm_yday*: cint  ## Day of year [0,365].
    tm_isdst*: cint ## Daylight Savings flag.

  Itimerspec* {.importc: "struct itimerspec", header: "<time.h>",
                 final, pure.} = object ## struct itimerspec
    it_interval*: Timespec  ## Timer period.
    it_value*: Timespec     ## Timer expiration.

  Sig_atomic* {.importc: "sig_atomic_t", header: "<signal.h>".} = cint
    ## Possibly volatile-qualified integer type of an object that can be
    ## accessed as an atomic entity, even in the presence of asynchronous
    ## interrupts.
  Sigset* {.importc: "sigset_t", header: "<signal.h>", final.} = culong

  SigEvent* {.importc: "struct sigevent",
               header: "<signal.h>", final, pure.} = object ## struct sigevent
    sigev_notify*: cint           ## Notification type.
    sigev_signo*: cint            ## Signal number.
    sigev_value*: SigVal          ## Signal value.

  SigVal* {.importc: "union sigval",
             header: "<signal.h>", final, pure.} = object ## struct sigval
    sival_int*: cint    ## integer signal value
    sival_ptr*: pointer ## pointer signal value;

  Sigaction* {.importc: "struct sigaction",
                header: "<signal.h>", final, pure.} = object ## struct sigaction
    sa_handler*: proc (x: cint) {.noconv.}  ## Pointer to a signal-catching
                                            ## function or one of the macros
                                            ## SIG_IGN or SIG_DFL.
    sa_mask*: Sigset ## Set of signals to be blocked during execution of
                      ## the signal handling function.
    sa_flags*: cint   ## Special flags.

  Stack* {.importc: "stack_t",
            header: "<signal.h>", final, pure.} = object ## stack_t
    ss_sp*: pointer  ## Stack base or pointer.
    ss_flags*: cint  ## Flags.
    ss_size*: csize_t ## Stack size.

  SigInfo* {.importc: "siginfo_t",
              header: "<signal.h>", final, pure.} = object ## siginfo_t
    si_signo*: cint    ## Signal number.
    si_code*: cint     ## Signal code.
    si_value*: SigVal  ## Signal value.

  Nl_item* {.importc: "nl_item", header: "<langinfo.h>".} = cint

  Sched_param* {.importc: "struct sched_param",
                  header: "<sched.h>",
                  final, pure.} = object ## struct sched_param
    sched_priority*: cint

  Timeval* {.importc: "struct timeval", header: "<sys/select.h>",
             final, pure.} = object ## struct timeval
    tv_sec*: Time       ## Seconds.
    tv_usec*: Suseconds ## Microseconds.
  TFdSet* {.importc: "fd_set", header: "<sys/select.h>",
           final, pure.} = object
    abi: array[((64+(sizeof(clong) * 8)-1) div (sizeof(clong) * 8)), clong]

proc si_pid*(info: SigInfo): Pid =
  ## This might not be correct behavior. si_pid doesn't exist in Switch's
  ## devkitpro headers
  raise newException(OSError, "Nintendo switch cannot get si_pid!")

type
  Taiocb* {.importc: "struct aiocb", header: "<aio.h>",
            final, pure.} = object ## struct aiocb
    aio_fildes*: cint         ## File descriptor.
    aio_lio_opcode*: cint     ## Operation to be performed.
    aio_reqprio*: cint        ## Request priority offset.
    aio_buf*: pointer         ## Location of buffer.
    aio_nbytes*: csize_t      ## Length of transfer.
    aio_sigevent*: SigEvent   ## Signal number and value.
    next_prio: pointer
    abs_prio: cint
    policy: cint
    error_Code: cint
    return_value: clong
    aio_offset*: Off          ## File offset.
    reserved: array[32, uint8]

type
  Tposix_spawnattr* {.importc: "posix_spawnattr_t",
                      header: "<spawn.h>", final, pure.} = object
  Tposix_spawn_file_actions* {.importc: "posix_spawn_file_actions_t",
                               header: "<spawn.h>", final, pure.} = object

# from sys/un.h
const Sockaddr_un_path_length* = 108

type
  SockLen* {.importc: "socklen_t", header: "<sys/socket.h>".} = cuint
  # cushort really
  TSa_Family* {.importc: "sa_family_t", header: "<sys/socket.h>".} = cshort

  SockAddr* {.importc: "struct sockaddr", header: "<sys/socket.h>",
              pure, final.} = object ## struct sockaddr
    sa_len: uint8
    sa_family*: TSa_Family         ## Address family.
    sa_data*: array[14, char] ## Socket address (variable-length data).

  Sockaddr_storage* {.importc: "struct sockaddr_storage",
                       header: "<sys/socket.h>",
                       pure, final.} = object ## struct sockaddr_storage
    ss_len: uint8
    ss_family*: TSa_Family ## Address family.
    ss_padding1: array[64 - sizeof(uint8) - sizeof(cshort), char]
    ss_align: clonglong
    ss_padding2: array[
      128 - sizeof(uint8) - sizeof(cshort) -
      (64 - sizeof(uint8) - sizeof(cshort)) - 64, char]

  Tif_nameindex* {.importc: "struct if_nameindex", final,
                   pure, header: "<net/if.h>".} = object ## struct if_nameindex
    if_index*: cuint   ## Numeric index of the interface.
    if_name*: cstring ## Null-terminated name of the interface.


  IOVec* {.importc: "struct iovec", pure, final,
            header: "<sys/socket.h>".} = object ## struct iovec
    iov_base*: pointer ## Base address of a memory region for input or output.
    iov_len*: csize_t    ## The size of the memory pointed to by iov_base.

  Tmsghdr* {.importc: "struct msghdr", pure, final,
             header: "<sys/socket.h>".} = object  ## struct msghdr
    msg_name*: pointer  ## Optional address.
    msg_namelen*: SockLen  ## Size of address.
    msg_iov*: ptr IOVec    ## Scatter/gather array.
    msg_iovlen*: csize_t   ## Members in msg_iov.
    msg_control*: pointer  ## Ancillary data; see below.
    msg_controllen*: csize_t ## Ancillary data buffer len.
    msg_flags*: cint ## Flags on received message.


  Tcmsghdr* {.importc: "struct cmsghdr", pure, final,
              header: "<sys/socket.h>".} = object ## struct cmsghdr
    cmsg_len*: csize_t ## Data byte count, including the cmsghdr.
    cmsg_level*: cint   ## Originating protocol.
    cmsg_type*: cint    ## Protocol-specific type.

  TLinger* {.importc: "struct linger", pure, final,
             header: "<sys/socket.h>".} = object ## struct linger
    l_onoff*: cint  ## Indicates whether linger option is enabled.
    l_linger*: cint ## Linger time, in seconds.
    # data follows...

  InPort* = uint16
  InAddrScalar* = uint32

  InAddrT* {.importc: "in_addr_t", pure, final,
             header: "<netinet/in.h>".} = uint32

  InAddr* {.importc: "struct in_addr", pure, final,
             header: "<netinet/in.h>".} = object ## struct in_addr
    s_addr*: InAddrScalar

  Sockaddr_in* {.importc: "struct sockaddr_in", pure, final,
                  header: "<netinet/in.h>".} = object ## struct sockaddr_in
    sin_len*: cushort
    sin_family*: TSa_Family ## AF_INET.
    sin_port*: InPort      ## Port number.
    sin_addr*: InAddr      ## IP address.
    sin_zero: array[8, uint8]

  In6Addr* {.importc: "struct in6_addr", pure, final,
              header: "<netinet/in.h>".} = object ## struct in6_addr
    s6_addr*: array[0..15, char]

  Sockaddr_in6* {.importc: "struct sockaddr_in6", pure, final,
                   header: "<netinet/in.h>".} = object ## struct sockaddr_in6
    sin6_family*: TSa_Family ## AF_INET6.
    sin6_port*: InPort      ## Port number.
    sin6_flowinfo*: uint32    ## IPv6 traffic class and flow information.
    sin6_addr*: In6Addr     ## IPv6 address.
    sin6_scope_id*: uint32    ## Set of interfaces for a scope.

  Hostent* {.importc: "struct hostent", pure, final,
              header: "<netdb.h>".} = object ## struct hostent
    h_name*: cstring           ## Official name of the host.
    h_aliases*: cstringArray   ## A pointer to an array of pointers to
                               ## alternative host names, terminated by a
                               ## null pointer.
    h_addrtype*: cint          ## Address type.
    h_length*: cint            ## The length, in bytes, of the address.
    h_addr_list*: cstringArray ## A pointer to an array of pointers to network
                               ## addresses (in network byte order) for the
                               ## host, terminated by a null pointer.

  Tnetent* {.importc: "struct netent", pure, final,
              header: "<netdb.h>".} = object ## struct netent
    n_name*: cstring         ## Official, fully-qualified (including the
                             ## domain) name of the host.
    n_aliases*: cstringArray ## A pointer to an array of pointers to
                             ## alternative network names, terminated by a
                             ## null pointer.
    n_addrtype*: cint        ## The address type of the network.
    n_net*: uint32            ## The network number, in host byte order.

  Protoent* {.importc: "struct protoent", pure, final,
              header: "<netdb.h>".} = object ## struct protoent
    p_name*: cstring         ## Official name of the protocol.
    p_aliases*: cstringArray ## A pointer to an array of pointers to
                             ## alternative protocol names, terminated by
                             ## a null pointer.
    p_proto*: cint           ## The protocol number.

  Servent* {.importc: "struct servent", pure, final,
             header: "<netdb.h>".} = object ## struct servent
    s_name*: cstring         ## Official name of the service.
    s_aliases*: cstringArray ## A pointer to an array of pointers to
                             ## alternative service names, terminated by
                             ## a null pointer.
    s_port*: cint            ## The port number at which the service
                             ## resides, in network byte order.
    s_proto*: cstring        ## The name of the protocol to use when
                             ## contacting the service.

  AddrInfo* {.importc: "struct addrinfo", pure, final,
              header: "<netdb.h>".} = object ## struct addrinfo
    ai_flags*: cint         ## Input flags.
    ai_family*: cint        ## Address family of socket.
    ai_socktype*: cint      ## Socket type.
    ai_protocol*: cint      ## Protocol of socket.
    ai_addrlen*: SockLen   ## Length of socket address.
    ai_canonname*: cstring  ## Canonical name of service location.
    ai_addr*: ptr SockAddr ## Socket address of socket.
    ai_next*: ptr AddrInfo ## Pointer to next in list.

  TPollfd* {.importc: "struct pollfd", pure, final,
             header: "<poll.h>".} = object ## struct pollfd
    fd*: cint        ## The following descriptor being polled.
    events*: cshort  ## The input event flags (see below).
    revents*: cshort ## The output event flags (see below).

var
  errno* {.importc, header: "<errno.h>".}: cint ## error variable
  h_errno* {.importc, header: "<netdb.h>".}: cint
  daylight* {.importc: "_daylight", header: "<time.h>".}: cint
  timezone* {.importc: "_timezone", header: "<time.h>".}: clong

# Regenerate using detect.nim!
include posix_nintendoswitch_consts

const POSIX_SPAWN_USEVFORK* = cint(0x40)  # needs _GNU_SOURCE!

# <sys/wait.h>
proc WEXITSTATUS*(s: cint): cint =  (s shr 8) and 0xff
proc WIFEXITED*(s:cint) : bool = (s and 0xff) == 0
proc WTERMSIG*(s:cint): cint = s and 0x7f
proc WSTOPSIG*(s:cint): cint = WEXITSTATUS(s)
proc WIFSIGNALED*(s:cint) : bool = ((s and 0x7f) > 0) and ((s and 0x7f) < 0x7f)
proc WIFSTOPPED*(s:cint) : bool = (s and 0xff) == 0x7f
