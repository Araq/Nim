func toLowerAscii*(c: char): char {.inline.} =
  if c in {'A'..'Z'}:
    result = chr(ord(c) + (ord('a') - ord('A')))
  else:
    result = c

template firstCharCaseSensitiveImpl[T: string | cstring](a, b: T, aLen, bLen: int) =
  if aLen == 0 or bLen == 0:
    return aLen - bLen
  if a[0] != b[0]: return ord(a[0]) - ord(b[0])

template cmpIgnoreStyleImpl*[T: string | cstring](a, b: T,
            firstCharCaseSensitive: static bool = false) =
  let aLen = a.len
  let bLen = b.len
  var i = 0
  var j = 0
  when firstCharCaseSensitive:
    firstCharCaseSensitiveImpl(a, b, aLen, bLen)
    inc i
    inc j
  while true:
    while i < aLen and a[i] == '_': inc i
    while j < bLen and b[j] == '_': inc j
    let aa = if i < aLen: toLowerAscii(a[i]) else: '\0'
    let bb = if j < bLen: toLowerAscii(b[j]) else: '\0'
    result = ord(aa) - ord(bb)
    if result != 0: return result
    # the characters are identical:
    if i >= aLen:
      # both cursors at the end:
      if j >= bLen: return 0
      # not yet at the end of 'b':
      return -1
    elif j >= bLen:
      return 1
    inc i
    inc j

template cmpIgnoreCaseImpl*[T: string | cstring](a, b: T,
        firstCharCaseSensitive: static bool = false) =
  let aLen = a.len
  let bLen = b.len
  var i = 0
  when firstCharCaseSensitive:
    firstCharCaseSensitiveImpl(a, b, aLen, bLen)
    inc i
  var m = min(aLen, bLen)
  while i < m:
    result = ord(toLowerAscii(a[i])) - ord(toLowerAscii(b[i]))
    if result != 0: return
    inc i
  result = aLen - bLen

template startsWithImpl*[T: string | cstring](s, prefix: T) =
  let prefixLen = prefix.len
  let sLen = s.len
  var i = 0
  while true:
    if i >= prefixLen: return true
    if i >= sLen or s[i] != prefix[i]: return false
    inc(i)

template endsWithImpl*[T: string | cstring](s, suffix: T) =
  let suffixLen = suffix.len
  let sLen = s.len
  var i = 0
  var j = sLen - suffixLen
  while i+j >= 0 and i+j < sLen:
    if s[i+j] != suffix[i]: return false
    inc(i)
  if i >= suffixLen: return true


func cmpNimIdentifier*[T: string | cstring](a, b: T): int =
  cmpIgnoreStyleImpl(a, b, true)

from system/ansi_c import c_memchr, c_strstr

func find*(s: cstring, sub: char, start: Natural = 0, last = 0): int =
  ## Searches for `sub` in `s` inside the range `start..last` (both ends included).
  ## If `last` is unspecified, it defaults to `s.high` (the last element).
  ##
  ## Searching is case-sensitive. If `sub` is not in `s`, -1 is returned.
  ## Otherwise the index returned is relative to `s[0]`, not `start`.
  ## Use `s[start..last].rfind` for a `start`-origin index.
  let last = if last == 0: s.high else: last
  let L = last-start+1
  if L > 0:
    let found = c_memchr(s[start].unsafeAddr, cint(sub), cast[csize_t](L))
    if not found.isNil:
      return cast[int](found) -% cast[int](s)
  return -1

func find*(s, sub: cstring, start: Natural = 0, last = 0): int =
  ## Searches for `sub` in `s` inside the range `start..last` (both ends included).
  ## If `last` is unspecified, it defaults to `s.high` (the last element).
  ##
  ## Searching is case-sensitive. If `sub` is not in `s`, -1 is returned.
  ## Otherwise the index returned is relative to `s[0]`, not `start`.
  ## Use `s[start..last].find` for a `start`-origin index.
  if sub.len > s.len - start: return -1
  if sub.len == 1: return find(s, sub[0], start, last)
  if last == 0 and s.len > start:
    let found = c_strstr(cast[cstring](s[start].unsafeAddr), sub)
    if not found.isNil:
      result = cast[int](found) -% cast[int](s)
    else:
      result = -1
  else:
    result = 0
