#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module contains a few procedures to control the *terminal*
## (also called *console*). On UNIX, the implementation simply uses ANSI escape
## sequences and does not depend on any other module, on Windows it uses the
## Windows API.
## Changing the style is permanent even after program termination! Use the
## code `exitprocs.addExitProc(resetAttributes)` to restore the defaults.
## Similarly, if you hide the cursor, make sure to unhide it with
## `showCursor` before quitting.
##
## Progress bar
## ============
##
## Basic progress bar example:
runnableExamples("-r:off"):
  import std/[os, strutils]

  for i in 0..100:
    stdout.styledWriteLine(fgRed, "0% ", fgWhite, '#'.repeat i, if i > 50: fgGreen else: fgYellow, "\t", $i , "%")
    sleep 42
    cursorUp 1
    eraseLine()

  stdout.resetAttributes()

##[
## Playing with colorful and styled text
]##

## Procs like `styledWriteLine`, `styledEcho` etc. have a temporary effect on
## text parameters. Style parameters only affect the text parameter right after them.
## After being called, these procs will reset the default style of the terminal.
## While `setBackGroundColor`, `setForeGroundColor` etc. have a lasting
## influence on the terminal, you can use `resetAttributes` to
## reset the default style of the terminal.
runnableExamples("-r:off"):
  stdout.styledWriteLine({styleBright, styleBlink, styleUnderscore}, "styled text ")
  stdout.styledWriteLine(fgRed, "red text ")
  stdout.styledWriteLine(fgWhite, bgRed, "white text in red background")
  stdout.styledWriteLine(" ordinary text without style ")

  stdout.setBackGroundColor(bgCyan, true)
  stdout.setForeGroundColor(fgBlue)
  stdout.write("blue text in cyan background")
  stdout.resetAttributes()

  # You can specify multiple text parameters. Style parameters
  # only affect the text parameter right after them.
  styledEcho styleBright, fgGreen, "[PASS]", resetStyle, fgGreen, " Yay!"

  stdout.styledWriteLine(fgRed, "red text ", styleBright, "bold red", fgDefault, " bold text")

import std/macros
import std/strformat
from std/strutils import toLowerAscii, `%`, parseInt
import std/colors

when defined(windows):
  import std/winlean

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]

type
  PTerminal = ref object
    trueColorIsSupported: bool
    trueColorIsEnabled: bool
    fgSetColor: bool
    when defined(windows):
      hStdout: Handle
      hStderr: Handle
      oldStdoutAttr: int16
      oldStderrAttr: int16

var gTerm {.threadvar.}: owned(PTerminal)

when defined(windows) and defined(consoleapp):
  proc newTerminal(): owned(PTerminal) {.gcsafe, raises: [OSError].}
else:
  proc newTerminal(): owned(PTerminal) {.gcsafe, raises: [].}

proc getTerminal(): PTerminal {.inline.} =
  if isNil(gTerm):
    gTerm = newTerminal()
  result = gTerm

const
  fgPrefix = "\e[38;2;"
  bgPrefix = "\e[48;2;"
  ansiResetCode* = "\e[0m"
  getPos = "\e[6n"
  stylePrefix = "\e["

when defined(windows):
  import std/[winlean, os]

  const
    DUPLICATE_SAME_ACCESS = 2
    FOREGROUND_BLUE = 1
    FOREGROUND_GREEN = 2
    FOREGROUND_RED = 4
    FOREGROUND_INTENSITY = 8
    BACKGROUND_BLUE = 16
    BACKGROUND_GREEN = 32
    BACKGROUND_RED = 64
    BACKGROUND_INTENSITY = 128
    FOREGROUND_RGB = FOREGROUND_RED or FOREGROUND_GREEN or FOREGROUND_BLUE
    BACKGROUND_RGB = BACKGROUND_RED or BACKGROUND_GREEN or BACKGROUND_BLUE

    ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004

  type
    SHORT = int16
    COORD = object
      x: SHORT
      y: SHORT

    SMALL_RECT = object
      left: SHORT
      top: SHORT
      right: SHORT
      bottom: SHORT

    CONSOLE_SCREEN_BUFFER_INFO = object
      dwSize: COORD
      dwCursorPosition: COORD
      wAttributes: int16
      srWindow: SMALL_RECT
      dwMaximumWindowSize: COORD

    CONSOLE_CURSOR_INFO = object
      dwSize: DWORD
      bVisible: WINBOOL

  proc duplicateHandle(hSourceProcessHandle: Handle, hSourceHandle: Handle,
                       hTargetProcessHandle: Handle, lpTargetHandle: ptr Handle,
                       dwDesiredAccess: DWORD, bInheritHandle: WINBOOL,
                       dwOptions: DWORD): WINBOOL{.stdcall, dynlib: "kernel32",
      importc: "DuplicateHandle".}
  proc getCurrentProcess(): Handle{.stdcall, dynlib: "kernel32",
                                     importc: "GetCurrentProcess".}
  proc getConsoleScreenBufferInfo(hConsoleOutput: Handle,
    lpConsoleScreenBufferInfo: ptr CONSOLE_SCREEN_BUFFER_INFO): WINBOOL{.stdcall,
    dynlib: "kernel32", importc: "GetConsoleScreenBufferInfo".}

  proc getConsoleCursorInfo(hConsoleOutput: Handle,
      lpConsoleCursorInfo: ptr CONSOLE_CURSOR_INFO): WINBOOL{.
      stdcall, dynlib: "kernel32", importc: "GetConsoleCursorInfo".}

  proc setConsoleCursorInfo(hConsoleOutput: Handle,
      lpConsoleCursorInfo: ptr CONSOLE_CURSOR_INFO): WINBOOL{.
      stdcall, dynlib: "kernel32", importc: "SetConsoleCursorInfo".}

  proc terminalWidthIoctl*(handles: openArray[Handle]): int =
    var csbi: CONSOLE_SCREEN_BUFFER_INFO
    for h in handles:
      if getConsoleScreenBufferInfo(h, addr csbi) != 0:
        return int(csbi.srWindow.right - csbi.srWindow.left + 1)
    return 0

  proc terminalHeightIoctl*(handles: openArray[Handle]): int =
    var csbi: CONSOLE_SCREEN_BUFFER_INFO
    for h in handles:
      if getConsoleScreenBufferInfo(h, addr csbi) != 0:
        return int(csbi.srWindow.bottom - csbi.srWindow.top + 1)
    return 0

  proc terminalWidth*(): int =
    ## Returns the terminal width in columns.
    var w: int = 0
    w = terminalWidthIoctl([getStdHandle(STD_INPUT_HANDLE),
                             getStdHandle(STD_OUTPUT_HANDLE),
                             getStdHandle(STD_ERROR_HANDLE)])
    if w > 0: return w
    return 80

  proc terminalHeight*(): int =
    ## Returns the terminal height in rows.
    var h: int = 0
    h = terminalHeightIoctl([getStdHandle(STD_INPUT_HANDLE),
                              getStdHandle(STD_OUTPUT_HANDLE),
                              getStdHandle(STD_ERROR_HANDLE)])
    if h > 0: return h
    return 0

  proc setConsoleCursorPosition(hConsoleOutput: Handle,
                                dwCursorPosition: COORD): WINBOOL{.
      stdcall, dynlib: "kernel32", importc: "SetConsoleCursorPosition".}

  proc fillConsoleOutputCharacter(hConsoleOutput: Handle, cCharacter: char,
                                  nLength: DWORD, dwWriteCoord: COORD,
                                  lpNumberOfCharsWritten: ptr DWORD): WINBOOL{.
      stdcall, dynlib: "kernel32", importc: "FillConsoleOutputCharacterA".}

  proc fillConsoleOutputAttribute(hConsoleOutput: Handle, wAttribute: int16,
                                  nLength: DWORD, dwWriteCoord: COORD,
                                  lpNumberOfAttrsWritten: ptr DWORD): WINBOOL{.
      stdcall, dynlib: "kernel32", importc: "FillConsoleOutputAttribute".}

  proc setConsoleTextAttribute(hConsoleOutput: Handle,
                               wAttributes: int16): WINBOOL{.
      stdcall, dynlib: "kernel32", importc: "SetConsoleTextAttribute".}

  proc getConsoleMode(hConsoleHandle: Handle, dwMode: ptr DWORD): WINBOOL{.
      stdcall, dynlib: "kernel32", importc: "GetConsoleMode".}

  proc setConsoleMode(hConsoleHandle: Handle, dwMode: DWORD): WINBOOL{.
      stdcall, dynlib: "kernel32", importc: "SetConsoleMode".}

  proc getCursorPos(h: Handle): tuple [x, y: int] =
    var c: CONSOLE_SCREEN_BUFFER_INFO
    if getConsoleScreenBufferInfo(h, addr(c)) == 0:
      raiseOSError(osLastError())
    return (int(c.dwCursorPosition.x), int(c.dwCursorPosition.y))

  proc getCursorPos*(): tuple [x, y: int] {.raises: [ValueError, IOError, OSError].} =
    return getCursorPos(getStdHandle(STD_OUTPUT_HANDLE))

  proc setCursorPos(h: Handle, x, y: int) =
    var c: COORD
    c.x = int16(x)
    c.y = int16(y)
    if setConsoleCursorPosition(h, c) == 0:
      raiseOSError(osLastError())

  proc getAttributes(h: Handle): int16 =
    var c: CONSOLE_SCREEN_BUFFER_INFO
    # workaround Windows bugs: try several times
    if getConsoleScreenBufferInfo(h, addr(c)) != 0:
      return c.wAttributes
    return 0x70'i16 # ERROR: return white background, black text

  proc initTerminal(term: PTerminal) =
    var hStdoutTemp = getStdHandle(STD_OUTPUT_HANDLE)
    if duplicateHandle(getCurrentProcess(), hStdoutTemp, getCurrentProcess(),
                       addr(term.hStdout), 0, 1, DUPLICATE_SAME_ACCESS) == 0:
      when defined(consoleapp):
        raiseOSError(osLastError())
    var hStderrTemp = getStdHandle(STD_ERROR_HANDLE)
    if duplicateHandle(getCurrentProcess(), hStderrTemp, getCurrentProcess(),
                       addr(term.hStderr), 0, 1, DUPLICATE_SAME_ACCESS) == 0:
      when defined(consoleapp):
        raiseOSError(osLastError())
    term.oldStdoutAttr = getAttributes(term.hStdout)
    term.oldStderrAttr = getAttributes(term.hStderr)

  template conHandle(f: File): Handle =
    let term = getTerminal()
    if f == stderr: term.hStderr else: term.hStdout

else:
  import std/[termios, posix, os, parseutils]

  proc setRaw(fd: FileHandle, time: cint = TCSAFLUSH) =
    var mode: Termios = default(Termios)
    discard fd.tcGetAttr(addr mode)
    mode.c_iflag = mode.c_iflag and not Cflag(BRKINT or ICRNL or INPCK or
      ISTRIP or IXON)
    mode.c_oflag = mode.c_oflag and not Cflag(OPOST)
    mode.c_cflag = (mode.c_cflag and not Cflag(CSIZE or PARENB)) or CS8
    mode.c_lflag = mode.c_lflag and not Cflag(ECHO or ICANON or IEXTEN or ISIG)
    mode.c_cc[VMIN] = 1.cuchar
    mode.c_cc[VTIME] = 0.cuchar
    discard fd.tcSetAttr(time, addr mode)

  proc getCursorPos*(): tuple [x, y: int] {.raises: [ValueError, IOError].} =
    ## Returns cursor position (x, y)
    ## writes to stdout and expects the terminal to respond via stdin
    var
      xStr = ""
      yStr = ""
      ch: char = '\0'
      ct: int = 0
      readX = false

    # use raw mode to ask terminal for cursor position
    let fd = getFileHandle(stdin)
    var oldMode: Termios
    discard fd.tcGetAttr(addr oldMode)
    fd.setRaw()
    stdout.write(getPos)
    flushFile(stdout)

    try:
      # parse response format: [yyy;xxxR
      while true:
        let n = readBuffer(stdin, addr ch, 1)
        if n == 0 or ch == 'R':
          if xStr == "" or yStr == "":
            raise newException(ValueError, "Got character position message that was missing data")
          break
        ct += 1
        if ct > 16:
          raise newException(ValueError, "Got unterminated character position message from terminal")
        if ch == ';':
          readX = true
        elif ch in {'0'..'9'}:
          if readX:
            xStr.add(ch)
          else:
            yStr.add(ch)
    finally:
      # restore previous terminal mode
      discard fd.tcSetAttr(TCSADRAIN, addr oldMode)

    return (parseInt(xStr), parseInt(yStr))

  proc terminalWidthIoctl*(fds: openArray[int]): int =
    ## Returns terminal width from first fd that supports the ioctl.

    var win: IOctl_WinSize = default(IOctl_WinSize)
    for fd in fds:
      if ioctl(cint(fd), TIOCGWINSZ, addr win) != -1:
        return int(win.ws_col)
    return 0

  proc terminalHeightIoctl*(fds: openArray[int]): int =
    ## Returns terminal height from first fd that supports the ioctl.

    var win: IOctl_WinSize = default(IOctl_WinSize)
    for fd in fds:
      if ioctl(cint(fd), TIOCGWINSZ, addr win) != -1:
        return int(win.ws_row)
    return 0

  var L_ctermid{.importc, header: "<stdio.h>".}: cint

  proc terminalWidth*(): int =
    ## Returns some reasonable terminal width from either standard file
    ## descriptors, controlling terminal, environment variables or tradition.

    # POSIX environment variable takes precendence.
    # _COLUMNS_: This variable shall represent a decimal integer >0 used
    # to indicate the user's preferred width in column positions for
    # the terminal screen or window. If this variable is unset or null,
    # the implementation determines the number of columns, appropriate
    # for the terminal or window, in an unspecified manner.
    # When COLUMNS is set, any terminal-width information implied by TERM
    # is overridden. Users and conforming applications should not set COLUMNS
    # unless they wish to override the system selection and produce output
    # unrelated to the terminal characteristics.
    # See POSIX Base Definitions Section 8.1 Environment Variable Definition

    var w: int = 0
    var s = getEnv("COLUMNS") # Try standard env var
    if len(s) > 0 and parseSaturatedNatural(s, w) > 0 and w > 0:
      return w
    w = terminalWidthIoctl([0, 1, 2]) # Try standard file descriptors
    if w > 0: return w
    var cterm = newString(L_ctermid) # Try controlling tty
    var fd = open(ctermid(cstring(cterm)), O_RDONLY)
    if fd != -1:
      w = terminalWidthIoctl([int(fd)])
    discard close(fd)
    if w > 0: return w
    return 80 # Finally default to venerable value

  proc terminalHeight*(): int =
    ## Returns some reasonable terminal height from either standard file
    ## descriptors, controlling terminal, environment variables or tradition.
    ## Zero is returned if the height could not be determined.

    # POSIX environment variable takes precendence.
    # _LINES_: This variable shall represent a decimal integer >0 used
    # to indicate the user's preferred number of lines on a page or
    # the vertical screen or window size in lines. A line in this case
    # is a vertical measure large enough to hold the tallest character
    # in the character set being displayed. If this variable is unset or null,
    # the implementation determines the number of lines, appropriate
    # for the terminal or window (size, terminal baud rate, and so on),
    # in an unspecified manner.
    # When LINES is set, any terminal-height information implied by TERM
    # is overridden. Users and conforming applications should not set LINES
    # unless they wish to override the system selection and produce output
    # unrelated to the terminal characteristics.
    # See POSIX Base Definitions Section 8.1 Environment Variable Definition

    var h: int = 0
    var s = getEnv("LINES") # Try standard env var
    if len(s) > 0 and parseSaturatedNatural(s, h) > 0 and h > 0:
      return h
    h = terminalHeightIoctl([0, 1, 2]) # Try standard file descriptors
    if h > 0: return h
    var cterm = newString(L_ctermid) # Try controlling tty
    var fd = open(ctermid(cstring(cterm)), O_RDONLY)
    if fd != -1:
      h = terminalHeightIoctl([int(fd)])
    discard close(fd)
    if h > 0: return h
    return 0 # Could not determine height

proc terminalSize*(): tuple[w, h: int] =
  ## Returns the terminal width and height as a tuple. Internally calls
  ## `terminalWidth` and `terminalHeight`, so the same assumptions apply.
  result = (terminalWidth(), terminalHeight())

when defined(windows):
  proc setCursorVisibility(f: File, visible: bool) =
    var ccsi: CONSOLE_CURSOR_INFO
    let h = conHandle(f)
    if getConsoleCursorInfo(h, addr(ccsi)) == 0:
      raiseOSError(osLastError())
    ccsi.bVisible = if visible: 1 else: 0
    if setConsoleCursorInfo(h, addr(ccsi)) == 0:
      raiseOSError(osLastError())

proc hideCursor*(f: File) =
  ## Hides the cursor.
  when defined(windows):
    setCursorVisibility(f, false)
  else:
    f.write("\e[?25l")

proc showCursor*(f: File) =
  ## Shows the cursor.
  when defined(windows):
    setCursorVisibility(f, true)
  else:
    f.write("\e[?25h")

proc setCursorPos*(f: File, x, y: int) =
  ## Sets the terminal's cursor to the (x,y) position.
  ## (0,0) is the upper left of the screen.
  when defined(windows):
    let h = conHandle(f)
    setCursorPos(h, x, y)
  else:
    f.write(fmt"{stylePrefix}{y+1};{x+1}f")

proc setCursorXPos*(f: File, x: int) =
  ## Sets the terminal's cursor to the x position.
  ## The y position is not changed.
  when defined(windows):
    let h = conHandle(f)
    var scrbuf: CONSOLE_SCREEN_BUFFER_INFO
    if getConsoleScreenBufferInfo(h, addr(scrbuf)) == 0:
      raiseOSError(osLastError())
    var origin = scrbuf.dwCursorPosition
    origin.x = int16(x)
    if setConsoleCursorPosition(h, origin) == 0:
      raiseOSError(osLastError())
  else:
    f.write(fmt"{stylePrefix}{x+1}G")

when defined(windows):
  proc setCursorYPos*(f: File, y: int) =
    ## Sets the terminal's cursor to the y position.
    ## The x position is not changed.
    ## .. warning:: This is not supported on UNIX!
    when defined(windows):
      let h = conHandle(f)
      var scrbuf: CONSOLE_SCREEN_BUFFER_INFO
      if getConsoleScreenBufferInfo(h, addr(scrbuf)) == 0:
        raiseOSError(osLastError())
      var origin = scrbuf.dwCursorPosition
      origin.y = int16(y)
      if setConsoleCursorPosition(h, origin) == 0:
        raiseOSError(osLastError())
    else:
      discard

proc cursorUp*(f: File, count = 1) =
  ## Moves the cursor up by `count` rows.
  runnableExamples("-r:off"):
    stdout.cursorUp(2)
    write(stdout, "Hello World!") # anything written at that location will be erased/replaced with this
  when defined(windows):
    let h = conHandle(f)
    var p = getCursorPos(h)
    dec(p.y, count)
    setCursorPos(h, p.x, p.y)
  else:
    f.write("\e[" & $count & 'A')

proc cursorDown*(f: File, count = 1) =
  ## Moves the cursor down by `count` rows.
  runnableExamples("-r:off"):
    stdout.cursorDown(2)
    write(stdout, "Hello World!") # anything written at that location will be erased/replaced with this
  when defined(windows):
    let h = conHandle(f)
    var p = getCursorPos(h)
    inc(p.y, count)
    setCursorPos(h, p.x, p.y)
  else:
    f.write(fmt"{stylePrefix}{count}B")

proc cursorForward*(f: File, count = 1) =
  ## Moves the cursor forward by `count` columns.
  runnableExamples("-r:off"):
    stdout.cursorForward(2)
    write(stdout, "Hello World!") # anything written at that location will be erased/replaced with this
  when defined(windows):
    let h = conHandle(f)
    var p = getCursorPos(h)
    inc(p.x, count)
    setCursorPos(h, p.x, p.y)
  else:
    f.write(fmt"{stylePrefix}{count}C")

proc cursorBackward*(f: File, count = 1) =
  ## Moves the cursor backward by `count` columns.
  runnableExamples("-r:off"):
    stdout.cursorBackward(2)
    write(stdout, "Hello World!") # anything written at that location will be erased/replaced with this
  when defined(windows):
    let h = conHandle(f)
    var p = getCursorPos(h)
    dec(p.x, count)
    setCursorPos(h, p.x, p.y)
  else:
    f.write(fmt"{stylePrefix}{count}D")

when true:
  discard
else:
  proc eraseLineEnd*(f: File) =
    ## Erases from the current cursor position to the end of the current line.
    when defined(windows):
      discard
    else:
      f.write("\e[K")

  proc eraseLineStart*(f: File) =
    ## Erases from the current cursor position to the start of the current line.
    when defined(windows):
      discard
    else:
      f.write("\e[1K")

  proc eraseDown*(f: File) =
    ## Erases the screen from the current line down to the bottom of the screen.
    when defined(windows):
      discard
    else:
      f.write("\e[J")

  proc eraseUp*(f: File) =
    ## Erases the screen from the current line up to the top of the screen.
    when defined(windows):
      discard
    else:
      f.write("\e[1J")

proc eraseLine*(f: File) =
  ## Erases the entire current line.
  runnableExamples("-r:off"):
    write(stdout, "never mind")
    stdout.eraseLine() # nothing will be printed on the screen
  when defined(windows):
    let h = conHandle(f)
    var scrbuf: CONSOLE_SCREEN_BUFFER_INFO
    var numwrote: DWORD
    if getConsoleScreenBufferInfo(h, addr(scrbuf)) == 0:
      raiseOSError(osLastError())
    var origin = scrbuf.dwCursorPosition
    origin.x = 0'i16
    if setConsoleCursorPosition(h, origin) == 0:
      raiseOSError(osLastError())
    var wt: DWORD = scrbuf.dwSize.x - origin.x
    if fillConsoleOutputCharacter(h, ' ', wt,
                                  origin, addr(numwrote)) == 0:
      raiseOSError(osLastError())
    if fillConsoleOutputAttribute(h, scrbuf.wAttributes, wt,
                                  scrbuf.dwCursorPosition, addr(numwrote)) == 0:
      raiseOSError(osLastError())
  else:
    f.write("\e[2K")
    setCursorXPos(f, 0)

proc eraseScreen*(f: File) =
  ## Erases the screen with the background colour and moves the cursor to home.
  when defined(windows):
    let h = conHandle(f)
    var scrbuf: CONSOLE_SCREEN_BUFFER_INFO
    var numwrote: DWORD
    var origin: COORD # is inititalized to 0, 0

    if getConsoleScreenBufferInfo(h, addr(scrbuf)) == 0:
      raiseOSError(osLastError())
    let numChars = int32(scrbuf.dwSize.x)*int32(scrbuf.dwSize.y)

    if fillConsoleOutputCharacter(h, ' ', numChars,
                                  origin, addr(numwrote)) == 0:
      raiseOSError(osLastError())
    if fillConsoleOutputAttribute(h, scrbuf.wAttributes, numChars,
                                  origin, addr(numwrote)) == 0:
      raiseOSError(osLastError())
    setCursorXPos(f, 0)
  else:
    f.write("\e[2J")

when not defined(windows):
  var
    gFG {.threadvar.}: int
    gBG {.threadvar.}: int

proc resetAttributes*(f: File) =
  ## Resets all attributes.
  when defined(windows):
    let term = getTerminal()
    if f == stderr:
      discard setConsoleTextAttribute(term.hStderr, term.oldStderrAttr)
    else:
      discard setConsoleTextAttribute(term.hStdout, term.oldStdoutAttr)
  else:
    f.write(ansiResetCode)
    gFG = 0
    gBG = 0

type
  Style* = enum        ## Different styles for text output.
    styleBright = 1,   ## bright text
    styleDim,          ## dim text
    styleItalic,       ## italic (or reverse on terminals not supporting)
    styleUnderscore,   ## underscored text
    styleBlink,        ## blinking/bold text
    styleBlinkRapid,   ## rapid blinking/bold text (not widely supported)
    styleReverse,      ## reverse
    styleHidden,       ## hidden text
    styleStrikethrough ## strikethrough

proc ansiStyleCode*(style: int): string =
  result = fmt"{stylePrefix}{style}m"

template ansiStyleCode*(style: Style): string =
  ansiStyleCode(style.int)

# The styleCache can be skipped when `style` is known at compile-time
template ansiStyleCode*(style: static[Style]): string =
  (static(stylePrefix & $style.int & "m"))

proc setStyle*(f: File, style: set[Style]) =
  ## Sets the terminal style.
  when defined(windows):
    let h = conHandle(f)
    var old = getAttributes(h) and (FOREGROUND_RGB or BACKGROUND_RGB)
    var a = 0'i16
    if styleBright in style: a = a or int16(FOREGROUND_INTENSITY)
    if styleBlink in style: a = a or int16(BACKGROUND_INTENSITY)
    if styleReverse in style: a = a or 0x4000'i16 # COMMON_LVB_REVERSE_VIDEO
    if styleUnderscore in style: a = a or 0x8000'i16 # COMMON_LVB_UNDERSCORE
    discard setConsoleTextAttribute(h, old or a)
  else:
    for s in items(style):
      f.write(ansiStyleCode(s))

proc writeStyled*(txt: string, style: set[Style] = {styleBright}) =
  ## Writes the text `txt` in a given `style` to stdout.
  when defined(windows):
    let term = getTerminal()
    var old = getAttributes(term.hStdout)
    stdout.setStyle(style)
    stdout.write(txt)
    discard setConsoleTextAttribute(term.hStdout, old)
  else:
    stdout.setStyle(style)
    stdout.write(txt)
    stdout.resetAttributes()
    if gFG != 0:
      stdout.write(ansiStyleCode(gFG))
    if gBG != 0:
      stdout.write(ansiStyleCode(gBG))

type
  ForegroundColor* = enum ## Terminal's foreground colors.
    fgBlack = 30,         ## black
    fgRed,                ## red
    fgGreen,              ## green
    fgYellow,             ## yellow
    fgBlue,               ## blue
    fgMagenta,            ## magenta
    fgCyan,               ## cyan
    fgWhite,              ## white
    fg8Bit,               ## 256-color (not supported, see `enableTrueColors` instead.)
    fgDefault             ## default terminal foreground color

  BackgroundColor* = enum ## Terminal's background colors.
    bgBlack = 40,         ## black
    bgRed,                ## red
    bgGreen,              ## green
    bgYellow,             ## yellow
    bgBlue,               ## blue
    bgMagenta,            ## magenta
    bgCyan,               ## cyan
    bgWhite,              ## white
    bg8Bit,               ## 256-color (not supported, see `enableTrueColors` instead.)
    bgDefault             ## default terminal background color

when defined(windows):
  var defaultForegroundColor, defaultBackgroundColor: int16 = 0xFFFF'i16 # Default to an invalid value 0xFFFF

proc setForegroundColor*(f: File, fg: ForegroundColor, bright = false) =
  ## Sets the terminal's foreground color.
  when defined(windows):
    let h = conHandle(f)
    var old = getAttributes(h) and not FOREGROUND_RGB
    if defaultForegroundColor == 0xFFFF'i16:
      defaultForegroundColor = old
    old = if bright: old or FOREGROUND_INTENSITY
          else: old and not(FOREGROUND_INTENSITY)
    const lookup: array[ForegroundColor, int] = [
      0, # ForegroundColor enum with ordinal 30
      (FOREGROUND_RED),
      (FOREGROUND_GREEN),
      (FOREGROUND_RED or FOREGROUND_GREEN),
      (FOREGROUND_BLUE),
      (FOREGROUND_RED or FOREGROUND_BLUE),
      (FOREGROUND_BLUE or FOREGROUND_GREEN),
      (FOREGROUND_BLUE or FOREGROUND_GREEN or FOREGROUND_RED),
      0, # fg8Bit not supported, see `enableTrueColors` instead.
      0] # unused
    if fg == fgDefault:
      discard setConsoleTextAttribute(h, cast[int16](cast[uint16](old) or cast[uint16](defaultForegroundColor)))
    else:
      discard setConsoleTextAttribute(h, cast[int16](cast[uint16](old) or cast[uint16](lookup[fg])))
  else:
    gFG = ord(fg)
    if bright: inc(gFG, 60)
    f.write(ansiStyleCode(gFG))

proc setBackgroundColor*(f: File, bg: BackgroundColor, bright = false) =
  ## Sets the terminal's background color.
  when defined(windows):
    let h = conHandle(f)
    var old = getAttributes(h) and not BACKGROUND_RGB
    if defaultBackgroundColor == 0xFFFF'i16:
      defaultBackgroundColor = old
    old = if bright: old or BACKGROUND_INTENSITY
          else: old and not(BACKGROUND_INTENSITY)
    const lookup: array[BackgroundColor, int] = [
      0, # BackgroundColor enum with ordinal 40
      (BACKGROUND_RED),
      (BACKGROUND_GREEN),
      (BACKGROUND_RED or BACKGROUND_GREEN),
      (BACKGROUND_BLUE),
      (BACKGROUND_RED or BACKGROUND_BLUE),
      (BACKGROUND_BLUE or BACKGROUND_GREEN),
      (BACKGROUND_BLUE or BACKGROUND_GREEN or BACKGROUND_RED),
      0, # bg8Bit not supported, see `enableTrueColors` instead.
      0] # unused
    if bg == bgDefault:
      discard setConsoleTextAttribute(h, cast[int16](cast[uint16](old) or cast[uint16](defaultBackgroundColor)))
    else:
      discard setConsoleTextAttribute(h, cast[int16](cast[uint16](old) or cast[uint16](lookup[bg])))
  else:
    gBG = ord(bg)
    if bright: inc(gBG, 60)
    f.write(ansiStyleCode(gBG))

proc ansiForegroundColorCode*(fg: ForegroundColor, bright = false): string =
  var style = ord(fg)
  if bright: inc(style, 60)
  return ansiStyleCode(style)

template ansiForegroundColorCode*(fg: static[ForegroundColor],
                                  bright: static[bool] = false): string =
  ansiStyleCode(fg.int + bright.int * 60)

proc ansiForegroundColorCode*(color: Color): string =
  let rgb = extractRGB(color)
  result = fmt"{fgPrefix}{rgb.r};{rgb.g};{rgb.b}m"

template ansiForegroundColorCode*(color: static[Color]): string =
  const rgb = extractRGB(color)
  # no usage of `fmt`, see issue #7632
  (static("$1$2;$3;$4m" % [$fgPrefix, $(rgb.r), $(rgb.g), $(rgb.b)]))

proc ansiBackgroundColorCode*(color: Color): string =
  let rgb = extractRGB(color)
  result = fmt"{bgPrefix}{rgb.r};{rgb.g};{rgb.b}m"

template ansiBackgroundColorCode*(color: static[Color]): string =
  const rgb = extractRGB(color)
  # no usage of `fmt`, see issue #7632
  (static("$1$2;$3;$4m" % [$bgPrefix, $(rgb.r), $(rgb.g), $(rgb.b)]))

proc setForegroundColor*(f: File, color: Color) =
  ## Sets the terminal's foreground true color.
  if getTerminal().trueColorIsEnabled:
    f.write(ansiForegroundColorCode(color))

proc setBackgroundColor*(f: File, color: Color) =
  ## Sets the terminal's background true color.
  if getTerminal().trueColorIsEnabled:
    f.write(ansiBackgroundColorCode(color))

proc setTrueColor(f: File, color: Color) =
  let term = getTerminal()
  if term.fgSetColor:
    setForegroundColor(f, color)
  else:
    setBackgroundColor(f, color)

proc isatty*(f: File): bool =
  ## Returns true if `f` is associated with a terminal device.
  when defined(posix):
    proc isatty(fildes: FileHandle): cint {.
      importc: "isatty", header: "<unistd.h>".}
  else:
    proc isatty(fildes: FileHandle): cint {.
      importc: "_isatty", header: "<io.h>".}

  result = isatty(getFileHandle(f)) != 0'i32

type
  TerminalCmd* = enum ## commands that can be expressed as arguments
    resetStyle,       ## reset attributes
    fgColor,          ## set foreground's true color
    bgColor           ## set background's true color

template styledEchoProcessArg(f: File, s: string) = write f, s
template styledEchoProcessArg(f: File, style: Style) = setStyle(f, {style})
template styledEchoProcessArg(f: File, style: set[Style]) = setStyle f, style
template styledEchoProcessArg(f: File, color: ForegroundColor) =
  setForegroundColor f, color
template styledEchoProcessArg(f: File, color: BackgroundColor) =
  setBackgroundColor f, color
template styledEchoProcessArg(f: File, color: Color) =
  setTrueColor f, color
template styledEchoProcessArg(f: File, cmd: TerminalCmd) =
  when cmd == resetStyle:
    resetAttributes(f)
  elif cmd in {fgColor, bgColor}:
    let term = getTerminal()
    term.fgSetColor = cmd == fgColor

macro styledWrite*(f: File, m: varargs[typed]): untyped =
  ## Similar to `write`, but treating terminal style arguments specially.
  ## When some argument is `Style`, `set[Style]`, `ForegroundColor`,
  ## `BackgroundColor` or `TerminalCmd` then it is not sent directly to
  ## `f`, but instead corresponding terminal style proc is called.
  runnableExamples("-r:off"):
    stdout.styledWrite(fgRed, "red text ")
    stdout.styledWrite(fgGreen, "green text")

  var reset = false
  result = newNimNode(nnkStmtList)

  for i in countup(0, m.len - 1):
    let item = m[i]
    case item.kind
    of nnkStrLit..nnkTripleStrLit:
      if i == m.len - 1:
        # optimize if string literal is last, just call write
        result.add(newCall(bindSym"write", f, item))
        if reset: result.add(newCall(bindSym"resetAttributes", f))
        return
      else:
        # if it is string literal just call write, do not enable reset
        result.add(newCall(bindSym"write", f, item))
    else:
      result.add(newCall(bindSym"styledEchoProcessArg", f, item))
      reset = true
  if reset: result.add(newCall(bindSym"resetAttributes", f))

template styledWriteLine*(f: File, args: varargs[untyped]) =
  ## Calls `styledWrite` and appends a newline at the end.
  runnableExamples:
    proc error(msg: string) =
      styledWriteLine(stderr, fgRed, "Error: ", resetStyle, msg)

  styledWrite(f, args)
  write(f, "\n")

template styledEcho*(args: varargs[untyped]) =
  ## Echoes styles arguments to stdout using `styledWriteLine`.
  stdout.styledWriteLine(args)

proc getch*(): char =
  ## Reads a single character from the terminal, blocking until it is entered.
  ## The character is not printed to the terminal.
  when defined(windows):
    let fd = getStdHandle(STD_INPUT_HANDLE)
    var keyEvent = KEY_EVENT_RECORD()
    var numRead: cint
    while true:
      # Block until character is entered
      doAssert(waitForSingleObject(fd, INFINITE) == WAIT_OBJECT_0)
      doAssert(readConsoleInput(fd, addr(keyEvent), 1, addr(numRead)) != 0)
      if numRead == 0 or keyEvent.eventType != 1 or keyEvent.bKeyDown == 0:
        continue
      return char(keyEvent.uChar)
  else:
    let fd = getFileHandle(stdin)
    var oldMode: Termios
    discard fd.tcGetAttr(addr oldMode)
    fd.setRaw()
    result = stdin.readChar()
    discard fd.tcSetAttr(TCSADRAIN, addr oldMode)

when defined(windows):
  proc readPasswordFromStdin*(prompt: string, password: var string):
                              bool {.tags: [ReadIOEffect, WriteIOEffect].} =
    ## Reads a `password` from stdin without printing it. `password` must not
    ## be `nil`! Returns `false` if the end of the file has been reached,
    ## `true` otherwise.
    password.setLen(0)
    stdout.write(prompt)
    let hi = createFileA("CONIN$",
      GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0)
    var mode = DWORD 0
    discard getConsoleMode(hi, addr mode)
    let origMode = mode
    const
      ENABLE_PROCESSED_INPUT = 1
      ENABLE_ECHO_INPUT = 4
    mode = (mode or ENABLE_PROCESSED_INPUT) and not ENABLE_ECHO_INPUT

    discard setConsoleMode(hi, mode)
    result = readLine(stdin, password)
    discard setConsoleMode(hi, origMode)
    discard closeHandle(hi)
    stdout.write "\n"

else:
  import std/termios

  proc readPasswordFromStdin*(prompt: string, password: var string):
                            bool {.tags: [ReadIOEffect, WriteIOEffect].} =
    password.setLen(0)
    let fd = stdin.getFileHandle()
    var cur, old: Termios = default(Termios)
    discard fd.tcGetAttr(cur.addr)
    old = cur
    cur.c_lflag = cur.c_lflag and not Cflag(ECHO)
    discard fd.tcSetAttr(TCSADRAIN, cur.addr)
    stdout.write prompt
    result = stdin.readLine(password)
    stdout.write "\n"
    discard fd.tcSetAttr(TCSADRAIN, old.addr)

proc readPasswordFromStdin*(prompt = "password: "): string =
  ## Reads a password from stdin without printing it.
  result = ""
  discard readPasswordFromStdin(prompt, result)


# Wrappers assuming output to stdout:
template hideCursor*() = hideCursor(stdout)
template showCursor*() = showCursor(stdout)
template setCursorPos*(x, y: int) = setCursorPos(stdout, x, y)
template setCursorXPos*(x: int) = setCursorXPos(stdout, x)
when defined(windows):
  template setCursorYPos*(x: int) = setCursorYPos(stdout, x)
template cursorUp*(count = 1) = cursorUp(stdout, count)
template cursorDown*(count = 1) = cursorDown(stdout, count)
template cursorForward*(count = 1) = cursorForward(stdout, count)
template cursorBackward*(count = 1) = cursorBackward(stdout, count)
template eraseLine*() = eraseLine(stdout)
template eraseScreen*() = eraseScreen(stdout)
template setStyle*(style: set[Style]) =
  setStyle(stdout, style)
template setForegroundColor*(fg: ForegroundColor, bright = false) =
  setForegroundColor(stdout, fg, bright)
template setBackgroundColor*(bg: BackgroundColor, bright = false) =
  setBackgroundColor(stdout, bg, bright)
template setForegroundColor*(color: Color) =
  setForegroundColor(stdout, color)
template setBackgroundColor*(color: Color) =
  setBackgroundColor(stdout, color)
proc resetAttributes*() {.noconv.} =
  ## Resets all attributes on stdout.
  ## It is advisable to register this as a quit proc with
  ## `exitprocs.addExitProc(resetAttributes)`.
  resetAttributes(stdout)

proc isTrueColorSupported*(): bool =
  ## Returns true if a terminal supports true color.
  return getTerminal().trueColorIsSupported

when defined(windows):
  import std/os

proc enableTrueColors*() =
  ## Enables true color.
  var term = getTerminal()
  when defined(windows):
    var
      ver: OSVERSIONINFO
    ver.dwOSVersionInfoSize = sizeof(ver).DWORD
    let res = getVersionExW(addr ver)
    if res == 0:
      term.trueColorIsSupported = false
    else:
      term.trueColorIsSupported = ver.dwMajorVersion > 10 or
        (ver.dwMajorVersion == 10 and (ver.dwMinorVersion > 0 or
        (ver.dwMinorVersion == 0 and ver.dwBuildNumber >= 10586)))
    if not term.trueColorIsSupported:
      term.trueColorIsSupported = getEnv("ANSICON_DEF").len > 0

    if term.trueColorIsSupported:
      if getEnv("ANSICON_DEF").len == 0:
        var mode: DWORD = 0
        if getConsoleMode(getStdHandle(STD_OUTPUT_HANDLE), addr(mode)) != 0:
          mode = mode or ENABLE_VIRTUAL_TERMINAL_PROCESSING
          if setConsoleMode(getStdHandle(STD_OUTPUT_HANDLE), mode) != 0:
            term.trueColorIsEnabled = true
          else:
            term.trueColorIsEnabled = false
      else:
        term.trueColorIsEnabled = true
  else:
    term.trueColorIsSupported = getEnv("COLORTERM").toLowerAscii() in [
        "truecolor", "24bit"]
    term.trueColorIsEnabled = term.trueColorIsSupported

proc disableTrueColors*() =
  ## Disables true color.
  var term = getTerminal()
  when defined(windows):
    if term.trueColorIsSupported:
      if getEnv("ANSICON_DEF").len == 0:
        var mode: DWORD = 0
        if getConsoleMode(getStdHandle(STD_OUTPUT_HANDLE), addr(mode)) != 0:
          mode = mode and not ENABLE_VIRTUAL_TERMINAL_PROCESSING
          discard setConsoleMode(getStdHandle(STD_OUTPUT_HANDLE), mode)
      term.trueColorIsEnabled = false
  else:
    term.trueColorIsEnabled = false

proc newTerminal(): owned(PTerminal) =
  new result
  when defined(windows):
    initTerminal(result)
