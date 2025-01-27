#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module contains helpers that deal with different byte orders
## (`endian`:idx:).
##
## Endianness is the order of bytes of a value in memory. Big-endian means that
## the most significant byte is stored at the smallest memory address,
## while little endian means that the least-significant byte is stored
## at the smallest address. See also https://en.wikipedia.org/wiki/Endianness.
##
## Unstable API.

when defined(gcc) or defined(llvm_gcc) or defined(clang):
  const useBuiltinSwap = true
  proc builtin_bswap16(a: uint16): uint16 {.
      importc: "__builtin_bswap16", nodecl, noSideEffect.}

  proc builtin_bswap32(a: uint32): uint32 {.
      importc: "__builtin_bswap32", nodecl, noSideEffect.}

  proc builtin_bswap64(a: uint64): uint64 {.
      importc: "__builtin_bswap64", nodecl, noSideEffect.}
elif defined(icc):
  const useBuiltinSwap = true
  proc builtin_bswap16(a: uint16): uint16 {.
      importc: "_bswap16", nodecl, noSideEffect.}

  proc builtin_bswap32(a: uint32): uint32 {.
      importc: "_bswap", nodecl, noSideEffect.}

  proc builtin_bswap64(a: uint64): uint64 {.
      importc: "_bswap64", nodecl, noSideEffect.}
elif defined(vcc):
  const useBuiltinSwap = true
  proc builtin_bswap16(a: uint16): uint16 {.
      importc: "_byteswap_ushort", nodecl, header: "<intrin.h>", noSideEffect.}

  proc builtin_bswap32(a: uint32): uint32 {.
      importc: "_byteswap_ulong", nodecl, header: "<intrin.h>", noSideEffect.}

  proc builtin_bswap64(a: uint64): uint64 {.
      importc: "_byteswap_uint64", nodecl, header: "<intrin.h>", noSideEffect.}
else:
  const useBuiltinSwap = false

when useBuiltinSwap:
  template swapOpImpl(T: typedesc, op: untyped) =
    ## We have to use `copyMem` here instead of a simple dereference because they
    ## may point to a unaligned address. A sufficiently smart compiler _should_
    ## be able to elide them when they're not necessary.
    var tmp: T = default(T)
    copyMem(addr tmp, inp, sizeof(T))
    tmp = op(tmp)
    copyMem(outp, addr tmp, sizeof(T))

  proc swapEndian64*(outp, inp: pointer) {.inline, noSideEffect.} =
    ## Copies `inp` to `outp`, reversing the byte order.
    ## Both buffers are supposed to contain at least 8 bytes.
    runnableExamples:
      var a = [1'u8, 2, 3, 4, 5, 6, 7, 8]
      var b: array[8, uint8]
      swapEndian64(addr b, addr a)
      assert b == [8'u8, 7, 6, 5, 4, 3, 2, 1]

    swapOpImpl(uint64, builtin_bswap64)

  proc swapEndian32*(outp, inp: pointer) {.inline, noSideEffect.} =
    ## Copies `inp` to `outp`, reversing the byte order.
    ## Both buffers are supposed to contain at least 4 bytes.
    runnableExamples:
      var a = [1'u8, 2, 3, 4]
      var b: array[4, uint8]
      swapEndian32(addr b, addr a)
      assert b == [4'u8, 3, 2, 1]

    swapOpImpl(uint32, builtin_bswap32)

  proc swapEndian16*(outp, inp: pointer) {.inline, noSideEffect.} =
    ## Copies `inp` to `outp`, reversing the byte order.
    ## Both buffers are supposed to contain at least 2 bytes.
    runnableExamples:
      var a = [1'u8, 2]
      var b: array[2, uint8]
      swapEndian16(addr b, addr a)
      assert b == [2'u8, 1]

    swapOpImpl(uint16, builtin_bswap16)

else:
  proc swapEndian64*(outp, inp: pointer) =
    var i = cast[cstring](inp)
    var o = cast[cstring](outp)
    o[0] = i[7]
    o[1] = i[6]
    o[2] = i[5]
    o[3] = i[4]
    o[4] = i[3]
    o[5] = i[2]
    o[6] = i[1]
    o[7] = i[0]

  proc swapEndian32*(outp, inp: pointer) =
    var i = cast[cstring](inp)
    var o = cast[cstring](outp)
    o[0] = i[3]
    o[1] = i[2]
    o[2] = i[1]
    o[3] = i[0]

  proc swapEndian16*(outp, inp: pointer) =
    var i = cast[cstring](inp)
    var o = cast[cstring](outp)
    o[0] = i[1]
    o[1] = i[0]

when system.cpuEndian == bigEndian:
  proc littleEndian64*(outp, inp: pointer) {.inline.} = swapEndian64(outp, inp)
  proc littleEndian32*(outp, inp: pointer) {.inline.} = swapEndian32(outp, inp)
  proc littleEndian16*(outp, inp: pointer) {.inline.} = swapEndian16(outp, inp)
  proc bigEndian64*(outp, inp: pointer) {.inline.} = copyMem(outp, inp, 8)
  proc bigEndian32*(outp, inp: pointer) {.inline.} = copyMem(outp, inp, 4)
  proc bigEndian16*(outp, inp: pointer) {.inline.} = copyMem(outp, inp, 2)
else:
  proc littleEndian64*(outp, inp: pointer) {.inline.} = copyMem(outp, inp, 8)
    ## Copies `inp` to `outp`, storing it in 64-bit little-endian order.
    ## Both buffers are supposed to contain at least 8 bytes.
  proc littleEndian32*(outp, inp: pointer) {.inline.} = copyMem(outp, inp, 4)
    ## Copies `inp` to `outp`, storing it in 32-bit little-endian order.
    ## Both buffers are supposed to contain at least 4 bytes.
  proc littleEndian16*(outp, inp: pointer){.inline.} = copyMem(outp, inp, 2)
    ## Copies `inp` to `outp`, storing it in 16-bit little-endian order.
    ## Both buffers are supposed to contain at least 2 bytes.
  proc bigEndian64*(outp, inp: pointer) {.inline.} = swapEndian64(outp, inp)
    ## Copies `inp` to `outp`, storing it in 64-bit big-endian order.
    ## Both buffers are supposed to contain at least 8 bytes.
  proc bigEndian32*(outp, inp: pointer) {.inline.} = swapEndian32(outp, inp)
    ## Copies `inp` to `outp`, storing it in 32-bit big-endian order.
    ## Both buffers are supposed to contain at least 4 bytes.
  proc bigEndian16*(outp, inp: pointer) {.inline.} = swapEndian16(outp, inp)
    ## Copies `inp` to `outp`, storing it in 16-bit big-endian order.
    ## Both buffers are supposed to contain at least 2 bytes.
