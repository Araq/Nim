#
#
#            Nim's Runtime Library
#        (c) Copyright 2016 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Contains functionality shared between the `httpclient` and
## `asynchttpserver` modules.
##
## Unstable API.
import std/private/since
import std/[tables, strutils, parseutils]

type
  HttpHeaders* = ref object
    table*: TableRef[string, seq[string]]
    isTitleCase: bool

  HttpHeaderValues* = distinct seq[string]

  # The range starts at '0' so that we don't have to explicitly initialise
  # it. See: https://irclogs.nim-lang.org/19-09-2016.html#19:48:27 for context.
  HttpCode* = distinct range[0 .. 599]

  HttpVersion* = enum
    HttpVer11,
    HttpVer10

  HttpMethod* = enum         ## the requested HttpMethod
    HttpHead = "HEAD"        ## Asks for the response identical to the one that
                             ## would correspond to a GET request, but without
                             ## the response body.
    HttpGet = "GET"          ## Retrieves the specified resource.
    HttpPost = "POST"        ## Submits data to be processed to the identified
                             ## resource. The data is included in the body of
                             ## the request.
    HttpPut = "PUT"          ## Uploads a representation of the specified
                             ## resource.
    HttpDelete = "DELETE"    ## Deletes the specified resource.
    HttpTrace = "TRACE"      ## Echoes back the received request, so that a
                             ## client
                             ## can see what intermediate servers are adding or
                             ## changing in the request.
    HttpOptions = "OPTIONS"  ## Returns the HTTP methods that the server
                             ## supports for specified address.
    HttpConnect = "CONNECT"  ## Converts the request connection to a transparent
                             ## TCP/IP tunnel, usually used for proxies.
    HttpPatch = "PATCH"      ## Applies partial modifications to a resource.


const
  Http100* = HttpCode(100)
  Http101* = HttpCode(101)
  Http102* = HttpCode(102)  ## https://tools.ietf.org/html/rfc2518.html WebDAV
  Http103* = HttpCode(103)  ## https://tools.ietf.org/html/rfc8297.html Early hints
  Http200* = HttpCode(200)
  Http201* = HttpCode(201)
  Http202* = HttpCode(202)
  Http203* = HttpCode(203)
  Http204* = HttpCode(204)
  Http205* = HttpCode(205)
  Http206* = HttpCode(206)
  Http207* = HttpCode(207)  ## https://tools.ietf.org/html/rfc4918.html WebDAV
  Http208* = HttpCode(208)  ## https://tools.ietf.org/html/rfc5842.html WebDAV, Section 7.1
  Http226* = HttpCode(226)  ## https://tools.ietf.org/html/rfc3229.html Delta encoding, Section 10.4.1
  Http300* = HttpCode(300)
  Http301* = HttpCode(301)
  Http302* = HttpCode(302)
  Http303* = HttpCode(303)
  Http304* = HttpCode(304)
  Http305* = HttpCode(305)
  Http307* = HttpCode(307)
  Http308* = HttpCode(308)
  Http400* = HttpCode(400)
  Http401* = HttpCode(401)
  Http402* = HttpCode(402)  ## https://tools.ietf.org/html/rfc7231.html Payment required, Section 6.5.2
  Http403* = HttpCode(403)
  Http404* = HttpCode(404)
  Http405* = HttpCode(405)
  Http406* = HttpCode(406)
  Http407* = HttpCode(407)
  Http408* = HttpCode(408)
  Http409* = HttpCode(409)
  Http410* = HttpCode(410)
  Http411* = HttpCode(411)
  Http412* = HttpCode(412)
  Http413* = HttpCode(413)
  Http414* = HttpCode(414)
  Http415* = HttpCode(415)
  Http416* = HttpCode(416)
  Http417* = HttpCode(417)
  Http418* = HttpCode(418)
  Http421* = HttpCode(421)
  Http422* = HttpCode(422)
  Http423* = HttpCode(423)  ## https://tools.ietf.org/html/rfc4918.html WebDAV, Section 11.3
  Http424* = HttpCode(424)  ## https://tools.ietf.org/html/rfc4918.html WebDAV, Section 11.3
  Http425* = HttpCode(425)  ## https://tools.ietf.org/html/rfc8470.html Early data
  Http426* = HttpCode(426)
  Http428* = HttpCode(428)
  Http429* = HttpCode(429)
  Http431* = HttpCode(431)
  Http451* = HttpCode(451)
  Http500* = HttpCode(500)
  Http501* = HttpCode(501)
  Http502* = HttpCode(502)
  Http503* = HttpCode(503)
  Http504* = HttpCode(504)
  Http505* = HttpCode(505)
  Http506* = HttpCode(506)  ## https://tools.ietf.org/html/rfc2295.html Content negotiation, Section 8.1
  Http507* = HttpCode(507)  ## https://tools.ietf.org/html/rfc4918.html WebDAV, Section 11.5
  Http508* = HttpCode(508)  ## https://tools.ietf.org/html/rfc5842.html WebDAV, Section 7.2
  Http510* = HttpCode(510)  ## https://tools.ietf.org/html/rfc2774.html Extension framework, Section 7
  Http511* = HttpCode(511)  ## https://tools.ietf.org/html/rfc6585.html Additional status code, Section 6


const httpNewLine* = "\c\L"
const headerLimit* = 10_000

func toTitleCase(s: string): string =
  result = newString(len(s))
  var upper = true
  for i in 0..len(s) - 1:
    result[i] = if upper: toUpperAscii(s[i]) else: toLowerAscii(s[i])
    upper = s[i] == '-'

func toCaseInsensitive*(headers: HttpHeaders, s: string): string {.inline.} =
  ## For internal usage only. Do not use.
  return if headers.isTitleCase: toTitleCase(s) else: toLowerAscii(s)

func newHttpHeaders*(titleCase=false): HttpHeaders =
  ## Returns a new `HttpHeaders` object. if `titleCase` is set to true,
  ## headers are passed to the server in title case (e.g. "Content-Length")
  result = HttpHeaders(table: newTable[string, seq[string]](), isTitleCase: titleCase)

func newHttpHeaders*(keyValuePairs:
    openArray[tuple[key: string, val: string]], titleCase=false): HttpHeaders =
  ## Returns a new `HttpHeaders` object from an array. if `titleCase` is set to true,
  ## headers are passed to the server in title case (e.g. "Content-Length")
  result = HttpHeaders(table: newTable[string, seq[string]](), isTitleCase: titleCase)

  for pair in keyValuePairs:
    let key = result.toCaseInsensitive(pair.key)
    {.cast(noSideEffect).}:
      if key in result.table:
        result.table[key].add(pair.val)
      else:
        result.table[key] = @[pair.val]

func `$`*(headers: HttpHeaders): string {.inline.} =
  $headers.table

proc clear*(headers: HttpHeaders) {.inline.} =
  headers.table.clear()

func `[]`*(headers: HttpHeaders, key: string): HttpHeaderValues =
  ## Returns the values associated with the given `key`. If the returned
  ## values are passed to a procedure expecting a `string`, the first
  ## value is automatically picked. If there are
  ## no values associated with the key, an exception is raised.
  ##
  ## To access multiple values of a key, use the overloaded `[]` below or
  ## to get all of them access the `table` field directly.
  {.cast(noSideEffect).}:
    let tmp = headers.table[headers.toCaseInsensitive(key)]
    return HttpHeaderValues(tmp)

converter toString*(values: HttpHeaderValues): string =
  return seq[string](values)[0]

func `[]`*(headers: HttpHeaders, key: string, i: int): string =
  ## Returns the `i`'th value associated with the given key. If there are
  ## no values associated with the key or the `i`'th value doesn't exist,
  ## an exception is raised.
  {.cast(noSideEffect).}:
    return headers.table[headers.toCaseInsensitive(key)][i]

proc `[]=`*(headers: HttpHeaders, key, value: string) =
  ## Sets the header entries associated with `key` to the specified value.
  ## Replaces any existing values.
  headers.table[headers.toCaseInsensitive(key)] = @[value]

proc `[]=`*(headers: HttpHeaders, key: string, value: seq[string]) =
  ## Sets the header entries associated with `key` to the specified list of
  ## values. Replaces any existing values. If `value` is empty,
  ## deletes the header entries associated with `key`.
  if value.len > 0:
    headers.table[headers.toCaseInsensitive(key)] = value
  else:
    headers.table.del(headers.toCaseInsensitive(key))

proc add*(headers: HttpHeaders, key, value: string) =
  ## Adds the specified value to the specified key. Appends to any existing
  ## values associated with the key.
  if not headers.table.hasKey(headers.toCaseInsensitive(key)):
    headers.table[headers.toCaseInsensitive(key)] = @[value]
  else:
    headers.table[headers.toCaseInsensitive(key)].add(value)

proc del*(headers: HttpHeaders, key: string) =
  ## Deletes the header entries associated with `key`
  headers.table.del(headers.toCaseInsensitive(key))

iterator pairs*(headers: HttpHeaders): tuple[key, value: string] =
  ## Yields each key, value pair.
  for k, v in headers.table:
    for value in v:
      yield (k, value)

func contains*(values: HttpHeaderValues, value: string): bool =
  ## Determines if `value` is one of the values inside `values`. Comparison
  ## is performed without case sensitivity.
  result = false
  for val in seq[string](values):
    if val.toLowerAscii == value.toLowerAscii: return true

func hasKey*(headers: HttpHeaders, key: string): bool =
  return headers.table.hasKey(headers.toCaseInsensitive(key))

func getOrDefault*(headers: HttpHeaders, key: string,
    default = @[""].HttpHeaderValues): HttpHeaderValues =
  ## Returns the values associated with the given `key`. If there are no
  ## values associated with the key, then `default` is returned.
  if headers.hasKey(key):
    return headers[key]
  else:
    return default

func len*(headers: HttpHeaders): int {.inline.} = headers.table.len

func parseList(line: string, list: var seq[string], start: int): int =
  result = 0
  var i = 0
  var current = ""
  while start+i < line.len and line[start + i] notin {'\c', '\l'}:
    i += line.skipWhitespace(start + i)
    i += line.parseUntil(current, {'\c', '\l', ','}, start + i)
    list.add(move current)  # implicit current.setLen(0)
    if start+i < line.len and line[start + i] == ',':
      i.inc # Skip ,

func parseHeader*(line: string): tuple[key: string, value: seq[string]] =
  ## Parses a single raw header HTTP line into key value pairs.
  ##
  ## Used by `asynchttpserver` and `httpclient` internally and should not
  ## be used by you.
  result = ("", @[])
  var i = 0
  i = line.parseUntil(result.key, ':')
  inc(i) # skip :
  if i < len(line):
    if cmpIgnoreCase(result.key, "cookie") == 0:
      i += line.skipWhitespace(i)
      result.value.add line.substr(i)
    else:
      i += parseList(line, result.value, i)
  elif result.key.len > 0:
    result.value = @[""]
  else:
    result.value = @[]

func `==`*(protocol: tuple[orig: string, major, minor: int],
           ver: HttpVersion): bool =
  let major =
    case ver
    of HttpVer11, HttpVer10: 1
  let minor =
    case ver
    of HttpVer11: 1
    of HttpVer10: 0
  result = protocol.major == major and protocol.minor == minor

func contains*(methods: set[HttpMethod], x: string): bool =
  return parseEnum[HttpMethod](x) in methods

func `$`*(code: HttpCode): string =
  ## Converts the specified `HttpCode` into a HTTP status.
  runnableExamples:
    doAssert($Http404 == "404 Not Found")
  case code.int
  of 100: "100 Continue"
  of 101: "101 Switching Protocols"
  of 102: "102 Processing"
  of 103: "103 Early Hints"
  of 200: "200 OK"
  of 201: "201 Created"
  of 202: "202 Accepted"
  of 203: "203 Non-Authoritative Information"
  of 204: "204 No Content"
  of 205: "205 Reset Content"
  of 206: "206 Partial Content"
  of 207: "207 Multi-Status"
  of 208: "208 Already Reported"
  of 226: "226 IM Used"
  of 300: "300 Multiple Choices"
  of 301: "301 Moved Permanently"
  of 302: "302 Found"
  of 303: "303 See Other"
  of 304: "304 Not Modified"
  of 305: "305 Use Proxy"
  of 307: "307 Temporary Redirect"
  of 308: "308 Permanent Redirect"
  of 400: "400 Bad Request"
  of 401: "401 Unauthorized"
  of 402: "402 Payment Required"
  of 403: "403 Forbidden"
  of 404: "404 Not Found"
  of 405: "405 Method Not Allowed"
  of 406: "406 Not Acceptable"
  of 407: "407 Proxy Authentication Required"
  of 408: "408 Request Timeout"
  of 409: "409 Conflict"
  of 410: "410 Gone"
  of 411: "411 Length Required"
  of 412: "412 Precondition Failed"
  of 413: "413 Request Entity Too Large"
  of 414: "414 Request-URI Too Long"
  of 415: "415 Unsupported Media Type"
  of 416: "416 Requested Range Not Satisfiable"
  of 417: "417 Expectation Failed"
  of 418: "418 I'm a teapot"
  of 421: "421 Misdirected Request"
  of 422: "422 Unprocessable Entity"
  of 423: "423 Locked"
  of 424: "424 Failed Dependency"
  of 425: "425 Too Early"
  of 426: "426 Upgrade Required"
  of 428: "428 Precondition Required"
  of 429: "429 Too Many Requests"
  of 431: "431 Request Header Fields Too Large"
  of 451: "451 Unavailable For Legal Reasons"
  of 500: "500 Internal Server Error"
  of 501: "501 Not Implemented"
  of 502: "502 Bad Gateway"
  of 503: "503 Service Unavailable"
  of 504: "504 Gateway Timeout"
  of 505: "505 HTTP Version Not Supported"
  of 506: "506 Variant Also Negotiates"
  of 507: "507 Insufficient Storage"
  of 508: "508 Loop Detected"
  of 510: "510 Not Extended"
  of 511: "511 Network Authentication Required"
  else: $(int(code))

func `==`*(a, b: HttpCode): bool {.borrow.}

func is1xx*(code: HttpCode): bool {.inline, since: (1, 5).} =
  ## Determines whether `code` is a 1xx HTTP status code.
  runnableExamples:
    doAssert is1xx(HttpCode(103))

  code.int in 100 .. 199

func is2xx*(code: HttpCode): bool {.inline.} =
  ## Determines whether `code` is a 2xx HTTP status code.
  code.int in 200 .. 299

func is3xx*(code: HttpCode): bool {.inline.} =
  ## Determines whether `code` is a 3xx HTTP status code.
  code.int in 300 .. 399

func is4xx*(code: HttpCode): bool {.inline.} =
  ## Determines whether `code` is a 4xx HTTP status code.
  code.int in 400 .. 499

func is5xx*(code: HttpCode): bool {.inline.} =
  ## Determines whether `code` is a 5xx HTTP status code.
  code.int in 500 .. 599
