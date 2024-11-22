discard """
  cmd: "nim $target --mm:refc -d:ssl $options $file"
  disabled: "openbsd"
  retries: 2
"""

#            Nim - Basic SSL integration tests
#        (c) Copyright 2018 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
## Warning: this test performs local networking.
## Test with:
## ./bin/nim c -d:ssl -p:. --threads:on -r tests/stdlib/thttpclient_ssl.nim


from stdtest/testutils import disableSSLTesting

when not defined(windows) and not disableSSLTesting():
  # Disabled on Windows due to old OpenSSL version
  import std/[formatfloat, syncio]
  import
    httpclient,
    net,
    openssl,
    os,
    strutils,
    threadpool,
    times,
    unittest

  # bogus self-signed certificate
  const
    certFile = "tests/stdlib/thttpclient_ssl_cert.pem"
    keyFile = "tests/stdlib/thttpclient_ssl_key.pem"

  proc log(msg: string) =
    when defined(ssldebug):
      echo "    [" & $epochTime() & "] " & msg
    # FIXME
    echo "    [" & $epochTime() & "] " & msg
    discard

  proc runServer(port: Port): bool {.thread.} =
    ## Run a trivial HTTPS server in a {.thread.}
    ## Exit after serving one request

    var socket = newSocket()
    socket.setSockOpt(OptReusePort, true)
    socket.bindAddr(port)

    var ctx = newContext(certFile=certFile, keyFile=keyFile)

    ##  Handle one connection
    socket.listen()

    var client: Socket
    var address = ""

    log "server: ready"
    socket.acceptAddr(client, address)
    log "server: incoming connection"

    var ssl: SslPtr = SSL_new(ctx.context)
    discard SSL_set_fd(ssl, client.getFd())
    log "server: accepting connection"
    ErrClearError()
    if SSL_accept(ssl) <= 0:
      ERR_print_errors_fp(stderr)
    else:
      const reply = "HTTP/1.0 200 OK\r\nServer: test\r\nContent-type: text/html\r\nContent-Length: 0\r\n\r\n"
      log "server: sending reply"
      discard SSL_write(ssl, reply.cstring, reply.len)

    log "server: receiving a line"
    let line = client.recvLine()
    log "server: received $# bytes" % $line.len
    log "closing"
    SSL_free(ssl)
    close(client)
    close(socket)
    log "server: exited"


  suite "SSL self signed certificate check":

    test "TCP socket":
      const port = 12347.Port
      let t = spawn runServer(port)
      sleep(100)
      var sock = newSocket()
      var ctx = newContext()
      ctx.wrapSocket(sock)
      try:
        log "client: connect"
        sock.connect("127.0.0.1", port)
        fail()
      except:
        let msg = getCurrentExceptionMsg()
        check(msg.contains("certificate verify failed"))

    test "HttpClient default: no check":
      const port = 12345.Port
      let t = spawn runServer(port)
      sleep(100)

      var client = newHttpClient(sslContext=newContext(verifyMode=CVerifyNone))
      try:
        log "client: connect"
        discard client.getContent("https://127.0.0.1:12345")
      except:
        let msg = getCurrentExceptionMsg()
        log "client: unexpected exception: " & msg
        fail()

    test "HttpClient with CVerifyPeer":
      const port = 12346.Port
      let t = spawn runServer(port)
      sleep(100)

      var client = newHttpClient(sslContext=newContext(verifyMode=CVerifyPeer))
      try:
        log "client: connect"
        discard client.getContent("https://127.0.0.1:12346")
        log "getContent should have raised an exception"
        fail()
      except:
        let msg = getCurrentExceptionMsg()
        log "client: exception: " & msg
        # SSL_shutdown:shutdown while in init
        if not (msg.contains("alert number 48") or
          msg.contains("certificate verify failed")):
          echo "CVerifyPeer exception: " & msg
          check(false)

    test "HttpClient with CVerifyPeerUseEnvVars":
      const port = 12346.Port
      let t = spawn runServer(port)
      sleep(100)

      putEnv("SSL_CERT_FILE", getCurrentDir() / certFile)
      var client = newHttpClient(sslContext=newContext(verifyMode=CVerifyPeerUseEnvVars))
      try:
        log "client: connect"
        discard client.getContent("https://127.0.0.1:12346")
      except:
        let msg = getCurrentExceptionMsg()
        log "client: exception: " & msg
        log "getContent should not have raised an exception"
        fail()
