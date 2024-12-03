#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Implements some helper procs for Nimble (Nim's package manager) support.

import options, msgs, lineinfos, pathutils

import std/[parseutils, strutils, os, tables, sequtils]

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]

import ../dist/checksums/src/checksums/sha1

proc addPath*(conf: ConfigRef; path: AbsoluteDir, info: TLineInfo) =
  if not conf.searchPaths.contains(path):
    conf.searchPaths.insert(path, 0)

type
  Version* = distinct string
  PackageInfo = Table[string, tuple[version, checksum: string]]

proc `$`*(ver: Version): string {.borrow.}

proc newVersion*(ver: string): Version =
  doAssert(ver.len == 0 or ver[0] in {'#', '\0'} + Digits,
           "Wrong version: " & ver)
  return Version(ver)

proc isSpecial(ver: Version): bool =
  return ($ver).len > 0 and ($ver)[0] == '#'

proc isValidVersion(v: string): bool =
  if v.len > 0:
    if v[0] in {'#'} + Digits:
      result = true
    else:
      result = false
  else:
    result = false

proc `<`*(ver: Version, ver2: Version): bool =
  ## This is synced from Nimble's version module.
  result = false
  # Handling for special versions such as "#head" or "#branch".
  if ver.isSpecial or ver2.isSpecial:
    if ver2.isSpecial and ($ver2).normalize == "#head":
      return ($ver).normalize != "#head"

    if not ver2.isSpecial:
      # `#aa111 < 1.1`
      return ($ver).normalize != "#head"

  # Handling for normal versions such as "0.1.0" or "1.0".
  var sVer = string(ver).split('.')
  var sVer2 = string(ver2).split('.')
  for i in 0..<max(sVer.len, sVer2.len):
    var sVerI = 0
    if i < sVer.len:
      discard parseInt(sVer[i], sVerI)
    var sVerI2 = 0
    if i < sVer2.len:
      discard parseInt(sVer2[i], sVerI2)
    if sVerI < sVerI2:
      return true
    elif sVerI == sVerI2:
      discard
    else:
      return false

proc getPathVersionChecksum*(p: string): tuple[name, version, checksum: string] =
  ## Splits path ``p`` in the format
  ## ``/home/user/.nimble/pkgs/package-0.1-febadeaea2345e777f0f6f8433f7f0a52edd5d1b`` into
  ## ``("/home/user/.nimble/pkgs/package", "0.1", "febadeaea2345e777f0f6f8433f7f0a52edd5d1b")``

  result = ("", "", "")

  const checksumSeparator = '-'
  const versionSeparator = '-'
  const specialVersionSepartator = "-#"
  const separatorNotFound = -1

  var checksumSeparatorIndex = p.rfind(checksumSeparator)
  if checksumSeparatorIndex != separatorNotFound:
    result.checksum = p.substr(checksumSeparatorIndex + 1)
    if not result.checksum.isValidSha1Hash():
      result.checksum = ""
      checksumSeparatorIndex = p.len()
  else:
    checksumSeparatorIndex = p.len()

  var versionSeparatorIndex = p.rfind(
    specialVersionSepartator, 0, checksumSeparatorIndex - 1)
  if versionSeparatorIndex != separatorNotFound:
    result.version = p.substr(
      versionSeparatorIndex + 1, checksumSeparatorIndex - 1)
  else:
    versionSeparatorIndex = p.rfind(
      versionSeparator, 0, checksumSeparatorIndex - 1)
    if versionSeparatorIndex != separatorNotFound:
      result.version = p.substr(
        versionSeparatorIndex + 1, checksumSeparatorIndex - 1)
    else:
      versionSeparatorIndex = checksumSeparatorIndex

  result.name = p[0..<versionSeparatorIndex]

proc addPackage*(conf: ConfigRef; packages: var PackageInfo, p: string;
                 info: TLineInfo) =
  let (name, ver, checksum) = getPathVersionChecksum(p)
  if isValidVersion(ver):
    let version = newVersion(ver)
    if packages.getOrDefault(name).version.newVersion < version or
      (not packages.hasKey(name)):
      if checksum.isValidSha1Hash():
        packages[name] = ($version, checksum)
      else:
        packages[name] = ($version, "")
  else:
    localError(conf, info, "invalid package name: " & p)

iterator chosen(packages: PackageInfo): string =
  for key, val in pairs(packages):
    var res = key
    if val.version.len != 0:
      res &= '-'
      res &= val.version
    if val.checksum.len != 0:
      res &= '-'
      res &= val.checksum
    yield res

proc addNimblePath(conf: ConfigRef; p: string, info: TLineInfo) =
  var path = p
  let nimbleLinks = toSeq(walkPattern(p / "*.nimble-link"))
  if nimbleLinks.len > 0:
    # If the user has more than one .nimble-link file then... we just ignore it.
    # Spec for these files is available in Nimble's readme:
    # https://github.com/nim-lang/nimble#nimble-link
    let nimbleLinkLines = readFile(nimbleLinks[0]).splitLines()
    path = nimbleLinkLines[1]
    if not path.isAbsolute():
      path = p / path

  if not contains(conf.searchPaths, AbsoluteDir path):
    message(conf, info, hintPath, path)
    conf.lazyPaths.insert(AbsoluteDir path, 0)

proc addPathRec(conf: ConfigRef; dir: string, info: TLineInfo) =
  var packages: PackageInfo = initTable[string, tuple[version, checksum: string]]()
  var pos = dir.len-1
  if dir[pos] in {DirSep, AltSep}: inc(pos)
  for k,p in os.walkDir(dir):
    if k == pcDir and p[pos] != '.':
      addPackage(conf, packages, p, info)
  for p in packages.chosen:
    addNimblePath(conf, p, info)

proc nimblePath*(conf: ConfigRef; path: AbsoluteDir, info: TLineInfo) =
  addPathRec(conf, path.string, info)
  addNimblePath(conf, path.string, info)
  let i = conf.nimblePaths.find(path)
  if i != -1:
    conf.nimblePaths.delete(i)
  conf.nimblePaths.insert(path, 0)
