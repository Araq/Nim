#
#            Nim - SSL integration tests
#        (c) Copyright 2017 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
## Compile and run with:
## nim r --putenv:NIM_TESTAMENT_REMOTE_NETWORKING:1 -d:nimDisableCertificateValidation -d:ssl -p:. tests/untestable/thttpclient_ssl_disabled.nim

from stdtest/testutils import enableRemoteNetworking
# badssl tests disabled indefinitely
when false and enableRemoteNetworking and (defined(nimTestsEnableFlaky) or not defined(openbsd)):
  import httpclient, net, unittest

  const expired = "https://expired.badssl.com/"

  doAssert defined(nimDisableCertificateValidation)

  suite "SSL certificate check - disabled":

    test "httpclient in insecure mode":
      var ctx = newContext(verifyMode = CVerifyPeer)
      var client = newHttpClient(sslContext = ctx)
      let a = $client.getContent(expired)

    test "httpclient in insecure mode":
      var ctx = newContext(verifyMode = CVerifyPeerUseEnvVars)
      var client = newHttpClient(sslContext = ctx)
      let a = $client.getContent(expired)

    test "net socket in insecure mode":
      var sock = newSocket()
      var ctx = newContext(verifyMode = CVerifyPeerUseEnvVars)
      ctx.wrapSocket(sock)
      sock.connect("expired.badssl.com", 443.Port)
      sock.close
