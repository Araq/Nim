#[
Copyright (c) Facebook, Inc. and its affiliates.
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
    https://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Adapted `setenv` from https://github.com/facebook/folly/blob/master/folly/portability/Stdlib.cpp
translated from C to nim.
]#

#[
Introduced in https://github.com/facebook/folly/commit/5d8ca09a3f96afefb44e35808f03651a096ab9c7

TODO:
check errno_t vs cint
]#

when not defined(windows): discard
else:
  when defined(nimPreviewSlimSystem):
    import std/widestrs

  type wchar_t  {.importc: "wchar_t".} = int16

  proc setEnvironmentVariableW*(lpName, lpValue: WideCString): int32 {.
    stdcall, dynlib: "kernel32", importc: "SetEnvironmentVariableW", sideEffect.}
    # same as winlean.setEnvironmentVariableA

  proc c_getenv(varname: cstring): cstring {.importc: "getenv", header: "<stdlib.h>".}
  proc c_wputenv(envstring: ptr wchar_t): cint {.importc: "_wputenv", header: "<stdlib.h>".}
  proc c_wgetenv(varname: ptr wchar_t): ptr wchar_t {.importc: "_wgetenv", header: "<stdlib.h>".}

  var errno {.importc, header: "<errno.h>".}: cint
  var genviron {.importc: "_environ".}: ptr ptr char
    # xxx `ptr UncheckedArray[WideCString]` did not work

  proc wcstombs(wcstr: ptr char, mbstr: ptr wchar_t, count: csize_t): csize_t {.importc, header: "<stdlib.h>".}
    # xxx cint vs errno_t?

  proc setEnvImpl*(name: string, value: string, overwrite: cint): cint =
    const EINVAL = cint(22)
    let wideName: WideCString = newWideCString(name)
    if overwrite == 0 and c_wgetenv(cast[ptr wchar_t](wideName)) != nil:
      return 0

    if value != "":
      let envstring: WideCString = newWideCString(name & "=" & value)
      let e = c_wputenv(cast[ptr wchar_t](envstring))
      if e != 0:
        errno = EINVAL
        return -1
      return 0
    #[
    We are trying to set the value to an empty string, but `_putenv` deletes
    entries if the value is an empty string, and just calling
    SetEnvironmentVariableA doesn't update `_environ`,
    so we have to do these terrible things.
    ]#
    let envstring: WideCString = newWideCString(name & "=  ")
    if c_wputenv(cast[ptr wchar_t](envstring)) != 0:
      errno = EINVAL
      return -1
    # Here lies the documentation we blatently ignore to make this work.
    var s = cast[WideCString](c_wgetenv(cast[ptr wchar_t](wideName)))
    s[0] = Utf16Char('\0')
    #[
    This would result in a double null termination, which normally signifies the
    end of the environment variable list, so we stick a completely empty
    environment variable into the list instead.
    ]#
    s = cast[WideCString](c_wgetenv(cast[ptr wchar_t](wideName)))
    s[1] = Utf16Char('=')
    #[
    If genviron is null, the MBCS environment has not been initialized
    yet, and we don't need to try to update it. We have to do this otherwise
    we'd be forcing the initialization and maintenance of the MBCS environment
    even though it's never actually used in most programs.
    ]#
    if genviron != nil:

      # wcstombs returns `high(csize_t)` if any characters cannot be represented
      # in the current codepage. Skip updating MBCS environment in this case.
      # For some reason, second `wcstombs` can find non-convertible characters
      # that the first `wcstombs` cannot.
      let requiredSizeS = wcstombs(nil, cast[ptr wchar_t](wideName), 0)
      if requiredSizeS != high(csize_t):
        let requiredSize = requiredSizeS.int
        var buf = newSeq[char](requiredSize + 1)
        let buf2 = buf[0].addr
        if wcstombs(buf2, cast[ptr wchar_t](wideName), csize_t(requiredSize + 1)) != high(csize_t):
          var ptrToEnv = c_getenv(cast[cstring](buf2))
          ptrToEnv[0] = '\0'
          ptrToEnv = c_getenv(cast[cstring](buf2))
          ptrToEnv[1] = '='

    # And now, we have to update the outer environment to have a proper empty value.
    if setEnvironmentVariableW(wideName, value.newWideCString) == 0:
      errno = EINVAL
      return -1
    return 0
