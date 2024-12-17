discard """
  targets: "c cpp js"
"""

import std/strutils

template forceConst(a: untyped): untyped =
  ## Force evaluation at CT, but `static(a)` is simpler
  const ret = a
  ret

proc isNimVm(): bool =
  when nimvm: result = true
  else: result = false

block:
  doAssert forceConst(isNimVm())
  doAssert not isNimVm()
  doAssert forceConst(isNimVm()) == static(isNimVm())
  doAssert forceConst(isNimVm()) == isNimVm().static

template main() =
  # xxx merge more const related tests here
  const ct = CompileTime
    # refs https://github.com/timotheecour/Nim/issues/718, apparently `CompileTime`
    # isn't cached, which seems surprising.
  block:
    const
      a = """
    Version $1|
    Compiled at: $2, $3
    """ % [NimVersion & spaces(44-len(NimVersion)), CompileDate, ct]
    let b = $a
    doAssert ct in b, $(b, ct)
    doAssert NimVersion in b

  block: # Test for fix on broken const unpacking
    template mytemp() =
      const
        (x, increment) = (4, true)
        a = 100
      discard (x, increment, a)
    mytemp()

  block: # bug #12334
    block:
      const b: cstring = "foo"
      var c = b
      doAssert c == "foo"
    block:
      const a = "foo"
      const b: cstring = a
      var c = b
      doAssert c == "foo"


  when not defined(js):
    block: # bug #19698
      type
        FormatInfo = object
          readproc: ReadProc
          writeproc: WriteProc

        ReadProc = proc (s: pointer)
        WriteProc = proc (s: pointer)

      func initFormatInfo(readproc: ReadProc, writeproc: WriteProc = nil): FormatInfo {.compileTime.} =
        result = FormatInfo(readproc: readproc, writeproc: nil)

      proc readSampleImage(s: pointer) = discard

      const SampleFormatInfo = initFormatInfo(readproc = readSampleImage)

      const KnownFormats = [SampleFormatInfo]

      func sortedFormatInfos(): array[len KnownFormats, FormatInfo] {.compileTime.} =
        result = default(array[len KnownFormats, FormatInfo])
        for i, info in KnownFormats:
          result[i] = info

      const SortedFormats = sortedFormatInfos()

      discard SortedFormats

static: main()
main()
