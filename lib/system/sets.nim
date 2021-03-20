#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# set handling
from std/private/vmutils import forwardImpl, toUnsigned


const useBuiltins = not defined(noIntrinsicsBitOpts)
const noUndefined = defined(noUndefinedBitOpts)
const useGCC_builtins = (defined(gcc) or defined(llvm_gcc) or
                         defined(clang)) and useBuiltins
const useICC_builtins = defined(icc) and useBuiltins
const useVCC_builtins = defined(vcc) and useBuiltins

type
  NimSet = array[0..4*2048-1, uint8]


proc cardSet*(s: NimSet, len: int): int {.compilerproc, inline.} =
  var i = 0
  result = 0
  when defined(x86) or defined(amd64):
    while i < len - 8:
      inc(result, countBits64((cast[ptr uint64](s[i].unsafeAddr))[]))
      inc(i, 8)

  while i < len:
    inc(result, countBits32(uint32(s[i])))
    inc(i, 1)


when not declared(ThisIsSystem):
  export useBuiltins, noUndefined, useGCC_builtins, useICC_builtins, useVCC_builtins
  export countSetBitsImpl
