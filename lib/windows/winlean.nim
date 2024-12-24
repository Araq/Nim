#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements a small wrapper for some needed Win API procedures,
## so that the Nim compiler does not depend on the huge Windows module.

import std/dynlib

when defined(nimHasStyleChecks):
  {.push styleChecks: off.}

{.passc: "-DWIN32_LEAN_AND_MEAN".}

when defined(nimPreviewSlimSystem):
  from std/syncio import FileHandle
  import std/widestrs

type WinChar* = Utf16Char

# See https://docs.microsoft.com/en-us/windows/win32/winprog/windows-data-types
type
  Handle* = int
  LONG* = int32
  ULONG* = int32
  PULONG* = ptr int
  WINBOOL* = int32
    ## `WINBOOL` uses opposite convention as posix, !=0 meaning success.
    # xxx this should be distinct int32, distinct would make code less error prone
  PBOOL* = ptr WINBOOL
  DWORD* = int32
  PDWORD* = ptr DWORD
  LPINT* = ptr int32
  ULONG_PTR* = uint
  PULONG_PTR* = ptr uint
  HDC* = Handle
  HGLRC* = Handle
  BYTE* = uint8

  SECURITY_ATTRIBUTES* = object
    nLength*: int32
    lpSecurityDescriptor*: pointer
    bInheritHandle*: WINBOOL

  STARTUPINFO* = object
    cb*: int32
    lpReserved*: cstring
    lpDesktop*: cstring
    lpTitle*: cstring
    dwX*: int32
    dwY*: int32
    dwXSize*: int32
    dwYSize*: int32
    dwXCountChars*: int32
    dwYCountChars*: int32
    dwFillAttribute*: int32
    dwFlags*: int32
    wShowWindow*: int16
    cbReserved2*: int16
    lpReserved2*: pointer
    hStdInput*: Handle
    hStdOutput*: Handle
    hStdError*: Handle

  PROCESS_INFORMATION* = object
    hProcess*: Handle
    hThread*: Handle
    dwProcessId*: int32
    dwThreadId*: int32

  FILETIME* = object ## CANNOT BE int64 BECAUSE OF ALIGNMENT
    dwLowDateTime*: DWORD
    dwHighDateTime*: DWORD

  BY_HANDLE_FILE_INFORMATION* = object
    dwFileAttributes*: DWORD
    ftCreationTime*: FILETIME
    ftLastAccessTime*: FILETIME
    ftLastWriteTime*: FILETIME
    dwVolumeSerialNumber*: DWORD
    nFileSizeHigh*: DWORD
    nFileSizeLow*: DWORD
    nNumberOfLinks*: DWORD
    nFileIndexHigh*: DWORD
    nFileIndexLow*: DWORD

  OSVERSIONINFO* = object
    dwOSVersionInfoSize*: DWORD
    dwMajorVersion*: DWORD
    dwMinorVersion*: DWORD
    dwBuildNumber*: DWORD
    dwPlatformId*: DWORD
    szCSDVersion*: array[0..127, WinChar]

  Protoent* = object
    p_name*: cstring
    p_aliases*: cstringArray
    p_proto*: cshort


const
  STARTF_USESHOWWINDOW* = 1'i32
  STARTF_USESTDHANDLES* = 256'i32
  HIGH_PRIORITY_CLASS* = 128'i32
  IDLE_PRIORITY_CLASS* = 64'i32
  NORMAL_PRIORITY_CLASS* = 32'i32
  REALTIME_PRIORITY_CLASS* = 256'i32
  WAIT_OBJECT_0* = 0'i32
  WAIT_TIMEOUT* = 0x00000102'i32
  WAIT_FAILED* = 0xFFFFFFFF'i32
  INFINITE* = -1'i32
  STILL_ACTIVE* = 0x00000103'i32

  STD_INPUT_HANDLE* = -10'i32
  STD_OUTPUT_HANDLE* = -11'i32
  STD_ERROR_HANDLE* = -12'i32

  DETACHED_PROCESS* = 8'i32

  SW_SHOWNORMAL* = 1'i32
  INVALID_HANDLE_VALUE* = Handle(-1)

  CREATE_UNICODE_ENVIRONMENT* = 1024'i32

  PIPE_ACCESS_DUPLEX* = 0x00000003'i32
  PIPE_ACCESS_INBOUND* = 1'i32
  PIPE_ACCESS_OUTBOUND* = 2'i32
  PIPE_NOWAIT* = 0x00000001'i32
  SYNCHRONIZE* = 0x00100000'i32

  CREATE_NO_WINDOW* = 0x08000000'i32

  HANDLE_FLAG_INHERIT* = 0x00000001'i32

proc isSuccess*(a: WINBOOL): bool {.inline.} =
  ## Returns true if `a != 0`. Windows uses a different convention than POSIX,
  ## where `a == 0` is commonly used on success.
  a != 0
proc getVersionExW*(lpVersionInfo: ptr OSVERSIONINFO): WINBOOL {.
    stdcall, dynlib: "kernel32", importc: "GetVersionExW", sideEffect.}
proc getVersionExA*(lpVersionInfo: ptr OSVERSIONINFO): WINBOOL {.
    stdcall, dynlib: "kernel32", importc: "GetVersionExA", sideEffect.}

proc getVersion*(): DWORD {.stdcall, dynlib: "kernel32", importc: "GetVersion", sideEffect.}

proc closeHandle*(hObject: Handle): WINBOOL {.stdcall, dynlib: "kernel32",
    importc: "CloseHandle".}

proc readFile*(hFile: Handle, buffer: pointer, nNumberOfBytesToRead: int32,
               lpNumberOfBytesRead: ptr int32, lpOverlapped: pointer): WINBOOL{.
    stdcall, dynlib: "kernel32", importc: "ReadFile", sideEffect.}

proc writeFile*(hFile: Handle, buffer: pointer, nNumberOfBytesToWrite: int32,
                lpNumberOfBytesWritten: ptr int32,
                lpOverlapped: pointer): WINBOOL{.
    stdcall, dynlib: "kernel32", importc: "WriteFile", sideEffect.}

proc createPipe*(hReadPipe, hWritePipe: var Handle,
                 lpPipeAttributes: var SECURITY_ATTRIBUTES,
                 nSize: int32): WINBOOL{.
    stdcall, dynlib: "kernel32", importc: "CreatePipe", sideEffect.}

proc createNamedPipe*(lpName: WideCString,
                     dwOpenMode, dwPipeMode, nMaxInstances, nOutBufferSize,
                     nInBufferSize, nDefaultTimeOut: int32,
                     lpSecurityAttributes: ptr SECURITY_ATTRIBUTES): Handle {.
    stdcall, dynlib: "kernel32", importc: "CreateNamedPipeW", sideEffect.}

proc peekNamedPipe*(hNamedPipe: Handle, lpBuffer: pointer=nil,
                    nBufferSize: int32 = 0,
                    lpBytesRead: ptr int32 = nil,
                    lpTotalBytesAvail: ptr int32 = nil,
                    lpBytesLeftThisMessage: ptr int32 = nil): bool {.
    stdcall, dynlib: "kernel32", importc: "PeekNamedPipe".}

proc createProcessW*(lpApplicationName, lpCommandLine: WideCString,
                   lpProcessAttributes: ptr SECURITY_ATTRIBUTES,
                   lpThreadAttributes: ptr SECURITY_ATTRIBUTES,
                   bInheritHandles: WINBOOL, dwCreationFlags: int32,
                   lpEnvironment, lpCurrentDirectory: WideCString,
                   lpStartupInfo: var STARTUPINFO,
                   lpProcessInformation: var PROCESS_INFORMATION): WINBOOL{.
  stdcall, dynlib: "kernel32", importc: "CreateProcessW", sideEffect.}

proc suspendThread*(hThread: Handle): int32 {.stdcall, dynlib: "kernel32",
    importc: "SuspendThread", sideEffect.}
proc resumeThread*(hThread: Handle): int32 {.stdcall, dynlib: "kernel32",
    importc: "ResumeThread", sideEffect.}

proc waitForSingleObject*(hHandle: Handle, dwMilliseconds: int32): int32 {.
    stdcall, dynlib: "kernel32", importc: "WaitForSingleObject", sideEffect.}

proc terminateProcess*(hProcess: Handle, uExitCode: int): WINBOOL {.stdcall,
    dynlib: "kernel32", importc: "TerminateProcess", sideEffect.}

proc getExitCodeProcess*(hProcess: Handle, lpExitCode: var int32): WINBOOL {.
    stdcall, dynlib: "kernel32", importc: "GetExitCodeProcess".}

proc getStdHandle*(nStdHandle: int32): Handle {.stdcall, dynlib: "kernel32",
    importc: "GetStdHandle".}
proc setStdHandle*(nStdHandle: int32, hHandle: Handle): WINBOOL {.stdcall,
    dynlib: "kernel32", importc: "SetStdHandle", sideEffect.}
proc flushFileBuffers*(hFile: Handle): WINBOOL {.stdcall, dynlib: "kernel32",
    importc: "FlushFileBuffers", sideEffect.}

proc getLastError*(): int32 {.importc: "GetLastError",
    stdcall, dynlib: "kernel32", sideEffect.}

proc setLastError*(error: int32) {.importc: "SetLastError",
    stdcall, dynlib: "kernel32", sideEffect.}

proc formatMessageW*(dwFlags: int32, lpSource: pointer,
                    dwMessageId, dwLanguageId: int32,
                    lpBuffer: pointer, nSize: int32,
                    arguments: pointer): int32 {.
                    importc: "FormatMessageW", stdcall, dynlib: "kernel32".}

proc localFree*(p: pointer) {.
  importc: "LocalFree", stdcall, dynlib: "kernel32".}

proc getCurrentDirectoryW*(nBufferLength: int32,
                           lpBuffer: WideCString): int32 {.
  importc: "GetCurrentDirectoryW", dynlib: "kernel32", stdcall, sideEffect.}
proc setCurrentDirectoryW*(lpPathName: WideCString): int32 {.
  importc: "SetCurrentDirectoryW", dynlib: "kernel32", stdcall, sideEffect.}
proc createDirectoryW*(pathName: WideCString, security: pointer=nil): int32 {.
  importc: "CreateDirectoryW", dynlib: "kernel32", stdcall, sideEffect.}
proc removeDirectoryW*(lpPathName: WideCString): int32 {.
  importc: "RemoveDirectoryW", dynlib: "kernel32", stdcall, sideEffect.}
proc setEnvironmentVariableW*(lpName, lpValue: WideCString): int32 {.
  stdcall, dynlib: "kernel32", importc: "SetEnvironmentVariableW", sideEffect.}

proc getModuleFileNameW*(handle: Handle, buf: WideCString,
                         size: int32): int32 {.importc: "GetModuleFileNameW",
  dynlib: "kernel32", stdcall.}

proc createSymbolicLinkW*(lpSymlinkFileName, lpTargetFileName: WideCString,
                       flags: DWORD): int32 {.
  importc:"CreateSymbolicLinkW", dynlib: "kernel32", stdcall, sideEffect.}
proc createHardLinkW*(lpFileName, lpExistingFileName: WideCString,
                       security: pointer=nil): int32 {.
  importc:"CreateHardLinkW", dynlib: "kernel32", stdcall, sideEffect.}

const
  FILE_ATTRIBUTE_READONLY* = 0x00000001'i32
  FILE_ATTRIBUTE_HIDDEN* = 0x00000002'i32
  FILE_ATTRIBUTE_SYSTEM* = 0x00000004'i32
  FILE_ATTRIBUTE_DIRECTORY* = 0x00000010'i32
  FILE_ATTRIBUTE_ARCHIVE* = 0x00000020'i32
  FILE_ATTRIBUTE_DEVICE* = 0x00000040'i32
  FILE_ATTRIBUTE_NORMAL* = 0x00000080'i32
  FILE_ATTRIBUTE_TEMPORARY* = 0x00000100'i32
  FILE_ATTRIBUTE_SPARSE_FILE* = 0x00000200'i32
  FILE_ATTRIBUTE_REPARSE_POINT* = 0x00000400'i32
  FILE_ATTRIBUTE_COMPRESSED* = 0x00000800'i32
  FILE_ATTRIBUTE_OFFLINE* = 0x00001000'i32
  FILE_ATTRIBUTE_NOT_CONTENT_INDEXED* = 0x00002000'i32

  FILE_FLAG_FIRST_PIPE_INSTANCE* = 0x00080000'i32
  FILE_FLAG_OPEN_NO_RECALL* = 0x00100000'i32
  FILE_FLAG_OPEN_REPARSE_POINT* = 0x00200000'i32
  FILE_FLAG_POSIX_SEMANTICS* = 0x01000000'i32
  FILE_FLAG_BACKUP_SEMANTICS* = 0x02000000'i32
  FILE_FLAG_DELETE_ON_CLOSE* = 0x04000000'i32
  FILE_FLAG_SEQUENTIAL_SCAN* = 0x08000000'i32
  FILE_FLAG_RANDOM_ACCESS* = 0x10000000'i32
  FILE_FLAG_NO_BUFFERING* = 0x20000000'i32
  FILE_FLAG_OVERLAPPED* = 0x40000000'i32
  FILE_FLAG_WRITE_THROUGH* = 0x80000000'i32

  MAX_PATH* = 260

  MOVEFILE_COPY_ALLOWED* = 0x2'i32
  MOVEFILE_CREATE_HARDLINK* = 0x10'i32
  MOVEFILE_DELAY_UNTIL_REBOOT* = 0x4'i32
  MOVEFILE_FAIL_IF_NOT_TRACKABLE* = 0x20'i32
  MOVEFILE_REPLACE_EXISTING* = 0x1'i32
  MOVEFILE_WRITE_THROUGH* = 0x8'i32

type
  WIN32_FIND_DATA* {.pure.} = object
    dwFileAttributes*: int32
    ftCreationTime*: FILETIME
    ftLastAccessTime*: FILETIME
    ftLastWriteTime*: FILETIME
    nFileSizeHigh*: int32
    nFileSizeLow*: int32
    dwReserved0: int32
    dwReserved1: int32
    cFileName*: array[0..(MAX_PATH) - 1, WinChar]
    cAlternateFileName*: array[0..13, WinChar]

proc findFirstFileW*(lpFileName: WideCString,
                    lpFindFileData: var WIN32_FIND_DATA): Handle {.
    stdcall, dynlib: "kernel32", importc: "FindFirstFileW", sideEffect.}
proc findNextFileW*(hFindFile: Handle,
                   lpFindFileData: var WIN32_FIND_DATA): int32 {.
    stdcall, dynlib: "kernel32", importc: "FindNextFileW", sideEffect.}

proc findClose*(hFindFile: Handle) {.stdcall, dynlib: "kernel32",
  importc: "FindClose".}

proc getFullPathNameW*(lpFileName: WideCString, nBufferLength: int32,
                      lpBuffer: WideCString,
                      lpFilePart: var WideCString): int32 {.
                      stdcall, dynlib: "kernel32",
                      importc: "GetFullPathNameW", sideEffect.}
proc getFileAttributesW*(lpFileName: WideCString): int32 {.
                        stdcall, dynlib: "kernel32",
                        importc: "GetFileAttributesW", sideEffect.}
proc setFileAttributesW*(lpFileName: WideCString,
                         dwFileAttributes: int32): WINBOOL {.
    stdcall, dynlib: "kernel32", importc: "SetFileAttributesW", sideEffect.}

proc copyFileW*(lpExistingFileName, lpNewFileName: WideCString,
               bFailIfExists: WINBOOL): WINBOOL {.
  importc: "CopyFileW", stdcall, dynlib: "kernel32", sideEffect.}

proc moveFileW*(lpExistingFileName, lpNewFileName: WideCString): WINBOOL {.
  importc: "MoveFileW", stdcall, dynlib: "kernel32", sideEffect.}
proc moveFileExW*(lpExistingFileName, lpNewFileName: WideCString,
                  flags: DWORD): WINBOOL {.
  importc: "MoveFileExW", stdcall, dynlib: "kernel32", sideEffect.}

proc getEnvironmentStringsW*(): WideCString {.
  stdcall, dynlib: "kernel32", importc: "GetEnvironmentStringsW", sideEffect.}
proc freeEnvironmentStringsW*(para1: WideCString): int32 {.
  stdcall, dynlib: "kernel32", importc: "FreeEnvironmentStringsW", sideEffect.}

proc getCommandLineW*(): WideCString {.importc: "GetCommandLineW",
  stdcall, dynlib: "kernel32", sideEffect.}

proc rdFileTime*(f: FILETIME): int64 =
  result = int64(cast[uint32](f.dwLowDateTime)) or (int64(cast[uint32](f.dwHighDateTime)) shl 32)

proc rdFileSize*(f: WIN32_FIND_DATA): int64 =
  result = int64(cast[uint32](f.nFileSizeLow)) or (int64(cast[uint32](f.nFileSizeHigh)) shl 32)

proc getSystemTimeAsFileTime*(lpSystemTimeAsFileTime: var FILETIME) {.
  importc: "GetSystemTimeAsFileTime", dynlib: "kernel32", stdcall, sideEffect.}

proc sleep*(dwMilliseconds: int32){.stdcall, dynlib: "kernel32",
                                    importc: "Sleep", sideEffect.}

proc shellExecuteW*(hwnd: Handle, lpOperation, lpFile,
                   lpParameters, lpDirectory: WideCString,
                   nShowCmd: int32): Handle{.
    stdcall, dynlib: "shell32.dll", importc: "ShellExecuteW", sideEffect.}

proc getFileInformationByHandle*(hFile: Handle,
  lpFileInformation: ptr BY_HANDLE_FILE_INFORMATION): WINBOOL{.
    stdcall, dynlib: "kernel32", importc: "GetFileInformationByHandle", sideEffect.}

const
  WSADESCRIPTION_LEN* = 256
  WSASYS_STATUS_LEN* = 128
  FD_SETSIZE* = 64
  MSG_PEEK* = 2

  INADDR_ANY* = 0'u32
  INADDR_LOOPBACK* = 0x7F000001
  INADDR_BROADCAST* = -1
  INADDR_NONE* = -1

  ws2dll = "Ws2_32.dll"

proc wsaGetLastError*(): cint {.importc: "WSAGetLastError", dynlib: ws2dll, sideEffect.}

type
  SocketHandle* = distinct int

type
  WSAData* {.importc: "WSADATA", header: "winsock2.h".} = object
    wVersion, wHighVersion: int16
    szDescription: array[0..WSADESCRIPTION_LEN, char]
    szSystemStatus: array[0..WSASYS_STATUS_LEN, char]
    iMaxSockets, iMaxUdpDg: int16
    lpVendorInfo: cstring

  SockAddr* {.importc: "SOCKADDR", header: "winsock2.h".} = object
    sa_family*: uint16
    sa_data*: array[0..13, char]

  PSockAddr = ptr SockAddr

  InAddr* {.importc: "IN_ADDR", header: "winsock2.h", union.} = object
    s_addr*: uint32  # IP address

  Sockaddr_in* {.importc: "SOCKADDR_IN",
                  header: "winsock2.h".} = object
    sin_family*: uint16
    sin_port*: uint16
    sin_addr*: InAddr
    sin_zero*: array[0..7, char]

  In6_addr* {.importc: "IN6_ADDR", header: "winsock2.h".} = object
    bytes* {.importc: "u.Byte".}: array[0..15, char]

  Sockaddr_in6* {.importc: "SOCKADDR_IN6",
                   header: "ws2tcpip.h".} = object
    sin6_family*: uint16
    sin6_port*: uint16
    sin6_flowinfo*: int32 # unsigned
    sin6_addr*: In6_addr
    sin6_scope_id*: int32 # unsigned

  Sockaddr_storage* {.importc: "SOCKADDR_STORAGE",
                      header: "winsock2.h".} = object
    ss_family*: uint16
    ss_pad1 {.importc: "__ss_pad1".}: array[6, byte]
    ss_align {.importc: "__ss_align".}: int64
    ss_pad2 {.importc: "__ss_pad2".}: array[112, byte]

  Servent* = object
    s_name*: cstring
    s_aliases*: cstringArray
    when defined(cpu64):
      s_proto*: cstring
      s_port*: int16
    else:
      s_port*: int16
      s_proto*: cstring

  Hostent* = object
    h_name*: cstring
    h_aliases*: cstringArray
    h_addrtype*: int16
    h_length*: int16
    h_addr_list*: cstringArray

  TFdSet* = object
    fd_count*: cint # unsigned
    fd_array*: array[0..FD_SETSIZE-1, SocketHandle]

  AddrInfo* = object
    ai_flags*: cint         ## Input flags.
    ai_family*: cint        ## Address family of socket.
    ai_socktype*: cint      ## Socket type.
    ai_protocol*: cint      ## Protocol of socket.
    ai_addrlen*: csize_t        ## Length of socket address.
    ai_canonname*: cstring  ## Canonical name of service location.
    ai_addr*: ptr SockAddr ## Socket address of socket.
    ai_next*: ptr AddrInfo ## Pointer to next in list.

  SockLen* = cuint

type
  Timeval* {.importc: "struct timeval", header: "<time.h>".} = object
    tv_sec*, tv_usec*: int32

var
  SOMAXCONN* {.importc, header: "winsock2.h".}: cint
  INVALID_SOCKET* {.importc, header: "winsock2.h".}: SocketHandle
  SOL_SOCKET* {.importc, header: "winsock2.h".}: cint
  SO_DEBUG* {.importc, header: "winsock2.h".}: cint ## turn on debugging info recording
  SO_ACCEPTCONN* {.importc, header: "winsock2.h".}: cint # socket has had listen()
  SO_REUSEADDR* {.importc, header: "winsock2.h".}: cint # allow local address reuse
  SO_REUSEPORT* {.importc: "SO_REUSEADDR", header: "winsock2.h".}: cint # allow port reuse. Since Windows does not really support it, mapped to SO_REUSEADDR. This shouldn't cause problems.

  SO_KEEPALIVE* {.importc, header: "winsock2.h".}: cint # keep connections alive
  SO_DONTROUTE* {.importc, header: "winsock2.h".}: cint # just use interface addresses
  SO_BROADCAST* {.importc, header: "winsock2.h".}: cint # permit sending of broadcast msgs
  SO_USELOOPBACK* {.importc, header: "winsock2.h".}: cint # bypass hardware when possible
  SO_LINGER* {.importc, header: "winsock2.h".}: cint # linger on close if data present
  SO_OOBINLINE* {.importc, header: "winsock2.h".}: cint # leave received OOB data in line

  SO_DONTLINGER* {.importc, header: "winsock2.h".}: cint
  SO_EXCLUSIVEADDRUSE* {.importc, header: "winsock2.h".}: cint # disallow local address reuse
  SO_ERROR* {.importc, header: "winsock2.h".}: cint
  TCP_NODELAY* {.importc, header: "winsock2.h".}: cint

proc `==`*(x, y: SocketHandle): bool {.borrow.}

proc getservbyname*(name, proto: cstring): ptr Servent {.
  stdcall, importc: "getservbyname", dynlib: ws2dll, sideEffect.}

proc getservbyport*(port: cint, proto: cstring): ptr Servent {.
  stdcall, importc: "getservbyport", dynlib: ws2dll, sideEffect.}

proc gethostbyaddr*(ip: ptr InAddr, len: cuint, theType: cint): ptr Hostent {.
  stdcall, importc: "gethostbyaddr", dynlib: ws2dll, sideEffect.}

proc gethostbyname*(name: cstring): ptr Hostent {.
  stdcall, importc: "gethostbyname", dynlib: ws2dll, sideEffect.}

proc gethostname*(hostname: cstring, len: cint): cint {.
  stdcall, importc: "gethostname", dynlib: ws2dll, sideEffect.}

proc getprotobyname*(
  name: cstring
): ptr Protoent {.stdcall, importc: "getprotobyname", dynlib: ws2dll, sideEffect.}

proc getprotobynumber*(
  proto: cint
): ptr Protoent {.stdcall, importc: "getprotobynumber", dynlib: ws2dll, sideEffect.}

proc socket*(af, typ, protocol: cint): SocketHandle {.
  stdcall, importc: "socket", dynlib: ws2dll.}

proc closesocket*(s: SocketHandle): cint {.
  stdcall, importc: "closesocket", dynlib: ws2dll.}

proc accept*(s: SocketHandle, a: ptr SockAddr, addrlen: ptr SockLen): SocketHandle {.
  stdcall, importc: "accept", dynlib: ws2dll.}
proc bindSocket*(s: SocketHandle, name: ptr SockAddr, namelen: SockLen): cint {.
  stdcall, importc: "bind", dynlib: ws2dll.}
proc connect*(s: SocketHandle, name: ptr SockAddr, namelen: SockLen): cint {.
  stdcall, importc: "connect", dynlib: ws2dll.}
proc getsockname*(s: SocketHandle, name: ptr SockAddr,
                  namelen: ptr SockLen): cint {.
  stdcall, importc: "getsockname", dynlib: ws2dll.}
proc getpeername*(s: SocketHandle, name: ptr SockAddr,
                  namelen: ptr SockLen): cint {.
  stdcall, importc, dynlib: ws2dll.}
proc getsockopt*(s: SocketHandle, level, optname: cint, optval: pointer,
                 optlen: ptr SockLen): cint {.
  stdcall, importc: "getsockopt", dynlib: ws2dll.}
proc setsockopt*(s: SocketHandle, level, optname: cint, optval: pointer,
                 optlen: SockLen): cint {.
  stdcall, importc: "setsockopt", dynlib: ws2dll.}

proc listen*(s: SocketHandle, backlog: cint): cint {.
  stdcall, importc: "listen", dynlib: ws2dll.}
proc recv*(s: SocketHandle, buf: pointer, len, flags: cint): cint {.
  stdcall, importc: "recv", dynlib: ws2dll.}
proc recvfrom*(s: SocketHandle, buf: cstring, len, flags: cint,
               fromm: ptr SockAddr, fromlen: ptr SockLen): cint {.
  stdcall, importc: "recvfrom", dynlib: ws2dll.}
proc select*(nfds: cint, readfds, writefds, exceptfds: ptr TFdSet,
             timeout: ptr Timeval): cint {.
  stdcall, importc: "select", dynlib: ws2dll.}
proc send*(s: SocketHandle, buf: pointer, len, flags: cint): cint {.
  stdcall, importc: "send", dynlib: ws2dll.}
proc sendto*(s: SocketHandle, buf: pointer, len, flags: cint,
             to: ptr SockAddr, tolen: SockLen): cint {.
  stdcall, importc: "sendto", dynlib: ws2dll.}

proc shutdown*(s: SocketHandle, how: cint): cint {.
  stdcall, importc: "shutdown", dynlib: ws2dll.}

proc getnameinfo*(a1: ptr SockAddr, a2: SockLen,
                  a3: cstring, a4: SockLen, a5: cstring,
                  a6: SockLen, a7: cint): cint {.
  stdcall, importc: "getnameinfo", dynlib: ws2dll.}

proc inet_addr*(cp: cstring): uint32 {.
  stdcall, importc: "inet_addr", dynlib: ws2dll.}

proc WSAFDIsSet(s: SocketHandle, set: var TFdSet): bool {.
  stdcall, importc: "__WSAFDIsSet", dynlib: ws2dll, noSideEffect.}

proc FD_ISSET*(socket: SocketHandle, set: var TFdSet): cint =
  result = if WSAFDIsSet(socket, set): 1'i32 else: 0'i32

proc FD_SET*(socket: SocketHandle, s: var TFdSet) =
  if s.fd_count < FD_SETSIZE:
    s.fd_array[int(s.fd_count)] = socket
    inc(s.fd_count)

proc FD_ZERO*(s: var TFdSet) =
  s.fd_count = 0

proc wsaStartup*(wVersionRequired: int16, WSData: ptr WSAData): cint {.
  stdcall, importc: "WSAStartup", dynlib: ws2dll.}

proc getaddrinfo*(nodename, servname: cstring, hints: ptr AddrInfo,
                  res: var ptr AddrInfo): cint {.
  stdcall, importc: "getaddrinfo", dynlib: ws2dll.}

proc freeAddrInfo*(ai: ptr AddrInfo) {.
  stdcall, importc: "freeaddrinfo", dynlib: ws2dll.}

proc inet_ntoa*(i: InAddr): cstring {.
  stdcall, importc, dynlib: ws2dll.}

const
  MAXIMUM_WAIT_OBJECTS* = 0x00000040

type
  WOHandleArray* = array[0..MAXIMUM_WAIT_OBJECTS - 1, Handle]
  PWOHandleArray* = ptr WOHandleArray

proc waitForMultipleObjects*(nCount: DWORD, lpHandles: PWOHandleArray,
                             bWaitAll: WINBOOL, dwMilliseconds: DWORD): DWORD{.
    stdcall, dynlib: "kernel32", importc: "WaitForMultipleObjects".}


# for memfiles.nim:

const
  GENERIC_READ* = 0x80000000'i32
  GENERIC_WRITE* = 0x40000000'i32
  GENERIC_ALL* = 0x10000000'i32
  FILE_SHARE_READ* = 1'i32
  FILE_SHARE_DELETE* = 4'i32
  FILE_SHARE_WRITE* = 2'i32

  CREATE_ALWAYS* = 2'i32
  CREATE_NEW* = 1'i32
  OPEN_EXISTING* = 3'i32
  OPEN_ALWAYS* = 4'i32
  FILE_BEGIN* = 0'i32
  INVALID_SET_FILE_POINTER* = -1'i32
  NO_ERROR* = 0'i32
  PAGE_NOACCESS* = 0x01'i32
  PAGE_EXECUTE* = 0x10'i32
  PAGE_EXECUTE_READ* = 0x20'i32
  PAGE_EXECUTE_READWRITE* = 0x40'i32
  PAGE_READONLY* = 2'i32
  PAGE_READWRITE* = 4'i32
  FILE_MAP_READ* = 4'i32
  FILE_MAP_WRITE* = 2'i32
  INVALID_FILE_SIZE* = -1'i32

  DUPLICATE_SAME_ACCESS* = 2
  FILE_READ_DATA* = 0x00000001 # file & pipe
  FILE_WRITE_DATA* = 0x00000002 # file & pipe

# Error Constants
const
  ERROR_FILE_NOT_FOUND* = 2 ## https://docs.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-
  ERROR_PATH_NOT_FOUND* = 3
  ERROR_ACCESS_DENIED* = 5
  ERROR_NO_MORE_FILES* = 18
  ERROR_LOCK_VIOLATION* = 33
  ERROR_HANDLE_EOF* = 38
  ERROR_FILE_EXISTS* = 80
  ERROR_BAD_ARGUMENTS* = 165

proc duplicateHandle*(hSourceProcessHandle: Handle, hSourceHandle: Handle,
                      hTargetProcessHandle: Handle,
                      lpTargetHandle: ptr Handle,
                      dwDesiredAccess: DWORD, bInheritHandle: WINBOOL,
                      dwOptions: DWORD): WINBOOL{.stdcall, dynlib: "kernel32",
    importc: "DuplicateHandle".}

proc getHandleInformation*(hObject: Handle, lpdwFlags: ptr DWORD): WINBOOL {.
    stdcall, dynlib: "kernel32", importc: "GetHandleInformation".}

proc setHandleInformation*(hObject: Handle, dwMask: DWORD,
                           dwFlags: DWORD): WINBOOL {.stdcall,
    dynlib: "kernel32", importc: "SetHandleInformation".}

proc getCurrentProcess*(): Handle{.stdcall, dynlib: "kernel32",
                                   importc: "GetCurrentProcess".}

proc createFileW*(lpFileName: WideCString, dwDesiredAccess, dwShareMode: DWORD,
                  lpSecurityAttributes: pointer,
                  dwCreationDisposition, dwFlagsAndAttributes: DWORD,
                  hTemplateFile: Handle): Handle {.
    stdcall, dynlib: "kernel32", importc: "CreateFileW".}
proc deleteFileW*(pathName: WideCString): int32 {.
  importc: "DeleteFileW", dynlib: "kernel32", stdcall.}
proc createFileA*(lpFileName: cstring, dwDesiredAccess, dwShareMode: DWORD,
                  lpSecurityAttributes: pointer,
                  dwCreationDisposition, dwFlagsAndAttributes: DWORD,
                  hTemplateFile: Handle): Handle {.
    stdcall, dynlib: "kernel32", importc: "CreateFileA".}
proc deleteFileA*(pathName: cstring): int32 {.
  importc: "DeleteFileA", dynlib: "kernel32", stdcall.}

proc setEndOfFile*(hFile: Handle): WINBOOL {.stdcall, dynlib: "kernel32",
    importc: "SetEndOfFile".}

proc setFilePointer*(hFile: Handle, lDistanceToMove: LONG,
                     lpDistanceToMoveHigh: ptr LONG,
                     dwMoveMethod: DWORD): DWORD {.
    stdcall, dynlib: "kernel32", importc: "SetFilePointer".}

proc getFileSize*(hFile: Handle, lpFileSizeHigh: ptr DWORD): DWORD{.stdcall,
    dynlib: "kernel32", importc: "GetFileSize".}

when defined(cpu32):
  type
    WinSizeT* = uint32
else:
  type
    WinSizeT* = uint64

proc mapViewOfFileEx*(hFileMappingObject: Handle, dwDesiredAccess: DWORD,
                      dwFileOffsetHigh, dwFileOffsetLow: DWORD,
                      dwNumberOfBytesToMap: WinSizeT,
                      lpBaseAddress: pointer): pointer{.
    stdcall, dynlib: "kernel32", importc: "MapViewOfFileEx".}

proc createFileMappingW*(hFile: Handle,
                       lpFileMappingAttributes: pointer,
                       flProtect, dwMaximumSizeHigh: DWORD,
                       dwMaximumSizeLow: DWORD,
                       lpName: pointer): Handle {.
  stdcall, dynlib: "kernel32", importc: "CreateFileMappingW".}

proc unmapViewOfFile*(lpBaseAddress: pointer): WINBOOL {.stdcall,
    dynlib: "kernel32", importc: "UnmapViewOfFile".}

proc flushViewOfFile*(lpBaseAddress: pointer, dwNumberOfBytesToFlush: DWORD): WINBOOL {.
  stdcall, dynlib: "kernel32", importc: "FlushViewOfFile".}

type
  OVERLAPPED* {.pure, inheritable.} = object
    internal*: PULONG
    internalHigh*: PULONG
    offset*: DWORD
    offsetHigh*: DWORD
    hEvent*: Handle

  POVERLAPPED* = ptr OVERLAPPED

  POVERLAPPED_COMPLETION_ROUTINE* = proc (para1: DWORD, para2: DWORD,
      para3: POVERLAPPED){.stdcall.}

  GUID* = object
    D1*: int32
    D2*: int16
    D3*: int16
    D4*: array[0..7, int8]

const
  ERROR_IO_PENDING* = 997 # a.k.a WSA_IO_PENDING
  WSAECONNABORTED* = 10053
  WSAEADDRINUSE* = 10048
  WSAECONNRESET* = 10054
  WSAEDISCON* = 10101
  WSAENETRESET* = 10052
  WSAETIMEDOUT* = 10060
  WSANOTINITIALISED* = 10093
  WSAENOTSOCK* = 10038
  WSAEINPROGRESS* = 10036
  WSAEINTR* = 10004
  WSAEWOULDBLOCK* = 10035
  WSAESHUTDOWN* = 10058
  ERROR_NETNAME_DELETED* = 64
  STATUS_PENDING* = 0x103

proc createIoCompletionPort*(FileHandle: Handle, ExistingCompletionPort: Handle,
                             CompletionKey: ULONG_PTR,
                             NumberOfConcurrentThreads: DWORD): Handle{.stdcall,
    dynlib: "kernel32", importc: "CreateIoCompletionPort".}

proc getQueuedCompletionStatus*(CompletionPort: Handle,
    lpNumberOfBytesTransferred: PDWORD, lpCompletionKey: PULONG_PTR,
                                lpOverlapped: ptr POVERLAPPED,
                                dwMilliseconds: DWORD): WINBOOL{.stdcall,
    dynlib: "kernel32", importc: "GetQueuedCompletionStatus".}

proc getOverlappedResult*(hFile: Handle, lpOverlapped: POVERLAPPED,
              lpNumberOfBytesTransferred: var DWORD, bWait: WINBOOL): WINBOOL{.
    stdcall, dynlib: "kernel32", importc: "GetOverlappedResult".}

# this is copy of HasOverlappedIoCompleted() macro from <winbase.h>
# because we have declared own OVERLAPPED structure with member names not
# compatible with original names.
template hasOverlappedIoCompleted*(lpOverlapped): bool =
  (cast[uint](lpOverlapped.internal) != STATUS_PENDING)

const
 IOC_OUT* = 0x40000000'i32
 IOC_IN*  = 0x80000000'i32
 IOC_WS2* = 0x08000000'i32
 IOC_INOUT* = IOC_IN or IOC_OUT

template WSAIORW*(x,y): untyped = (IOC_INOUT or x or y)

const
  SIO_GET_EXTENSION_FUNCTION_POINTER* = WSAIORW(IOC_WS2,6).DWORD
  SO_UPDATE_ACCEPT_CONTEXT* = 0x700B
  AI_V4MAPPED* = 0x0008
  AF_UNSPEC* = 0
  AF_INET* = 2
  AF_INET6* = 23

var
  WSAID_CONNECTEX*: GUID = GUID(D1: 0x25a207b9, D2: 0xddf3'i16, D3: 0x4660, D4: [
    0x8e'i8, 0xe9'i8, 0x76'i8, 0xe5'i8, 0x8c'i8, 0x74'i8, 0x06'i8, 0x3e'i8])
  WSAID_ACCEPTEX*: GUID = GUID(D1: 0xb5367df1'i32, D2: 0xcbac'i16, D3: 0x11cf, D4: [
    0x95'i8, 0xca'i8, 0x00'i8, 0x80'i8, 0x5f'i8, 0x48'i8, 0xa1'i8, 0x92'i8])
  WSAID_GETACCEPTEXSOCKADDRS*: GUID = GUID(D1: 0xb5367df2'i32, D2: 0xcbac'i16, D3: 0x11cf, D4: [
    0x95'i8, 0xca'i8, 0x00'i8, 0x80'i8, 0x5f'i8, 0x48'i8, 0xa1'i8, 0x92'i8])

proc WSAIoctl*(s: SocketHandle, dwIoControlCode: DWORD, lpvInBuffer: pointer,
  cbInBuffer: DWORD, lpvOutBuffer: pointer, cbOutBuffer: DWORD,
  lpcbBytesReturned: PDWORD, lpOverlapped: POVERLAPPED,
  lpCompletionRoutine: POVERLAPPED_COMPLETION_ROUTINE): cint
  {.stdcall, importc: "WSAIoctl", dynlib: "Ws2_32.dll".}

type
  TWSABuf* {.importc: "WSABUF", header: "winsock2.h".} = object
    len*: ULONG
    buf*: cstring

proc WSARecv*(s: SocketHandle, buf: ptr TWSABuf, bufCount: DWORD,
  bytesReceived, flags: PDWORD, lpOverlapped: POVERLAPPED,
  completionProc: POVERLAPPED_COMPLETION_ROUTINE): cint {.
  stdcall, importc: "WSARecv", dynlib: "Ws2_32.dll".}

proc WSARecvFrom*(s: SocketHandle, buf: ptr TWSABuf, bufCount: DWORD,
                  bytesReceived: PDWORD, flags: PDWORD, name: ptr SockAddr,
                  namelen: ptr cint, lpOverlapped: POVERLAPPED,
                  completionProc: POVERLAPPED_COMPLETION_ROUTINE): cint {.
     stdcall, importc: "WSARecvFrom", dynlib: "Ws2_32.dll".}

proc WSASend*(s: SocketHandle, buf: ptr TWSABuf, bufCount: DWORD,
  bytesSent: PDWORD, flags: DWORD, lpOverlapped: POVERLAPPED,
  completionProc: POVERLAPPED_COMPLETION_ROUTINE): cint {.
  stdcall, importc: "WSASend", dynlib: "Ws2_32.dll".}

proc WSASendTo*(s: SocketHandle, buf: ptr TWSABuf, bufCount: DWORD,
                bytesSent: PDWORD, flags: DWORD, name: ptr SockAddr,
                namelen: cint, lpOverlapped: POVERLAPPED,
                completionProc: POVERLAPPED_COMPLETION_ROUTINE): cint {.
     stdcall, importc: "WSASendTo", dynlib: "Ws2_32.dll".}

proc get_osfhandle*(fd:FileHandle): Handle {.
  importc: "_get_osfhandle", header:"<io.h>".}

proc getSystemTimes*(lpIdleTime, lpKernelTime,
                     lpUserTime: var FILETIME): WINBOOL {.stdcall,
  dynlib: "kernel32", importc: "GetSystemTimes".}

proc getProcessTimes*(hProcess: Handle; lpCreationTime, lpExitTime,
  lpKernelTime, lpUserTime: var FILETIME): WINBOOL {.stdcall,
  dynlib: "kernel32", importc: "GetProcessTimes".}

proc getSystemTimePreciseAsFileTime*(lpSystemTimeAsFileTime: var FILETIME) {.
  importc: "GetSystemTimePreciseAsFileTime", dynlib: "kernel32", stdcall, sideEffect.}

type inet_ntop_proc = proc(family: cint, paddr: pointer, pStringBuffer: cstring,
                      stringBufSize: int32): cstring {.gcsafe, stdcall, tags: [].}

var inet_ntop_real: inet_ntop_proc = nil

let ws2 = loadLib(ws2dll)
if ws2 != nil:
  inet_ntop_real = cast[inet_ntop_proc](symAddr(ws2, "inet_ntop"))

proc WSAAddressToStringA(pAddr: ptr SockAddr, addrSize: DWORD, unused: pointer, pBuff: cstring, pBuffSize: ptr DWORD): cint {.stdcall, importc, dynlib: ws2dll.}
proc inet_ntop_emulated(family: cint, paddr: pointer, pStringBuffer: cstring,
                  stringBufSize: int32): cstring {.stdcall.} =
  case family
  of AF_INET:
    var sa: Sockaddr_in = default(Sockaddr_in)
    sa.sin_family = AF_INET
    sa.sin_addr = cast[ptr InAddr](paddr)[]
    var bs = stringBufSize.DWORD
    let r = WSAAddressToStringA(cast[ptr SockAddr](sa.addr), sa.sizeof.DWORD, nil, pStringBuffer, bs.addr)
    if r != 0:
      result = nil
    else:
      result = pStringBuffer
  of AF_INET6:
    var sa: Sockaddr_in6 = default(Sockaddr_in6)
    sa.sin6_family = AF_INET6
    sa.sin6_addr = cast[ptr In6_addr](paddr)[]
    var bs = stringBufSize.DWORD
    let r = WSAAddressToStringA(cast[ptr SockAddr](sa.addr), sa.sizeof.DWORD, nil, pStringBuffer, bs.addr)
    if r != 0:
      result = nil
    else:
      result = pStringBuffer
  else:
    setLastError(ERROR_BAD_ARGUMENTS)
    result = nil

proc inet_ntop*(family: cint, paddr: pointer, pStringBuffer: cstring,
                  stringBufSize: int32): cstring {.stdcall.} =
  var ver: OSVERSIONINFO = default(OSVERSIONINFO)
  ver.dwOSVersionInfoSize = sizeof(ver).DWORD
  let res = getVersionExW(ver.addr)
  if res == 0:
    result = nil
  elif ver.dwMajorVersion >= 6:
    if inet_ntop_real == nil:
      quit("Can't load inet_ntop proc from " & ws2dll)
    result = inet_ntop_real(family, paddr, pStringBuffer, stringBufSize)
  else:
    result = inet_ntop_emulated(family, paddr, pStringBuffer, stringBufSize)

type
  WSAPROC_ACCEPTEX* = proc (sListenSocket: SocketHandle,
                            sAcceptSocket: SocketHandle,
                            lpOutputBuffer: pointer, dwReceiveDataLength: DWORD,
                            dwLocalAddressLength: DWORD,
                            dwRemoteAddressLength: DWORD,
                            lpdwBytesReceived: ptr DWORD,
                            lpOverlapped: POVERLAPPED): bool {.
                            stdcall, gcsafe, raises: [].}

  WSAPROC_CONNECTEX* = proc (s: SocketHandle, name: ptr SockAddr, namelen: cint,
                             lpSendBuffer: pointer, dwSendDataLength: DWORD,
                             lpdwBytesSent: ptr DWORD,
                             lpOverlapped: POVERLAPPED): bool {.
                             stdcall, gcsafe, raises: [].}

  WSAPROC_GETACCEPTEXSOCKADDRS* = proc(lpOutputBuffer: pointer,
                                       dwReceiveDataLength: DWORD,
                                       dwLocalAddressLength: DWORD,
                                       dwRemoteAddressLength: DWORD,
                                       LocalSockaddr: ptr PSockAddr,
                                       LocalSockaddrLength: ptr cint,
                                       RemoteSockaddr: ptr PSockAddr,
                                       RemoteSockaddrLength: ptr cint) {.
                                       stdcall, gcsafe, raises: [].}

const
  WT_EXECUTEDEFAULT* = 0x00000000'i32
  WT_EXECUTEINIOTHREAD* = 0x00000001'i32
  WT_EXECUTEINUITHREAD* = 0x00000002'i32
  WT_EXECUTEINWAITTHREAD* = 0x00000004'i32
  WT_EXECUTEONLYONCE* = 0x00000008'i32
  WT_EXECUTELONGFUNCTION* = 0x00000010'i32
  WT_EXECUTEINTIMERTHREAD* = 0x00000020'i32
  WT_EXECUTEINPERSISTENTIOTHREAD* = 0x00000040'i32
  WT_EXECUTEINPERSISTENTTHREAD* = 0x00000080'i32
  WT_TRANSFER_IMPERSONATION* = 0x00000100'i32
  PROCESS_TERMINATE* = 0x00000001'i32
  PROCESS_CREATE_THREAD* = 0x00000002'i32
  PROCESS_SET_SESSIONID* = 0x00000004'i32
  PROCESS_VM_OPERATION* = 0x00000008'i32
  PROCESS_VM_READ* = 0x00000010'i32
  PROCESS_VM_WRITE* = 0x00000020'i32
  PROCESS_DUP_HANDLE* = 0x00000040'i32
  PROCESS_CREATE_PROCESS* = 0x00000080'i32
  PROCESS_SET_QUOTA* = 0x00000100'i32
  PROCESS_SET_INFORMATION* = 0x00000200'i32
  PROCESS_QUERY_INFORMATION* = 0x00000400'i32
  PROCESS_SUSPEND_RESUME* = 0x00000800'i32
  PROCESS_QUERY_LIMITED_INFORMATION* = 0x00001000'i32
  PROCESS_SET_LIMITED_INFORMATION* = 0x00002000'i32
type
  WAITORTIMERCALLBACK* = proc(para1: pointer, para2: int32) {.stdcall.}

proc postQueuedCompletionStatus*(CompletionPort: Handle,
                                dwNumberOfBytesTransferred: DWORD,
                                dwCompletionKey: ULONG_PTR,
                                lpOverlapped: pointer): bool
     {.stdcall, dynlib: "kernel32", importc: "PostQueuedCompletionStatus".}

proc registerWaitForSingleObject*(phNewWaitObject: ptr Handle, hObject: Handle,
                                 Callback: WAITORTIMERCALLBACK,
                                 Context: pointer,
                                 dwMilliseconds: ULONG,
                                 dwFlags: ULONG): bool
     {.stdcall, dynlib: "kernel32", importc: "RegisterWaitForSingleObject".}

proc unregisterWait*(WaitHandle: Handle): DWORD
     {.stdcall, dynlib: "kernel32", importc: "UnregisterWait".}

proc openProcess*(dwDesiredAccess: DWORD, bInheritHandle: WINBOOL,
                    dwProcessId: DWORD): Handle
     {.stdcall, dynlib: "kernel32", importc: "OpenProcess".}

proc createEvent*(lpEventAttributes: ptr SECURITY_ATTRIBUTES,
                  bManualReset: DWORD, bInitialState: DWORD,
                  lpName: ptr Utf16Char): Handle
     {.stdcall, dynlib: "kernel32", importc: "CreateEventW".}

proc setEvent*(hEvent: Handle): cint
     {.stdcall, dynlib: "kernel32", importc: "SetEvent".}

const
  FD_READ* = 0x00000001'i32
  FD_WRITE* = 0x00000002'i32
  FD_OOB* = 0x00000004'i32
  FD_ACCEPT* = 0x00000008'i32
  FD_CONNECT* = 0x00000010'i32
  FD_CLOSE* = 0x00000020'i32
  FD_QQS* = 0x00000040'i32
  FD_GROUP_QQS* = 0x00000080'i32
  FD_ROUTING_INTERFACE_CHANGE* = 0x00000100'i32
  FD_ADDRESS_LIST_CHANGE* = 0x00000200'i32
  FD_ALL_EVENTS* = 0x000003FF'i32

proc wsaEventSelect*(s: SocketHandle, hEventObject: Handle,
                     lNetworkEvents: clong): cint
    {.stdcall, importc: "WSAEventSelect", dynlib: "ws2_32.dll".}

proc wsaCreateEvent*(): Handle
    {.stdcall, importc: "WSACreateEvent", dynlib: "ws2_32.dll".}

proc wsaCloseEvent*(hEvent: Handle): bool
     {.stdcall, importc: "WSACloseEvent", dynlib: "ws2_32.dll".}

proc wsaResetEvent*(hEvent: Handle): bool
     {.stdcall, importc: "WSAResetEvent", dynlib: "ws2_32.dll".}

type
  KEY_EVENT_RECORD* = object
    eventType*: int16
    bKeyDown*: WINBOOL
    wRepeatCount*: int16
    wVirtualKeyCode*: int16
    wVirtualScanCode*: int16
    uChar*: int16
    dwControlKeyState*: DWORD

proc readConsoleInput*(hConsoleInput: Handle, lpBuffer: pointer, nLength: cint,
                      lpNumberOfEventsRead: ptr cint): cint
     {.stdcall, dynlib: "kernel32", importc: "ReadConsoleInputW".}

type
  LPFIBER_START_ROUTINE* = proc (param: pointer) {.stdcall.}

const
  FIBER_FLAG_FLOAT_SWITCH* = 0x01

proc CreateFiber*(stackSize: int, fn: LPFIBER_START_ROUTINE, param: pointer): pointer {.stdcall, discardable, dynlib: "kernel32", importc.}
proc CreateFiberEx*(stkCommit: int, stkReserve: int, flags: int32, fn: LPFIBER_START_ROUTINE, param: pointer): pointer {.stdcall, discardable, dynlib: "kernel32", importc.}
proc ConvertThreadToFiber*(param: pointer): pointer {.stdcall, discardable, dynlib: "kernel32", importc.}
proc ConvertThreadToFiberEx*(param: pointer, flags: int32): pointer {.stdcall, discardable, dynlib: "kernel32", importc.}
proc DeleteFiber*(fiber: pointer) {.stdcall, discardable, dynlib: "kernel32", importc.}
proc SwitchToFiber*(fiber: pointer) {.stdcall, discardable, dynlib: "kernel32", importc.}
proc GetCurrentFiber*(): pointer {.stdcall, importc, header: "windows.h".}

proc toFILETIME*(t: int64): FILETIME =
  ## Convert the Windows file time timestamp `t` to `FILETIME`.
  result = FILETIME(dwLowDateTime: cast[DWORD](t), dwHighDateTime: DWORD(t shr 32))

type
  LPFILETIME* = ptr FILETIME

proc setFileTime*(hFile: Handle, lpCreationTime: LPFILETIME,
                 lpLastAccessTime: LPFILETIME, lpLastWriteTime: LPFILETIME): WINBOOL
     {.stdcall, dynlib: "kernel32", importc: "SetFileTime".}

type
  # https://docs.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-sid_identifier_authority
  SID_IDENTIFIER_AUTHORITY* {.importc, header: "<windows.h>".} = object
    value* {.importc: "Value".}: array[6, BYTE]
  # https://docs.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-sid
  SID* {.importc, header: "<windows.h>".} = object
    Revision: BYTE
    SubAuthorityCount: BYTE
    IdentifierAuthority: SID_IDENTIFIER_AUTHORITY
    SubAuthority: ptr ptr DWORD
  PSID* = ptr SID

const
  # https://docs.microsoft.com/en-us/windows/win32/secauthz/sid-components
  # https://github.com/mirror/mingw-w64/blob/84c950bdab7c999ace49fe8383856be77f88c4a8/mingw-w64-headers/include/winnt.h#L2994
  SECURITY_NT_AUTHORITY* = [BYTE(0), BYTE(0), BYTE(0), BYTE(0), BYTE(0), BYTE(5)]
  SECURITY_BUILTIN_DOMAIN_RID* = 32
  DOMAIN_ALIAS_RID_ADMINS* = 544

proc allocateAndInitializeSid*(pIdentifierAuthority: ptr SID_IDENTIFIER_AUTHORITY,
                               nSubAuthorityCount: BYTE,
                               nSubAuthority0: DWORD,
                               nSubAuthority1: DWORD,
                               nSubAuthority2: DWORD,
                               nSubAuthority3: DWORD,
                               nSubAuthority4: DWORD,
                               nSubAuthority5: DWORD,
                               nSubAuthority6: DWORD,
                               nSubAuthority7: DWORD,
                               pSid: ptr PSID): WINBOOL
     {.stdcall, dynlib: "Advapi32", importc: "AllocateAndInitializeSid".}
proc checkTokenMembership*(tokenHandle: Handle, sidToCheck: PSID,
                           isMember: PBOOL): WINBOOL
     {.stdcall, dynlib: "Advapi32", importc: "CheckTokenMembership".}
proc freeSid*(pSid: PSID): PSID
     {.stdcall, dynlib: "Advapi32", importc: "FreeSid".}

when defined(nimHasStyleChecks):
  {.pop.} # {.push styleChecks: off.}
