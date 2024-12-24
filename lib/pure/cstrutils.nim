#
#
#            Nim's Runtime Library
#        (c) Copyright 2017 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module supports helper routines for working with `cstring`
## without having to convert `cstring` to `string`, in order to
## save allocations.
##
## See also
## ========
## * `strutils module <strutils.html>`_ for working with `string`

include system/inclrtl
import std/private/strimpl


when defined(js):
  func jsStartsWith(s, prefix: cstring): bool {.importjs: "#.startsWith(#)".}
  func jsEndsWith(s, suffix: cstring): bool {.importjs: "#.endsWith(#)".}


func startsWith*(s, prefix: cstring): bool {.rtl, extern: "csuStartsWith".} =
  ## Returns true if `s` starts with `prefix`.
  ##
  ## The JS backend uses the native `String.prototype.startsWith` function.
  runnableExamples:
    assert startsWith(cstring"Hello, Nimion", cstring"Hello")
    assert not startsWith(cstring"Hello, Nimion", cstring"Nimion")
    assert startsWith(cstring"Hello", cstring"")

  when nimvm:
    result = false
    startsWithImpl(s, prefix)
  else:
    when defined(js):
      result = jsStartsWith(s, prefix)
    else:
      result = false
      var i = 0
      while true:
        if prefix[i] == '\0': return true
        if s[i] != prefix[i]: return false
        inc(i)

func endsWith*(s, suffix: cstring): bool {.rtl, extern: "csuEndsWith".} =
  ## Returns true if `s` ends with `suffix`.
  ##
  ## The JS backend uses the native `String.prototype.endsWith` function.
  runnableExamples:
    assert endsWith(cstring"Hello, Nimion", cstring"Nimion")
    assert not endsWith(cstring"Hello, Nimion", cstring"Hello")
    assert endsWith(cstring"Hello", cstring"")

  when nimvm:
    result = false
    endsWithImpl(s, suffix)
  else:
    when defined(js):
      result = jsEndsWith(s, suffix)
    else:
      result = false
      let slen = s.len
      var i = 0
      var j = slen - len(suffix)
      while i + j <% slen:
        if s[i + j] != suffix[i]: return false
        inc(i)
      if suffix[i] == '\0': return true

func cmpIgnoreStyle*(a, b: cstring): int {.rtl, extern: "csuCmpIgnoreStyle".} =
  ## Semantically the same as `cmp(normalize($a), normalize($b))`. It
  ## is just optimized to not allocate temporary strings. This should
  ## NOT be used to compare Nim identifier names, use `macros.eqIdent`
  ## for that. Returns:
  ## * 0 if `a == b`
  ## * < 0 if `a < b`
  ## * \> 0 if `a > b`
  runnableExamples:
    assert cmpIgnoreStyle(cstring"hello", cstring"H_e_L_Lo") == 0

  when nimvm:
    cmpIgnoreStyleImpl(a, b)
  else:
    when defined(js):
      cmpIgnoreStyleImpl(a, b)
    else:
      var i = 0
      var j = 0
      while true:
        while a[i] == '_': inc(i)
        while b[j] == '_': inc(j) # BUGFIX: typo
        var aa = toLowerAscii(a[i])
        var bb = toLowerAscii(b[j])
        result = ord(aa) - ord(bb)
        if result != 0 or aa == '\0': break
        inc(i)
        inc(j)

func cmpIgnoreCase*(a, b: cstring): int {.rtl, extern: "csuCmpIgnoreCase".} =
  ## Compares two strings in a case insensitive manner. Returns:
  ## * 0 if `a == b`
  ## * < 0 if `a < b`
  ## * \> 0 if `a > b`
  runnableExamples:
    assert cmpIgnoreCase(cstring"hello", cstring"HeLLo") == 0
    assert cmpIgnoreCase(cstring"echo", cstring"hello") < 0
    assert cmpIgnoreCase(cstring"yellow", cstring"hello") > 0

  when nimvm:
    cmpIgnoreCaseImpl(a, b)
  else:
    when defined(js):
      cmpIgnoreCaseImpl(a, b)
    else:
      var i = 0
      while true:
        var aa = toLowerAscii(a[i])
        var bb = toLowerAscii(b[i])
        result = ord(aa) - ord(bb)
        if result != 0 or aa == '\0': break
        inc(i)
