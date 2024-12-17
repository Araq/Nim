#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module provides the standard Nim command line parser.
## It supports one convenience iterator over all command line options and some
## lower-level features.
##
## Supported Syntax
## ================
##
## The following syntax is supported when arguments for the `shortNoVal` and
## `longNoVal` parameters, which are
## `described later<#nimshortnoval-and-nimlongnoval>`_, are not provided:
##
## 1. Short options: `-abcd`, `-e:5`, `-e=5`
## 2. Long options: `--foo:bar`, `--foo=bar`, `--foo`
## 3. Arguments: everything that does not start with a `-`
##
## These three kinds of tokens are enumerated in the
## `CmdLineKind enum<#CmdLineKind>`_.
##
## When option values begin with ':' or '=', they need to be doubled up (as in
## `--delim::`) or alternated (as in `--delim=:`).
##
## The `--` option, commonly used to denote that every token that follows is
## an argument, is interpreted as a long option, and its name is the empty
## string.
##
## Parsing
## =======
##
## Use an `OptParser<#OptParser>`_ to parse command line options. It can be
## created with `initOptParser<#initOptParser,string,set[char],seq[string]>`_,
## and `next<#next,OptParser>`_ advances the parser by one token.
##
## For each token, the parser's `kind`, `key`, and `val` fields give
## information about that token. If the token is a long or short option, `key`
## is the option's name, and  `val` is either the option's value, if provided,
## or the empty string. For arguments, the `key` field contains the argument
## itself, and `val` is unused. To check if the end of the command line has
## been reached, check if `kind` is equal to `cmdEnd`.
##
## Here is an example:
##
##   ```Nim
##   import std/parseopt
##
##   var p = initOptParser("-ab -e:5 --foo --bar=20 file.txt")
##   while true:
##     p.next()
##     case p.kind
##     of cmdEnd: break
##     of cmdShortOption, cmdLongOption:
##       if p.val == "":
##         echo "Option: ", p.key
##       else:
##         echo "Option and value: ", p.key, ", ", p.val
##     of cmdArgument:
##       echo "Argument: ", p.key
##
##   # Output:
##   # Option: a
##   # Option: b
##   # Option and value: e, 5
##   # Option: foo
##   # Option and value: bar, 20
##   # Argument: file.txt
##   ```
##
## The `getopt iterator<#getopt.i,OptParser>`_, which is provided for
## convenience, can be used to iterate through all command line options as well.
##
## To set a default value for a variable assigned through `getopt` and accept arguments from the cmd line.
## Assign the default value to a variable before parsing.
## Then set the variable to the new value while parsing.
##
## Here is an example:
##
##   ```Nim
##   import std/parseopt
##
##   var varName: string = "defaultValue"
##
##   for kind, key, val in getopt():
##     case kind
##     of cmdArgument:
##       discard
##     of cmdLongOption, cmdShortOption:
##       case key:
##       of "varName": # --varName:<value> in the console when executing
##         varName = val # do input sanitization in production systems
##     of cmdEnd:
##       discard
##   ```
##
## `shortNoVal` and `longNoVal`
## ============================
##
## The optional `shortNoVal` and `longNoVal` parameters present in
## `initOptParser<#initOptParser,string,set[char],seq[string]>`_ are for
## specifying which short and long options do not accept values.
##
## When `shortNoVal` is non-empty, users are not required to separate short
## options and their values with a ':' or '=' since the parser knows which
## options accept values and which ones do not. This behavior also applies for
## long options if `longNoVal` is non-empty. For short options, `-j4`
## becomes supported syntax, and for long options, `--foo bar` becomes
## supported. This is in addition to the `previously mentioned
## syntax<#supported-syntax>`_. Users can still separate options and their
## values with ':' or '=', but that becomes optional.
##
## As more options which do not accept values are added to your program,
## remember to amend `shortNoVal` and `longNoVal` accordingly.
##
## The following example illustrates the difference between having an empty
## `shortNoVal` and `longNoVal`, which is the default, and providing
## arguments for those two parameters:
##
##   ```Nim
##   import std/parseopt
##
##   proc printToken(kind: CmdLineKind, key: string, val: string) =
##     case kind
##     of cmdEnd: doAssert(false)  # Doesn't happen with getopt()
##     of cmdShortOption, cmdLongOption:
##       if val == "":
##         echo "Option: ", key
##       else:
##         echo "Option and value: ", key, ", ", val
##     of cmdArgument:
##       echo "Argument: ", key
##
##   let cmdLine = "-j4 --first bar"
##
##   var emptyNoVal = initOptParser(cmdLine)
##   for kind, key, val in emptyNoVal.getopt():
##     printToken(kind, key, val)
##
##   # Output:
##   # Option: j
##   # Option: 4
##   # Option: first
##   # Argument: bar
##
##   var withNoVal = initOptParser(cmdLine, shortNoVal = {'c'},
##                                 longNoVal = @["second"])
##   for kind, key, val in withNoVal.getopt():
##     printToken(kind, key, val)
##
##   # Output:
##   # Option and value: j, 4
##   # Option and value: first, bar
##   ```
##
## See also
## ========
##
## * `os module<os.html>`_ for lower-level command line parsing procs
## * `parseutils module<parseutils.html>`_ for helpers that parse tokens,
##   numbers, identifiers, etc.
## * `strutils module<strutils.html>`_ for common string handling operations
## * `json module<json.html>`_ for a JSON parser
## * `parsecfg module<parsecfg.html>`_ for a configuration file parser
## * `parsecsv module<parsecsv.html>`_ for a simple CSV (comma separated value)
##   parser
## * `parsexml module<parsexml.html>`_ for a XML / HTML parser
## * `other parsers<lib.html#pure-libraries-parsers>`_ for more parsers

{.push debugger: off.}

include "system/inclrtl"

import std/strutils
import std/os

type
  CmdLineKind* = enum ## The detected command line token.
    cmdEnd,           ## End of command line reached
    cmdArgument,      ## An argument such as a filename
    cmdLongOption,    ## A long option such as --option
    cmdShortOption    ## A short option such as -c
  OptParser* = object of RootObj ## \
    ## Implementation of the command line parser.
    ##
    ## To initialize it, use the
    ## `initOptParser proc<#initOptParser,string,set[char],seq[string]>`_.
    pos: int
    inShortState: bool
    allowWhitespaceAfterColon: bool
    shortNoVal: set[char]
    longNoVal: seq[string]
    cmds: seq[string]
    idx: int
    kind*: CmdLineKind           ## The detected command line token
    key*, val*: string           ## Key and value pair; the key is the option
                                 ## or the argument, and the value is not "" if
                                 ## the option was given a value

proc parseWord(s: string, i: int, w: var string,
               delim: set[char] = {'\t', ' '}): int =
  result = i
  if result < s.len and s[result] == '\"':
    inc(result)
    while result < s.len:
      if s[result] == '"':
        inc result
        break
      add(w, s[result])
      inc(result)
  else:
    while result < s.len and s[result] notin delim:
      add(w, s[result])
      inc(result)

proc initOptParser*(cmdline: seq[string], shortNoVal: set[char] = {},
                    longNoVal: seq[string] = @[];
                    allowWhitespaceAfterColon = true): OptParser =
  ## Initializes the command line parser.
  ##
  ## If `cmdline.len == 0`, the real command line as provided by the
  ## `os` module is retrieved instead if it is available. If the
  ## command line is not available, a `ValueError` will be raised.
  ## Behavior of the other parameters remains the same as in
  ## `initOptParser(string, ...)
  ## <#initOptParser,string,set[char],seq[string]>`_.
  ##
  ## See also:
  ## * `getopt iterator<#getopt.i,seq[string],set[char],seq[string]>`_
  runnableExamples:
    var p = initOptParser()
    p = initOptParser(@["--left", "--debug:3", "-l", "-r:2"])
    p = initOptParser(@["--left", "--debug:3", "-l", "-r:2"],
                      shortNoVal = {'l'}, longNoVal = @["left"])
  result = OptParser(pos: 0, idx: 0, inShortState: false,
                    shortNoVal: shortNoVal, longNoVal: longNoVal,
                    allowWhitespaceAfterColon: allowWhitespaceAfterColon
                    )
  if cmdline.len != 0:
    result.cmds = newSeq[string](cmdline.len)
    for i in 0..<cmdline.len:
      result.cmds[i] = cmdline[i]
  else:
    when declared(paramCount):
      when defined(nimscript):
        var ctr = 0
        var firstNimsFound = false
        for i in countup(0, paramCount()):
          if firstNimsFound: 
            result.cmds[ctr] = paramStr(i)
            inc ctr, 1
          if paramStr(i).endsWith(".nims") and not firstNimsFound:
            firstNimsFound = true 
            result.cmds = newSeq[string](paramCount()-i)
      else:
        result.cmds = newSeq[string](paramCount())
        for i in countup(1, paramCount()):
          result.cmds[i-1] = paramStr(i)
    else:
      # we cannot provide this for NimRtl creation on Posix, because we can't
      # access the command line arguments then!
      raiseAssert "empty command line given but" &
        " real command line is not accessible"
  result.kind = cmdEnd
  result.key = ""
  result.val = ""

proc initOptParser*(cmdline = "", shortNoVal: set[char] = {},
                    longNoVal: seq[string] = @[];
                    allowWhitespaceAfterColon = true): OptParser =
  ## Initializes the command line parser.
  ##
  ## If `cmdline == ""`, the real command line as provided by the
  ## `os` module is retrieved instead if it is available. If the
  ## command line is not available, a `ValueError` will be raised.
  ##
  ## `shortNoVal` and `longNoVal` are used to specify which options
  ## do not take values. See the `documentation about these
  ## parameters<#nimshortnoval-and-nimlongnoval>`_ for more information on
  ## how this affects parsing.
  ##
  ## This does not provide a way of passing default values to arguments.
  ##
  ## See also:
  ## * `getopt iterator<#getopt.i,OptParser>`_
  runnableExamples:
    var p = initOptParser()
    p = initOptParser("--left --debug:3 -l -r:2")
    p = initOptParser("--left --debug:3 -l -r:2",
                      shortNoVal = {'l'}, longNoVal = @["left"])

  initOptParser(parseCmdLine(cmdline), shortNoVal, longNoVal, allowWhitespaceAfterColon)

proc handleShortOption(p: var OptParser; cmd: string) =
  var i = p.pos
  p.kind = cmdShortOption
  if i < cmd.len:
    add(p.key, cmd[i])
    inc(i)
  p.inShortState = true
  while i < cmd.len and cmd[i] in {'\t', ' '}:
    inc(i)
    p.inShortState = false
  if i < cmd.len and (cmd[i] in {':', '='} or
      card(p.shortNoVal) > 0 and p.key[0] notin p.shortNoVal):
    if i < cmd.len and cmd[i] in {':', '='}:
      inc(i)
    p.inShortState = false
    while i < cmd.len and cmd[i] in {'\t', ' '}: inc(i)
    p.val = substr(cmd, i)
    p.pos = 0
    inc p.idx
  else:
    p.pos = i
  if i >= cmd.len:
    p.inShortState = false
    p.pos = 0
    inc p.idx

proc next*(p: var OptParser) {.rtl, extern: "npo$1".} =
  ## Parses the next token.
  ##
  ## `p.kind` describes what kind of token has been parsed. `p.key` and
  ## `p.val` are set accordingly.
  runnableExamples:
    var p = initOptParser("--left -r:2 file.txt")
    p.next()
    doAssert p.kind == cmdLongOption and p.key == "left"
    p.next()
    doAssert p.kind == cmdShortOption and p.key == "r" and p.val == "2"
    p.next()
    doAssert p.kind == cmdArgument and p.key == "file.txt"
    p.next()
    doAssert p.kind == cmdEnd

  if p.idx >= p.cmds.len:
    p.kind = cmdEnd
    return

  var i = p.pos
  while i < p.cmds[p.idx].len and p.cmds[p.idx][i] in {'\t', ' '}: inc(i)
  p.pos = i
  setLen(p.key, 0)
  setLen(p.val, 0)
  if p.inShortState:
    p.inShortState = false
    if i >= p.cmds[p.idx].len:
      inc(p.idx)
      p.pos = 0
      if p.idx >= p.cmds.len:
        p.kind = cmdEnd
        return
    else:
      handleShortOption(p, p.cmds[p.idx])
      return

  if i < p.cmds[p.idx].len and p.cmds[p.idx][i] == '-':
    inc(i)
    if i < p.cmds[p.idx].len and p.cmds[p.idx][i] == '-':
      p.kind = cmdLongOption
      inc(i)
      i = parseWord(p.cmds[p.idx], i, p.key, {' ', '\t', ':', '='})
      while i < p.cmds[p.idx].len and p.cmds[p.idx][i] in {'\t', ' '}: inc(i)
      if i < p.cmds[p.idx].len and p.cmds[p.idx][i] in {':', '='}:
        inc(i)
        while i < p.cmds[p.idx].len and p.cmds[p.idx][i] in {'\t', ' '}: inc(i)
        # if we're at the end, use the next command line option:
        if i >= p.cmds[p.idx].len and p.idx < p.cmds.len and
            p.allowWhitespaceAfterColon:
          inc p.idx
          i = 0
        if p.idx < p.cmds.len:
          p.val = p.cmds[p.idx].substr(i)
      elif len(p.longNoVal) > 0 and p.key notin p.longNoVal and p.idx+1 < p.cmds.len:
        p.val = p.cmds[p.idx+1]
        inc p.idx
      else:
        p.val = ""
      inc p.idx
      p.pos = 0
    else:
      p.pos = i
      handleShortOption(p, p.cmds[p.idx])
  else:
    p.kind = cmdArgument
    p.key = p.cmds[p.idx]
    inc p.idx
    p.pos = 0

when declared(quoteShellCommand):
  proc cmdLineRest*(p: OptParser): string {.rtl, extern: "npo$1".} =
    ## Retrieves the rest of the command line that has not been parsed yet.
    ##
    ## See also:
    ## * `remainingArgs proc<#remainingArgs,OptParser>`_
    ##
    ## **Examples:**
    ##   ```Nim
    ##   var p = initOptParser("--left -r:2 -- foo.txt bar.txt")
    ##   while true:
    ##     p.next()
    ##     if p.kind == cmdLongOption and p.key == "":  # Look for "--"
    ##       break
    ##   doAssert p.cmdLineRest == "foo.txt bar.txt"
    ##   ```
    result = p.cmds[p.idx .. ^1].quoteShellCommand

proc remainingArgs*(p: OptParser): seq[string] {.rtl, extern: "npo$1".} =
  ## Retrieves a sequence of the arguments that have not been parsed yet.
  ##
  ## See also:
  ## * `cmdLineRest proc<#cmdLineRest,OptParser>`_
  ##
  ## **Examples:**
  ##   ```Nim
  ##   var p = initOptParser("--left -r:2 -- foo.txt bar.txt")
  ##   while true:
  ##     p.next()
  ##     if p.kind == cmdLongOption and p.key == "":  # Look for "--"
  ##       break
  ##   doAssert p.remainingArgs == @["foo.txt", "bar.txt"]
  ##   ```
  result = @[]
  for i in p.idx..<p.cmds.len: result.add p.cmds[i]

iterator getopt*(p: var OptParser): tuple[kind: CmdLineKind, key,
    val: string] =
  ## Convenience iterator for iterating over the given
  ## `OptParser<#OptParser>`_.
  ##
  ## There is no need to check for `cmdEnd` while iterating. If using `getopt`
  ## with case switching, checking for `cmdEnd` is required.
  ##
  ## See also:
  ## * `initOptParser proc<#initOptParser,string,set[char],seq[string]>`_
  ##
  ## **Examples:**
  ##
  ##   ```Nim
  ##   # these are placeholders, of course
  ##   proc writeHelp() = discard
  ##   proc writeVersion() = discard
  ##
  ##   var filename: string
  ##   var p = initOptParser("--left --debug:3 -l -r:2")
  ##
  ##   for kind, key, val in p.getopt():
  ##     case kind
  ##     of cmdArgument:
  ##       filename = key
  ##     of cmdLongOption, cmdShortOption:
  ##       case key
  ##       of "help", "h": writeHelp()
  ##       of "version", "v": writeVersion()
  ##     of cmdEnd: assert(false) # cannot happen
  ##   if filename == "":
  ##     # no filename has been given, so we show the help
  ##     writeHelp()
  ##   ```
  p.pos = 0
  p.idx = 0
  while true:
    next(p)
    if p.kind == cmdEnd: break
    yield (p.kind, p.key, p.val)

iterator getopt*(cmdline: seq[string] = @[],
                  shortNoVal: set[char] = {}, longNoVal: seq[string] = @[]):
            tuple[kind: CmdLineKind, key, val: string] =
  ## Convenience iterator for iterating over command line arguments.
  ##
  ## This creates a new `OptParser<#OptParser>`_. If no command line
  ## arguments are provided, the real command line as provided by the
  ## `os` module is retrieved instead.
  ##
  ## `shortNoVal` and `longNoVal` are used to specify which options
  ## do not take values. See the `documentation about these
  ## parameters<#nimshortnoval-and-nimlongnoval>`_ for more information on
  ## how this affects parsing.
  ##
  ## There is no need to check for `cmdEnd` while iterating. If using `getopt`
  ## with case switching, checking for `cmdEnd` is required.
  ##
  ## See also:
  ## * `initOptParser proc<#initOptParser,seq[string],set[char],seq[string]>`_
  ##
  ## **Examples:**
  ##
  ##   ```Nim
  ##   # these are placeholders, of course
  ##   proc writeHelp() = discard
  ##   proc writeVersion() = discard
  ##
  ##   var filename: string
  ##   let params = @["--left", "--debug:3", "-l", "-r:2"]
  ##
  ##   for kind, key, val in getopt(params):
  ##     case kind
  ##     of cmdArgument:
  ##       filename = key
  ##     of cmdLongOption, cmdShortOption:
  ##       case key
  ##       of "help", "h": writeHelp()
  ##       of "version", "v": writeVersion()
  ##     of cmdEnd: assert(false) # cannot happen
  ##   if filename == "":
  ##     # no filename has been written, so we show the help
  ##     writeHelp()
  ##   ```
  var p = initOptParser(cmdline, shortNoVal = shortNoVal,
      longNoVal = longNoVal)
  while true:
    next(p)
    if p.kind == cmdEnd: break
    yield (p.kind, p.key, p.val)

{.pop.}
