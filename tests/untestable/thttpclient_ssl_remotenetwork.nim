#
#
#            Nim - SSL integration tests
#        (c) Copyright 2017 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
## Test with:
## nim r --putenv:NIM_TESTAMENT_REMOTE_NETWORKING:1 -d:ssl -p:. --threads:on tests/untestable/thttpclient_ssl_remotenetwork.nim
##
## See https://github.com/FedericoCeratto/ssl-comparison/blob/master/README.md
## for a comparison with other clients.

from stdtest/testutils import enableRemoteNetworking
when enableRemoteNetworking and (defined(nimTestsEnableFlaky) or not defined(windows) and not defined(openbsd)):
  # Not supported on Windows due to old openssl version
  import
    httpclient,
    net,
    strutils,
    threadpool,
    unittest


  type
    # bad and dubious tests should not pass SSL validation
    # "_broken" mark the test as skipped. Some tests have different
    # behavior depending on OS and SSL version!
    # TODO: chase and fix the broken tests
    Category = enum
      good, bad, dubious, good_broken, bad_broken, dubious_broken
    CertTest = tuple[url:string, category:Category, desc: string]

  # badssl certs sometimes expire, set to false when that happens
  # badssl now disabled indefinitely
  when false:
    const certificate_tests: array[0..54, CertTest] = [
      ("https://wrong.host.badssl.com/", bad, "wrong.host"),
      ("https://captive-portal.badssl.com/", bad, "captive-portal"),
      ("https://expired.badssl.com/", bad, "expired"),
      ("https://google.com/", good, "good"),
      ("https://self-signed.badssl.com/", bad, "self-signed"),
      ("https://untrusted-root.badssl.com/", bad, "untrusted-root"),
      ("https://revoked.badssl.com/", bad_broken, "revoked"),
      ("https://pinning-test.badssl.com/", bad_broken, "pinning-test"),
      ("https://no-common-name.badssl.com/", bad, "no-common-name"),
      ("https://no-subject.badssl.com/", bad, "no-subject"),
      ("https://sha1-intermediate.badssl.com/", bad, "sha1-intermediate"),
      ("https://sha256.badssl.com/", good, "sha256"),
      ("https://sha384.badssl.com/", bad, "sha384"),
      ("https://sha512.badssl.com/", bad, "sha512"),
      ("https://1000-sans.badssl.com/", bad, "1000-sans"),
      ("https://10000-sans.badssl.com/", good_broken, "10000-sans"),
      ("https://ecc256.badssl.com/", good_broken, "ecc256"),
      ("https://ecc384.badssl.com/", good_broken, "ecc384"),
      ("https://rsa2048.badssl.com/", good, "rsa2048"),
      ("https://rsa8192.badssl.com/", dubious_broken, "rsa8192"),
      ("http://http.badssl.com/", good, "regular http"),
      ("https://http.badssl.com/", bad_broken, "http on https URL"),  # FIXME
      ("https://cbc.badssl.com/", dubious, "cbc"),
      ("https://rc4-md5.badssl.com/", bad, "rc4-md5"),
      ("https://rc4.badssl.com/", bad, "rc4"),
      ("https://3des.badssl.com/", bad, "3des"),
      ("https://null.badssl.com/", bad, "null"),
      ("https://mozilla-old.badssl.com/", bad_broken, "mozilla-old"),
      ("https://mozilla-intermediate.badssl.com/", dubious_broken, "mozilla-intermediate"),
      ("https://mozilla-modern.badssl.com/", good, "mozilla-modern"),
      ("https://dh480.badssl.com/", bad, "dh480"),
      ("https://dh512.badssl.com/", bad, "dh512"),
      ("https://dh1024.badssl.com/", dubious_broken, "dh1024"),
      ("https://dh2048.badssl.com/", good, "dh2048"),
      ("https://dh-small-subgroup.badssl.com/", bad_broken, "dh-small-subgroup"),
      ("https://dh-composite.badssl.com/", bad_broken, "dh-composite"),
      ("https://static-rsa.badssl.com/", dubious, "static-rsa"),
      ("https://tls-v1-0.badssl.com:1010/", dubious, "tls-v1-0"),
      ("https://tls-v1-1.badssl.com:1011/", dubious, "tls-v1-1"),
      ("https://invalid-expected-sct.badssl.com/", bad, "invalid-expected-sct"),
      ("https://hsts.badssl.com/", good, "hsts"),
      ("https://upgrade.badssl.com/", good, "upgrade"),
      ("https://preloaded-hsts.badssl.com/", good, "preloaded-hsts"),
      ("https://subdomain.preloaded-hsts.badssl.com/", bad, "subdomain.preloaded-hsts"),
      ("https://https-everywhere.badssl.com/", good, "https-everywhere"),
      ("https://long-extended-subdomain-name-containing-many-letters-and-dashes.badssl.com/", good,
        "long-extended-subdomain-name-containing-many-letters-and-dashes"),
      ("https://longextendedsubdomainnamewithoutdashesinordertotestwordwrapping.badssl.com/", good,
        "longextendedsubdomainnamewithoutdashesinordertotestwordwrapping"),
      ("https://superfish.badssl.com/", bad, "(Lenovo) Superfish"),
      ("https://edellroot.badssl.com/", bad, "(Dell) eDellRoot"),
      ("https://dsdtestprovider.badssl.com/", bad, "(Dell) DSD Test Provider"),
      ("https://preact-cli.badssl.com/", bad, "preact-cli"),
      ("https://webpack-dev-server.badssl.com/", bad, "webpack-dev-server"),
      ("https://mitm-software.badssl.com/", bad, "mitm-software"),
      ("https://sha1-2016.badssl.com/", dubious, "sha1-2016"),
      ("https://sha1-2017.badssl.com/", bad, "sha1-2017"),
    ]
  else:
    const certificate_tests: array[0..0, CertTest] = [
      ("https://google.com/", good, "good")
    ]


  template evaluate(exception_msg: string, category: Category, desc: string) =
    # Evaluate test outcome. Tests flagged as `_broken` are evaluated and skipped
    let raised = (exception_msg.len > 0)
    let should_not_raise = category in {good, dubious_broken, bad_broken}
    if should_not_raise xor raised:
      # we are seeing a known behavior
      if category in {good_broken, dubious_broken, bad_broken}:
        skip()
      if raised:
        # check exception_msg == "No SSL certificate found." or
        doAssert exception_msg == "No SSL certificate found." or
          exception_msg == "SSL Certificate check failed." or
          exception_msg.contains("certificate verify failed") or
          exception_msg.contains("key too small") or
          exception_msg.contains("alert handshake failure") or
          exception_msg.contains("bad dh p length") or
          # TODO: This one should only triggers for 10000-sans
          exception_msg.contains("excessive message size"), exception_msg

    else:
      # this is unexpected
      var fatal = true
      var msg = ""
      if raised:
        msg = "         $# ($#) raised: $#" % [desc, $category, exception_msg]
        if "500 Internal Server Error" in exception_msg:
          # refs https://github.com/nim-lang/Nim/issues/16338#issuecomment-804300278
          # we got: `good (good) raised: 500 Internal Server Error`
          fatal = false
          msg.add " (http 500 => assuming this is not our problem)"
      else:
        msg = "         $# ($#) did not raise" % [desc, $category]

      if category in {good, dubious, bad} and fatal:
        echo "D20210322T121353: error: " & msg
        fail()
      else:
        echo "D20210322T121353: warning: " & msg


  suite "SSL certificate check - httpclient":

    for i, ct in certificate_tests:

      test ct.desc:
        var ctx = newContext(verifyMode=CVerifyPeer)
        var client = newHttpClient(sslContext=ctx)
        let exception_msg =
          try:
            let a = $client.getContent(ct.url)
            ""
          except:
            getCurrentExceptionMsg()

        evaluate(exception_msg, ct.category, ct.desc)



  # threaded tests


  type
    TTOutcome = ref object
      desc, exception_msg: string
      category: Category

  proc run_t_test(ct: CertTest): TTOutcome {.thread.} =
    ## Run test in a {.thread.} - return by ref
    result = TTOutcome(desc:ct.desc, exception_msg:"", category: ct.category)
    try:
      var ctx = newContext(verifyMode=CVerifyPeer)
      var client = newHttpClient(sslContext=ctx)
      let a = $client.getContent(ct.url)
    except:
      result.exception_msg = getCurrentExceptionMsg()


  suite "SSL certificate check - httpclient - threaded":
    when defined(nimTestsEnableFlaky) or not defined(linux): # xxx pending bug #16338
      # Spawn threads before the "test" blocks
      var outcomes = newSeq[FlowVar[TTOutcome]](certificate_tests.len)
      for i, ct in certificate_tests:
        let t = spawn run_t_test(ct)
        outcomes[i] = t

      # create "test" blocks and handle thread outputs
      for t in outcomes:
        let outcome = ^t  # wait for a thread to terminate
        test outcome.desc:
          evaluate(outcome.exception_msg, outcome.category, outcome.desc)
    else:
      echo "skipped test"

  # net tests


  type NetSocketTest = tuple[hostname: string, port: Port, category:Category, desc: string]
  # badssl certs sometimes expire, set to false when that happens
  when false:
    const net_tests:array[0..3, NetSocketTest] = [
      ("imap.gmail.com", 993.Port, good, "IMAP"),
      ("wrong.host.badssl.com", 443.Port, bad, "wrong.host"),
      ("captive-portal.badssl.com", 443.Port, bad, "captive-portal"),
      ("expired.badssl.com", 443.Port, bad, "expired"),
    ]
  else:
    const net_tests: array[0..0, NetSocketTest] = [
      ("imap.gmail.com", 993.Port, good, "IMAP")
    ]
  # TODO: ("null.badssl.com", 443.Port, bad_broken, "null"),


  suite "SSL certificate check - sockets":

    for ct in net_tests:

      test ct.desc:

        var sock = newSocket()
        var ctx = newContext()
        ctx.wrapSocket(sock)
        let exception_msg =
          try:
            sock.connect(ct.hostname, ct.port)
            ""
          except:
            getCurrentExceptionMsg()

        evaluate(exception_msg, ct.category, ct.desc)
