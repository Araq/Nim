import std/[os, uri, strformat, strutils]
import std/private/gitutils

when defined(nimPreviewSlimSystem):
  import std/assertions

proc exec(cmd: string) =
  echo "deps.cmd: " & cmd
  let status = execShellCmd(cmd)
  doAssert status == 0, cmd

proc execRetry(cmd: string) =
  let ok = retryCall(call = block:
    let status = execShellCmd(cmd)
    let result = status == 0
    if not result:
      echo fmt"failed command: '{cmd}', status: {status}"
    result)
  doAssert ok, cmd

proc cloneDependency*(destDirBase: string, url: string, commit = commitHead,
                      appendRepoName = true, allowBundled = false) =
  let destDirBase = destDirBase.absolutePath
  let p = url.parseUri.path
  let name = p.splitFile.name
  var destDir = destDirBase
  if appendRepoName: destDir = destDir / name
  let quotedDestDir = destDir.quoteShell
  if not dirExists(destDir):
    # note: old code used `destDir / .git` but that wouldn't prevent git clone
    # from failing
    execRetry fmt"git clone -q {url} {quotedDestDir}"
  if isGitRepo(destDir):
    let oldDir = getCurrentDir()
    setCurrentDir(destDir)
    try:
      execRetry "git fetch -q"
      exec fmt"git checkout -q {commit}"
    finally:
      setCurrentDir(oldDir)
  elif allowBundled:
    discard "this dependency was bundled with Nim, don't do anything"
  else:
    quit "FAILURE: " & destdir & " already exists but is not a git repo"

proc updateSubmodules*(dir: string, allowBundled = false) =
  if isGitRepo(dir):
    let oldDir = getCurrentDir()
    setCurrentDir(dir)
    try:
      exec "git submodule update --init"
    finally:
      setCurrentDir(oldDir)
  elif allowBundled:
    discard "this dependency was bundled with Nim, don't do anything"
  else:
    quit "FAILURE: " & dir & " already exists but is not a git repo"
