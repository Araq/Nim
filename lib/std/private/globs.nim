##[
unstable API, internal use only for now.
this can eventually be moved to std/os and `walkDirRec` can be implemented in terms of this
to avoid duplication
]##

import std/os
when defined(windows):
  from std/strutils import replace

when defined(nimPreviewSlimSystem):
  import std/[assertions, objectdollar]


when defined(nimHasEffectsOf):
  {.experimental: "strictEffects".}
else:
  {.pragma: effectsOf.}

type
  PathEntry* = object
    kind*: PathComponent
    path*: string

iterator walkDirRecFilter*(dir: string, follow: proc(entry: PathEntry): bool = nil,
    relative = false, checkDir = true): PathEntry {.tags: [ReadDirEffect], effectsOf: follow.} =
  ## Improved `os.walkDirRec`.
  #[
  note: a yieldFilter isn't needed because caller can filter at call site, without
  loss of generality, unlike `follow`.

  Future work:
  * need to document
  * add a `sort` option, which can be implemented efficiently only here, not at call site.
  * provide a way to do error reporting, which is tricky because iteration cannot be resumed
  ]#
  var stack = @["."]
  var checkDir = checkDir
  var entry: PathEntry = PathEntry()
  while stack.len > 0:
    let d = stack.pop()
    for k, p in walkDir(dir / d, relative = true, checkDir = checkDir):
      let rel = d / p
      entry.kind = k
      if relative: entry.path = rel
      else: entry.path = dir / rel
      if k in {pcDir, pcLinkToDir}:
        if follow == nil or follow(entry): stack.add rel
      yield entry
    checkDir = false
      # We only check top-level dir, otherwise if a subdir is invalid (eg. wrong
      # permissions), it'll abort iteration and there would be no way to
      # continue iteration.

proc nativeToUnixPath*(path: string): string =
  # pending https://github.com/nim-lang/Nim/pull/13265
  result = path
  when defined(windows):
    if path.len >= 2 and path[0] in {'a'..'z', 'A'..'Z'} and path[1] == ':':
      result[0] = '/'
      result[1] = path[0]
      if path.len > 2 and path[2] != '\\':
        raiseAssert "paths like `C:foo` are currently unsupported, path: " & path
  when DirSep == '\\':
    result = replace(result, '\\', '/')

when isMainModule:
  import std/sugar
  for a in walkDirRecFilter(".", follow = a=>a.path.lastPathPart notin ["nimcache", ".git", "csources_v1", "csources", "bin"]):
    echo a
