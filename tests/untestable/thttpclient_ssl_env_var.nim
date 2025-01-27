#
#            Nim - SSL integration tests
#        (c) Copyright 2017 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
## Warning: this test performs external networking.
## Compile with:
## ./bin/nim c -d:ssl -p:. tests/untestable/thttpclient_ssl_env_var.nim
##
## Test with:
##  SSL_CERT_FILE=BogusInexistentFileName tests/untestable/thttpclient_ssl_env_var
##  SSL_CERT_DIR=BogusInexistentDirName tests/untestable/thttpclient_ssl_env_var

import httpclient, unittest, os
from net import newSocket, newContext, wrapSocket, connect, close, Port,
  CVerifyPeerUseEnvVars
from strutils import contains

const
  good = "https://google.com/"


suite "SSL certificate check":

  test "httpclient with inexistent file":
    if existsEnv("SSL_CERT_FILE"):
      var ctx = newContext(verifyMode=CVerifyPeerUseEnvVars)
      var client = newHttpClient(sslContext=ctx)
      checkpoint("Client created")
      check client.getContent("https://google.com").contains("doctype")
      checkpoint("Google ok")
      try:
        let a = $client.getContent(good)
        echo "Connection should have failed"
        fail()
      except:
        echo getCurrentExceptionMsg()
        check getCurrentExceptionMsg().contains("certificate verify failed")

    elif existsEnv("SSL_CERT_DIR"):
      try:
        var ctx = newContext(verifyMode=CVerifyPeerUseEnvVars)
        var client = newHttpClient(sslContext=ctx)
        echo "Should have raised 'No SSL/TLS CA certificates found.'"
        fail()
      except:
        check getCurrentExceptionMsg() ==
          "No SSL/TLS CA certificates found."

  test "net socket with inexistent file":
    if existsEnv("SSL_CERT_FILE"):
      var sock = newSocket()
      var ctx = newContext(verifyMode=CVerifyPeerUseEnvVars)
      ctx.wrapSocket(sock)
      checkpoint("Socket created")
      when false: # badssl tests disabled indefinitely
        try:
          sock.connect("expired.badssl.com", 443.Port)
          fail()
        except:
          sock.close
          check getCurrentExceptionMsg().contains("certificate verify failed")

    elif existsEnv("SSL_CERT_DIR"):
      var sock = newSocket()
      checkpoint("Socket created")
      try:
        var ctx = newContext(verifyMode=CVerifyPeerUseEnvVars) # raises here
        fail()
      except:
        check getCurrentExceptionMsg() ==
          "No SSL/TLS CA certificates found."
