import unittest
include nre

from std/pcre2 import nil

block: # Test NRE initialization
  block: # correct initialization
    check(re("[0-9]+") != nil)
    check(re("(?i)[0-9]+") != nil)

  block: # options
    check(extractOptions("(*NEVER_UTF)") ==
          ("", pcre2.NEVER_UTF, false))
    check(extractOptions("(*UTF8)(*ANCHORED)(*UCP)z") ==
          ("(*UTF8)(*UCP)z", pcre2.ANCHORED, false))
    # check(extractOptions("(*ANCHORED)(*UTF8)(*JAVASCRIPT_COMPAT)z") ==
    #       ("(*UTF8)z", pcre2.ANCHORED or pcre2.JAVASCRIPT_COMPAT, true))

    # check(extractOptions("(*NO_STUDY)(") == ("(", 0'u32))

    check(extractOptions("(*LIMIT_MATCH=6)(*ANCHORED)z") ==
          ("(*LIMIT_MATCH=6)z", pcre2.ANCHORED, false))

  block: # incorrect options
    for s in ["CR", "(CR", "(*CR", "(*abc)", "(*abc)CR",
              "(?i)",
              "(*LIMIT_MATCH=5", "(*NO_AUTO_POSSESS=5)"]:
      let ss = s & "(*NEVER_UTF)"
      check(extractOptions(ss) == (ss, 0'u32, false))

  block: # invalid regex
    # expect(SyntaxError): discard re("[0-9")
    try:
      discard re("[0-9")
    except SyntaxError:
      let ex = SyntaxError(getCurrentException())
      check(ex.pos == 4)
      check(ex.pattern == "[0-9")
