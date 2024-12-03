#
#
#            Nim's Runtime Library
#        (c) Copyright 2016 Joey Payne
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module contains various string utility routines that are uncommonly
## used in comparison to the ones in `strutils <strutils.html>`_.

import std/strutils

func expandTabs*(s: string, tabSize: int = 8): string =
  ## Expands tab characters in `s`, replacing them by spaces.
  ##
  ## The amount of inserted spaces for each tab character is the difference
  ## between the current column number and the next tab position. Tab positions
  ## occur every `tabSize` characters.
  ## The column number starts at 0 and is increased with every single character
  ## and inserted space, except for newline, which resets the column number
  ## back to 0.
  runnableExamples:
    doAssert expandTabs("\t", 4) == "    "
    doAssert expandTabs("\tfoo\t", 4) == "    foo "
    doAssert expandTabs("a\tb\n\txy\t", 3) == "a  b\n   xy "

  result = newStringOfCap(s.len + s.len shr 2)

  template addSpaces(n) =
    for _ in 1..n:
      result.add(' ')
    pos += n

  var pos = 0
  let denominator = if tabSize > 0: tabSize else: 1
  for c in s:
    if c == '\t':
      let numSpaces = tabSize - pos mod denominator
      addSpaces(numSpaces)
    else:
      result.add(c)
      pos += 1
    if c == '\l':
      pos = 0

func partition*(s: string, sep: string,
                right: bool = false): (string, string, string) =
  ## Splits the string at the first (if `right` is false)
  ## or last (if `right` is true) occurrence of `sep` into a 3-tuple.
  ##
  ## Returns a 3-tuple of strings, `(beforeSep, sep, afterSep)` or
  ## `(s, "", "")` if `sep` is not found and `right` is false or
  ## `("", "", s)` if `sep` is not found and `right` is true.
  ##
  ## **See also:**
  ## * `rpartition proc <#rpartition,string,string>`_
  runnableExamples:
    doAssert partition("foo:bar:baz", ":") == ("foo", ":", "bar:baz")
    doAssert partition("foo:bar:baz", ":", right = true) == ("foo:bar", ":", "baz")
    doAssert partition("foobar", ":") == ("foobar", "", "")
    doAssert partition("foobar", ":", right = true) == ("", "", "foobar")

  let position = if right: s.rfind(sep) else: s.find(sep)
  if position != -1:
    return (s[0 ..< position], sep, s[position + sep.len ..< s.len])
  return if right: ("", "", s) else: (s, "", "")

func rpartition*(s: string, sep: string): (string, string, string) =
  ## Splits the string at the last occurrence of `sep` into a 3-tuple.
  ##
  ## Returns a 3-tuple of strings, `(beforeSep, sep, afterSep)` or
  ## `("", "", s)` if `sep` is not found. This is the same as
  ## `partition(s, sep, right = true)`.
  ##
  ## **See also:**
  ## * `partition proc <#partition,string,string,bool>`_
  runnableExamples:
    doAssert rpartition("foo:bar:baz", ":") == ("foo:bar", ":", "baz")
    doAssert rpartition("foobar", ":") == ("", "", "foobar")

  partition(s, sep, right = true)
