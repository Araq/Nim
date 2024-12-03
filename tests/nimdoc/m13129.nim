# issue #13129

when defined(cpp):
  {.push header: "<vector>".}
  type
    Vector[T] {.importcpp: "std::vector".} = object
  {.pop.}
elif defined(js):
  proc endsWith*(s, suffix: cstring): bool {.noSideEffect,importjs: "#.endsWith(#)".}
elif defined(c):
  proc c_printf*(frmt: cstring): cint {.
    importc: "printf", header: "<stdio.h>", varargs, discardable.}

proc main*() =
  runnableExamples:
    import std/compilesettings
    doAssert not defined(m13129Foo1)
    doAssert defined(m13129Foo2)
    doAssert not defined(nimdoc)
    echo "ok2: backend: " & querySetting(backend)

import std/compilesettings
when defined nimdoc:
  static:
    doAssert defined(m13129Foo1)
    doAssert not defined(m13129Foo2)
    echo "ok1:" & querySetting(backend)

when isMainModule:
  when not defined(js):
    import std/os
    let cache = querySetting(nimcacheDir)
    doAssert cache.len > 0
    let app = getAppFilename()
    doAssert app.isRelativeTo(cache), $(app, cache)
    doAssert querySetting(projectFull) == currentSourcePath
    echo "ok3"
