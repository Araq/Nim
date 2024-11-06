discard """
matrix: "--mm:refc; --mm:orc"
outputsub: ""
"""

import net, nativesockets
import unittest
import std/assertions

block: # isIpAddress tests
  block: # 127.0.0.1 is valid
    check isIpAddress("127.0.0.1") == true

  block: # ipv6 localhost is valid
    check isIpAddress("::1") == true

  block: # fqdn is not an ip address
    check isIpAddress("example.com") == false

  block: # random string is not an ipaddress
    check isIpAddress("foo bar") == false

  block: # 5127.0.0.1 is invalid
    check isIpAddress("5127.0.0.1") == false

  block: # ipv6 is valid
    check isIpAddress("2001:cdba:0000:0000:0000:0000:3257:9652") == true

  block: # invalid ipv6
    check isIpAddress("gggg:cdba:0000:0000:0000:0000:3257:9652") == false


block: # parseIpAddress tests
  block: # 127.0.0.1 is valid
    discard parseIpAddress("127.0.0.1")

  block: # ipv6 localhost is valid
    discard parseIpAddress("::1")

  block: # fqdn is not an ip address
    expect(ValueError):
      discard parseIpAddress("example.com")

  block: # random string is not an ipaddress
    expect(ValueError):
      discard parseIpAddress("foo bar")

  block: # ipv6 is valid
    discard parseIpAddress("2001:cdba:0000:0000:0000:0000:3257:9652")

  block: # invalid ipv6
    expect(ValueError):
      discard parseIpAddress("gggg:cdba:0000:0000:0000:0000:3257:9652")

  block: # ipv4-compatible ipv6 address (embedded ipv4 address)
    check parseIpAddress("::ffff:10.0.0.23") == parseIpAddress("::ffff:0a00:0017")

  block: # octal number in ipv4 address
    expect(ValueError):
      discard parseIpAddress("010.8.8.8")
    expect(ValueError):
      discard parseIpAddress("8.010.8.8")

  block: # hexadecimal number in ipv4 address
    expect(ValueError):
      discard parseIpAddress("0xc0.168.0.1")
    expect(ValueError):
      discard parseIpAddress("192.0xa8.0.1")

  block: # less than 4 numbers in ipv4 address
    expect(ValueError):
      discard parseIpAddress("127.0.1")

  block: # octal number in embedded ipv4 address
    expect(ValueError):
      discard parseIpAddress("::ffff:010.8.8.8")
    expect(ValueError):
      discard parseIpAddress("::ffff:8.010.8.8")

  block: # hexadecimal number in embedded ipv4 address
    expect(ValueError):
      discard parseIpAddress("::ffff:0xc0.168.0.1")
    expect(ValueError):
      discard parseIpAddress("::ffff:192.0xa8.0.1")

  block: # less than 4 numbers in embedded ipv4 address
    expect(ValueError):
      discard parseIpAddress("::ffff:127.0.1")

block: # "IpAddress/Sockaddr conversion"
  proc test(ipaddrstr: string) =
    var ipaddr_1 = parseIpAddress(ipaddrstr)
    # echo ipaddrstr, " ", $ipaddr_1

    doAssert($ipaddrstr == $ipaddr_1)

    var sockaddr: Sockaddr_storage = default(Sockaddr_storage)
    var socklen: SockLen = default(SockLen)
    var ipaddr_2: IpAddress = default(IpAddress)
    var port_2: Port = default(Port)

    toSockAddr(ipaddr_1, Port(0), sockaddr, socklen)
    fromSockAddr(sockaddr, socklen, ipaddr_2, port_2)

    doAssert(ipaddrstr == $ipaddr_1)

    doAssert(ipaddr_1 == ipaddr_2)
    doAssert($ipaddr_1 == $ipaddr_2)

    if sockaddr.ss_family.cint == AF_INET.toInt:
      var sockaddr4: Sockaddr_in = default(Sockaddr_in)
      copyMem(addr sockaddr4, addr sockaddr, sizeof(sockaddr4))
      fromSockAddr(sockaddr4, socklen, ipaddr_2, port_2)
    elif sockaddr.ss_family.cint == AF_INET6.toInt:
      var sockaddr6: Sockaddr_in6 = default(Sockaddr_in6)
      copyMem(addr sockaddr6, addr sockaddr, sizeof(sockaddr6))
      fromSockAddr(sockaddr6, socklen, ipaddr_2, port_2)

    doAssert(ipaddr_1 == ipaddr_2)
    doAssert($ipaddr_1 == $ipaddr_2)


  # ipv6 address of example.com
  test("2606:2800:220:1:248:1893:25c8:1946")
  # ipv6 address of localhost
  test("::1")
  # ipv4 address of example.com
  test("93.184.216.34")
  # ipv4 address of localhost
  test("127.0.0.1")
