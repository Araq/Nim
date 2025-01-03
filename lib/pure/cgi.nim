#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements helper procs for CGI applications. Example:
##
##   ```Nim
##   import std/[strtabs, cgi]
##
##   # Fill the values when debugging:
##   when debug:
##     setTestData("name", "Klaus", "password", "123456")
##   # read the data into `myData`
##   var myData = readData()
##   # check that the data's variable names are "name" or "password"
##   validateData(myData, "name", "password")
##   # start generating content:
##   writeContentType()
##   # generate content:
##   write(stdout, "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\">\n")
##   write(stdout, "<html><head><title>Test</title></head><body>\n")
##   writeLine(stdout, "your name: " & myData["name"])
##   writeLine(stdout, "your password: " & myData["password"])
##   writeLine(stdout, "</body></html>")
##   ```

import std/[strutils, os, strtabs, cookies, uri]
export uri.encodeUrl, uri.decodeUrl

when defined(nimPreviewSlimSystem):
  import std/syncio


proc addXmlChar(dest: var string, c: char) {.inline.} =
  case c
  of '&': add(dest, "&amp;")
  of '<': add(dest, "&lt;")
  of '>': add(dest, "&gt;")
  of '\"': add(dest, "&quot;")
  else: add(dest, c)

proc xmlEncode*(s: string): string =
  ## Encodes a value to be XML safe:
  ## * `"` is replaced by `&quot;`
  ## * `<` is replaced by `&lt;`
  ## * `>` is replaced by `&gt;`
  ## * `&` is replaced by `&amp;`
  ## * every other character is carried over.
  result = newStringOfCap(s.len + s.len shr 2)
  for i in 0..len(s)-1: addXmlChar(result, s[i])

type
  CgiError* = object of IOError ## Exception that is raised if a CGI error occurs.
  RequestMethod* = enum ## The used request method.
    methodNone,         ## no REQUEST_METHOD environment variable
    methodPost,         ## query uses the POST method
    methodGet           ## query uses the GET method

proc cgiError*(msg: string) {.noreturn.} =
  ## Raises a `CgiError` exception with message `msg`.
  raise newException(CgiError, msg)

proc getEncodedData(allowedMethods: set[RequestMethod]): string =
  case getEnv("REQUEST_METHOD")
  of "POST":
    if methodPost notin allowedMethods:
      cgiError("'REQUEST_METHOD' 'POST' is not supported")
    var L = parseInt(getEnv("CONTENT_LENGTH"))
    if L == 0:
      return ""
    result = newString(L)
    if readBuffer(stdin, addr(result[0]), L) != L:
      cgiError("cannot read from stdin")
  of "GET":
    if methodGet notin allowedMethods:
      cgiError("'REQUEST_METHOD' 'GET' is not supported")
    result = getEnv("QUERY_STRING")
  else:
    if methodNone notin allowedMethods:
      cgiError("'REQUEST_METHOD' must be 'POST' or 'GET'")
    else:
      result = ""

iterator decodeData*(data: string): tuple[key, value: string] =
  ## Reads and decodes CGI data and yields the (name, value) pairs the
  ## data consists of.
  for (key, value) in uri.decodeQuery(data):
    yield (key, value)

iterator decodeData*(allowedMethods: set[RequestMethod] =
       {methodNone, methodPost, methodGet}): tuple[key, value: string] =
  ## Reads and decodes CGI data and yields the (name, value) pairs the
  ## data consists of. If the client does not use a method listed in the
  ## `allowedMethods` set, a `CgiError` exception is raised.
  let data = getEncodedData(allowedMethods)
  for (key, value) in uri.decodeQuery(data):
    yield (key, value)

proc readData*(allowedMethods: set[RequestMethod] =
               {methodNone, methodPost, methodGet}): StringTableRef =
  ## Reads CGI data. If the client does not use a method listed in the
  ## `allowedMethods` set, a `CgiError` exception is raised.
  result = newStringTable()
  for name, value in decodeData(allowedMethods):
    result[name] = value

proc readData*(data: string): StringTableRef =
  ## Reads CGI data from a string.
  result = newStringTable()
  for name, value in decodeData(data):
    result[name] = value

proc validateData*(data: StringTableRef, validKeys: varargs[string]) =
  ## Validates data; raises `CgiError` if this fails. This checks that each variable
  ## name of the CGI `data` occurs in the `validKeys` array.
  for key, val in pairs(data):
    if find(validKeys, key) < 0:
      cgiError("unknown variable name: " & key)

proc getContentLength*(): string =
  ## Returns contents of the `CONTENT_LENGTH` environment variable.
  return getEnv("CONTENT_LENGTH")

proc getContentType*(): string =
  ## Returns contents of the `CONTENT_TYPE` environment variable.
  return getEnv("CONTENT_Type")

proc getDocumentRoot*(): string =
  ## Returns contents of the `DOCUMENT_ROOT` environment variable.
  return getEnv("DOCUMENT_ROOT")

proc getGatewayInterface*(): string =
  ## Returns contents of the `GATEWAY_INTERFACE` environment variable.
  return getEnv("GATEWAY_INTERFACE")

proc getHttpAccept*(): string =
  ## Returns contents of the `HTTP_ACCEPT` environment variable.
  return getEnv("HTTP_ACCEPT")

proc getHttpAcceptCharset*(): string =
  ## Returns contents of the `HTTP_ACCEPT_CHARSET` environment variable.
  return getEnv("HTTP_ACCEPT_CHARSET")

proc getHttpAcceptEncoding*(): string =
  ## Returns contents of the `HTTP_ACCEPT_ENCODING` environment variable.
  return getEnv("HTTP_ACCEPT_ENCODING")

proc getHttpAcceptLanguage*(): string =
  ## Returns contents of the `HTTP_ACCEPT_LANGUAGE` environment variable.
  return getEnv("HTTP_ACCEPT_LANGUAGE")

proc getHttpConnection*(): string =
  ## Returns contents of the `HTTP_CONNECTION` environment variable.
  return getEnv("HTTP_CONNECTION")

proc getHttpCookie*(): string =
  ## Returns contents of the `HTTP_COOKIE` environment variable.
  return getEnv("HTTP_COOKIE")

proc getHttpHost*(): string =
  ## Returns contents of the `HTTP_HOST` environment variable.
  return getEnv("HTTP_HOST")

proc getHttpReferer*(): string =
  ## Returns contents of the `HTTP_REFERER` environment variable.
  return getEnv("HTTP_REFERER")

proc getHttpUserAgent*(): string =
  ## Returns contents of the `HTTP_USER_AGENT` environment variable.
  return getEnv("HTTP_USER_AGENT")

proc getPathInfo*(): string =
  ## Returns contents of the `PATH_INFO` environment variable.
  return getEnv("PATH_INFO")

proc getPathTranslated*(): string =
  ## Returns contents of the `PATH_TRANSLATED` environment variable.
  return getEnv("PATH_TRANSLATED")

proc getQueryString*(): string =
  ## Returns contents of the `QUERY_STRING` environment variable.
  return getEnv("QUERY_STRING")

proc getRemoteAddr*(): string =
  ## Returns contents of the `REMOTE_ADDR` environment variable.
  return getEnv("REMOTE_ADDR")

proc getRemoteHost*(): string =
  ## Returns contents of the `REMOTE_HOST` environment variable.
  return getEnv("REMOTE_HOST")

proc getRemoteIdent*(): string =
  ## Returns contents of the `REMOTE_IDENT` environment variable.
  return getEnv("REMOTE_IDENT")

proc getRemotePort*(): string =
  ## Returns contents of the `REMOTE_PORT` environment variable.
  return getEnv("REMOTE_PORT")

proc getRemoteUser*(): string =
  ## Returns contents of the `REMOTE_USER` environment variable.
  return getEnv("REMOTE_USER")

proc getRequestMethod*(): string =
  ## Returns contents of the `REQUEST_METHOD` environment variable.
  return getEnv("REQUEST_METHOD")

proc getRequestURI*(): string =
  ## Returns contents of the `REQUEST_URI` environment variable.
  return getEnv("REQUEST_URI")

proc getScriptFilename*(): string =
  ## Returns contents of the `SCRIPT_FILENAME` environment variable.
  return getEnv("SCRIPT_FILENAME")

proc getScriptName*(): string =
  ## Returns contents of the `SCRIPT_NAME` environment variable.
  return getEnv("SCRIPT_NAME")

proc getServerAddr*(): string =
  ## Returns contents of the `SERVER_ADDR` environment variable.
  return getEnv("SERVER_ADDR")

proc getServerAdmin*(): string =
  ## Returns contents of the `SERVER_ADMIN` environment variable.
  return getEnv("SERVER_ADMIN")

proc getServerName*(): string =
  ## Returns contents of the `SERVER_NAME` environment variable.
  return getEnv("SERVER_NAME")

proc getServerPort*(): string =
  ## Returns contents of the `SERVER_PORT` environment variable.
  return getEnv("SERVER_PORT")

proc getServerProtocol*(): string =
  ## Returns contents of the `SERVER_PROTOCOL` environment variable.
  return getEnv("SERVER_PROTOCOL")

proc getServerSignature*(): string =
  ## Returns contents of the `SERVER_SIGNATURE` environment variable.
  return getEnv("SERVER_SIGNATURE")

proc getServerSoftware*(): string =
  ## Returns contents of the `SERVER_SOFTWARE` environment variable.
  return getEnv("SERVER_SOFTWARE")

proc setTestData*(keysvalues: varargs[string]) =
  ## Fills the appropriate environment variables to test your CGI application.
  ## This can only simulate the 'GET' request method. `keysvalues` should
  ## provide embedded (name, value)-pairs. Example:
  ##   ```Nim
  ##   setTestData("name", "Hanz", "password", "12345")
  ##   ```
  putEnv("REQUEST_METHOD", "GET")
  var i = 0
  var query = ""
  while i < keysvalues.len:
    add(query, encodeUrl(keysvalues[i]))
    add(query, '=')
    add(query, encodeUrl(keysvalues[i+1]))
    add(query, '&')
    inc(i, 2)
  putEnv("QUERY_STRING", query)

proc writeContentType*() =
  ## Calls this before starting to send your HTML data to `stdout`. This
  ## implements this part of the CGI protocol:
  ##   ```Nim
  ##   write(stdout, "Content-type: text/html\n\n")
  ##   ```
  write(stdout, "Content-type: text/html\n\n")

proc resetForStacktrace() =
  stdout.write """<!--: spam
Content-Type: text/html

<body bgcolor=#f0f0f8><font color=#f0f0f8 size=-5> -->
<body bgcolor=#f0f0f8><font color=#f0f0f8 size=-5> --> -->
</font> </font> </font> </script> </object> </blockquote> </pre>
</table> </table> </table> </table> </table> </font> </font> </font>
"""

proc writeErrorMessage*(data: string) =
  ## Tries to reset browser state and writes `data` to stdout in
  ## <plaintext> tag.
  resetForStacktrace()
  # We use <plaintext> here, instead of escaping, so stacktrace can
  # be understood by human looking at source.
  stdout.write("<plaintext>\n")
  stdout.write(data)

proc setStackTraceStdout*() =
  ## Makes Nim output stacktraces to stdout, instead of server log.
  errorMessageWriter = writeErrorMessage

proc setCookie*(name, value: string) =
  ## Sets a cookie.
  write(stdout, "Set-Cookie: ", name, "=", value, "\n")

var
  gcookies {.threadvar.}: StringTableRef

proc getCookie*(name: string): string =
  ## Gets a cookie. If no cookie of `name` exists, "" is returned.
  if gcookies == nil: gcookies = parseCookies(getHttpCookie())
  result = gcookies.getOrDefault(name)

proc existsCookie*(name: string): bool =
  ## Checks if a cookie of `name` exists.
  if gcookies == nil: gcookies = parseCookies(getHttpCookie())
  result = hasKey(gcookies, name)
