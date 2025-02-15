#
#
#            Nim's Runtime Library
#        (c) Copyright 2022 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#


## The `std/envvars` module implements environment variable handling.
import std/oserrors

when defined(nimPreviewSlimSystem):
  import std/assertions

type
  ReadEnvEffect* = object of ReadIOEffect   ## Effect that denotes a read
                                            ## from an environment variable.
  WriteEnvEffect* = object of WriteIOEffect ## Effect that denotes a write
                                            ## to an environment variable.


when not defined(nimscript):
  when defined(nodejs):
    proc getEnv*(key: string, default = ""): string {.tags: [ReadEnvEffect].} =
      var ret = default.cstring
      let key2 = key.cstring
      {.emit: "const value = process.env[`key2`];".}
      {.emit: "if (value !== undefined) { `ret` = value };".}
      result = $ret

    proc existsEnv*(key: string): bool {.tags: [ReadEnvEffect].} =
      var key2 = key.cstring
      var ret: bool
      {.emit: "`ret` = `key2` in process.env;".}
      result = ret

    proc putEnv*(key, val: string) {.tags: [WriteEnvEffect].} =
      var key2 = key.cstring
      var val2 = val.cstring
      {.emit: "process.env[`key2`] = `val2`;".}

    proc delEnv*(key: string) {.tags: [WriteEnvEffect].} =
      var key2 = key.cstring
      {.emit: "delete process.env[`key2`];".}

    iterator envPairsImpl(): tuple[key, value: string] {.tags: [ReadEnvEffect].} =
      var num: int
      var keys: RootObj
      {.emit: "`keys` = Object.keys(process.env); `num` = `keys`.length;".}
      for i in 0..<num:
        var key, value: cstring
        {.emit: "`key` = `keys`[`i`]; `value` = process.env[`key`];".}
        yield ($key, $value)

  # commented because it must keep working with js+VM
  # elif defined(js):
  #   {.error: "requires -d:nodejs".}

  else:

    when defined(windows):
      proc c_putenv(envstring: cstring): cint {.importc: "_putenv", header: "<stdlib.h>".}
      from std/private/win_setenv import setEnvImpl
      import std/winlean
      when defined(nimPreviewSlimSystem):
        import std/widestrs

      type wchar_t {.importc: "wchar_t", header: "<stdlib.h>".} = int16
      proc c_wgetenv(varname: ptr wchar_t): ptr wchar_t {.importc: "_wgetenv",
          header: "<stdlib.h>".}
      proc getEnvImpl(env: cstring): WideCString =
        let r: WideCString = env.newWideCString
        cast[WideCString](c_wgetenv(cast[ptr wchar_t](r)))
    else:
      proc c_getenv(env: cstring): cstring {.
        importc: "getenv", header: "<stdlib.h>".}
      proc c_setenv(envname: cstring, envval: cstring, overwrite: cint): cint {.importc: "setenv", header: "<stdlib.h>".}
      proc c_unsetenv(env: cstring): cint {.importc: "unsetenv", header: "<stdlib.h>".}
      proc getEnvImpl(env: cstring): cstring = c_getenv(env)

    proc getEnv*(key: string, default = ""): string {.tags: [ReadEnvEffect].} =
      ## Returns the value of the `environment variable`:idx: named `key`.
      ##
      ## If the variable does not exist, `""` is returned. To distinguish
      ## whether a variable exists or it's value is just `""`, call
      ## `existsEnv(key) proc`_.
      ##
      ## See also:
      ## * `existsEnv proc`_
      ## * `putEnv proc`_
      ## * `delEnv proc`_
      ## * `envPairs iterator`_
      runnableExamples:
        assert getEnv("unknownEnv") == ""
        assert getEnv("unknownEnv", "doesn't exist") == "doesn't exist"

      let env = getEnvImpl(key)
      if env == nil:
        result = default
      else:
        result = $env

    proc existsEnv*(key: string): bool {.tags: [ReadEnvEffect].} =
      ## Checks whether the environment variable named `key` exists.
      ## Returns true if it exists, false otherwise.
      ##
      ## See also:
      ## * `getEnv proc`_
      ## * `putEnv proc`_
      ## * `delEnv proc`_
      ## * `envPairs iterator`_
      runnableExamples:
        assert not existsEnv("unknownEnv")

      result = getEnvImpl(key) != nil

    proc putEnv*(key, val: string) {.tags: [WriteEnvEffect].} =
      ## Sets the value of the `environment variable`:idx: named `key` to `val`.
      ## If an error occurs, `OSError` is raised.
      ##
      ## See also:
      ## * `getEnv proc`_
      ## * `existsEnv proc`_
      ## * `delEnv proc`_
      ## * `envPairs iterator`_
      when defined(windows):
        if key.len == 0 or '=' in key:
          raise newException(OSError, "invalid key, got: " & $(key, val))
        if setEnvImpl(key, val, 1'i32) != 0'i32:
          raiseOSError(osLastError(), $(key, val))
      else:
        if c_setenv(key, val, 1'i32) != 0'i32:
          raiseOSError(osLastError(), $(key, val))

    proc delEnv*(key: string) {.tags: [WriteEnvEffect].} =
      ## Deletes the `environment variable`:idx: named `key`.
      ## If an error occurs, `OSError` is raised.
      ##
      ## See also:ven
      ## * `getEnv proc`_
      ## * `existsEnv proc`_
      ## * `putEnv proc`_
      ## * `envPairs iterator`_
      template bail = raiseOSError(osLastError(), key)
      when defined(windows):
        #[
        # https://docs.microsoft.com/en-us/cpp/c-runtime-library/reference/putenv-s-wputenv-s?view=msvc-160
        > You can remove a variable from the environment by specifying an empty string (that is, "") for value_string
        note that nil is not legal
        ]#
        if key.len == 0 or '=' in key:
          raise newException(OSError, "invalid key, got: " & key)
        let envToDel = key & "="
        if c_putenv(cstring envToDel) != 0'i32: bail
      else:
        if c_unsetenv(key) != 0'i32: bail

    when defined(windows):
      when defined(cpp):
        proc strEnd(cstr: WideCString, c = 0'i32): WideCString {.importcpp: "(NI16*)wcschr((const wchar_t *)#, #)",
            header: "<string.h>".}
      else:
        proc strEnd(cstr: WideCString, c = 0'i32): WideCString {.importc: "wcschr",
            header: "<string.h>".}
    elif defined(macosx) and not defined(ios) and not defined(emscripten):
      # From the manual:
      # Shared libraries and bundles don't have direct access to environ,
      # which is only available to the loader ld(1) when a complete program
      # is being linked.
      # The environment routines can still be used, but if direct access to
      # environ is needed, the _NSGetEnviron() routine, defined in
      # <crt_externs.h>, can be used to retrieve the address of environ
      # at runtime.
      proc NSGetEnviron(): ptr cstringArray {.importc: "_NSGetEnviron",
          header: "<crt_externs.h>".}
    elif defined(haiku):
      var gEnv {.importc: "environ", header: "<stdlib.h>".}: cstringArray
    else:
      var gEnv {.importc: "environ".}: cstringArray

    iterator envPairsImpl(): tuple[key, value: string] {.tags: [ReadEnvEffect].} =
      when defined(windows):
        let env = getEnvironmentStringsW()
        var e = env
        if e != nil:
          while true:
            let eend = strEnd(e)
            let kv = $e
            let p = find(kv, '=')
            yield (substr(kv, 0, p-1), substr(kv, p+1))
            e = cast[WideCString](cast[ByteAddress](eend)+2)
            if int(eend[1]) == 0: break
          discard freeEnvironmentStringsW(env)
      else:
        var i = 0
        when defined(macosx) and not defined(ios) and not defined(emscripten):
          var gEnv = NSGetEnviron()[]
        while gEnv[i] != nil:
          let kv = $gEnv[i]
          inc(i)
          let p = find(kv, '=')
          yield (substr(kv, 0, p-1), substr(kv, p+1))

proc envPairsImplSeq(): seq[tuple[key, value: string]] = raiseAssert "implemented in the vmops" # vmops

iterator envPairs*(): tuple[key, value: string] {.tags: [ReadEnvEffect].} =
  ## Iterate over all `environments variables`:idx:.
  ##
  ## In the first component of the tuple is the name of the current variable stored,
  ## in the second its value.
  ##
  ## Works in native backends, nodejs and vm, like the following APIs:
  ## * `getEnv proc`_
  ## * `existsEnv proc`_
  ## * `putEnv proc`_
  ## * `delEnv proc`_
  when nimvm:
    for ai in envPairsImplSeq(): yield ai
  else:
    when defined(nimscript): discard
    else:
      for ai in envPairsImpl(): yield ai
