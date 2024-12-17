#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements URI parsing as specified by RFC 3986.
##
## A Uniform Resource Identifier (URI) provides a simple and extensible
## means for identifying a resource. A URI can be further classified
## as a locator, a name, or both. The term "Uniform Resource Locator"
## (URL) refers to the subset of URIs.
##
## .. warning:: URI parsers in this module do not perform security validation.
##
## # Basic usage


## ## Combine URIs
runnableExamples:
  let host = parseUri("https://nim-lang.org")
  assert $host == "https://nim-lang.org"
  assert $(host / "/blog.html") == "https://nim-lang.org/blog.html"
  assert $(host / "blog2.html") == "https://nim-lang.org/blog2.html"

## ## Access URI item
runnableExamples:
  let res = parseUri("sftp://127.0.0.1:4343")
  assert isAbsolute(res)
  assert res.port == "4343"

## ## Data URI Base64
runnableExamples:
  assert getDataUri("Hello World", "text/plain") == "data:text/plain;charset=utf-8;base64,SGVsbG8gV29ybGQ="
  assert getDataUri("Nim", "text/plain") == "data:text/plain;charset=utf-8;base64,Tmlt"


import std/[strutils, parseutils, base64]
import std/private/[since, decode_helpers]

when defined(nimPreviewSlimSystem):
  import std/assertions


type
  Url* = distinct string

  Uri* = object
    scheme*, username*, password*: string
    hostname*, port*, path*, query*, anchor*: string
    opaque*: bool
    isIpv6*: bool

  UriParseError* = object of ValueError


proc uriParseError*(msg: string) {.noreturn.} =
  ## Raises a `UriParseError` exception with message `msg`.
  raise newException(UriParseError, msg)

func encodeUrl*(s: string, usePlus = true): string =
  ## Encodes a URL according to RFC3986.
  ##
  ## This means that characters in the set
  ## `{'a'..'z', 'A'..'Z', '0'..'9', '-', '.', '_', '~'}` are
  ## carried over to the result.
  ## All other characters are encoded as `%xx` where `xx`
  ## denotes its hexadecimal value.
  ##
  ## As a special rule, when the value of `usePlus` is true,
  ## spaces are encoded as `+` instead of `%20`.
  ##
  ## **See also:**
  ## * `decodeUrl func<#decodeUrl,string>`_
  runnableExamples:
    assert encodeUrl("https://nim-lang.org") == "https%3A%2F%2Fnim-lang.org"
    assert encodeUrl("https://nim-lang.org/this is a test") == "https%3A%2F%2Fnim-lang.org%2Fthis+is+a+test"
    assert encodeUrl("https://nim-lang.org/this is a test", false) == "https%3A%2F%2Fnim-lang.org%2Fthis%20is%20a%20test"
  result = newStringOfCap(s.len + s.len shr 2) # assume 12% non-alnum-chars
  let fromSpace = if usePlus: "+" else: "%20"
  for c in s:
    case c
    # https://tools.ietf.org/html/rfc3986#section-2.3
    of 'a'..'z', 'A'..'Z', '0'..'9', '-', '.', '_', '~': add(result, c)
    of ' ': add(result, fromSpace)
    else:
      add(result, '%')
      add(result, toHex(ord(c), 2))

func decodeUrl*(s: string, decodePlus = true): string =
  ## Decodes a URL according to RFC3986.
  ##
  ## This means that any `%xx` (where `xx` denotes a hexadecimal
  ## value) are converted to the character with ordinal number `xx`,
  ## and every other character is carried over.
  ## If `xx` is not a valid hexadecimal value, it is left intact.
  ##
  ## As a special rule, when the value of `decodePlus` is true, `+`
  ## characters are converted to a space.
  ##
  ## **See also:**
  ## * `encodeUrl func<#encodeUrl,string>`_
  runnableExamples:
    assert decodeUrl("https%3A%2F%2Fnim-lang.org") == "https://nim-lang.org"
    assert decodeUrl("https%3A%2F%2Fnim-lang.org%2Fthis+is+a+test") == "https://nim-lang.org/this is a test"
    assert decodeUrl("https%3A%2F%2Fnim-lang.org%2Fthis%20is%20a%20test",
        false) == "https://nim-lang.org/this is a test"
    assert decodeUrl("abc%xyz") == "abc%xyz"

  result = newString(s.len)
  var i = 0
  var j = 0
  while i < s.len:
    case s[i]
    of '%':
      result[j] = decodePercent(s, i)
    of '+':
      if decodePlus:
        result[j] = ' '
      else:
        result[j] = s[i]
    else: result[j] = s[i]
    inc(i)
    inc(j)
  setLen(result, j)

func encodeQuery*(query: openArray[(string, string)], usePlus = true,
    omitEq = true, sep = '&'): string =
  ## Encodes a set of (key, value) parameters into a URL query string.
  ##
  ## Every (key, value) pair is URL-encoded and written as `key=value`. If the
  ## value is an empty string then the `=` is omitted, unless `omitEq` is
  ## false.
  ## The pairs are joined together by the `sep` character.
  ##
  ## The `usePlus` parameter is passed down to the `encodeUrl` function that
  ## is used for the URL encoding of the string values.
  ##
  ## **See also:**
  ## * `encodeUrl func<#encodeUrl,string>`_
  runnableExamples:
    assert encodeQuery({: }) == ""
    assert encodeQuery({"a": "1", "b": "2"}) == "a=1&b=2"
    assert encodeQuery({"a": "1", "b": ""}) == "a=1&b"
    assert encodeQuery({"a": "1", "b": ""}, omitEq = false, sep = ';') == "a=1;b="
  result = ""
  for elem in query:
    # Encode the `key = value` pairs and separate them with 'sep'
    if result.len > 0: result.add(sep)
    let (key, val) = elem
    result.add(encodeUrl(key, usePlus))
    # Omit the '=' if the value string is empty
    if not omitEq or val.len > 0:
      result.add('=')
      result.add(encodeUrl(val, usePlus))

iterator decodeQuery*(data: string, sep = '&'): tuple[key, value: string] =
  ## Reads and decodes the query string `data` and yields the `(key, value)` pairs
  ## the data consists of. If compiled with `-d:nimLegacyParseQueryStrict`,
  ## a `UriParseError` is raised when there is an unencoded `=` character in a decoded
  ## value, which was the behavior in Nim < 1.5.1.
  runnableExamples:
    import std/sequtils
    assert toSeq(decodeQuery("foo=1&bar=2=3")) == @[("foo", "1"), ("bar", "2=3")]
    assert toSeq(decodeQuery("foo=1;bar=2=3", ';')) == @[("foo", "1"), ("bar", "2=3")]
    assert toSeq(decodeQuery("&a&=b&=&&")) == @[("", ""), ("a", ""), ("", "b"), ("", ""), ("", "")]

  proc parseData(data: string, i: int, field: var string, sep: char): int =
    result = i
    while result < data.len:
      let c = data[result]
      case c
      of '%': add(field, decodePercent(data, result))
      of '+': add(field, ' ')
      of '&': break
      else:
        if c == sep: break
        else: add(field, data[result])
      inc(result)

  var i = 0
  var name = ""
  var value = ""
  # decode everything in one pass:
  while i < data.len:
    setLen(name, 0) # reuse memory
    i = parseData(data, i, name, '=')
    setLen(value, 0) # reuse memory
    if i < data.len and data[i] == '=':
      inc(i) # skip '='
      when defined(nimLegacyParseQueryStrict):
        i = parseData(data, i, value, '=')
      else:
        i = parseData(data, i, value, sep)
    yield (name, value)
    if i < data.len:
      when defined(nimLegacyParseQueryStrict):
        if data[i] != '&':
          uriParseError("'&' expected at index '$#' for '$#'" % [$i, data])
      inc(i)

func parseAuthority(authority: string, result: var Uri) =
  var i = 0
  var inPort = false
  var inIPv6 = false
  while i < authority.len:
    case authority[i]
    of '@':
      swap result.password, result.port
      result.port.setLen(0)
      swap result.username, result.hostname
      result.hostname.setLen(0)
      inPort = false
    of ':':
      if inIPv6:
        result.hostname.add(authority[i])
      else:
        inPort = true
    of '[':
      inIPv6 = true
      result.isIpv6 = true
    of ']':
      inIPv6 = false
    else:
      if inPort:
        result.port.add(authority[i])
      else:
        result.hostname.add(authority[i])
    i.inc

func parsePath(uri: string, i: var int, result: var Uri) =
  i.inc parseUntil(uri, result.path, {'?', '#'}, i)

  # The 'mailto' scheme's PATH actually contains the hostname/username
  if cmpIgnoreCase(result.scheme, "mailto") == 0:
    parseAuthority(result.path, result)
    result.path.setLen(0)

  if i < uri.len and uri[i] == '?':
    i.inc # Skip '?'
    i.inc parseUntil(uri, result.query, {'#'}, i)

  if i < uri.len and uri[i] == '#':
    i.inc # Skip '#'
    i.inc parseUntil(uri, result.anchor, {}, i)

func initUri*(isIpv6 = false): Uri =
  ## Initializes a URI with `scheme`, `username`, `password`,
  ## `hostname`, `port`, `path`, `query`, `anchor` and `isIpv6`.
  ##
  ## **See also:**
  ## * `Uri type <#Uri>`_ for available fields in the URI type
  runnableExamples:
    var uri2 = initUri(isIpv6 = true)
    uri2.scheme = "tcp"
    uri2.hostname = "2001:0db8:85a3:0000:0000:8a2e:0370:7334"
    uri2.port = "8080"
    assert $uri2 == "tcp://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]:8080"
  result = Uri(scheme: "", username: "", password: "", hostname: "", port: "",
                path: "", query: "", anchor: "", isIpv6: isIpv6)

func resetUri(uri: var Uri) =
  for f in uri.fields:
    when f is string:
      f.setLen(0)
    else:
      f = false

func parseUri*(uri: string, result: var Uri) =
  ## Parses a URI. The `result` variable will be cleared before.
  ##
  ## **See also:**
  ## * `Uri type <#Uri>`_ for available fields in the URI type
  ## * `initUri func <#initUri>`_ for initializing a URI
  runnableExamples:
    var res = initUri()
    parseUri("https://nim-lang.org/docs/manual.html", res)
    assert res.scheme == "https"
    assert res.hostname == "nim-lang.org"
    assert res.path == "/docs/manual.html"
  resetUri(result)

  var i = 0

  # Check if this is a reference URI (relative URI)
  let doubleSlash = uri.len > 1 and uri[0] == '/' and uri[1] == '/'
  if i < uri.len and uri[i] == '/':
    # Make sure `uri` doesn't begin with '//'.
    if not doubleSlash:
      parsePath(uri, i, result)
      return

  # Scheme
  i.inc parseWhile(uri, result.scheme, Letters + Digits + {'+', '-', '.'}, i)
  if (i >= uri.len or uri[i] != ':') and not doubleSlash:
    # Assume this is a reference URI (relative URI)
    i = 0
    result.scheme.setLen(0)
    parsePath(uri, i, result)
    return
  if not doubleSlash:
    i.inc # Skip ':'

  # Authority
  if i+1 < uri.len and uri[i] == '/' and uri[i+1] == '/':
    i.inc(2) # Skip //
    var authority = ""
    i.inc parseUntil(uri, authority, {'/', '?', '#'}, i)
    if authority.len > 0:
      parseAuthority(authority, result)
  else:
    result.opaque = true

  # Path
  parsePath(uri, i, result)

func parseUri*(uri: string): Uri =
  ## Parses a URI and returns it.
  ##
  ## **See also:**
  ## * `Uri type <#Uri>`_ for available fields in the URI type
  runnableExamples:
    let res = parseUri("ftp://Username:Password@Hostname")
    assert res.username == "Username"
    assert res.password == "Password"
    assert res.scheme == "ftp"
  result = initUri()
  parseUri(uri, result)

func removeDotSegments(path: string): string =
  ## Collapses `..` and `.` in `path` in a similar way as done in `os.normalizedPath`
  ## Caution: this is buggy.
  runnableExamples:
    assert removeDotSegments("a1/a2/../a3/a4/a5/./a6/a7/.//./") == "a1/a3/a4/a5/a6/a7/"
    assert removeDotSegments("http://www.ai.") == "http://www.ai."
  # xxx adapt or reuse `pathnorm.normalizePath(path, '/')` to make this more reliable, but
  # taking into account url specificities such as not collapsing leading `//` in scheme
  # `https://`. see `turi` for failing tests.
  if path.len == 0: return ""
  var collection: seq[string] = @[]
  let endsWithSlash = path.endsWith '/'
  var i = 0
  var currentSegment = ""
  while i < path.len:
    case path[i]
    of '/':
      collection.add(currentSegment)
      currentSegment = ""
    of '.':
      if i+2 < path.len and path[i+1] == '.' and path[i+2] == '/':
        if collection.len > 0:
          discard collection.pop()
          i.inc 3
          continue
      elif i + 1 < path.len and path[i+1] == '/':
        i.inc 2
        continue
      currentSegment.add path[i]
    else:
      currentSegment.add path[i]
    i.inc
  if currentSegment != "":
    collection.add currentSegment

  result = collection.join("/")
  if endsWithSlash: result.add '/'

func merge(base, reference: Uri): string =
  # http://tools.ietf.org/html/rfc3986#section-5.2.3
  if base.hostname != "" and base.path == "":
    '/' & reference.path
  else:
    let lastSegment = rfind(base.path, "/")
    if lastSegment == -1:
      reference.path
    else:
      base.path[0 .. lastSegment] & reference.path

func combine*(base: Uri, reference: Uri): Uri =
  ## Combines a base URI with a reference URI.
  ##
  ## This uses the algorithm specified in
  ## `section 5.2.2 of RFC 3986 <https://tools.ietf.org/html/rfc3986#section-5.2.2>`_.
  ##
  ## This means that the slashes inside the base URIs path as well as reference
  ## URIs path affect the resulting URI.
  ##
  ## **See also:**
  ## * `/ func <#/,Uri,string>`_ for building URIs
  runnableExamples:
    let foo = combine(parseUri("https://nim-lang.org/foo/bar"), parseUri("/baz"))
    assert foo.path == "/baz"
    let bar = combine(parseUri("https://nim-lang.org/foo/bar"), parseUri("baz"))
    assert bar.path == "/foo/baz"
    let qux = combine(parseUri("https://nim-lang.org/foo/bar/"), parseUri("baz"))
    assert qux.path == "/foo/bar/baz"

  template setAuthority(dest, src): untyped =
    dest.hostname = src.hostname
    dest.username = src.username
    dest.port = src.port
    dest.password = src.password

  result = initUri()
  if reference.scheme != base.scheme and reference.scheme != "":
    result = reference
    result.path = removeDotSegments(result.path)
  else:
    if reference.hostname != "":
      setAuthority(result, reference)
      result.path = removeDotSegments(reference.path)
      result.query = reference.query
    else:
      if reference.path == "":
        result.path = base.path
        if reference.query != "":
          result.query = reference.query
        else:
          result.query = base.query
      else:
        if reference.path.startsWith("/"):
          result.path = removeDotSegments(reference.path)
        else:
          result.path = removeDotSegments(merge(base, reference))
        result.query = reference.query
      setAuthority(result, base)
    result.scheme = base.scheme
  result.anchor = reference.anchor

func combine*(uris: varargs[Uri]): Uri =
  ## Combines multiple URIs together.
  ##
  ## **See also:**
  ## * `/ func <#/,Uri,string>`_ for building URIs
  runnableExamples:
    let foo = combine(parseUri("https://nim-lang.org/"), parseUri("docs/"),
        parseUri("manual.html"))
    assert foo.hostname == "nim-lang.org"
    assert foo.path == "/docs/manual.html"
  result = uris[0]
  for i in 1 ..< uris.len:
    result = combine(result, uris[i])

func isAbsolute*(uri: Uri): bool =
  ## Returns true if URI is absolute, false otherwise.
  runnableExamples:
    assert parseUri("https://nim-lang.org").isAbsolute
    assert not parseUri("nim-lang").isAbsolute
  return uri.scheme != "" and (uri.hostname != "" or uri.path != "")

func `/`*(x: Uri, path: string): Uri =
  ## Concatenates the path specified to the specified URIs path.
  ##
  ## Contrary to the `combine func <#combine,Uri,Uri>`_ you do not have to worry about
  ## the slashes at the beginning and end of the path and URIs path
  ## respectively.
  ##
  ## **See also:**
  ## * `combine func <#combine,Uri,Uri>`_
  runnableExamples:
    let foo = parseUri("https://nim-lang.org/foo/bar") / "/baz"
    assert foo.path == "/foo/bar/baz"
    let bar = parseUri("https://nim-lang.org/foo/bar") / "baz"
    assert bar.path == "/foo/bar/baz"
    let qux = parseUri("https://nim-lang.org/foo/bar/") / "baz"
    assert qux.path == "/foo/bar/baz"
  result = x

  if result.path.len == 0:
    if path.len == 0 or path[0] != '/':
      result.path = "/"
    result.path.add(path)
    return

  if result.path.len > 0 and result.path[result.path.len-1] == '/':
    if path.len > 0 and path[0] == '/':
      result.path.add(path[1 .. path.len-1])
    else:
      result.path.add(path)
  else:
    if path.len == 0 or path[0] != '/':
      result.path.add '/'
    result.path.add(path)

func `?`*(u: Uri, query: openArray[(string, string)]): Uri =
  ## Concatenates the query parameters to the specified URI object.
  runnableExamples:
    let foo = parseUri("https://example.com") / "foo" ? {"bar": "qux"}
    assert $foo == "https://example.com/foo?bar=qux"
  result = u
  result.query = encodeQuery(query)

func `$`*(u: Uri): string =
  ## Returns the string representation of the specified URI object.
  runnableExamples:
    assert $parseUri("https://nim-lang.org") == "https://nim-lang.org"
  # Get the len of all the parts.
  let schemeLen = u.scheme.len
  let usernameLen = u.username.len
  let passwordLen = u.password.len
  let hostnameLen = u.hostname.len
  let portLen = u.port.len
  let pathLen = u.path.len
  let queryLen = u.query.len
  let anchorLen = u.anchor.len
  # Prepare a string that fits all the parts and all punctuation chars.
  # 12 is the max len required by all possible punctuation chars.
  result = newStringOfCap(
    schemeLen + usernameLen + passwordLen + hostnameLen + portLen + pathLen + queryLen + anchorLen + 12
  )
  # Insert to result.
  if schemeLen > 0:
    result.add u.scheme
    result.add ':'
    if not u.opaque:
      result.add '/'
      result.add '/'
  if usernameLen > 0:
    result.add u.username
    if passwordLen > 0:
      result.add ':'
      result.add u.password
    result.add '@'
  if u.hostname.endsWith('/'):
    if u.isIpv6:
      result.add '['
      result.add u.hostname[0 .. ^2]
      result.add ']'
    else:
      result.add u.hostname[0 .. ^2]
  else:
    if u.isIpv6:
      result.add '['
      result.add u.hostname
      result.add ']'
    else:
      result.add u.hostname
  if portLen > 0:
    result.add ':'
    result.add u.port
  if pathLen > 0:
    if hostnameLen > 0 and u.path[0] != '/':
      result.add '/'
    result.add u.path
  if queryLen > 0:
    result.add '?'
    result.add u.query
  if anchorLen > 0:
    result.add '#'
    result.add u.anchor


proc getDataUri*(data, mime: string, encoding = "utf-8"): string {.since: (1, 3).} =
  ## Convenience proc for `base64.encode` returns a standard Base64 Data URI (RFC-2397)
  ##
  ## **See also:**
  ## * `mimetypes <mimetypes.html>`_ for `mime` argument
  ## * https://tools.ietf.org/html/rfc2397
  ## * https://en.wikipedia.org/wiki/Data_URI_scheme
  runnableExamples: static: assert getDataUri("Nim", "text/plain") == "data:text/plain;charset=utf-8;base64,Tmlt"
  assert encoding.len > 0 and mime.len > 0 # Must *not* be URL-Safe, see RFC-2397
  let base64encoded: string = base64.encode(data)
  # ("data:".len + ";charset=".len + ";base64,".len) == 22
  result = newStringOfCap(22 + mime.len + encoding.len + base64encoded.len)
  result.add "data:"
  result.add mime
  result.add ";charset="
  result.add encoding
  result.add ";base64,"
  result.add base64encoded
