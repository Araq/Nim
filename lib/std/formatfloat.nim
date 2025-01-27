#
#
#            Nim's Runtime Library
#        (c) Copyright 2022 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements formatting floats as strings.

when defined(nimPreviewSlimSystem):
  import std/assertions

from system/ansi_c import c_memcpy

proc addCstringN(result: var string, buf: cstring; buflen: int) =
  # no nimvm support needed, so it doesn't need to be fast here either
  let oldLen = result.len
  let newLen = oldLen + buflen
  result.setLen newLen
  c_memcpy(result[oldLen].addr, buf, buflen.csize_t)

import std/private/[dragonbox, schubfach]

proc writeFloatToBufferRoundtrip*(buf: var array[65, char]; value: BiggestFloat): int =
  ## This is the implementation to format floats.
  ##
  ## returns the amount of bytes written to `buf` not counting the
  ## terminating '\0' character.
  result = toChars(buf, value, forceTrailingDotZero=true).int
  buf[result] = '\0'

proc writeFloatToBufferRoundtrip*(buf: var array[65, char]; value: float32): int =
  result = float32ToChars(buf, value, forceTrailingDotZero=true).int
  buf[result] = '\0'

proc c_snprintf(buf: cstring, n: csize_t, frmt: cstring): cint {.header: "<stdio.h>",
                                    importc: "snprintf", varargs, noSideEffect.}

proc writeToBuffer(buf: var array[65, char]; value: cstring) =
  var i = 0
  while value[i] != '\0':
    buf[i] = value[i]
    inc i

proc writeFloatToBufferSprintf*(buf: var array[65, char]; value: BiggestFloat): int =
  ## This is the implementation to format floats.
  ##
  ## returns the amount of bytes written to `buf` not counting the
  ## terminating '\0' character.
  var n = c_snprintf(cast[cstring](addr buf), 65, "%.16g", value).int
  var hasDot = false
  for i in 0..n-1:
    if buf[i] == ',':
      buf[i] = '.'
      hasDot = true
    elif buf[i] in {'a'..'z', 'A'..'Z', '.'}:
      hasDot = true
  if not hasDot:
    buf[n] = '.'
    buf[n+1] = '0'
    buf[n+2] = '\0'
    result = n + 2
  else:
    result = n
  # On Windows nice numbers like '1.#INF', '-1.#INF' or '1.#NAN' or 'nan(ind)'
  # of '-1.#IND' are produced.
  # We want to get rid of these here:
  if buf[n-1] in {'n', 'N', 'D', 'd', ')'}:
    writeToBuffer(buf, "nan")
    result = 3
  elif buf[n-1] == 'F':
    if buf[0] == '-':
      writeToBuffer(buf, "-inf")
      result = 4
    else:
      writeToBuffer(buf, "inf")
      result = 3

proc writeFloatToBuffer*(buf: var array[65, char]; value: BiggestFloat | float32): int {.inline.} =
  when defined(nimLegacySprintf):
    writeFloatToBufferSprintf(buf, value)
  else:
    writeFloatToBufferRoundtrip(buf, value)

proc addFloatRoundtrip*(result: var string; x: float | float32) =
  when nimvm:
    raiseAssert "unreachable"
  else:
    var buffer {.noinit.}: array[65, char]
    let n = writeFloatToBufferRoundtrip(buffer, x)
    result.addCstringN(cast[cstring](buffer[0].addr), n)

proc addFloatSprintf*(result: var string; x: float) =
  when nimvm:
    raiseAssert "unreachable"
  else:
    var buffer {.noinit.}: array[65, char]
    let n = writeFloatToBufferSprintf(buffer, x)
    result.addCstringN(cast[cstring](buffer[0].addr), n)

when defined(js):
  proc nimFloatToString(a: float): cstring =
    ## ensures the result doesn't print like an integer, i.e. return 2.0, not 2
    # print `-0.0` properly
    {.emit: """
      function nimOnlyDigitsOrMinus(n) {
        return n.toString().match(/^-?\d+$/);
      }
      if (Number.isSafeInteger(`a`))
        `result` = `a` === 0 && 1 / `a` < 0 ? "-0.0" : `a`+".0";
      else {
        `result` = `a`+"";
        if(nimOnlyDigitsOrMinus(`result`)){
          `result` = `a`+".0";
        }
      }
    """.}

proc addFloat*(result: var string; x: float | float32) {.inline.} =
  ## Converts float to its string representation and appends it to `result`.
  runnableExamples:
    var
      s = "foo:"
      b = 45.67
    s.addFloat(45.67)
    assert s == "foo:45.67"
  template impl =
    when defined(nimLegacySprintf):
      addFloatSprintf(result, x)
    else:
      addFloatRoundtrip(result, x)
  when defined(js):
    when nimvm: impl()
    else:
      result.add nimFloatToString(x)
  else: impl()

when defined(nimPreviewSlimSystem):
  func `$`*(x: float | float32): string =
    ## Outplace version of `addFloat`.
    result = ""
    result.addFloat(x)
