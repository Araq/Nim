#
#
#            Nim's Runtime Library
#        (c) Copyright 2021 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## .. warning:: This module was added in Nim 1.6. If you are using it for cryptographic purposes,
##   keep in mind that so far this has not been audited by any security professionals,
##   therefore may not be secure.
##
## `std/sysrand` generates random numbers from a secure source provided by the operating system.
## It is a cryptographically secure pseudorandom number generator
## and should be unpredictable enough for cryptographic applications,
## though its exact quality depends on the OS implementation.
##
## | Targets              | Implementation        |
## | :---                 | ----:                 |
## | Windows              | `BCryptGenRandom`_    |
## | Linux                | `getrandom`_          |
## | MacOSX               | `SecRandomCopyBytes`_ |
## | iOS                  | `SecRandomCopyBytes`_ |
## | OpenBSD              | `getentropy openbsd`_ |
## | FreeBSD              | `getrandom freebsd`_  |
## | JS (Web Browser)     | `getRandomValues`_    |
## | Node.js              | `randomFillSync`_     |
## | Other Unix platforms | `/dev/urandom`_       |
##
## .. _BCryptGenRandom: https://docs.microsoft.com/en-us/windows/win32/api/bcrypt/nf-bcrypt-bcryptgenrandom
## .. _getrandom: https://man7.org/linux/man-pages/man2/getrandom.2.html
## .. _getentropy: https://www.unix.com/man-page/mojave/2/getentropy
## .. _SecRandomCopyBytes: https://developer.apple.com/documentation/security/1399291-secrandomcopybytes?language=objc
## .. _getentropy openbsd: https://man.openbsd.org/getentropy.2
## .. _getrandom freebsd: https://www.freebsd.org/cgi/man.cgi?query=getrandom&manpath=FreeBSD+12.0-stable
## .. _getRandomValues: https://www.w3.org/TR/WebCryptoAPI/#Crypto-method-getRandomValues
## .. _randomFillSync: https://nodejs.org/api/crypto.html#crypto_crypto_randomfillsync_buffer_offset_size
## .. _/dev/urandom: https://en.wikipedia.org/wiki//dev/random
##
## On a Linux target, a call to the `getrandom` syscall can be avoided (e.g.
## for targets running kernel version < 3.17) by passing a compile flag of
## `-d:nimNoGetRandom`. If this flag is passed, sysrand will use `/dev/urandom`
## as with any other POSIX compliant OS.
##

runnableExamples:
  doAssert urandom(0).len == 0
  doAssert urandom(113).len == 113
  doAssert urandom(1234) != urandom(1234) # unlikely to fail in practice

##
## See also
## ========
## * `random module <random.html>`_
##


when not defined(js):
  import std/oserrors

when defined(posix):
  import std/posix

when defined(nimPreviewSlimSystem):
  import std/assertions

const
  batchImplOS = defined(freebsd) or defined(openbsd) or defined(zephyr)
  batchSize {.used.} = 256

when batchImplOS:
  template batchImpl(result: var int, dest: var openArray[byte], getRandomImpl) =
    let size = dest.len
    if size == 0:
      return

    let
      chunks = (size - 1) div batchSize
      left = size - chunks * batchSize

    for i in 0 ..< chunks:
      let readBytes = getRandomImpl(addr dest[result], batchSize)
      if readBytes < 0:
        return readBytes
      inc(result, batchSize)

    result = getRandomImpl(addr dest[result], left)

when defined(js):
  import std/private/jsutils

  when defined(nodejs):
    {.emit: "const _nim_nodejs_crypto = require('crypto');".}

    proc randomFillSync(p: Uint8Array) {.importjs: "_nim_nodejs_crypto.randomFillSync(#)".}

    template urandomImpl(result: var int, dest: var openArray[byte]) =
      let size = dest.len
      if size == 0:
        return

      var src = newUint8Array(size)
      randomFillSync(src)
      for i in 0 ..< size:
        dest[i] = src[i]

  else:
    proc getRandomValues(p: Uint8Array) {.importjs: "window.crypto.getRandomValues(#)".}
      # The requested length of `p` must not be more than 65536.

    proc assign(dest: var openArray[byte], src: Uint8Array, base: int, size: int) =
      getRandomValues(src)
      for j in 0 ..< size:
        dest[base + j] = src[j]

    template urandomImpl(result: var int, dest: var openArray[byte]) =
      let size = dest.len
      if size == 0:
        return

      if size <= batchSize:
        var src = newUint8Array(size)
        assign(dest, src, 0, size)
        return

      let
        chunks = (size - 1) div batchSize
        left = size - chunks * batchSize

      var srcArray = newUint8Array(batchSize)
      for i in 0 ..< chunks:
        assign(dest, srcArray, result, batchSize)
        inc(result, batchSize)

      var leftArray = newUint8Array(left)
      assign(dest, leftArray, result, left)

elif defined(windows):
  type
    PVOID = pointer
    BCRYPT_ALG_HANDLE = PVOID
    PUCHAR = ptr uint8
    NTSTATUS = clong
    ULONG = culong

  const
    STATUS_SUCCESS = 0x00000000
    BCRYPT_USE_SYSTEM_PREFERRED_RNG = 0x00000002

  proc bCryptGenRandom(
    hAlgorithm: BCRYPT_ALG_HANDLE,
    pbBuffer: PUCHAR,
    cbBuffer: ULONG,
    dwFlags: ULONG
  ): NTSTATUS {.stdcall, importc: "BCryptGenRandom", dynlib: "Bcrypt.dll".}


  proc randomBytes(pbBuffer: pointer, cbBuffer: Natural): int {.inline.} =
    bCryptGenRandom(nil, cast[PUCHAR](pbBuffer), ULONG(cbBuffer),
                            BCRYPT_USE_SYSTEM_PREFERRED_RNG)

  template urandomImpl(result: var int, dest: var openArray[byte]) =
    let size = dest.len
    if size == 0:
      return

    result = randomBytes(addr dest[0], size)

elif defined(linux) and not defined(nimNoGetRandom) and not defined(emscripten):
  when (NimMajor, NimMinor) >= (1, 4):
    let SYS_getrandom {.importc: "SYS_getrandom", header: "<sys/syscall.h>".}: clong
  else:
    var SYS_getrandom {.importc: "SYS_getrandom", header: "<sys/syscall.h>".}: clong
  const syscallHeader = """#include <unistd.h>
#include <sys/syscall.h>"""

  proc syscall(n: clong): clong {.
      importc: "syscall", varargs, header: syscallHeader.}
    #  When reading from the urandom source (GRND_RANDOM is not set),
    #  getrandom() will block until the entropy pool has been
    #  initialized (unless the GRND_NONBLOCK flag was specified).  If a
    #  request is made to read a large number of bytes (more than 256),
    #  getrandom() will block until those bytes have been generated and
    #  transferred from kernel memory to buf.

  template urandomImpl(result: var int, dest: var openArray[byte]) =
    let size = dest.len
    if size == 0:
      return

    while result < size:
      let readBytes = syscall(SYS_getrandom, addr dest[result], cint(size - result), 0).int
      if readBytes == 0:
        raiseAssert "unreachable"
      elif readBytes > 0:
        inc(result, readBytes)
      else:
        if osLastError().cint in [EINTR, EAGAIN]: discard
        else:
          result = -1
          break

elif defined(openbsd):
  proc getentropy(p: pointer, size: cint): cint {.importc: "getentropy", header: "<unistd.h>".}
    # Fills a buffer with high-quality entropy,
    # which can be used as input for process-context pseudorandom generators like `arc4random`.
    # The maximum buffer size permitted is 256 bytes.

  proc getRandomImpl(p: pointer, size: int): int {.inline.} =
    result = getentropy(p, cint(size)).int

elif defined(zephyr):
  proc sys_csrand_get(dst: pointer, length: csize_t): cint {.importc: "sys_csrand_get", header: "<random/rand32.h>".}
    # Fill the destination buffer with cryptographically secure
    # random data values
    #

  proc getRandomImpl(p: pointer, size: int): int {.inline.} =
    # 0 if success, -EIO if entropy reseed error
    result = sys_csrand_get(p, csize_t(size)).int

elif defined(freebsd):
  type cssize_t {.importc: "ssize_t", header: "<sys/types.h>".} = int

  proc getrandom(p: pointer, size: csize_t, flags: cuint): cssize_t {.importc: "getrandom", header: "<sys/random.h>".}
    # Upon successful completion, the number of bytes which were actually read
    # is returned. For requests larger than 256 bytes, this can be fewer bytes
    # than were requested. Otherwise, -1 is returned and the global variable
    # errno is set to indicate the error.

  proc getRandomImpl(p: pointer, size: int): int {.inline.} =
    result = getrandom(p, csize_t(size), 0)

elif defined(ios) or defined(macosx):
  {.passl: "-framework Security".}

  const errSecSuccess = 0 ## No error.

  type
    SecRandom {.importc: "struct __SecRandom".} = object

    SecRandomRef = ptr SecRandom
      ## An abstract Core Foundation-type object containing information about a random number generator.

  proc secRandomCopyBytes(
    rnd: SecRandomRef, count: csize_t, bytes: pointer
  ): cint {.importc: "SecRandomCopyBytes", header: "<Security/SecRandom.h>".}
    ## https://developer.apple.com/documentation/security/1399291-secrandomcopybytes

  template urandomImpl(result: var int, dest: var openArray[byte]) =
    let size = dest.len
    if size == 0:
      return

    result = secRandomCopyBytes(nil, csize_t(size), addr dest[0])

else:
  template urandomImpl(result: var int, dest: var openArray[byte]) =
    let size = dest.len
    if size == 0:
      return

    # see: https://www.2uo.de/myths-about-urandom/ which justifies using urandom instead of random
    let fd = posix.open("/dev/urandom", O_RDONLY)

    if fd < 0:
      result = -1
    else:
      try:
        var stat: Stat
        if fstat(fd, stat) != -1 and S_ISCHR(stat.st_mode):
          let
            chunks = (size - 1) div batchSize
            left = size - chunks * batchSize

          for i in 0 ..< chunks:
            let readBytes = posix.read(fd, addr dest[result], batchSize)
            if readBytes < 0:
              return readBytes
            inc(result, batchSize)

          result = posix.read(fd, addr dest[result], left)
        else:
          result = -1
      finally:
        discard posix.close(fd)

proc urandomInternalImpl(dest: var openArray[byte]): int {.inline.} =
  result = 0
  when batchImplOS:
    batchImpl(result, dest, getRandomImpl)
  else:
    urandomImpl(result, dest)

proc urandom*(dest: var openArray[byte]): bool =
  ## Fills `dest` with random bytes suitable for cryptographic use.
  ## If the call succeeds, returns `true`.
  ##
  ## If `dest` is empty, `urandom` immediately returns success,
  ## without calling the underlying operating system API.
  ##
  ## .. warning:: The code hasn't been audited by cryptography experts and
  ##   is provided as-is without guarantees. Use at your own risks. For production
  ##   systems we advise you to request an external audit.
  result = true
  when defined(js): discard urandomInternalImpl(dest)
  else:
    let ret = urandomInternalImpl(dest)
    when defined(windows):
      if ret != STATUS_SUCCESS:
        result = false
    else:
      if ret < 0:
        result = false

proc urandom*(size: Natural): seq[byte] {.inline.} =
  ## Returns random bytes suitable for cryptographic use.
  ##
  ## .. warning:: The code hasn't been audited by cryptography experts and
  ##   is provided as-is without guarantees. Use at your own risks. For production
  ##   systems we advise you to request an external audit.
  result = newSeq[byte](size)
  when defined(js): discard urandomInternalImpl(result)
  else:
    if not urandom(result):
      raiseOSError(osLastError())
