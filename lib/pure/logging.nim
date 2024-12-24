#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf, Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements a simple logger.
##
## It has been designed to be as simple as possible to avoid bloat.
## If this library does not fulfill your needs, write your own.
##
## Basic usage
## ===========
##
## To get started, first create a logger:
##
##   ```Nim
##   import std/logging
##
##   var logger = newConsoleLogger()
##   ```
##
## The logger that was created above logs to the console, but this module
## also provides loggers that log to files, such as the
## `FileLogger<#FileLogger>`_. Creating custom loggers is also possible by
## inheriting from the `Logger<#Logger>`_ type.
##
## Once a logger has been created, call its `log proc
## <#log.e,ConsoleLogger,Level,varargs[string,]>`_ to log a message:
##
##   ```Nim
##   logger.log(lvlInfo, "a log message")
##   # Output: INFO a log message
##   ```
##
## The ``INFO`` within the output is the result of a format string being
## prepended to the message, and it will differ depending on the message's
## level. Format strings are `explained in more detail
## here<#basic-usage-format-strings>`_.
##
## There are six logging levels: debug, info, notice, warn, error, and fatal.
## They are described in more detail within the `Level enum's documentation
## <#Level>`_. A message is logged if its level is at or above both the logger's
## ``levelThreshold`` field and the global log filter. The latter can be changed
## with the `setLogFilter proc<#setLogFilter,Level>`_.
##
## .. warning::
##   For loggers that log to a console or to files, only error and fatal
##   messages will cause their output buffers to be flushed immediately by default.
##   set ``flushThreshold`` when creating the logger to change this.
##
## Handlers
## --------
##
## When using multiple loggers, calling the log proc for each logger can
## become repetitive. Instead of doing that, register each logger that will be
## used with the `addHandler proc<#addHandler,Logger>`_, which is demonstrated
## in the following example:
##
##   ```Nim
##   import std/logging
##
##   var consoleLog = newConsoleLogger()
##   var fileLog = newFileLogger("errors.log", levelThreshold=lvlError)
##   var rollingLog = newRollingFileLogger("rolling.log")
##
##   addHandler(consoleLog)
##   addHandler(fileLog)
##   addHandler(rollingLog)
##   ```
##
## After doing this, use either the `log template
## <#log.t,Level,varargs[string,]>`_ or one of the level-specific templates,
## such as the `error template<#error.t,varargs[string,]>`_, to log messages
## to all registered handlers at once.
##
##   ```Nim
##   # This example uses the loggers created above
##   log(lvlError, "an error occurred")
##   error("an error occurred")  # Equivalent to the above line
##   info("something normal happened")  # Will not be written to errors.log
##   ```
##
## Note that a message's level is still checked against each handler's
## ``levelThreshold`` and the global log filter.
##
## Format strings
## --------------
##
## Log messages are prefixed with format strings. These strings contain
## placeholders for variables, such as ``$time``, that are replaced with their
## corresponding values, such as the current time, before they are prepended to
## a log message. Characters that are not part of variables are unaffected.
##
## The format string used by a logger can be specified by providing the `fmtStr`
## argument when creating the logger or by setting its `fmtStr` field afterward.
## If not specified, the `default format string<#defaultFmtStr>`_ is used.
##
## The following variables, which must be prefixed with a dollar sign (``$``),
## are available:
##
## ============  =======================
##   Variable      Output
## ============  =======================
## $date         Current date
## $time         Current time
## $datetime     $dateT$time
## $app          `os.getAppFilename()<os.html#getAppFilename>`_
## $appname      Base name of ``$app``
## $appdir       Directory name of ``$app``
## $levelid      First letter of log level
## $levelname    Log level name
## ============  =======================
##
## Note that ``$app``, ``$appname``, and ``$appdir`` are not supported when
## using the JavaScript backend.
##
## The following example illustrates how to use format strings:
##
##   ```Nim
##   import std/logging
##
##   var logger = newConsoleLogger(fmtStr="[$time] - $levelname: ")
##   logger.log(lvlInfo, "this is a message")
##   # Output: [19:50:13] - INFO: this is a message
##   ```
##
## Notes when using multiple threads
## ---------------------------------
##
## There are a few details to keep in mind when using this module within
## multiple threads:
## * The global log filter is actually a thread-local variable, so it needs to
##   be set in each thread that uses this module.
## * The list of registered handlers is also a thread-local variable. If a
##   handler will be used in multiple threads, it needs to be registered in
##   each of those threads.
##
## See also
## ========
## * `strutils module<strutils.html>`_ for common string functions
## * `strformat module<strformat.html>`_ for string interpolation and formatting
## * `strscans module<strscans.html>`_ for ``scanf`` and ``scanp`` macros, which
##   offer easier substring extraction than regular expressions

import std/[strutils, times]
when not defined(js):
  import std/os

when defined(nimPreviewSlimSystem):
  import std/syncio

type
  Level* = enum ## \
    ## Enumeration of logging levels.
    ##
    ## Debug messages represent the lowest logging level, and fatal error
    ## messages represent the highest logging level. ``lvlAll`` can be used
    ## to enable all messages, while ``lvlNone`` can be used to disable all
    ## messages.
    ##
    ## Typical usage for each logging level, from lowest to highest, is
    ## described below:
    ##
    ## * **Debug** - debugging information helpful only to developers
    ## * **Info** - anything associated with normal operation and without
    ##   any particular importance
    ## * **Notice** - more important information that users should be
    ##   notified about
    ## * **Warn** - impending problems that require some attention
    ## * **Error** - error conditions that the application can recover from
    ## * **Fatal** - fatal errors that prevent the application from continuing
    ##
    ## It is completely up to the application how to utilize each level.
    ##
    ## Individual loggers have a ``levelThreshold`` field that filters out
    ## any messages with a level lower than the threshold. There is also
    ## a global filter that applies to all log messages, and it can be changed
    ## using the `setLogFilter proc<#setLogFilter,Level>`_.
    lvlAll,     ## All levels active
    lvlDebug,   ## Debug level and above are active
    lvlInfo,    ## Info level and above are active
    lvlNotice,  ## Notice level and above are active
    lvlWarn,    ## Warn level and above are active
    lvlError,   ## Error level and above are active
    lvlFatal,   ## Fatal level and above are active
    lvlNone     ## No levels active; nothing is logged

const
  LevelNames*: array[Level, string] = [
    "DEBUG", "DEBUG", "INFO", "NOTICE", "WARN", "ERROR", "FATAL", "NONE"
  ] ## Array of strings representing each logging level.

  defaultFmtStr* = "$levelname "                         ## The default format string.
  verboseFmtStr* = "$levelid, [$datetime] -- $appname: " ## \
  ## A more verbose format string.
  ##
  ## This string can be passed as the ``frmStr`` argument to procs that create
  ## new loggers, such as the `newConsoleLogger proc<#newConsoleLogger>`_.
  ##
  ## If a different format string is preferred, refer to the
  ## `documentation about format strings<#basic-usage-format-strings>`_
  ## for more information, including a list of available variables.
  defaultFlushThreshold = when NimMajor >= 2:
      when defined(nimV1LogFlushBehavior): lvlError else: lvlAll
    else:
      when defined(nimFlushAllLogs): lvlAll else: lvlError
  ## The threshold above which log messages to file-like loggers
  ## are automatically flushed.
  ## 
  ## By default, only error and fatal messages are logged,
  ## but defining ``-d:nimFlushAllLogs`` will make all levels be flushed

type
  Logger* = ref object of RootObj
    ## The abstract base type of all loggers.
    ##
    ## Custom loggers should inherit from this type. They should also provide
    ## their own implementation of the
    ## `log method<#log.e,Logger,Level,varargs[string,]>`_.
    ##
    ## See also:
    ## * `ConsoleLogger<#ConsoleLogger>`_
    ## * `FileLogger<#FileLogger>`_
    ## * `RollingFileLogger<#RollingFileLogger>`_
    levelThreshold*: Level ## Only messages that are at or above this
                           ## threshold will be logged
    fmtStr*: string ## Format string to prepend to each log message;
                    ## defaultFmtStr is the default

  ConsoleLogger* = ref object of Logger
    ## A logger that writes log messages to the console.
    ##
    ## Create a new ``ConsoleLogger`` with the `newConsoleLogger proc
    ## <#newConsoleLogger>`_.
    ##
    ## See also:
    ## * `FileLogger<#FileLogger>`_
    ## * `RollingFileLogger<#RollingFileLogger>`_
    useStderr*: bool ## If true, writes to stderr; otherwise, writes to stdout
    flushThreshold*: Level ## Only messages that are at or above this
                           ## threshold will be flushed immediately

when not defined(js):
  type
    FileLogger* = ref object of Logger
      ## A logger that writes log messages to a file.
      ##
      ## Create a new ``FileLogger`` with the `newFileLogger proc
      ## <#newFileLogger,File>`_.
      ##
      ## **Note:** This logger is not available for the JavaScript backend.
      ##
      ## See also:
      ## * `ConsoleLogger<#ConsoleLogger>`_
      ## * `RollingFileLogger<#RollingFileLogger>`_
      file*: File ## The wrapped file
      flushThreshold*: Level ## Only messages that are at or above this
                           ## threshold will be flushed immediately

    RollingFileLogger* = ref object of FileLogger
      ## A logger that writes log messages to a file while performing log
      ## rotation.
      ##
      ## Create a new ``RollingFileLogger`` with the `newRollingFileLogger proc
      ## <#newRollingFileLogger,FileMode,Positive,int>`_.
      ##
      ## **Note:** This logger is not available for the JavaScript backend.
      ##
      ## See also:
      ## * `ConsoleLogger<#ConsoleLogger>`_
      ## * `FileLogger<#FileLogger>`_
      maxLines: int # maximum number of lines
      curLine: int
      baseName: string # initial filename
      baseMode: FileMode # initial file mode
      logFiles: int # how many log files already created, e.g. basename.1, basename.2...
      bufSize: int # size of output buffer (-1: use system defaults, 0: unbuffered, >0: fixed buffer size)

var
  level {.threadvar.}: Level          ## global log filter
  handlers {.threadvar.}: seq[Logger] ## handlers with their own log levels

proc substituteLog*(frmt: string, level: Level,
                    args: varargs[string, `$`]): string =
  ## Formats a log message at the specified level with the given format string.
  ##
  ## The `format variables<#basic-usage-format-strings>`_ present within
  ## ``frmt`` will be replaced with the corresponding values before being
  ## prepended to ``args`` and returned.
  ##
  ## Unless you are implementing a custom logger, there is little need to call
  ## this directly. Use either a logger's log method or one of the logging
  ## templates.
  ##
  ## See also:
  ## * `log method<#log.e,ConsoleLogger,Level,varargs[string,]>`_
  ##   for the ConsoleLogger
  ## * `log method<#log.e,FileLogger,Level,varargs[string,]>`_
  ##   for the FileLogger
  ## * `log method<#log.e,RollingFileLogger,Level,varargs[string,]>`_
  ##   for the RollingFileLogger
  ## * `log template<#log.t,Level,varargs[string,]>`_
  runnableExamples:
    doAssert substituteLog(defaultFmtStr, lvlInfo, "a message") == "INFO a message"
    doAssert substituteLog("$levelid - ", lvlError, "an error") == "E - an error"
    doAssert substituteLog("$levelid", lvlDebug, "error") == "Derror"
  var msgLen = 0
  for arg in args:
    msgLen += arg.len
  result = newStringOfCap(frmt.len + msgLen + 20)
  var i = 0
  while i < frmt.len:
    if frmt[i] != '$':
      result.add(frmt[i])
      inc(i)
    else:
      inc(i)
      var v = ""
      let app = when defined(js): "" else: getAppFilename()
      while i < frmt.len and frmt[i] in IdentChars:
        v.add(toLowerAscii(frmt[i]))
        inc(i)
      case v
      of "date": result.add(getDateStr())
      of "time": result.add(getClockStr())
      of "datetime": result.add(getDateStr() & "T" & getClockStr())
      of "app": result.add(app)
      of "appdir":
        when not defined(js): result.add(app.splitFile.dir)
      of "appname":
        when not defined(js): result.add(app.splitFile.name)
      of "levelid": result.add(LevelNames[level][0])
      of "levelname": result.add(LevelNames[level])
      else: discard
  for arg in args:
    result.add(arg)

method log*(logger: Logger, level: Level, args: varargs[string, `$`]) {.
            raises: [Exception], gcsafe,
            tags: [RootEffect], base.} =
  ## Override this method in custom loggers. The default implementation does
  ## nothing.
  ##
  ## See also:
  ## * `log method<#log.e,ConsoleLogger,Level,varargs[string,]>`_
  ##   for the ConsoleLogger
  ## * `log method<#log.e,FileLogger,Level,varargs[string,]>`_
  ##   for the FileLogger
  ## * `log method<#log.e,RollingFileLogger,Level,varargs[string,]>`_
  ##   for the RollingFileLogger
  ## * `log template<#log.t,Level,varargs[string,]>`_
  discard

method log*(logger: ConsoleLogger, level: Level, args: varargs[string, `$`]) =
  ## Logs to the console with the given `ConsoleLogger<#ConsoleLogger>`_ only.
  ##
  ## This method ignores the list of registered handlers.
  ##
  ## Whether the message is logged depends on both the ConsoleLogger's
  ## ``levelThreshold`` field and the global log filter set using the
  ## `setLogFilter proc<#setLogFilter,Level>`_.
  ##
  ## **Note:** Only error and fatal messages will cause the output buffer
  ## to be flushed immediately by default. Set ``flushThreshold`` when creating
  ## the logger to change this.
  ##
  ## See also:
  ## * `log method<#log.e,FileLogger,Level,varargs[string,]>`_
  ##   for the FileLogger
  ## * `log method<#log.e,RollingFileLogger,Level,varargs[string,]>`_
  ##   for the RollingFileLogger
  ## * `log template<#log.t,Level,varargs[string,]>`_
  ##
  ## **Examples:**
  ##
  ##   ```Nim
  ##   var consoleLog = newConsoleLogger()
  ##   consoleLog.log(lvlInfo, "this is a message")
  ##   consoleLog.log(lvlError, "error code is: ", 404)
  ##   ```
  if level >= logging.level and level >= logger.levelThreshold:
    let ln = substituteLog(logger.fmtStr, level, args)
    when defined(js):
      let cln = ln.cstring
      case level
      of lvlDebug: {.emit: "console.debug(`cln`);".}
      of lvlInfo:  {.emit: "console.info(`cln`);".}
      of lvlWarn:  {.emit: "console.warn(`cln`);".}
      of lvlError: {.emit: "console.error(`cln`);".}
      else:        {.emit: "console.log(`cln`);".}
    else:
      try:
        var handle = stdout
        if logger.useStderr:
          handle = stderr
        writeLine(handle, ln)
        if level >= logger.flushThreshold: flushFile(handle)
      except IOError:
        discard

proc newConsoleLogger*(levelThreshold = lvlAll, fmtStr = defaultFmtStr,
    useStderr = false, flushThreshold = defaultFlushThreshold): ConsoleLogger =
  ## Creates a new `ConsoleLogger<#ConsoleLogger>`_.
  ##
  ## By default, log messages are written to ``stdout``. If ``useStderr`` is
  ## true, they are written to ``stderr`` instead.
  ##
  ## For the JavaScript backend, log messages are written to the console,
  ## and ``useStderr`` is ignored.
  ##
  ## See also:
  ## * `newFileLogger proc<#newFileLogger,File>`_ that uses a file handle
  ## * `newFileLogger proc<#newFileLogger,FileMode,int>`_
  ##   that accepts a filename
  ## * `newRollingFileLogger proc<#newRollingFileLogger,FileMode,Positive,int>`_
  ##
  ## **Examples:**
  ##
  ##   ```Nim
  ##   var normalLog = newConsoleLogger()
  ##   var formatLog = newConsoleLogger(fmtStr=verboseFmtStr)
  ##   var errorLog = newConsoleLogger(levelThreshold=lvlError, useStderr=true)
  ##   ```
  new result
  result.fmtStr = fmtStr
  result.levelThreshold = levelThreshold
  result.flushThreshold = flushThreshold
  result.useStderr = useStderr

when not defined(js):
  method log*(logger: FileLogger, level: Level, args: varargs[string, `$`]) =
    ## Logs a message at the specified level using the given
    ## `FileLogger<#FileLogger>`_ only.
    ##
    ## This method ignores the list of registered handlers.
    ##
    ## Whether the message is logged depends on both the FileLogger's
    ## ``levelThreshold`` field and the global log filter set using the
    ## `setLogFilter proc<#setLogFilter,Level>`_.
    ##
    ## **Notes:**
    ## * Only error and fatal messages will cause the output buffer
    ##   to be flushed immediately by default. Set ``flushThreshold`` when creating
    ##   the logger to change this.
    ## * This method is not available for the JavaScript backend.
    ##
    ## See also:
    ## * `log method<#log.e,ConsoleLogger,Level,varargs[string,]>`_
    ##   for the ConsoleLogger
    ## * `log method<#log.e,RollingFileLogger,Level,varargs[string,]>`_
    ##   for the RollingFileLogger
    ## * `log template<#log.t,Level,varargs[string,]>`_
    ##
    ## **Examples:**
    ##
    ##   ```Nim
    ##   var fileLog = newFileLogger("messages.log")
    ##   fileLog.log(lvlInfo, "this is a message")
    ##   fileLog.log(lvlError, "error code is: ", 404)
    ##   ```
    if level >= logging.level and level >= logger.levelThreshold:
      writeLine(logger.file, substituteLog(logger.fmtStr, level, args))
      if level >= logger.flushThreshold: flushFile(logger.file)

  proc defaultFilename*(): string =
    ## Returns the filename that is used by default when naming log files.
    ##
    ## **Note:** This proc is not available for the JavaScript backend.
    var (path, name, _) = splitFile(getAppFilename())
    result = changeFileExt(path / name, "log")

  proc newFileLogger*(file: File,
                      levelThreshold = lvlAll,
                      fmtStr = defaultFmtStr,
                      flushThreshold = defaultFlushThreshold): FileLogger =
    ## Creates a new `FileLogger<#FileLogger>`_ that uses the given file handle.
    ##
    ## **Note:** This proc is not available for the JavaScript backend.
    ##
    ## See also:
    ## * `newConsoleLogger proc<#newConsoleLogger>`_
    ## * `newFileLogger proc<#newFileLogger,FileMode,int>`_
    ##   that accepts a filename
    ## * `newRollingFileLogger proc<#newRollingFileLogger,FileMode,Positive,int>`_
    ##
    ## **Examples:**
    ##
    ##   ```Nim
    ##   var messages = open("messages.log", fmWrite)
    ##   var formatted = open("formatted.log", fmWrite)
    ##   var errors = open("errors.log", fmWrite)
    ##
    ##   var normalLog = newFileLogger(messages)
    ##   var formatLog = newFileLogger(formatted, fmtStr=verboseFmtStr)
    ##   var errorLog = newFileLogger(errors, levelThreshold=lvlError)
    ##   ```
    new(result)
    result.file = file
    result.levelThreshold = levelThreshold
    result.flushThreshold = flushThreshold
    result.fmtStr = fmtStr

  proc newFileLogger*(filename = defaultFilename(),
                      mode: FileMode = fmAppend,
                      levelThreshold = lvlAll,
                      fmtStr = defaultFmtStr,
                      bufSize: int = -1,
                      flushThreshold = defaultFlushThreshold): FileLogger =
    ## Creates a new `FileLogger<#FileLogger>`_ that logs to a file with the
    ## given filename.
    ##
    ## ``bufSize`` controls the size of the output buffer that is used when
    ## writing to the log file. The following values can be provided:
    ## * ``-1`` - use system defaults
    ## * ``0`` - unbuffered
    ## * ``> 0`` - fixed buffer size
    ##
    ## **Note:** This proc is not available for the JavaScript backend.
    ##
    ## See also:
    ## * `newConsoleLogger proc<#newConsoleLogger>`_
    ## * `newFileLogger proc<#newFileLogger,File>`_ that uses a file handle
    ## * `newRollingFileLogger proc<#newRollingFileLogger,FileMode,Positive,int>`_
    ##
    ## **Examples:**
    ##
    ##   ```Nim
    ##   var normalLog = newFileLogger("messages.log")
    ##   var formatLog = newFileLogger("formatted.log", fmtStr=verboseFmtStr)
    ##   var errorLog = newFileLogger("errors.log", levelThreshold=lvlError)
    ##   ```
    let file = open(filename, mode, bufSize = bufSize)
    newFileLogger(file, levelThreshold, fmtStr, flushThreshold)

  # ------

  proc countLogLines(logger: RollingFileLogger): int =
    result = 0
    let fp = open(logger.baseName, fmRead)
    for line in fp.lines():
      result.inc()
    fp.close()

  proc countFiles(filename: string): int =
    # Example: file.log.1
    result = 0
    var (dir, name, ext) = splitFile(filename)
    if dir == "":
      dir = "."
    for kind, path in walkDir(dir):
      if kind == pcFile:
        let llfn = name & ext & ExtSep
        if path.extractFilename.startsWith(llfn):
          let numS = path.extractFilename[llfn.len .. ^1]
          try:
            let num = parseInt(numS)
            if num > result:
              result = num
          except ValueError: discard

  proc newRollingFileLogger*(filename = defaultFilename(),
                            mode: FileMode = fmReadWrite,
                            levelThreshold = lvlAll,
                            fmtStr = defaultFmtStr,
                            maxLines: Positive = 1000,
                            bufSize: int = -1,
                            flushThreshold = defaultFlushThreshold): RollingFileLogger =
    ## Creates a new `RollingFileLogger<#RollingFileLogger>`_.
    ##
    ## Once the current log file being written to contains ``maxLines`` lines,
    ## a new log file will be created, and the old log file will be renamed.
    ##
    ## ``bufSize`` controls the size of the output buffer that is used when
    ## writing to the log file. The following values can be provided:
    ## * ``-1`` - use system defaults
    ## * ``0`` - unbuffered
    ## * ``> 0`` - fixed buffer size
    ##
    ## **Note:** This proc is not available in the JavaScript backend.
    ##
    ## See also:
    ## * `newConsoleLogger proc<#newConsoleLogger>`_
    ## * `newFileLogger proc<#newFileLogger,File>`_ that uses a file handle
    ## * `newFileLogger proc<#newFileLogger,FileMode,int>`_
    ##   that accepts a filename
    ##
    ## **Examples:**
    ##
    ##   ```Nim
    ##   var normalLog = newRollingFileLogger("messages.log")
    ##   var formatLog = newRollingFileLogger("formatted.log", fmtStr=verboseFmtStr)
    ##   var shortLog = newRollingFileLogger("short.log", maxLines=200)
    ##   var errorLog = newRollingFileLogger("errors.log", levelThreshold=lvlError)
    ##   ```
    new(result)
    result.levelThreshold = levelThreshold
    result.fmtStr = fmtStr
    result.maxLines = maxLines
    result.bufSize = bufSize
    result.file = open(filename, mode, bufSize = result.bufSize)
    result.curLine = 0
    result.baseName = filename
    result.baseMode = mode
    result.flushThreshold = flushThreshold

    result.logFiles = countFiles(filename)

    if mode == fmAppend:
      # We need to get a line count because we will be appending to the file.
      result.curLine = countLogLines(result)

  proc rotate(logger: RollingFileLogger) =
    let (dir, name, ext) = splitFile(logger.baseName)
    for i in countdown(logger.logFiles, 0):
      let srcSuff = if i != 0: ExtSep & $i else: ""
      moveFile(dir / (name & ext & srcSuff),
              dir / (name & ext & ExtSep & $(i+1)))

  method log*(logger: RollingFileLogger, level: Level, args: varargs[string, `$`]) =
    ## Logs a message at the specified level using the given
    ## `RollingFileLogger<#RollingFileLogger>`_ only.
    ##
    ## This method ignores the list of registered handlers.
    ##
    ## Whether the message is logged depends on both the RollingFileLogger's
    ## ``levelThreshold`` field and the global log filter set using the
    ## `setLogFilter proc<#setLogFilter,Level>`_.
    ##
    ## **Notes:**
    ## * Only error and fatal messages will cause the output buffer
    ##   to be flushed immediately by default. Set ``flushThreshold`` when creating
    ##   the logger to change this.
    ## * This method is not available for the JavaScript backend.
    ##
    ## See also:
    ## * `log method<#log.e,ConsoleLogger,Level,varargs[string,]>`_
    ##   for the ConsoleLogger
    ## * `log method<#log.e,FileLogger,Level,varargs[string,]>`_
    ##   for the FileLogger
    ## * `log template<#log.t,Level,varargs[string,]>`_
    ##
    ## **Examples:**
    ##
    ##   ```Nim
    ##   var rollingLog = newRollingFileLogger("messages.log")
    ##   rollingLog.log(lvlInfo, "this is a message")
    ##   rollingLog.log(lvlError, "error code is: ", 404)
    ##   ```
    if level >= logging.level and level >= logger.levelThreshold:
      if logger.curLine >= logger.maxLines:
        logger.file.close()
        rotate(logger)
        logger.logFiles.inc
        logger.curLine = 0
        logger.file = open(logger.baseName, logger.baseMode,
            bufSize = logger.bufSize)

      writeLine(logger.file, substituteLog(logger.fmtStr, level, args))
      if level >= logger.flushThreshold: flushFile(logger.file)
      logger.curLine.inc

# --------

proc logLoop(level: Level, args: varargs[string, `$`]) =
  for logger in items(handlers):
    if level >= logger.levelThreshold:
      log(logger, level, args)

template log*(level: Level, args: varargs[string, `$`]) =
  ## Logs a message at the specified level to all registered handlers.
  ##
  ## Whether the message is logged depends on both the FileLogger's
  ## `levelThreshold` field and the global log filter set using the
  ## `setLogFilter proc<#setLogFilter,Level>`_.
  ##
  ## **Examples:**
  ##
  ##   ```Nim
  ##   var logger = newConsoleLogger()
  ##   addHandler(logger)
  ##
  ##   log(lvlInfo, "This is an example.")
  ##   ```
  ##
  ## See also:
  ## * `debug template<#debug.t,varargs[string,]>`_
  ## * `info template<#info.t,varargs[string,]>`_
  ## * `notice template<#notice.t,varargs[string,]>`_
  ## * `warn template<#warn.t,varargs[string,]>`_
  ## * `error template<#error.t,varargs[string,]>`_
  ## * `fatal template<#fatal.t,varargs[string,]>`_
  bind logLoop
  bind `%`
  bind logging.level

  if level >= logging.level:
    logLoop(level, args)

template debug*(args: varargs[string, `$`]) =
  ## Logs a debug message to all registered handlers.
  ##
  ## Debug messages are typically useful to the application developer only,
  ## and they are usually disabled in release builds, although this template
  ## does not make that distinction.
  ##
  ## **Examples:**
  ##
  ##   ```Nim
  ##   var logger = newConsoleLogger()
  ##   addHandler(logger)
  ##
  ##   debug("myProc called with arguments: foo, 5")
  ##   ```
  ##
  ## See also:
  ## * `log template<#log.t,Level,varargs[string,]>`_
  ## * `info template<#info.t,varargs[string,]>`_
  ## * `notice template<#notice.t,varargs[string,]>`_
  log(lvlDebug, args)

template info*(args: varargs[string, `$`]) =
  ## Logs an info message to all registered handlers.
  ##
  ## Info messages are typically generated during the normal operation
  ## of an application and are of no particular importance. It can be useful to
  ## aggregate these messages for later analysis.
  ##
  ## **Examples:**
  ##
  ##   ```Nim
  ##   var logger = newConsoleLogger()
  ##   addHandler(logger)
  ##
  ##   info("Application started successfully.")
  ##   ```
  ##
  ## See also:
  ## * `log template<#log.t,Level,varargs[string,]>`_
  ## * `debug template<#debug.t,varargs[string,]>`_
  ## * `notice template<#notice.t,varargs[string,]>`_
  log(lvlInfo, args)

template notice*(args: varargs[string, `$`]) =
  ## Logs an notice to all registered handlers.
  ##
  ## Notices are semantically very similar to info messages, but they are meant
  ## to be messages that the user should be actively notified about, depending
  ## on the application.
  ##
  ## **Examples:**
  ##
  ##   ```Nim
  ##   var logger = newConsoleLogger()
  ##   addHandler(logger)
  ##
  ##   notice("An important operation has completed.")
  ##   ```
  ##
  ## See also:
  ## * `log template<#log.t,Level,varargs[string,]>`_
  ## * `debug template<#debug.t,varargs[string,]>`_
  ## * `info template<#info.t,varargs[string,]>`_
  log(lvlNotice, args)

template warn*(args: varargs[string, `$`]) =
  ## Logs a warning message to all registered handlers.
  ##
  ## A warning is a non-error message that may indicate impending problems or
  ## degraded performance.
  ##
  ## **Examples:**
  ##
  ##   ```Nim
  ##   var logger = newConsoleLogger()
  ##   addHandler(logger)
  ##
  ##   warn("The previous operation took too long to process.")
  ##   ```
  ##
  ## See also:
  ## * `log template<#log.t,Level,varargs[string,]>`_
  ## * `error template<#error.t,varargs[string,]>`_
  ## * `fatal template<#fatal.t,varargs[string,]>`_
  log(lvlWarn, args)

template error*(args: varargs[string, `$`]) =
  ## Logs an error message to all registered handlers.
  ##
  ## Error messages are for application-level error conditions, such as when
  ## some user input generated an exception. Typically, the application will
  ## continue to run, but with degraded functionality or loss of data, and
  ## these effects might be visible to users.
  ##
  ## **Examples:**
  ##
  ##   ```Nim
  ##   var logger = newConsoleLogger()
  ##   addHandler(logger)
  ##
  ##   error("An exception occurred while processing the form.")
  ##   ```
  ##
  ## See also:
  ## * `log template<#log.t,Level,varargs[string,]>`_
  ## * `warn template<#warn.t,varargs[string,]>`_
  ## * `fatal template<#fatal.t,varargs[string,]>`_
  log(lvlError, args)

template fatal*(args: varargs[string, `$`]) =
  ## Logs a fatal error message to all registered handlers.
  ##
  ## Fatal error messages usually indicate that the application cannot continue
  ## to run and will exit due to a fatal condition. This template only logs the
  ## message, and it is the application's responsibility to exit properly.
  ##
  ## **Examples:**
  ##
  ##   ```Nim
  ##   var logger = newConsoleLogger()
  ##   addHandler(logger)
  ##
  ##   fatal("Can't open database -- exiting.")
  ##   ```
  ##
  ## See also:
  ## * `log template<#log.t,Level,varargs[string,]>`_
  ## * `warn template<#warn.t,varargs[string,]>`_
  ## * `error template<#error.t,varargs[string,]>`_
  log(lvlFatal, args)

proc addHandler*(handler: Logger) =
  ## Adds a logger to the list of registered handlers.
  ##
  ## .. warning:: The list of handlers is a thread-local variable. If the given
  ##   handler will be used in multiple threads, this proc should be called in
  ##   each of those threads.
  ##
  ## See also:
  ## * `removeHandler proc`_
  ## * `getHandlers proc<#getHandlers>`_
  runnableExamples:
    var logger = newConsoleLogger()
    addHandler(logger)
    doAssert logger in getHandlers()
  handlers.add(handler)

proc removeHandler*(handler: Logger) =
  ## Removes a logger from the list of registered handlers.
  ##
  ## Note that for n times a logger is registered, n calls to this proc
  ## are required to remove that logger.
  for i, hnd in handlers:
    if hnd == handler:
      handlers.delete(i)
      return

proc getHandlers*(): seq[Logger] =
  ## Returns a list of all the registered handlers.
  ##
  ## See also:
  ## * `addHandler proc<#addHandler,Logger>`_
  return handlers

proc setLogFilter*(lvl: Level) =
  ## Sets the global log filter.
  ##
  ## Messages below the provided level will not be logged regardless of an
  ## individual logger's ``levelThreshold``. By default, all messages are
  ## logged.
  ##
  ## .. warning:: The global log filter is a thread-local variable. If logging
  ##   is being performed in multiple threads, this proc should be called in each
  ##   thread unless it is intended that different threads should log at different
  ##   logging levels.
  ##
  ## See also:
  ## * `getLogFilter proc<#getLogFilter>`_
  runnableExamples:
    setLogFilter(lvlError)
    doAssert getLogFilter() == lvlError
  level = lvl

proc getLogFilter*(): Level =
  ## Gets the global log filter.
  ##
  ## See also:
  ## * `setLogFilter proc<#setLogFilter,Level>`_
  return level

# --------------

when not defined(testing) and isMainModule:
  var L = newConsoleLogger()
  when not defined(js):
    var fL = newFileLogger("test.log", fmtStr = verboseFmtStr)
    var rL = newRollingFileLogger("rolling.log", fmtStr = verboseFmtStr)
    addHandler(fL)
    addHandler(rL)
  addHandler(L)
  for i in 0 .. 25:
    info("hello", i)

  var nilString: string
  info "hello ", nilString
