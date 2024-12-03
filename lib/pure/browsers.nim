#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements a simple proc for opening URLs with the user's
## default browser.
##
## Unstable API.

import std/private/since # used by the deprecated `openDefaultBrowser()`

import std/strutils

when defined(nimPreviewSlimSystem):
  import std/assertions

when defined(windows):
  import std/winlean
  when defined(nimPreviewSlimSystem):
    import std/widestrs
  from std/os import absolutePath
else:
  import std/os
  when not defined(osx):
    import std/osproc

const osOpenCmd* =
  when defined(macos) or defined(macosx) or defined(windows): "open" else: "xdg-open" ## \
  ## Alias for the operating system specific *"open"* command,
  ## `"open"` on OSX, MacOS and Windows, `"xdg-open"` on Linux, BSD, etc.

proc prepare(s: string): string =
  if s.contains("://"):
    result = s
  else:
    result = "file://" & absolutePath(s)

proc openDefaultBrowserRaw(url: string) =
  ## note the url argument should be alreadly prepared, i.e. the url is passed "AS IS"

  when defined(windows):
    var o = newWideCString(osOpenCmd)
    var u = newWideCString(url)
    discard shellExecuteW(0'i32, o, u, nil, nil, SW_SHOWNORMAL)
  elif defined(macosx):
    discard execShellCmd(osOpenCmd & " " & quoteShell(url))
  else:
    var u = quoteShell(url)
    if execShellCmd(osOpenCmd & " " & u) == 0: return
    for b in getEnv("BROWSER").split(PathSep):
      try:
        # we use `startProcess` here because we don't want to block!
        discard startProcess(command = b, args = [url], options = {poUsePath})
        return
      except OSError:
        discard

proc openDefaultBrowser*(url: string) =
  ## Opens `url` with the user's default browser. This does not block.
  ## The URL must not be empty string, to open on a blank page see `openDefaultBrowser()`.
  ##
  ## Under Windows, `ShellExecute` is used. Under Mac OS X the `open`
  ## command is used. Under Unix, it is checked if `xdg-open` exists and
  ## used if it does. Otherwise the environment variable `BROWSER` is
  ## used to determine the default browser to use.
  ##
  ## This proc doesn't raise an exception on error, beware.
  ##
  ##   ```nim
  ##   block: openDefaultBrowser("https://nim-lang.org")
  ##   ```
  doAssert url.len > 0, "URL must not be empty string"
  openDefaultBrowserRaw(url)

proc openDefaultBrowser*() {.since: (1, 1), deprecated: 
  "not implemented, please open with a specific url instead".} =
  ## Intends to open the user's default browser without any `url` (blank page).
  ## This does not block.
  ## Intends to implement IETF RFC-6694 Section 3,
  ## ("about:blank" is reserved for a blank page).
  ##
  ## Beware that this intended behavior is **not** implemented and 
  ## considered not worthy to implement here.
  ##
  ## The following describes the behavior of current implementation:
  ## 
  ##  - Under Windows, this will only cause a pop-up dialog \
  ## asking the assocated application with `about` \
  ## (as Windows simply treats `about:` as a protocol like `http`).
  ##  - Under Mac OS X the `open "about:blank"` command is used.
  ##  - Under Unix, it is checked if `xdg-open` exists and used \
  ## if it does and open the application assocated with `text/html` mime \
  ## (not `x-scheme-handler/http`, so maybe html-viewer \
  ## other than your default browser is opened). \
  ## Otherwise the environment variable `BROWSER` is used \
  ## to determine the default browser to use.
  ##
  ## This proc doesn't raise an exception on error, beware.
  ##
  ##   ```nim
  ##   block: openDefaultBrowser()
  ##   ```
  ##
  ## **See also:**
  ##
  ## * https://tools.ietf.org/html/rfc6694#section-3
  openDefaultBrowserRaw("about:blank")  # See IETF RFC-6694 Section 3.
