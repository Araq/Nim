#
#
#            Nim's Runtime Library
#        (c) Copyright 2019 Nim Contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements a simple HTTP client that can be used to retrieve
## webpages and other data.
##
## .. warning:: Validate untrusted inputs: URI parsers and getters are not detecting malicious URIs.
##
## Retrieving a website
## ====================
##
## This example uses HTTP GET to retrieve
## `http://google.com`:
##
##   ```Nim
##   import std/httpclient
##   var client = newHttpClient()
##   try:
##     echo client.getContent("http://google.com")
##   finally:
##     client.close()
##   ```
##
## The same action can also be performed asynchronously, simply use the
## `AsyncHttpClient`:
##
##   ```Nim
##   import std/[asyncdispatch, httpclient]
##
##   proc asyncProc(): Future[string] {.async.} =
##     var client = newAsyncHttpClient()
##     try:
##       return await client.getContent("http://google.com")
##     finally:
##       client.close()
##
##   echo waitFor asyncProc()
##   ```
##
## The functionality implemented by `HttpClient` and `AsyncHttpClient`
## is the same, so you can use whichever one suits you best in the examples
## shown here.
##
## **Note:** You need to run asynchronous examples in an async proc
## otherwise you will get an `Undeclared identifier: 'await'` error.
##
## **Note:** An asynchronous client instance can only deal with one
## request at a time. To send multiple requests in parallel, use
## multiple client instances.
##
## Using HTTP POST
## ===============
##
## This example demonstrates the usage of the W3 HTML Validator, it
## uses `multipart/form-data` as the `Content-Type` to send the HTML to be
## validated to the server.
##
##   ```Nim
##   import std/[httpclient]
##   var client = newHttpClient()
##   var data = newMultipartData()
##   data["output"] = "soap12"
##   data["uploaded_file"] = ("test.html", "text/html",
##     "<html><head></head><body><p>test</p></body></html>")
##   try:
##     echo client.postContent("http://validator.w3.org/check", multipart=data)
##   finally:
##     client.close()
##   ```
##
## To stream files from disk when performing the request, use `addFiles`.
##
## **Note:** This will allocate a new `Mimetypes` database every time you call
## it, you can pass your own via the `mimeDb` parameter to avoid this.
##
##   ```Nim
##   import std/[httpclient, mimetypes]
##   let mimes = newMimetypes()
##   var client = newHttpClient()
##   var data = newMultipartData()
##   data.addFiles({"uploaded_file": "test.html"}, mimeDb = mimes)
##   try:
##     echo client.postContent("http://validator.w3.org/check", multipart=data)
##   finally:
##     client.close()
##   ```
##
## You can also make post requests with custom headers.
## This example sets `Content-Type` to `application/json`
## and uses a json object for the body
##
##   ```Nim
##   import std/[httpclient, json]
##
##   let client = newHttpClient()
##   client.headers = newHttpHeaders({ "Content-Type": "application/json" })
##   let body = %*{
##       "data": "some text"
##   }
##   try:
##     let response = client.request("http://some.api", httpMethod = HttpPost, body = $body)
##     echo response.status
##   finally:
##     client.close()
##   ```
##
## Progress reporting
## ==================
##
## You may specify a callback procedure to be called during an HTTP request.
## This callback will be executed every second with information about the
## progress of the HTTP request.
##
##   ```Nim
##   import std/[asyncdispatch, httpclient]
##
##   proc onProgressChanged(total, progress, speed: BiggestInt) {.async.} =
##     echo("Downloaded ", progress, " of ", total)
##     echo("Current rate: ", speed div 1000, "kb/s")
##
##   proc asyncProc() {.async.} =
##     var client = newAsyncHttpClient()
##     client.onProgressChanged = onProgressChanged
##     try:
##       discard await client.getContent("http://speedtest-ams2.digitalocean.com/100mb.test")
##     finally:
##       client.close()
##
##   waitFor asyncProc()
##   ```
##
## If you would like to remove the callback simply set it to `nil`.
##
##   ```Nim
##   client.onProgressChanged = nil
##   ```
##
## .. warning:: The `total` reported by httpclient may be 0 in some cases.
##
##
## SSL/TLS support
## ===============
## This requires the OpenSSL library. Fortunately it's widely used and installed
## on many operating systems. httpclient will use SSL automatically if you give
## any of the functions a url with the `https` schema, for example:
## `https://github.com/`.
##
## You will also have to compile with `ssl` defined like so:
## `nim c -d:ssl ...`.
##
## Certificate validation is performed by default.
##
## A set of directories and files from the `ssl_certs <ssl_certs.html>`_
## module are scanned to locate CA certificates.
##
## Example of setting SSL verification parameters in a new client:
##
##   ```Nim
##   import std/[net, httpclient]
##   var client = newHttpClient(sslContext=newContext(verifyMode=CVerifyPeer))
##   ```
##
## There are three options for verify mode:
##
## * ``CVerifyNone``: certificates are not verified;
## * ``CVerifyPeer``: certificates are verified;
## * ``CVerifyPeerUseEnvVars``: certificates are verified and the optional
##   environment variables SSL_CERT_FILE and SSL_CERT_DIR are also used to
##   locate certificates
##
## See `newContext <net.html#newContext.string,string,string,string>`_ to tweak or disable certificate validation.
##
## Timeouts
## ========
##
## Currently only the synchronous functions support a timeout.
## The timeout is
## measured in milliseconds, once it is set any call on a socket which may
## block will be susceptible to this timeout.
##
## It may be surprising but the
## function as a whole can take longer than the specified timeout, only
## individual internal calls on the socket are affected. In practice this means
## that as long as the server is sending data an exception will not be raised,
## if however data does not reach the client within the specified timeout a
## `TimeoutError` exception will be raised.
##
## Here is how to set a timeout when creating an `HttpClient` instance:
##
##   ```Nim
##   import std/httpclient
##
##   let client = newHttpClient(timeout = 42)
##   ```
##
## Proxy
## =====
##
## A proxy can be specified as a param to any of the procedures defined in
## this module. To do this, use the `newProxy` constructor. Unfortunately,
## only basic authentication is supported at the moment.
##
## Some examples on how to configure a Proxy for `HttpClient`:
##
##   ```Nim
##   import std/httpclient
##
##   let myProxy = newProxy("http://myproxy.network")
##   let client = newHttpClient(proxy = myProxy)
##   ```
##
## Use proxies with basic authentication:
##
##   ```Nim
##   import std/httpclient
##
##   let myProxy = newProxy("http://myproxy.network", auth="user:password")
##   let client = newHttpClient(proxy = myProxy)
##   ```
##
## Get Proxy URL from environment variables:
##
##   ```Nim
##   import std/httpclient
##
##   var url = ""
##   try:
##     if existsEnv("http_proxy"):
##       url = getEnv("http_proxy")
##     elif existsEnv("https_proxy"):
##       url = getEnv("https_proxy")
##   except ValueError:
##     echo "Unable to parse proxy from environment variables."
##
##   let myProxy = newProxy(url = url)
##   let client = newHttpClient(proxy = myProxy)
##   ```
##
## Redirects
## =========
##
## The maximum redirects can be set with the `maxRedirects` of `int` type,
## it specifies the maximum amount of redirects to follow,
## it defaults to `5`, you can set it to `0` to disable redirects.
##
## Here you can see an example about how to set the `maxRedirects` of `HttpClient`:
##
##   ```Nim
##   import std/httpclient
##
##   let client = newHttpClient(maxRedirects = 0)
##   ```
##

import std/private/since

import std/[
  net, strutils, uri, parseutils, base64, os, mimetypes,
  math, random, httpcore, times, tables, streams, monotimes,
  asyncnet, asyncdispatch, asyncfile, nativesockets,
]

when defined(nimPreviewSlimSystem):
  import std/[assertions, syncio]

export httpcore except parseHeader # TODO: The `except` doesn't work

type
  Response* = ref object
    version*: string
    status*: string
    headers*: HttpHeaders
    body: string
    bodyStream*: Stream

  AsyncResponse* = ref object
    version*: string
    status*: string
    headers*: HttpHeaders
    body: string
    bodyStream*: FutureStream[string]

proc code*(response: Response | AsyncResponse): HttpCode
           {.raises: [ValueError, OverflowDefect].} =
  ## Retrieves the specified response's `HttpCode`.
  ##
  ## Raises a `ValueError` if the response's `status` does not have a
  ## corresponding `HttpCode`.
  return response.status[0 .. 2].parseInt.HttpCode

proc contentType*(response: Response | AsyncResponse): string {.inline.} =
  ## Retrieves the specified response's content type.
  ##
  ## This is effectively the value of the "Content-Type" header.
  response.headers.getOrDefault("content-type")

proc contentLength*(response: Response | AsyncResponse): int =
  ## Retrieves the specified response's content length.
  ##
  ## This is effectively the value of the "Content-Length" header.
  ##
  ## A `ValueError` exception will be raised if the value is not an integer.
  ## If the Content-Length header is not set in the response, ContentLength is set to the value -1.
  var contentLengthHeader = response.headers.getOrDefault("Content-Length", HttpHeaderValues(@["-1"]))
  result = contentLengthHeader.parseInt()

proc lastModified*(response: Response | AsyncResponse): DateTime =
  ## Retrieves the specified response's last modified time.
  ##
  ## This is effectively the value of the "Last-Modified" header.
  ##
  ## Raises a `ValueError` if the parsing fails or the value is not a correctly
  ## formatted time.
  var lastModifiedHeader = response.headers.getOrDefault("last-modified")
  result = parse(lastModifiedHeader, "ddd, dd MMM yyyy HH:mm:ss 'GMT'", utc())

proc body*(response: Response): string =
  ## Retrieves the specified response's body.
  ##
  ## The response's body stream is read synchronously.
  if response.body.len == 0:
    response.body = response.bodyStream.readAll()
  return response.body

proc body*(response: AsyncResponse): Future[string] {.async.} =
  ## Reads the response's body and caches it. The read is performed only
  ## once.
  if response.body.len == 0:
    response.body = await readAll(response.bodyStream)
  return response.body

type
  Proxy* = ref object
    url*: Uri
    auth*: string

  MultipartEntry = object
    name, content: string
    case isFile: bool
    of true:
      filename, contentType: string
      fileSize: int64
      isStream: bool
    else: discard

  MultipartEntries* = openArray[tuple[name, content: string]]
  MultipartData* = ref object
    content: seq[MultipartEntry]

  ProtocolError* = object of IOError ## exception that is raised when server
                                     ## does not conform to the implemented
                                     ## protocol

  HttpRequestError* = object of IOError ## Thrown in the `getContent` proc
                                        ## and `postContent` proc,
                                        ## when the server returns an error

const defUserAgent* = "Nim-httpclient/" & NimVersion

proc httpError(msg: string) =
  var e: ref ProtocolError
  new(e)
  e.msg = msg
  raise e

proc fileError(msg: string) =
  var e: ref IOError
  new(e)
  e.msg = msg
  raise e

when not defined(ssl):
  type SslContext = ref object
var defaultSslContext {.threadvar.}: SslContext

proc getDefaultSSL(): SslContext =
  result = defaultSslContext
  when defined(ssl):
    if result == nil:
      defaultSslContext = newContext(verifyMode = CVerifyPeer)
      result = defaultSslContext
      doAssert result != nil, "failure to initialize the SSL context"

proc newProxy*(url: string; auth = ""): Proxy =
  ## Constructs a new `TProxy` object.
  result = Proxy(url: parseUri(url), auth: auth)

proc newProxy*(url: Uri; auth = ""): Proxy =
  ## Constructs a new `TProxy` object.
  result = Proxy(url: url, auth: auth)

proc newMultipartData*: MultipartData {.inline.} =
  ## Constructs a new `MultipartData` object.
  MultipartData()

proc `$`*(data: MultipartData): string {.since: (1, 1).} =
  ## convert MultipartData to string so it's human readable when echo
  ## see https://github.com/nim-lang/Nim/issues/11863
  const sep = "-".repeat(30)
  for pos, entry in data.content:
    result.add(sep & center($pos, 3) & sep)
    result.add("\nname=\"" & entry.name & "\"")
    if entry.isFile:
      result.add("; filename=\"" & entry.filename & "\"\n")
      result.add("Content-Type: " & entry.contentType)
    result.add("\n\n" & entry.content & "\n")

proc add*(p: MultipartData, name, content: string, filename: string = "",
          contentType: string = "", useStream = true) =
  ## Add a value to the multipart data.
  ##
  ## When `useStream` is `false`, the file will be read into memory.
  ##
  ## Raises a `ValueError` exception if
  ## `name`, `filename` or `contentType` contain newline characters.
  if {'\c', '\L'} in name:
    raise newException(ValueError, "name contains a newline character")
  if {'\c', '\L'} in filename:
    raise newException(ValueError, "filename contains a newline character")
  if {'\c', '\L'} in contentType:
    raise newException(ValueError, "contentType contains a newline character")

  var entry = MultipartEntry(
    name: name,
    content: content,
    isFile: filename.len > 0
  )

  if entry.isFile:
    entry.isStream = useStream
    entry.filename = filename
    entry.contentType = contentType

  p.content.add(entry)

proc add*(p: MultipartData, xs: MultipartEntries): MultipartData
         {.discardable.} =
  ## Add a list of multipart entries to the multipart data `p`. All values are
  ## added without a filename and without a content type.
  ##
  ##   ```Nim
  ##   data.add({"action": "login", "format": "json"})
  ##   ```
  for name, content in xs.items:
    p.add(name, content)
  result = p

proc newMultipartData*(xs: MultipartEntries): MultipartData =
  ## Create a new multipart data object and fill it with the entries `xs`
  ## directly.
  ##
  ##   ```Nim
  ##   var data = newMultipartData({"action": "login", "format": "json"})
  ##   ```
  result = MultipartData()
  for entry in xs:
    result.add(entry.name, entry.content)

proc addFiles*(p: MultipartData, xs: openArray[tuple[name, file: string]],
               mimeDb = newMimetypes(), useStream = true):
               MultipartData {.discardable.} =
  ## Add files to a multipart data object. The files will be streamed from disk
  ## when the request is being made. When `stream` is `false`, the files are
  ## instead read into memory, but beware this is very memory ineffecient even
  ## for small files. The MIME types will automatically be determined.
  ## Raises an `IOError` if the file cannot be opened or reading fails. To
  ## manually specify file content, filename and MIME type, use `[]=` instead.
  ##
  ##   ```Nim
  ##   data.addFiles({"uploaded_file": "public/test.html"})
  ##   ```
  for name, file in xs.items:
    var contentType: string
    let (_, fName, ext) = splitFile(file)
    if ext.len > 0:
      contentType = mimeDb.getMimetype(ext[1..ext.high], "")
    let content = if useStream: file else: readFile(file)
    p.add(name, content, fName & ext, contentType, useStream = useStream)
  result = p

proc `[]=`*(p: MultipartData, name, content: string) {.inline.} =
  ## Add a multipart entry to the multipart data `p`. The value is added
  ## without a filename and without a content type.
  ##
  ##   ```Nim
  ##   data["username"] = "NimUser"
  ##   ```
  p.add(name, content)

proc `[]=`*(p: MultipartData, name: string,
            file: tuple[name, contentType, content: string]) {.inline.} =
  ## Add a file to the multipart data `p`, specifying filename, contentType
  ## and content manually.
  ##
  ##   ```Nim
  ##   data["uploaded_file"] = ("test.html", "text/html",
  ##     "<html><head></head><body><p>test</p></body></html>")
  ##   ```
  p.add(name, file.content, file.name, file.contentType, useStream = false)

proc getBoundary(p: MultipartData): string =
  if p == nil or p.content.len == 0: return
  while true:
    result = $rand(int.high)
    for i, entry in p.content:
      if result in entry.content: break
      elif i == p.content.high: return

proc sendFile(socket: Socket | AsyncSocket,
              entry: MultipartEntry) {.multisync.} =
  const chunkSize = 2^18
  let file =
    when socket is AsyncSocket: openAsync(entry.content)
    else: newFileStream(entry.content, fmRead)

  var buffer: string
  while true:
    buffer =
      when socket is AsyncSocket: (await read(file, chunkSize))
      else: readStr(file, chunkSize)
    if buffer.len == 0: break
    await socket.send(buffer)
  file.close()

proc getNewLocation(lastURL: Uri, headers: HttpHeaders): Uri =
  let newLocation = headers.getOrDefault"Location"
  if newLocation == "": httpError("location header expected")
  # Relative URLs. (Not part of the spec, but soon will be.)
  let parsedLocation = parseUri(newLocation)
  if parsedLocation.hostname == "" and parsedLocation.path != "":
    result = lastURL
    result.path = parsedLocation.path
    result.query = parsedLocation.query
    result.anchor = parsedLocation.anchor
  else:
    result = parsedLocation

proc generateHeaders(requestUrl: Uri, httpMethod: HttpMethod, headers: HttpHeaders,
                     proxy: Proxy): string =
  # GET
  result = $httpMethod
  result.add ' '

  if proxy.isNil or requestUrl.scheme == "https":
    # /path?query
    if not requestUrl.path.startsWith("/"): result.add '/'
    result.add(requestUrl.path)
    if requestUrl.query.len > 0:
      result.add("?" & requestUrl.query)
  else:
    # Remove the 'http://' from the URL for CONNECT requests for TLS connections.
    var modifiedUrl = requestUrl
    if requestUrl.scheme == "https": modifiedUrl.scheme = ""
    result.add($modifiedUrl)

  # HTTP/1.1\c\l
  result.add(" HTTP/1.1" & httpNewLine)

  # Host header.
  if not headers.hasKey("Host"):
    if requestUrl.port == "":
      add(result, "Host: " & requestUrl.hostname & httpNewLine)
    else:
      add(result, "Host: " & requestUrl.hostname & ":" & requestUrl.port & httpNewLine)

  # Connection header.
  if not headers.hasKey("Connection"):
    add(result, "Connection: Keep-Alive" & httpNewLine)

  # Proxy auth header.
  if not proxy.isNil and proxy.auth != "":
    let auth = base64.encode(proxy.auth)
    add(result, "Proxy-Authorization: Basic " & auth & httpNewLine)

  for key, val in headers:
    add(result, key & ": " & val & httpNewLine)

  add(result, httpNewLine)

type
  ProgressChangedProc*[ReturnType] =
    proc (total, progress, speed: BiggestInt):
      ReturnType {.closure, gcsafe.}

  HttpClientBase*[SocketType] = ref object
    socket: SocketType
    connected: bool
    currentURL: Uri       ## Where we are currently connected.
    headers*: HttpHeaders ## Headers to send in requests.
    maxRedirects: Natural ## Maximum redirects, set to `0` to disable.
    userAgent: string
    timeout*: int         ## Only used for blocking HttpClient for now.
    proxy: Proxy
    ## `nil` or the callback to call when request progress changes.
    when SocketType is Socket:
      onProgressChanged*: ProgressChangedProc[void]
    else:
      onProgressChanged*: ProgressChangedProc[Future[void]]
    when defined(ssl):
      sslContext: net.SslContext
    contentTotal: BiggestInt
    contentProgress: BiggestInt
    oneSecondProgress: BiggestInt
    lastProgressReport: MonoTime
    when SocketType is AsyncSocket:
      bodyStream: FutureStream[string]
      parseBodyFut: Future[void]
    else:
      bodyStream: Stream
    getBody: bool         ## When `false`, the body is never read in requestAux.

type
  HttpClient* = HttpClientBase[Socket]

proc newHttpClient*(userAgent = defUserAgent, maxRedirects = 5,
                    sslContext = getDefaultSSL(), proxy: Proxy = nil,
                    timeout = -1, headers = newHttpHeaders()): HttpClient =
  ## Creates a new HttpClient instance.
  ##
  ## `userAgent` specifies the user agent that will be used when making
  ## requests.
  ##
  ## `maxRedirects` specifies the maximum amount of redirects to follow,
  ## default is 5.
  ##
  ## `sslContext` specifies the SSL context to use for HTTPS requests.
  ## See `SSL/TLS support <#sslslashtls-support>`_
  ##
  ## `proxy` specifies an HTTP proxy to use for this HTTP client's
  ## connections.
  ##
  ## `timeout` specifies the number of milliseconds to allow before a
  ## `TimeoutError` is raised.
  ##
  ## `headers` specifies the HTTP Headers.
  runnableExamples:
    import std/strutils

    let exampleHtml = newHttpClient().getContent("http://example.com")
    assert "Example Domain" in exampleHtml
    assert "Pizza" notin exampleHtml

  new result
  result.headers = headers
  result.userAgent = userAgent
  result.maxRedirects = maxRedirects
  result.proxy = proxy
  result.timeout = timeout
  result.onProgressChanged = nil
  result.bodyStream = newStringStream()
  result.getBody = true
  when defined(ssl):
    result.sslContext = sslContext

type
  AsyncHttpClient* = HttpClientBase[AsyncSocket]

proc newAsyncHttpClient*(userAgent = defUserAgent, maxRedirects = 5,
                         sslContext = getDefaultSSL(), proxy: Proxy = nil,
                         headers = newHttpHeaders()): AsyncHttpClient =
  ## Creates a new AsyncHttpClient instance.
  ##
  ## `userAgent` specifies the user agent that will be used when making
  ## requests.
  ##
  ## `maxRedirects` specifies the maximum amount of redirects to follow,
  ## default is 5.
  ##
  ## `sslContext` specifies the SSL context to use for HTTPS requests.
  ##
  ## `proxy` specifies an HTTP proxy to use for this HTTP client's
  ## connections.
  ##
  ## `headers` specifies the HTTP Headers.
  runnableExamples:
    import std/[asyncdispatch, strutils]

    proc asyncProc(): Future[string] {.async.} =
      let client = newAsyncHttpClient()
      result = await client.getContent("http://example.com")

    let exampleHtml = waitFor asyncProc()
    assert "Example Domain" in exampleHtml
    assert "Pizza" notin exampleHtml
  
  new result
  result.headers = headers
  result.userAgent = userAgent
  result.maxRedirects = maxRedirects
  result.proxy = proxy
  result.timeout = -1 # TODO
  result.onProgressChanged = nil
  result.bodyStream = newFutureStream[string]("newAsyncHttpClient")
  result.getBody = true
  when defined(ssl):
    result.sslContext = sslContext

proc close*(client: HttpClient | AsyncHttpClient) =
  ## Closes any connections held by the HTTP client.
  if client.connected:
    client.socket.close()
    client.connected = false

proc getSocket*(client: HttpClient): Socket {.inline.} =
  ## Get network socket, useful if you want to find out more details about the connection.
  ##
  ## This example shows info about local and remote endpoints:
  ##
  ##   ```Nim
  ##   if client.connected:
  ##     echo client.getSocket.getLocalAddr
  ##     echo client.getSocket.getPeerAddr
  ##   ```
  return client.socket

proc getSocket*(client: AsyncHttpClient): AsyncSocket {.inline.} =
  return client.socket

proc reportProgress(client: HttpClient | AsyncHttpClient,
                    progress: BiggestInt) {.multisync.} =
  client.contentProgress += progress
  client.oneSecondProgress += progress
  if (getMonoTime() - client.lastProgressReport).inSeconds >= 1:
    if not client.onProgressChanged.isNil:
      await client.onProgressChanged(client.contentTotal,
                                     client.contentProgress,
                                     client.oneSecondProgress)
      client.oneSecondProgress = 0
      client.lastProgressReport = getMonoTime()

proc recvFull(client: HttpClient | AsyncHttpClient, size: int, timeout: int,
              keep: bool): Future[int] {.multisync.} =
  ## Ensures that all the data requested is read and returned.
  var readLen = 0
  while true:
    if size == readLen: break

    let remainingSize = size - readLen
    let sizeToRecv = min(remainingSize, net.BufferSize)

    when client.socket is Socket:
      let data = client.socket.recv(sizeToRecv, timeout)
    else:
      let data = await client.socket.recv(sizeToRecv)
    if data == "":
      client.close()
      break # We've been disconnected.

    readLen.inc(data.len)
    if keep:
      await client.bodyStream.write(data)

    await reportProgress(client, data.len)

  return readLen

proc parseChunks(client: HttpClient | AsyncHttpClient): Future[void]
                 {.multisync.} =
  while true:
    var chunkSize = 0
    var chunkSizeStr = await client.socket.recvLine()
    var i = 0
    if chunkSizeStr == "":
      httpError("Server terminated connection prematurely")
    while i < chunkSizeStr.len:
      case chunkSizeStr[i]
      of '0'..'9':
        chunkSize = chunkSize shl 4 or (ord(chunkSizeStr[i]) - ord('0'))
      of 'a'..'f':
        chunkSize = chunkSize shl 4 or (ord(chunkSizeStr[i]) - ord('a') + 10)
      of 'A'..'F':
        chunkSize = chunkSize shl 4 or (ord(chunkSizeStr[i]) - ord('A') + 10)
      of ';':
        # http://tools.ietf.org/html/rfc2616#section-3.6.1
        # We don't care about chunk-extensions.
        break
      else:
        httpError("Invalid chunk size: " & chunkSizeStr)
      inc(i)
    if chunkSize <= 0:
      discard await recvFull(client, 2, client.timeout, false) # Skip \c\L
      break
    var bytesRead = await recvFull(client, chunkSize, client.timeout, true)
    if bytesRead != chunkSize:
      httpError("Server terminated connection prematurely")

    bytesRead = await recvFull(client, 2, client.timeout, false) # Skip \c\L
    if bytesRead != 2:
      httpError("Server terminated connection prematurely")

    # Trailer headers will only be sent if the request specifies that we want
    # them: http://tools.ietf.org/html/rfc2616#section-3.6.1

proc parseBody(client: HttpClient | AsyncHttpClient, headers: HttpHeaders,
               httpVersion: string): Future[void] {.multisync.} =
  # Reset progress from previous requests.
  client.contentTotal = 0
  client.contentProgress = 0
  client.oneSecondProgress = 0
  client.lastProgressReport = MonoTime()

  when client is AsyncHttpClient:
    assert(not client.bodyStream.finished)

  if headers.getOrDefault"Transfer-Encoding" == "chunked":
    await parseChunks(client)
  else:
    # -REGION- Content-Length
    # (http://tools.ietf.org/html/rfc2616#section-4.4) NR.3
    var contentLengthHeader = headers.getOrDefault"Content-Length"
    if contentLengthHeader != "":
      var length = contentLengthHeader.parseInt()
      client.contentTotal = length
      if length > 0:
        let recvLen = await client.recvFull(length, client.timeout, true)
        if recvLen == 0:
          client.close()
          httpError("Got disconnected while trying to read body.")
        if recvLen != length:
          httpError("Received length doesn't match expected length. Wanted " &
                    $length & " got: " & $recvLen)
    else:
      # (http://tools.ietf.org/html/rfc2616#section-4.4) NR.4 TODO

      # -REGION- Connection: Close
      # (http://tools.ietf.org/html/rfc2616#section-4.4) NR.5
      let implicitConnectionClose =
        httpVersion == "1.0" or
        # This doesn't match the HTTP spec, but it fixes issues for non-conforming servers.
        (httpVersion == "1.1" and headers.getOrDefault"Connection" == "")
      if headers.getOrDefault"Connection" == "close" or implicitConnectionClose:
        while true:
          let recvLen = await client.recvFull(4000, client.timeout, true)
          if recvLen != 4000:
            client.close()
            break

  when client is AsyncHttpClient:
    client.bodyStream.complete()
  else:
    client.bodyStream.setPosition(0)

  # If the server will close our connection, then no matter the method of
  # reading the body, we need to close our socket.
  if headers.getOrDefault"Connection" == "close":
    client.close()

proc parseResponse(client: HttpClient | AsyncHttpClient,
                   getBody: bool): Future[Response | AsyncResponse]
                   {.multisync.} =
  new result
  var parsedStatus = false
  var linei = 0
  var fullyRead = false
  var lastHeaderName = ""
  var line = ""
  result.headers = newHttpHeaders()
  while true:
    linei = 0
    when client is HttpClient:
      line = await client.socket.recvLine(client.timeout)
    else:
      line = await client.socket.recvLine()
    if line == "":
      # We've been disconnected.
      client.close()
      break
    if line == httpNewLine:
      fullyRead = true
      break
    if not parsedStatus:
      # Parse HTTP version info and status code.
      var le = skipIgnoreCase(line, "HTTP/", linei)
      if le <= 0:
        httpError("invalid http version, `" & line & "`")
      inc(linei, le)
      le = skipIgnoreCase(line, "1.1", linei)
      if le > 0: result.version = "1.1"
      else:
        le = skipIgnoreCase(line, "1.0", linei)
        if le <= 0: httpError("unsupported http version")
        result.version = "1.0"
      inc(linei, le)
      # Status code
      linei.inc skipWhitespace(line, linei)
      result.status = line[linei .. ^1]
      parsedStatus = true
    else:
      # Parse headers
      # There's at least one char because empty lines are handled above (with client.close)
      if line[0] in {' ', '\t'}:
        # Check if it's a multiline header value, if so, append to the header we're currently parsing
        # This works because a line with a header must start with the header name without any leading space
        # See https://datatracker.ietf.org/doc/html/rfc7230, section 3.2 and 3.2.4
        # Multiline headers are deprecated in the spec, but it's better to parse them than crash
        if lastHeaderName == "":
          # Some extra unparsable lines in the HTTP output - we ignore them
          discard
        else:
          result.headers.table[result.headers.toCaseInsensitive(lastHeaderName)][^1].add "\n" & line
      else:
        var name = ""
        var le = parseUntil(line, name, ':', linei)
        if le <= 0: httpError("Invalid headers - received empty header name")
        if line.len == le: httpError("Invalid headers - no colon after header name")
        inc(linei, le) # Skip the parsed header name
        inc(linei) # Skip :
        # If we want to be HTTP spec compliant later, error on linei == line.len (for empty header value)
        lastHeaderName = name # Remember the header name for the possible multi-line header
        result.headers.add(name, line[linei .. ^1].strip())
        if result.headers.len > headerLimit:
          httpError("too many headers")

  if not fullyRead:
    httpError("Connection was closed before full request has been made")

  when client is HttpClient:
    result.bodyStream = newStringStream()
  else:
    result.bodyStream = newFutureStream[string]("parseResponse")

  if getBody and result.code != Http204:
    client.bodyStream = result.bodyStream
    when client is HttpClient:
      parseBody(client, result.headers, result.version)
    else:
      assert(client.parseBodyFut.isNil or client.parseBodyFut.finished)
      # do not wait here for the body request to complete
      client.parseBodyFut = parseBody(client, result.headers, result.version)
      client.parseBodyFut.addCallback do():
        if client.parseBodyFut.failed:
          client.bodyStream.fail(client.parseBodyFut.error)
  else:
    when client is AsyncHttpClient:
      result.bodyStream.complete()

proc newConnection(client: HttpClient | AsyncHttpClient,
                   url: Uri) {.multisync.} =
  if client.currentURL.hostname != url.hostname or
      client.currentURL.scheme != url.scheme or
      client.currentURL.port != url.port or
      (not client.connected):
    # Connect to proxy if specified
    let connectionUrl =
      if client.proxy.isNil: url else: client.proxy.url

    let isSsl = connectionUrl.scheme.toLowerAscii() == "https"

    if isSsl and not defined(ssl):
      raise newException(HttpRequestError,
        "SSL support is not available. Cannot connect over SSL. Compile with -d:ssl to enable.")

    if client.connected:
      client.close()
      client.connected = false

    # TODO: I should be able to write 'net.Port' here...
    let port =
      if connectionUrl.port == "":
        if isSsl:
          nativesockets.Port(443)
        else:
          nativesockets.Port(80)
      else: nativesockets.Port(connectionUrl.port.parseInt)

    when client is HttpClient:
      client.socket = await net.dial(connectionUrl.hostname, port)
    elif client is AsyncHttpClient:
      client.socket = await asyncnet.dial(connectionUrl.hostname, port)
    else: {.fatal: "Unsupported client type".}

    when defined(ssl):
      if isSsl:
        try:
          client.sslContext.wrapConnectedSocket(
            client.socket, handshakeAsClient, connectionUrl.hostname)
        except:
          client.socket.close()
          raise getCurrentException()

    # If need to CONNECT through proxy
    if url.scheme == "https" and not client.proxy.isNil:
      when defined(ssl):
        # Pass only host:port for CONNECT
        var connectUrl = initUri()
        connectUrl.hostname = url.hostname
        connectUrl.port = if url.port != "": url.port else: "443"

        let proxyHeaderString = generateHeaders(connectUrl, HttpConnect,
            newHttpHeaders(), client.proxy)
        await client.socket.send(proxyHeaderString)
        let proxyResp = await parseResponse(client, false)

        if not proxyResp.status.startsWith("200"):
          raise newException(HttpRequestError,
                            "The proxy server rejected a CONNECT request, " &
                            "so a secure connection could not be established.")
        client.sslContext.wrapConnectedSocket(
          client.socket, handshakeAsClient, url.hostname)
      else:
        raise newException(HttpRequestError,
        "SSL support is not available. Cannot connect over SSL. Compile with -d:ssl to enable.")

    # May be connected through proxy but remember actual URL being accessed
    client.currentURL = url
    client.connected = true

proc readFileSizes(client: HttpClient | AsyncHttpClient,
                   multipart: MultipartData) {.multisync.} =
  for entry in multipart.content.mitems():
    if not entry.isFile: continue
    if not entry.isStream:
      entry.fileSize = entry.content.len
      continue

    # TODO: look into making getFileSize work with async
    let fileSize = getFileSize(entry.content)
    entry.fileSize = fileSize

proc format(entry: MultipartEntry, boundary: string): string =
  result = "--" & boundary & httpNewLine
  result.add("Content-Disposition: form-data; name=\"" & entry.name & "\"")
  if entry.isFile:
    result.add("; filename=\"" & entry.filename & "\"" & httpNewLine)
    result.add("Content-Type: " & entry.contentType & httpNewLine)
  else:
    result.add(httpNewLine & httpNewLine & entry.content)

proc format(client: HttpClient | AsyncHttpClient,
            multipart: MultipartData): Future[seq[string]] {.multisync.} =
  let bound = getBoundary(multipart)
  client.headers["Content-Type"] = "multipart/form-data; boundary=" & bound

  await client.readFileSizes(multipart)

  var length: int64
  for entry in multipart.content:
    result.add(format(entry, bound) & httpNewLine)
    if entry.isFile:
      length += entry.fileSize + httpNewLine.len

  result.add "--" & bound & "--" & httpNewLine

  for s in result: length += s.len
  client.headers["Content-Length"] = $length

proc override(fallback, override: HttpHeaders): HttpHeaders =
  # Right-biased map union for `HttpHeaders`

  result = newHttpHeaders()
  # Copy by value
  result.table[] = fallback.table[]

  if override.isNil:
    # Return the copy of fallback so it does not get modified
    return result

  for k, vs in override.table:
    result[k] = vs

proc requestAux(client: HttpClient | AsyncHttpClient, url: Uri,
                httpMethod: HttpMethod, body = "", headers: HttpHeaders = nil,
                multipart: MultipartData = nil): Future[Response | AsyncResponse]
                {.multisync.} =
  # Helper that actually makes the request. Does not handle redirects.
  if url.scheme == "":
    raise newException(ValueError, "No uri scheme supplied.")

  when client is AsyncHttpClient:
    if not client.parseBodyFut.isNil:
      # let the current operation finish before making another request
      await client.parseBodyFut
      client.parseBodyFut = nil

  await newConnection(client, url)

  var newHeaders: HttpHeaders

  var data: seq[string]
  if multipart != nil and multipart.content.len > 0:
    # `format` modifies `client.headers`, see 
    # https://github.com/nim-lang/Nim/pull/18208#discussion_r647036979
    data = await client.format(multipart)
    newHeaders = client.headers.override(headers)
  else:
    newHeaders = client.headers.override(headers)
    # Only change headers if they have not been specified already
    if not newHeaders.hasKey("Content-Length"):
      if body.len != 0:
        newHeaders["Content-Length"] = $body.len
      elif httpMethod notin {HttpGet, HttpHead}:
        newHeaders["Content-Length"] = "0"

  if not newHeaders.hasKey("user-agent") and client.userAgent.len > 0:
    newHeaders["User-Agent"] = client.userAgent

  let headerString = generateHeaders(url, httpMethod, newHeaders,
                                     client.proxy)
  await client.socket.send(headerString)

  if data.len > 0:
    var buffer: string
    for i, entry in multipart.content:
      buffer.add data[i]
      if not entry.isFile: continue
      if buffer.len > 0:
        await client.socket.send(buffer)
        buffer.setLen(0)
      if entry.isStream:
        await client.socket.sendFile(entry)
      else:
        await client.socket.send(entry.content)
      buffer.add httpNewLine
    # send the rest and the last boundary
    await client.socket.send(buffer & data[^1])
  elif body.len > 0:
    await client.socket.send(body)

  let getBody = httpMethod notin {HttpHead, HttpConnect} and
                client.getBody
  result = await parseResponse(client, getBody)

proc request*(client: HttpClient | AsyncHttpClient, url: Uri | string,
              httpMethod: HttpMethod | string = HttpGet, body = "",
              headers: HttpHeaders = nil,
              multipart: MultipartData = nil): Future[Response | AsyncResponse]
              {.multisync.} =
  ## Connects to the hostname specified by the URL and performs a request
  ## using the custom method string specified by `httpMethod`.
  ##
  ## Connection will be kept alive. Further requests on the same `client` to
  ## the same hostname will not require a new connection to be made. The
  ## connection can be closed by using the `close` procedure.
  ##
  ## This procedure will follow redirects up to a maximum number of redirects
  ## specified in `client.maxRedirects`.
  ##
  ## You need to make sure that the `url` doesn't contain any newline
  ## characters. Failing to do so will raise `AssertionDefect`.
  ##
  ## `headers` are HTTP headers that override the `client.headers` for
  ## this specific request only and will not be persisted.
  ##
  ## **Deprecated since v1.5**: use HttpMethod enum instead; string parameter httpMethod is deprecated
  when url is string:
    doAssert(not url.contains({'\c', '\L'}), "url shouldn't contain any newline characters")
    let url = parseUri(url)

  when httpMethod is string:
    {.warning:
       "Deprecated since v1.5; use HttpMethod enum instead; string parameter httpMethod is deprecated".}
    let httpMethod = case httpMethod
      of "HEAD":
        HttpHead
      of "GET":
        HttpGet
      of "POST":
        HttpPost
      of "PUT":
        HttpPut
      of "DELETE":
        HttpDelete
      of "TRACE":
        HttpTrace
      of "OPTIONS":
        HttpOptions
      of "CONNECT":
        HttpConnect
      of "PATCH":
        HttpPatch
      else:
        raise newException(ValueError, "Invalid HTTP method name: " & httpMethod)

  result = await client.requestAux(url, httpMethod, body, headers, multipart)

  var lastURL = url
  for i in 1..client.maxRedirects:
    let statusCode = result.code

    if statusCode notin {Http301, Http302, Http303, Http307, Http308}:
      break

    let redirectTo = getNewLocation(lastURL, result.headers)
    var redirectMethod: HttpMethod
    var redirectBody: string
    # For more informations about the redirect methods see:
    # https://developer.mozilla.org/en-US/docs/Web/HTTP/Redirections
    case statusCode
    of Http301, Http302, Http303:
      # The method is changed to GET unless it is GET or HEAD (RFC2616)
      if httpMethod notin {HttpGet, HttpHead}:
        redirectMethod = HttpGet
      else:
        redirectMethod = httpMethod
      # The body is stripped away
      redirectBody = ""
      # Delete any header value associated with the body
      if not headers.isNil():
        headers.del("Content-Length")
        headers.del("Content-Type")
        headers.del("Transfer-Encoding")
    of Http307, Http308:
      # The method and the body are unchanged
      redirectMethod = httpMethod
      redirectBody = body
    else:
      # Unreachable
      doAssert(false)

    # Check if the redirection is to the same domain or a sub-domain (foo.com
    # -> sub.foo.com)
    if redirectTo.hostname != lastURL.hostname and
      not redirectTo.hostname.endsWith("." & lastURL.hostname):
      # Perform some cleanup of the header values
      if headers != nil:
        # Delete the Host header
        headers.del("Host")
        # Do not send any sensitive info to a unknown host
        headers.del("Authorization")

    result = await client.requestAux(redirectTo, redirectMethod, redirectBody,
                                     headers, multipart)
    lastURL = redirectTo

proc responseContent(resp: Response | AsyncResponse): Future[string] {.multisync.} =
  ## Returns the content of a response as a string.
  ##
  ## A `HttpRequestError` will be raised if the server responds with a
  ## client error (status code 4xx) or a server error (status code 5xx).
  if resp.code.is4xx or resp.code.is5xx:
    raise newException(HttpRequestError, resp.status.move)
  else:
    return await resp.bodyStream.readAll()

proc head*(client: HttpClient | AsyncHttpClient,
          url: Uri | string): Future[Response | AsyncResponse] {.multisync.} =
  ## Connects to the hostname specified by the URL and performs a HEAD request.
  ##
  ## This procedure uses httpClient values such as `client.maxRedirects`.
  result = await client.request(url, HttpHead)

proc get*(client: HttpClient | AsyncHttpClient,
          url: Uri | string): Future[Response | AsyncResponse] {.multisync.} =
  ## Connects to the hostname specified by the URL and performs a GET request.
  ##
  ## This procedure uses httpClient values such as `client.maxRedirects`.
  result = await client.request(url, HttpGet)

proc getContent*(client: HttpClient | AsyncHttpClient,
                 url: Uri | string): Future[string] {.multisync.} =
  ## Connects to the hostname specified by the URL and returns the content of a GET request.
  let resp = await get(client, url)
  return await responseContent(resp)

proc delete*(client: HttpClient | AsyncHttpClient,
             url: Uri | string): Future[Response | AsyncResponse] {.multisync.} =
  ## Connects to the hostname specified by the URL and performs a DELETE request.
  ## This procedure uses httpClient values such as `client.maxRedirects`.
  result = await client.request(url, HttpDelete)

proc deleteContent*(client: HttpClient | AsyncHttpClient,
                    url: Uri | string): Future[string] {.multisync.} =
  ## Connects to the hostname specified by the URL and returns the content of a DELETE request.
  let resp = await delete(client, url)
  return await responseContent(resp)

proc post*(client: HttpClient | AsyncHttpClient, url: Uri | string, body = "",
           multipart: MultipartData = nil): Future[Response | AsyncResponse]
           {.multisync.} =
  ## Connects to the hostname specified by the URL and performs a POST request.
  ## This procedure uses httpClient values such as `client.maxRedirects`.
  result = await client.request(url, HttpPost, body, multipart=multipart)

proc postContent*(client: HttpClient | AsyncHttpClient, url: Uri | string, body = "",
                  multipart: MultipartData = nil): Future[string]
                  {.multisync.} =
  ## Connects to the hostname specified by the URL and returns the content of a POST request.
  let resp = await post(client, url, body, multipart)
  return await responseContent(resp)

proc put*(client: HttpClient | AsyncHttpClient, url: Uri | string, body = "",
          multipart: MultipartData = nil): Future[Response | AsyncResponse]
          {.multisync.} =
  ## Connects to the hostname specified by the URL and performs a PUT request.
  ## This procedure uses httpClient values such as `client.maxRedirects`.
  result = await client.request(url, HttpPut, body, multipart=multipart)

proc putContent*(client: HttpClient | AsyncHttpClient, url: Uri | string, body = "",
                 multipart: MultipartData = nil): Future[string] {.multisync.} =
  ## Connects to the hostname specified by the URL andreturns the content of a PUT request.
  let resp = await put(client, url, body, multipart)
  return await responseContent(resp)

proc patch*(client: HttpClient | AsyncHttpClient, url: Uri | string, body = "",
            multipart: MultipartData = nil): Future[Response | AsyncResponse]
            {.multisync.} =
  ## Connects to the hostname specified by the URL and performs a PATCH request.
  ## This procedure uses httpClient values such as `client.maxRedirects`.
  result = await client.request(url, HttpPatch, body, multipart=multipart)

proc patchContent*(client: HttpClient | AsyncHttpClient, url: Uri | string, body = "",
                   multipart: MultipartData = nil): Future[string]
                  {.multisync.} =
  ## Connects to the hostname specified by the URL and returns the content of a PATCH request.
  let resp = await patch(client, url, body, multipart)
  return await responseContent(resp)

proc downloadFile*(client: HttpClient, url: Uri | string, filename: string) =
  ## Downloads `url` and saves it to `filename`.
  client.getBody = false
  defer:
    client.getBody = true
  let resp = client.get(url)
  
  if resp.code.is4xx or resp.code.is5xx:
    raise newException(HttpRequestError, resp.status)

  client.bodyStream = newFileStream(filename, fmWrite)
  if client.bodyStream.isNil:
    fileError("Unable to open file")
  parseBody(client, resp.headers, resp.version)
  client.bodyStream.close()

proc downloadFileEx(client: AsyncHttpClient,
                    url: Uri | string, filename: string): Future[void] {.async.} =
  ## Downloads `url` and saves it to `filename`.
  client.getBody = false
  let resp = await client.get(url)
  
  if resp.code.is4xx or resp.code.is5xx:
    raise newException(HttpRequestError, resp.status)

  client.bodyStream = newFutureStream[string]("downloadFile")
  var file = openAsync(filename, fmWrite)
  defer: file.close()
  # Let `parseBody` write response data into client.bodyStream in the
  # background.
  let parseBodyFut = parseBody(client, resp.headers, resp.version)
  parseBodyFut.addCallback do():
    if parseBodyFut.failed:
      client.bodyStream.fail(parseBodyFut.error)
  # The `writeFromStream` proc will complete once all the data in the
  # `bodyStream` has been written to the file.
  await file.writeFromStream(client.bodyStream)

proc downloadFile*(client: AsyncHttpClient, url: Uri | string,
                   filename: string): Future[void] =
  result = newFuture[void]("downloadFile")
  try:
    result = downloadFileEx(client, url, filename)
  except Exception as exc:
    result.fail(exc)
  finally:
    result.addCallback(
      proc () = client.getBody = true
    )
