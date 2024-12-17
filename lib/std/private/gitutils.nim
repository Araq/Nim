##[
internal API for now, API subject to change
]##

# xxx move other git utilities here; candidate for stdlib.

import std/[os, paths, osproc, strutils, tempfiles]

when defined(nimPreviewSlimSystem):
  import std/[assertions, syncio]

const commitHead* = "HEAD"

template retryCall*(maxRetry = 3, backoffDuration = 1.0, call: untyped): bool =
  ## Retry `call` up to `maxRetry` times with exponential backoff and initial
  ## duraton of `backoffDuration` seconds.
  ## This is in particular useful for network commands that can fail.
  runnableExamples:
    doAssert not retryCall(maxRetry = 2, backoffDuration = 0.1, false)
    var i = 0
    doAssert: retryCall(maxRetry = 3, backoffDuration = 0.1, (i.inc; i >= 3))
    doAssert retryCall(call = true)
  var result = false
  var t = backoffDuration
  for i in 0..<maxRetry:
    if call:
      result = true
      break
    if i == maxRetry - 1: break
    sleep(int(t * 1000))
    t = t * 2 # exponential backoff
  result

proc isGitRepo*(dir: string): bool =
  ## Avoid calling git since it depends on /bin/sh existing and fails in Nix.
  return fileExists(dir/".git/HEAD")

proc diffFiles*(path1, path2: string): tuple[output: string, same: bool] =
  ## Returns a human readable diff of files `path1`, `path2`, the exact form of
  ## which is implementation defined.
  # This could be customized, e.g. non-git diff with `diff -uNdr`, or with
  # git diff options (e.g. --color-moved, --word-diff).
  # in general, `git diff` has more options than `diff`.
  result = default(tuple[output: string, same: bool])
  var status = 0
  (result.output, status) = execCmdEx("git diff --no-index $1 $2" % [path1.quoteShell, path2.quoteShell])
  doAssert (status == 0) or (status == 1)
  result.same = status == 0

proc diffStrings*(a, b: string): tuple[output: string, same: bool] =
  ## Returns a human readable diff of `a`, `b`, the exact form of which is
  ## implementation defined.
  ## See also `experimental.diff`.
  runnableExamples:
    let a = "ok1\nok2\nok3\n"
    let b = "ok1\nok2 alt\nok3\nok4\n"
    let (c, same) = diffStrings(a, b)
    doAssert not same
    let (c2, same2) = diffStrings(a, a)
    doAssert same2
  runnableExamples("-r:off"):
    let a = "ok1\nok2\nok3\n"
    let b = "ok1\nok2 alt\nok3\nok4\n"
    echo diffStrings(a, b).output

  template tmpFileImpl(prefix, str): auto =
    let path = genTempPath(prefix, "")
    writeFile(path, str)
    path
  let patha = tmpFileImpl("diffStrings_a_", a)
  let pathb = tmpFileImpl("diffStrings_b_", b)
  defer:
    removeFile(patha)
    removeFile(pathb)
  result = diffFiles(patha, pathb)
