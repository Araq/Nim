#
#
#            Nim's Runtime Library
#        (c) Copyright 2022 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module contains system facilities for reading command
## line parameters.

## **See also:**
## * `parseopt module <parseopt.html>`_ for command-line parser beyond
##   `parseCmdLine proc`_


include system/inclrtl

when defined(nimPreviewSlimSystem):
  import std/widestrs

when defined(nodejs):
  from std/private/oscommon import ReadDirEffect


const weirdTarget = defined(nimscript) or defined(js)


when weirdTarget:
  discard
elif defined(windows):
  import std/winlean
elif defined(posix):
  import std/posix


# Needed by windows in order to obtain the command line for targets
# other than command line targets
when defined(windows) and not weirdTarget:
  template getCommandLine*(): untyped = getCommandLineW()


proc parseCmdLine*(c: string): seq[string] {.
  noSideEffect, rtl, extern: "nos$1".} =
  ## Splits a `command line`:idx: into several components.
  ##
  ## **Note**: This proc is only occasionally useful, better use the
  ## `parseopt module <parseopt.html>`_.
  ##
  ## On Windows, it uses the `following parsing rules
  ## <https://msdn.microsoft.com/en-us/library/17w5ykft.aspx>`_:
  ##
  ## * Arguments are delimited by white space, which is either a space or a tab.
  ## * The caret character (^) is not recognized as an escape character or
  ##   delimiter. The character is handled completely by the command-line parser
  ##   in the operating system before being passed to the argv array in the
  ##   program.
  ## * A string surrounded by double quotation marks ("string") is interpreted
  ##   as a single argument, regardless of white space contained within. A
  ##   quoted string can be embedded in an argument.
  ## * A double quotation mark preceded by a backslash (\") is interpreted as a
  ##   literal double quotation mark character (").
  ## * Backslashes are interpreted literally, unless they immediately precede
  ##   a double quotation mark.
  ## * If an even number of backslashes is followed by a double quotation mark,
  ##   one backslash is placed in the argv array for every pair of backslashes,
  ##   and the double quotation mark is interpreted as a string delimiter.
  ## * If an odd number of backslashes is followed by a double quotation mark,
  ##   one backslash is placed in the argv array for every pair of backslashes,
  ##   and the double quotation mark is "escaped" by the remaining backslash,
  ##   causing a literal double quotation mark (") to be placed in argv.
  ##
  ## On Posix systems, it uses the following parsing rules:
  ## Components are separated by whitespace unless the whitespace
  ## occurs within ``"`` or ``'`` quotes.
  ##
  ## See also:
  ## * `parseopt module <parseopt.html>`_
  ## * `paramCount proc`_
  ## * `paramStr proc`_
  ## * `commandLineParams proc`_

  result = @[]
  var i = 0
  var a = ""
  while true:
    setLen(a, 0)
    # eat all delimiting whitespace
    while i < c.len and c[i] in {' ', '\t', '\l', '\r'}: inc(i)
    if i >= c.len: break
    when defined(windows):
      # parse a single argument according to the above rules:
      var inQuote = false
      while i < c.len:
        case c[i]
        of '\\':
          var j = i
          while j < c.len and c[j] == '\\': inc(j)
          if j < c.len and c[j] == '"':
            for k in 1..(j-i) div 2: a.add('\\')
            if (j-i) mod 2 == 0:
              i = j
            else:
              a.add('"')
              i = j+1
          else:
            a.add(c[i])
            inc(i)
        of '"':
          inc(i)
          if not inQuote: inQuote = true
          elif i < c.len and c[i] == '"':
            a.add(c[i])
            inc(i)
          else:
            inQuote = false
            break
        of ' ', '\t':
          if not inQuote: break
          a.add(c[i])
          inc(i)
        else:
          a.add(c[i])
          inc(i)
    else:
      case c[i]
      of '\'', '\"':
        var delim = c[i]
        inc(i) # skip ' or "
        while i < c.len and c[i] != delim:
          add a, c[i]
          inc(i)
        if i < c.len: inc(i)
      else:
        while i < c.len and c[i] > ' ':
          add(a, c[i])
          inc(i)
    add(result, move a)

when defined(nimdoc):
  # Common forward declaration docstring block for parameter retrieval procs.
  proc paramCount*(): int {.tags: [ReadIOEffect].} =
    ## Returns the number of `command line arguments`:idx: given to the
    ## application.
    ##
    ## Unlike `argc`:idx: in C, if your binary was called without parameters this
    ## will return zero.
    ## You can query each individual parameter with `paramStr proc`_
    ## or retrieve all of them in one go with `commandLineParams proc`_.
    ##
    ## **Availability**: When generating a dynamic library (see `--app:lib`) on
    ## Posix this proc is not defined.
    ## Test for availability using `declared() <system.html#declared,untyped>`_.
    ##
    ## See also:
    ## * `parseopt module <parseopt.html>`_
    ## * `parseCmdLine proc`_
    ## * `paramStr proc`_
    ## * `commandLineParams proc`_
    ##
    ## **Examples:**
    ##
    ##   ```nim
    ##   when declared(paramCount):
    ##     # Use paramCount() here
    ##   else:
    ##     # Do something else!
    ##   ```

  proc paramStr*(i: int): string {.tags: [ReadIOEffect].} =
    ## Returns the `i`-th `command line argument`:idx: given to the application.
    ##
    ## `i` should be in the range `1..paramCount()`, the `IndexDefect`
    ## exception will be raised for invalid values. Instead of iterating
    ## over `paramCount()`_ with this proc you can
    ## call the convenience `commandLineParams()`_.
    ##
    ## Similarly to `argv`:idx: in C,
    ## it is possible to call `paramStr(0)` but this will return OS specific
    ## contents (usually the name of the invoked executable). You should avoid
    ## this and call `getAppFilename() <os.html#getAppFilename>`_ instead.
    ##
    ## **Availability**: When generating a dynamic library (see `--app:lib`) on
    ## Posix this proc is not defined.
    ## Test for availability using `declared() <system.html#declared,untyped>`_.
    ##
    ## See also:
    ## * `parseopt module <parseopt.html>`_
    ## * `parseCmdLine proc`_
    ## * `paramCount proc`_
    ## * `commandLineParams proc`_
    ## * `getAppFilename proc <os.html#getAppFilename>`_
    ##
    ## **Examples:**
    ##
    ##   ```nim
    ##   when declared(paramStr):
    ##     # Use paramStr() here
    ##   else:
    ##     # Do something else!
    ##   ```

elif defined(nimscript): discard
elif defined(nodejs):
  type Argv = object of JsRoot
  let argv {.importjs: "process.argv".} : Argv
  proc len(argv: Argv): int {.importjs: "#.length".}
  proc `[]`(argv: Argv, i: int): cstring {.importjs: "#[#]".}

  proc paramCount*(): int {.tags: [ReadDirEffect].} =
    result = argv.len - 2

  proc paramStr*(i: int): string {.tags: [ReadIOEffect].} =
    let i = i + 1
    if i < argv.len and i >= 0:
      result = $argv[i]
    else:
      raise newException(IndexDefect, formatErrorIndexBound(i - 1, argv.len - 2))
elif defined(windows):
  # Since we support GUI applications with Nim, we sometimes generate
  # a WinMain entry proc. But a WinMain proc has no access to the parsed
  # command line arguments. The way to get them differs. Thus we parse them
  # ourselves. This has the additional benefit that the program's behaviour
  # is always the same -- independent of the used C compiler.
  var
    ownArgv {.threadvar.}: seq[string]
    ownParsedArgv {.threadvar.}: bool

  proc paramCount*(): int {.rtl, extern: "nos$1", tags: [ReadIOEffect].} =
    # Docstring in nimdoc block.
    if not ownParsedArgv:
      ownArgv = parseCmdLine($getCommandLine())
      ownParsedArgv = true
    result = ownArgv.len-1

  proc paramStr*(i: int): string {.rtl, extern: "nos$1",
    tags: [ReadIOEffect].} =
    # Docstring in nimdoc block.
    if not ownParsedArgv:
      ownArgv = parseCmdLine($getCommandLine())
      ownParsedArgv = true
    if i < ownArgv.len and i >= 0:
      result = ownArgv[i]
    else:
      raise newException(IndexDefect, formatErrorIndexBound(i, ownArgv.len-1))

elif defined(genode):
  proc paramStr*(i: int): string =
    raise newException(OSError, "paramStr is not implemented on Genode")

  proc paramCount*(): int =
    raise newException(OSError, "paramCount is not implemented on Genode")
elif weirdTarget or (defined(posix) and appType == "lib"):
  proc paramStr*(i: int): string {.tags: [ReadIOEffect].} =
    raise newException(OSError, "paramStr is not implemented on current platform")

  proc paramCount*(): int {.tags: [ReadIOEffect].} =
    raise newException(OSError, "paramCount is not implemented on current platform")
elif not defined(createNimRtl) and
  not(defined(posix) and appType == "lib"):
  # On Posix, there is no portable way to get the command line from a DLL.
  var
    cmdCount {.importc: "cmdCount".}: cint
    cmdLine {.importc: "cmdLine".}: cstringArray

  proc paramStr*(i: int): string {.tags: [ReadIOEffect].} =
    # Docstring in nimdoc block.
    if i < cmdCount and i >= 0:
      result = $cmdLine[i]
    else:
      raise newException(IndexDefect, formatErrorIndexBound(i, cmdCount-1))

  proc paramCount*(): int {.tags: [ReadIOEffect].} =
    # Docstring in nimdoc block.
    result = cmdCount-1

when declared(paramCount) or defined(nimdoc):
  proc commandLineParams*(): seq[string] =
    ## Convenience proc which returns the command line parameters.
    ##
    ## This returns **only** the parameters. If you want to get the application
    ## executable filename, call `getAppFilename() <os.html#getAppFilename>`_.
    ##
    ## **Availability**: On Posix there is no portable way to get the command
    ## line from a DLL and thus the proc isn't defined in this environment. You
    ## can test for its availability with `declared()
    ## <system.html#declared,untyped>`_.
    ##
    ## See also:
    ## * `parseopt module <parseopt.html>`_
    ## * `parseCmdLine proc`_
    ## * `paramCount proc`_
    ## * `paramStr proc`_
    ## * `getAppFilename proc <os.html#getAppFilename>`_
    ##
    ## **Examples:**
    ##
    ##   ```nim
    ##   when declared(commandLineParams):
    ##     # Use commandLineParams() here
    ##   else:
    ##     # Do something else!
    ##   ```
    result = @[]
    for i in 1..paramCount():
      result.add(paramStr(i))
else:
  proc commandLineParams*(): seq[string] {.error:
  "commandLineParams() unsupported by dynamic libraries".} =
    discard
