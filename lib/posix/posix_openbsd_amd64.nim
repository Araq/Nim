#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

when defined(nimHasStyleChecks):
  {.push styleChecks: off.}

const
  hasSpawnH = true # should exist for every Posix system nowadays
  hasAioH = false

type
  DIR* {.importc: "DIR", header: "<dirent.h>",
          incompleteStruct.} = object
    ## A type representing a directory stream.

type
  SocketHandle* = distinct cint # The type used to represent socket descriptors

type
  Time* {.importc: "time_t", header: "<time.h>".} = distinct clonglong

  Timespec* {.importc: "struct timespec",
               header: "<time.h>", final, pure.} = object ## struct timespec
    tv_sec*: Time  ## Seconds.
    tv_nsec*: int  ## Nanoseconds.

  Dirent* {.importc: "struct dirent",
             header: "<dirent.h>", final, pure.} = object ## dirent_t struct
    when defined(haiku):
      d_dev*: Dev ## Device (not POSIX)
      d_pdev*: Dev ## Parent device (only for queries) (not POSIX)
    d_ino*: Ino  ## File serial number.
    when defined(dragonfly):
      # DragonflyBSD doesn't have `d_reclen` field.
      d_type*: uint8
    elif defined(linux) or defined(macosx) or defined(freebsd) or
         defined(netbsd) or defined(openbsd) or defined(genode):
      d_reclen*: cshort ## Length of this record. (not POSIX)
      d_type*: int8 ## Type of file; not supported by all filesystem types.
                    ## (not POSIX)
      when defined(linux) or defined(openbsd):
        d_off*: Off  ## Not an offset. Value that `telldir()` would return.
    elif defined(haiku):
      d_pino*: Ino ## Parent inode (only for queries) (not POSIX)
      d_reclen*: cushort ## Length of this record. (not POSIX)

    d_name*: array[0..255, char] ## Name of entry.

  Tflock* {.importc: "struct flock", final, pure,
            header: "<fcntl.h>".} = object ## flock type
    l_type*: cshort   ## Type of lock; F_RDLCK, F_WRLCK, F_UNLCK.
    l_whence*: cshort ## Flag for starting offset.
    l_start*: Off     ## Relative offset in bytes.
    l_len*: Off       ## Size; if 0 then until EOF.
    l_pid*: Pid      ## Process ID of the process holding the lock;
                      ## returned with F_GETLK.

  FTW* {.importc: "struct FTW", header: "<ftw.h>", final, pure.} = object
    base*: cint
    level*: cint

  Glob* {.importc: "glob_t", header: "<glob.h>",
           final, pure.} = object ## glob_t
    gl_pathc*: int          ## Count of paths matched by pattern.
    gl_pathv*: cstringArray ## Pointer to a list of matched pathnames.
    gl_offs*: int           ## Slots to reserve at the beginning of gl_pathv.

  Group* {.importc: "struct group", header: "<grp.h>",
            final, pure.} = object ## struct group
    gr_name*: cstring     ## The name of the group.
    gr_gid*: Gid         ## Numerical group ID.
    gr_mem*: cstringArray ## Pointer to a null-terminated array of character
                          ## pointers to member names.

  Iconv* {.importc: "iconv_t", header: "<iconv.h>", final, pure.} =
    object ## Identifies the conversion from one codeset to another.

  Lconv* {.importc: "struct lconv", header: "<locale.h>", final,
            pure.} = object
    currency_symbol*: cstring
    decimal_point*: cstring
    frac_digits*: char
    grouping*: cstring
    int_curr_symbol*: cstring
    int_frac_digits*: char
    int_n_cs_precedes*: char
    int_n_sep_by_space*: char
    int_n_sign_posn*: char
    int_p_cs_precedes*: char
    int_p_sep_by_space*: char
    int_p_sign_posn*: char
    mon_decimal_point*: cstring
    mon_grouping*: cstring
    mon_thousands_sep*: cstring
    negative_sign*: cstring
    n_cs_precedes*: char
    n_sep_by_space*: char
    n_sign_posn*: char
    positive_sign*: cstring
    p_cs_precedes*: char
    p_sep_by_space*: char
    p_sign_posn*: char
    thousands_sep*: cstring

  Mqd* {.importc: "mqd_t", header: "<mqueue.h>", final, pure.} = object
  MqAttr* {.importc: "struct mq_attr",
             header: "<mqueue.h>",
             final, pure.} = object ## message queue attribute
    mq_flags*: int   ## Message queue flags.
    mq_maxmsg*: int  ## Maximum number of messages.
    mq_msgsize*: int ## Maximum message size.
    mq_curmsgs*: int ## Number of messages currently queued.

  Passwd* {.importc: "struct passwd", header: "<pwd.h>",
             final, pure.} = object ## struct passwd
    pw_name*: cstring   ## User's login name.
    pw_uid*: Uid        ## Numerical user ID.
    pw_gid*: Gid        ## Numerical group ID.
    pw_dir*: cstring    ## Initial working directory.
    pw_shell*: cstring  ## Program to use as shell.

  Blkcnt* {.importc: "blkcnt_t", header: "<sys/types.h>".} = int
    ## used for file block counts
  Blksize* {.importc: "blksize_t", header: "<sys/types.h>".} = int32
    ## used for block sizes
  Clock* {.importc: "clock_t", header: "<sys/types.h>".} = int
  ClockId* {.importc: "clockid_t", header: "<sys/types.h>".} = int
  Dev* {.importc: "dev_t", header: "<sys/types.h>".} = (
    when defined(freebsd):
      uint32
    else:
      int32)
  Fsblkcnt* {.importc: "fsblkcnt_t", header: "<sys/types.h>".} = int
  Fsfilcnt* {.importc: "fsfilcnt_t", header: "<sys/types.h>".} = int
  Gid* {.importc: "gid_t", header: "<sys/types.h>".} = uint32
  Id* {.importc: "id_t", header: "<sys/types.h>".} = int
  Ino* {.importc: "ino_t", header: "<sys/types.h>".} = int
  Key* {.importc: "key_t", header: "<sys/types.h>".} = int
  Mode* {.importc: "mode_t", header: "<sys/types.h>".} = uint32
  Nlink* {.importc: "nlink_t", header: "<sys/types.h>".} = uint32
  Off* {.importc: "off_t", header: "<sys/types.h>".} = int64
  Pid* {.importc: "pid_t", header: "<sys/types.h>".} = int32
  Pthread_attr* {.importc: "pthread_attr_t", header: "<pthread.h>".} = int
  Pthread_barrier* {.importc: "pthread_barrier_t",
                      header: "<pthread.h>".} = int
  Pthread_barrierattr* {.importc: "pthread_barrierattr_t",
                          header: "<pthread.h>".} = int
  Pthread_cond* {.importc: "pthread_cond_t", header: "<pthread.h>".} = int
  Pthread_condattr* {.importc: "pthread_condattr_t",
                       header: "<pthread.h>".} = int
  Pthread_key* {.importc: "pthread_key_t", header: "<pthread.h>".} = int
  Pthread_mutex* {.importc: "pthread_mutex_t", header: "<pthread.h>".} = int
  Pthread_mutexattr* {.importc: "pthread_mutexattr_t",
                        header: "<pthread.h>".} = int
  Pthread_once* {.importc: "pthread_once_t", header: "<pthread.h>".} = int
  Pthread_rwlock* {.importc: "pthread_rwlock_t",
                     header: "<pthread.h>".} = int
  Pthread_rwlockattr* {.importc: "pthread_rwlockattr_t",
                         header: "<pthread.h>".} = int
  Pthread_spinlock* {.importc: "pthread_spinlock_t",
                       header: "<pthread.h>".} = int
  Pthread* {.importc: "pthread_t", header: "<pthread.h>".} = int
  Suseconds* {.importc: "suseconds_t", header: "<sys/types.h>".} = int32
  #Ttime* {.importc: "time_t", header: "<sys/types.h>".} = int
  Timer* {.importc: "timer_t", header: "<sys/types.h>".} = int
  Trace_attr* {.importc: "trace_attr_t", header: "<sys/types.h>".} = int
  Trace_event_id* {.importc: "trace_event_id_t",
                     header: "<sys/types.h>".} = int
  Trace_event_set* {.importc: "trace_event_set_t",
                      header: "<sys/types.h>".} = int
  Trace_id* {.importc: "trace_id_t", header: "<sys/types.h>".} = int
  Uid* {.importc: "uid_t", header: "<sys/types.h>".} = uint32
  Useconds* {.importc: "useconds_t", header: "<sys/types.h>".} = int

  Utsname* {.importc: "struct utsname",
              header: "<sys/utsname.h>",
              final, pure.} = object ## struct utsname
    sysname*,      ## Name of this implementation of the operating system.
      nodename*,   ## Name of this node within the communications
                   ## network to which this node is attached, if any.
      release*,    ## Current release level of this implementation.
      version*,    ## Current version level of this release.
      machine*: array[0..255, char] ## Name of the hardware type on which the
                                     ## system is running.

  Sem* {.importc: "sem_t", header: "<semaphore.h>", final, pure.} = object
  Ipc_perm* {.importc: "struct ipc_perm",
               header: "<sys/ipc.h>", final, pure.} = object ## struct ipc_perm
    uid*: Uid    ## Owner's user ID.
    gid*: Gid    ## Owner's group ID.
    cuid*: Uid   ## Creator's user ID.
    cgid*: Gid   ## Creator's group ID.
    mode*: Mode  ## Read/write permission.

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
      st_mtim*: Timespec  ## Time of last data modification.
      st_ctim*: Timespec  ## Time of last status change.
    else:
      st_atime*: Time     ## Time of last access.
      st_mtime*: Time     ## Time of last data modification.
      st_ctime*: Time     ## Time of last status change.
    st_blksize*: Blksize  ## A file system-specific preferred I/O block size
                          ## for this object. In some file system types, this
                          ## may vary from file to file.
    st_blocks*: Blkcnt    ## Number of blocks allocated for this object.


  Statvfs* {.importc: "struct statvfs", header: "<sys/statvfs.h>",
              final, pure.} = object ## struct statvfs
    f_bsize*: int        ## File system block size.
    f_frsize*: int       ## Fundamental file system block size.
    f_blocks*: Fsblkcnt  ## Total number of blocks on file system
                         ## in units of f_frsize.
    f_bfree*: Fsblkcnt   ## Total number of free blocks.
    f_bavail*: Fsblkcnt  ## Number of free blocks available to
                         ## non-privileged process.
    f_files*: Fsfilcnt   ## Total number of file serial numbers.
    f_ffree*: Fsfilcnt   ## Total number of free file serial numbers.
    f_favail*: Fsfilcnt  ## Number of file serial numbers available to
                         ## non-privileged process.
    f_fsid*: int         ## File system ID.
    f_flag*: int         ## Bit mask of f_flag values.
    f_namemax*: int      ## Maximum filename length.

  Posix_typed_mem_info* {.importc: "struct posix_typed_mem_info",
                           header: "<sys/mman.h>", final, pure.} = object
    posix_tmi_length*: int

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
  Sigset* {.importc: "sigset_t", header: "<signal.h>", final, pure.} = object

  SigEvent* {.importc: "struct sigevent",
               header: "<signal.h>", final, pure.} = object ## struct sigevent
    sigev_notify*: cint           ## Notification type.
    sigev_signo*: cint            ## Signal number.
    sigev_value*: SigVal          ## Signal value.
    sigev_notify_function*: proc (x: SigVal) {.noconv.} ## Notification func.
    sigev_notify_attributes*: ptr Pthread_attr ## Notification attributes.

  SigVal* {.importc: "union sigval",
             header: "<signal.h>", final, pure.} = object ## struct sigval
    sival_ptr*: pointer ## pointer signal value;
                        ## integer signal value not defined!
  Sigaction* {.importc: "struct sigaction",
                header: "<signal.h>", final, pure.} = object ## struct sigaction
    sa_handler*: proc (x: cint) {.noconv.}  ## Pointer to a signal-catching
                                            ## function or one of the macros
                                            ## SIG_IGN or SIG_DFL.
    sa_mask*: Sigset ## Set of signals to be blocked during execution of
                      ## the signal handling function.
    sa_flags*: cint   ## Special flags.
    sa_sigaction*: proc (x: cint, y: ptr SigInfo, z: pointer) {.noconv.}

  Stack* {.importc: "stack_t",
            header: "<signal.h>", final, pure.} = object ## stack_t
    ss_sp*: pointer  ## Stack base or pointer.
    ss_size*: int    ## Stack size.
    ss_flags*: cint  ## Flags.

  SigStack* {.importc: "struct sigstack",
               header: "<signal.h>", final, pure.} = object ## struct sigstack
    ss_onstack*: cint ## Non-zero when signal stack is in use.
    ss_sp*: pointer   ## Signal stack pointer.

  SigInfo* {.importc: "siginfo_t",
              header: "<signal.h>", final, pure.} = object ## siginfo_t
    si_signo*: cint    ## Signal number.
    si_code*: cint     ## Signal code.
    si_errno*: cint    ## If non-zero, an errno value associated with
                       ## this signal, as defined in <errno.h>.
    si_pid*: Pid       ## Sending process ID.
    si_uid*: Uid       ## Real user ID of sending process.
    si_addr*: pointer  ## Address of faulting instruction.
    si_status*: cint   ## Exit value or signal.
    si_band*: int      ## Band event for SIGPOLL.
    si_value*: SigVal  ## Signal value.

  Nl_item* {.importc: "nl_item", header: "<nl_types.h>".} = cint
  Nl_catd* {.importc: "nl_catd", header: "<nl_types.h>".} = cint

  Sched_param* {.importc: "struct sched_param",
                  header: "<sched.h>",
                  final, pure.} = object ## struct sched_param
    sched_priority*: cint
    sched_ss_low_priority*: cint     ## Low scheduling priority for
                                     ## sporadic server.
    sched_ss_repl_period*: Timespec  ## Replenishment period for
                                     ## sporadic server.
    sched_ss_init_budget*: Timespec  ## Initial budget for sporadic server.
    sched_ss_max_repl*: cint         ## Maximum pending replenishments for
                                     ## sporadic server.

  Timeval* {.importc: "struct timeval", header: "<sys/select.h>",
             final, pure.} = object ## struct timeval
    tv_sec*: Time ## Seconds.
    tv_usec*: Suseconds ## Microseconds.
  TFdSet* {.importc: "fd_set", header: "<sys/select.h>",
           final, pure.} = object
  # the following aren't actually defined, but they're here to keep things happy for now
  Mcontext* {.importc: "mcontext_t", header: "<ucontext.h>",
               final, pure.} = object
  Ucontext* {.importc: "ucontext_t", header: "<ucontext.h>",
               final, pure.} = object ## ucontext_t
    uc_link*: ptr Ucontext  ## Pointer to the context that is resumed
                            ## when this context returns.
    uc_sigmask*: Sigset     ## The set of signals that are blocked when this
                            ## context is active.
    uc_stack*: Stack        ## The stack used by this context.
    uc_mcontext*: Mcontext  ## A machine-specific representation of the saved
                            ## context.

when hasAioH:
  type
    Taiocb* {.importc: "struct aiocb", header: "<aio.h>",
              final, pure.} = object ## struct aiocb
      aio_fildes*: cint         ## File descriptor.
      aio_offset*: Off          ## File offset.
      aio_buf*: pointer         ## Location of buffer.
      aio_nbytes*: int          ## Length of transfer.
      aio_reqprio*: cint        ## Request priority offset.
      aio_sigevent*: SigEvent   ## Signal number and value.
      aio_lio_opcode: cint      ## Operation to be performed.

when hasSpawnH:
  type
    Tposix_spawnattr* {.importc: "posix_spawnattr_t",
                        header: "<spawn.h>", final, pure.} = object
    Tposix_spawn_file_actions* {.importc: "posix_spawn_file_actions_t",
                                 header: "<spawn.h>", final, pure.} = object

# according to https://pubs.opengroup.org/onlinepubs/009604499/basedefs/sys/un.h.html
# this is >=92
const Sockaddr_un_path_length* = 92

type
  SockLen* {.importc: "socklen_t", header: "<sys/socket.h>".} = cuint
  TSa_Family* {.importc: "sa_family_t", header: "<sys/socket.h>".} = uint8

  SockAddr* {.importc: "struct sockaddr", header: "<sys/socket.h>",
              pure, final.} = object ## struct sockaddr
    sa_family*: TSa_Family         ## Address family.
    sa_data*: array[0..255, char] ## Socket address (variable-length data).

  Sockaddr_un* {.importc: "struct sockaddr_un", header: "<sys/un.h>",
              pure, final.} = object ## struct sockaddr_un
    sun_family*: TSa_Family         ## Address family.
    sun_path*: array[0..Sockaddr_un_path_length-1, char] ## Socket path

  Sockaddr_storage* {.importc: "struct sockaddr_storage",
                       header: "<sys/socket.h>",
                       pure, final.} = object ## struct sockaddr_storage
    ss_family*: TSa_Family ## Address family.

  Tif_nameindex* {.importc: "struct if_nameindex", final,
                   pure, header: "<net/if.h>".} = object ## struct if_nameindex
    if_index*: cint   ## Numeric index of the interface.
    if_name*: cstring ## Null-terminated name of the interface.


  IOVec* {.importc: "struct iovec", pure, final,
            header: "<sys/uio.h>".} = object ## struct iovec
    iov_base*: pointer ## Base address of a memory region for input or output.
    iov_len*: csize_t    ## The size of the memory pointed to by iov_base.

  Tmsghdr* {.importc: "struct msghdr", pure, final,
             header: "<sys/socket.h>".} = object  ## struct msghdr
    msg_name*: pointer  ## Optional address.
    msg_namelen*: SockLen  ## Size of address.
    msg_iov*: ptr IOVec    ## Scatter/gather array.
    msg_iovlen*: cint   ## Members in msg_iov.
    msg_control*: pointer  ## Ancillary data; see below.
    msg_controllen*: SockLen ## Ancillary data buffer len.
    msg_flags*: cint ## Flags on received message.


  Tcmsghdr* {.importc: "struct cmsghdr", pure, final,
              header: "<sys/socket.h>".} = object ## struct cmsghdr
    cmsg_len*: SockLen ## Data byte count, including the cmsghdr.
    cmsg_level*: cint   ## Originating protocol.
    cmsg_type*: cint    ## Protocol-specific type.

  TLinger* {.importc: "struct linger", pure, final,
             header: "<sys/socket.h>".} = object ## struct linger
    l_onoff*: cint  ## Indicates whether linger option is enabled.
    l_linger*: cint ## Linger time, in seconds.

  InPort* = uint16
  InAddrScalar* = uint32

  InAddrT* {.importc: "in_addr_t", pure, final,
             header: "<netinet/in.h>".} = uint32

  InAddr* {.importc: "struct in_addr", pure, final,
             header: "<netinet/in.h>".} = object ## struct in_addr
    s_addr*: InAddrScalar

  Sockaddr_in* {.importc: "struct sockaddr_in", pure, final,
                  header: "<netinet/in.h>".} = object ## struct sockaddr_in
    sin_family*: TSa_Family ## AF_INET.
    sin_port*: InPort      ## Port number.
    sin_addr*: InAddr      ## IP address.

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

  Tipv6_mreq* {.importc: "struct ipv6_mreq", pure, final,
                header: "<netinet/in.h>".} = object ## struct ipv6_mreq
    ipv6mr_multiaddr*: In6Addr ## IPv6 multicast address.
    ipv6mr_interface*: cint     ## Interface index.

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
    ai_addr*: ptr SockAddr ## Socket address of socket.
    ai_canonname*: cstring  ## Canonical name of service location.
    ai_next*: ptr AddrInfo ## Pointer to next in list.

  TPollfd* {.importc: "struct pollfd", pure, final,
             header: "<poll.h>".} = object ## struct pollfd
    fd*: cint        ## The following descriptor being polled.
    events*: cshort  ## The input event flags (see below).
    revents*: cshort ## The output event flags (see below).

var
  errno* {.importc, header: "<errno.h>".}: cint ## error variable
  h_errno* {.importc, header: "<netdb.h>".}: cint
  daylight* {.importc, header: "<time.h>".}: cint
  timezone* {.importc, header: "<time.h>".}: int

# Regenerate using detect.nim!
include posix_other_consts

var
  MAP_POPULATE*: cint = 0

when defined(nimdoc):
  const SO_REUSEPORT* = cint(0x0200)
else:
  var SO_REUSEPORT* {.importc, header: "<sys/socket.h>".}: cint

var SOCK_CLOEXEC* {.importc, header: "<sys/socket.h>".}: cint

var MSG_NOSIGNAL* {.importc, header: "<sys/socket.h>".}: cint

when hasSpawnH:
    # openbsd lacks this, so we define the constant to be 0 to not affect
    # OR'ing of flags:
    const POSIX_SPAWN_USEVFORK* = cint(0)

# <sys/wait.h>
proc WEXITSTATUS*(s: cint): cint {.importc, header: "<sys/wait.h>".}
  ## Exit code, if WIFEXITED(s)
proc WTERMSIG*(s: cint): cint {.importc, header: "<sys/wait.h>".}
  ## Termination signal, if WIFSIGNALED(s)
proc WSTOPSIG*(s: cint): cint {.importc, header: "<sys/wait.h>".}
  ## Stop signal, if WIFSTOPPED(s)
proc WIFEXITED*(s: cint): bool {.importc, header: "<sys/wait.h>".}
  ## True if child exited normally.
proc WIFSIGNALED*(s: cint): bool {.importc, header: "<sys/wait.h>".}
  ## True if child exited due to uncaught signal.
proc WIFSTOPPED*(s: cint): bool {.importc, header: "<sys/wait.h>".}
  ## True if child is currently stopped.
proc WIFCONTINUED*(s: cint): bool {.importc, header: "<sys/wait.h>".}
  ## True if child has been continued.

when defined(nimHasStyleChecks):
  {.pop.}
