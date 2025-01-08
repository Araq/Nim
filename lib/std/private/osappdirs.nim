## .. importdoc:: paths.nim, dirs.nim

include system/inclrtl
import std/envvars
import std/private/ospaths2

proc getHomeDir*(): string {.rtl, extern: "nos$1",
  tags: [ReadEnvEffect, ReadIOEffect].} =
  ## Returns the home directory of the current user.
  ##
  ## This proc is wrapped by the `expandTilde proc`_
  ## for the convenience of processing paths coming from user configuration files.
  ##
  ## See also:
  ## * `getDataDir proc`_
  ## * `getConfigDir proc`_
  ## * `getTempDir proc`_
  ## * `expandTilde proc`_
  ## * `getCurrentDir proc`_
  ## * `setCurrentDir proc`_
  runnableExamples:
    import std/os
    assert getHomeDir() == expandTilde("~")

  when defined(windows): return getEnv("USERPROFILE") & "\\"
  else: return getEnv("HOME") & "/"

proc getDataDir*(): string {.rtl, extern: "nos$1"
  tags: [ReadEnvEffect, ReadIOEffect].} =
  ## Returns the data directory of the current user for applications.
  ## 
  ## On non-Windows OSs, this proc conforms to the XDG Base Directory
  ## spec. Thus, this proc returns the value of the `XDG_DATA_HOME` environment
  ## variable if it is set, otherwise it returns the default configuration
  ## directory ("~/.local/share" or "~/Library/Application Support" on macOS).
  ## 
  ## See also:
  ## * `getHomeDir proc`_
  ## * `getConfigDir proc`_
  ## * `getTempDir proc`_
  ## * `expandTilde proc`_
  ## * `getCurrentDir proc`_
  ## * `setCurrentDir proc`_
  when defined(windows):
    result = getEnv("APPDATA")
  elif defined(macosx):
    result = getEnv("XDG_DATA_HOME", getEnv("HOME") / "Library" / "Application Support")
  else:
    result = getEnv("XDG_DATA_HOME", getEnv("HOME") / ".local" / "share")
  result.normalizePathEnd(trailingSep = true)

proc getConfigDir*(): string {.rtl, extern: "nos$1",
  tags: [ReadEnvEffect, ReadIOEffect].} =
  ## Returns the config directory of the current user for applications.
  ##
  ## On non-Windows OSs, this proc conforms to the XDG Base Directory
  ## spec. Thus, this proc returns the value of the `XDG_CONFIG_HOME` environment
  ## variable if it is set, otherwise it returns the default configuration
  ## directory ("~/.config/").
  ##
  ## An OS-dependent trailing slash is always present at the end of the
  ## returned string: `\\` on Windows and `/` on all other OSs.
  ##
  ## See also:
  ## * `getHomeDir proc`_
  ## * `getDataDir proc`_
  ## * `getTempDir proc`_
  ## * `expandTilde proc`_
  ## * `getCurrentDir proc`_
  ## * `setCurrentDir proc`_
  when defined(windows):
    result = getEnv("APPDATA")
  else:
    result = getEnv("XDG_CONFIG_HOME", getEnv("HOME") / ".config")
  result.normalizePathEnd(trailingSep = true)

proc getCacheDir*(): string =
  ## Returns the cache directory of the current user for applications.
  ##
  ## This makes use of the following environment variables:
  ##
  ## * On Windows: `getEnv("LOCALAPPDATA")`
  ##
  ## * On macOS: `getEnv("XDG_CACHE_HOME", getEnv("HOME") / "Library/Caches")`
  ##
  ## * On other platforms: `getEnv("XDG_CACHE_HOME", getEnv("HOME") / ".cache")`
  ##
  ## **See also:**
  ## * `getHomeDir proc`_
  ## * `getTempDir proc`_
  ## * `getConfigDir proc`_
  ## * `getDataDir proc`_
  # follows https://crates.io/crates/platform-dirs
  when defined(windows):
    result = getEnv("LOCALAPPDATA")
  elif defined(osx):
    result = getEnv("XDG_CACHE_HOME", getEnv("HOME") / "Library/Caches")
  else:
    result = getEnv("XDG_CACHE_HOME", getEnv("HOME") / ".cache")
  result.normalizePathEnd(false)

proc getCacheDir*(app: string): string =
  ## Returns the cache directory for an application `app`.
  ##
  ## * On Windows, this uses: `getCacheDir() / app / "cache"`
  ## * On other platforms, this uses: `getCacheDir() / app`
  when defined(windows):
    getCacheDir() / app / "cache"
  else:
    getCacheDir() / app


when defined(windows):
  type DWORD = uint32

  when defined(nimPreviewSlimSystem):
    import std/widestrs

  proc getTempPath(
    nBufferLength: DWORD, lpBuffer: WideCString
  ): DWORD {.stdcall, dynlib: "kernel32.dll", importc: "GetTempPathW".} =
    ## Retrieves the path of the directory designated for temporary files.

template getEnvImpl(result: var string, tempDirList: openArray[string]) =
  for dir in tempDirList:
    if existsEnv(dir):
      result = getEnv(dir)
      break

template getTempDirImpl(result: var string) =
  when defined(windows):
    getEnvImpl(result, ["TMP", "TEMP", "USERPROFILE"])
  else:
    getEnvImpl(result, ["TMPDIR", "TEMP", "TMP", "TEMPDIR"])

proc getTempDir*(): string {.rtl, extern: "nos$1",
  tags: [ReadEnvEffect, ReadIOEffect].} =
  ## Returns the temporary directory of the current user for applications to
  ## save temporary files in.
  ##
  ## On Windows, it calls [GetTempPath](https://docs.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-gettemppathw).
  ## On Posix based platforms, it will check `TMPDIR`, `TEMP`, `TMP` and `TEMPDIR` environment variables in order.
  ## On all platforms, `/tmp` will be returned if the procs fails.
  ##
  ## You can override this implementation
  ## by adding `-d:tempDir=mytempname` to your compiler invocation.
  ##
  ## **Note:** This proc does not check whether the returned path exists.
  ##
  ## See also:
  ## * `getHomeDir proc`_
  ## * `getConfigDir proc`_
  ## * `expandTilde proc`_
  ## * `getCurrentDir proc`_
  ## * `setCurrentDir proc`_
  const tempDirDefault = "/tmp"
  when defined(tempDir):
    const tempDir {.strdefine.}: string = tempDirDefault
    result = tempDir
  else:
    result = ""
    when nimvm:
      getTempDirImpl(result)
    else:
      when defined(windows):
        let size = getTempPath(0, nil)
        # If the function fails, the return value is zero.
        if size > 0:
          let buffer = newWideCString(size.int)
          if getTempPath(size, buffer) > 0:
            result = $buffer
      elif defined(android): result = "/data/local/tmp"
      else:
        getTempDirImpl(result)
    if result.len == 0:
      result = tempDirDefault
  normalizePathEnd(result, trailingSep=true)
