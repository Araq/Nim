discard """
  matrix: "--mm:refc; --mm:orc"
  targets: "c js"
"""

import std/mimetypes
import std/assertions


template main() =
  var m = newMimetypes()
  doAssert m.getMimetype("mp4") == "video/mp4"
  doAssert m.getExt("application/json") == "json"
  doAssert m.getMimetype("json") == "application/json"
  m.register("foo", "baa")
  doAssert m.getMimetype("foo") == "baa"
  doAssert m.getMimetype("txt") == "text/plain"
  doAssert m.getExt("text/plain") == "txt"
  # see also `runnableExamples`.
  # xxx we should have a way to avoid duplicating code between runnableExamples and tests

  doAssert m.getMimetype("nim") == "text/nim"
  doAssert m.getMimetype("nimble") == "text/nimble"
  doAssert m.getMimetype("nimf") == "text/nim"
  doAssert m.getMimetype("nims") == "text/nim"

static: main()
main()
