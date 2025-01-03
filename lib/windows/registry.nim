#
#
#            Nim's Runtime Library
#        (c) Copyright 2016 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module is experimental and its interface may change.

import std/oserrors

when defined(nimPreviewSlimSystem):
  import std/widestrs

type
  HKEY* = uint

const
  HKEY_LOCAL_MACHINE* = HKEY(0x80000002u)
  HKEY_CURRENT_USER* = HKEY(2147483649)

  RRF_RT_ANY = 0x0000ffff
  KEY_WOW64_64KEY = 0x0100
  KEY_WOW64_32KEY = 0x0200
  KEY_READ = 0x00020019
  REG_SZ = 1

proc regOpenKeyEx(hKey: HKEY, lpSubKey: WideCString, ulOptions: int32,
                  samDesired: int32,
                  phkResult: var HKEY): int32 {.
  importc: "RegOpenKeyExW", dynlib: "Advapi32.dll", stdcall.}

proc regCloseKey(hkey: HKEY): int32 {.
  importc: "RegCloseKey", dynlib: "Advapi32.dll", stdcall.}

proc regGetValue(key: HKEY, lpSubKey, lpValue: WideCString;
                 dwFlags: int32 = RRF_RT_ANY, pdwType: ptr int32,
                 pvData: pointer,
                 pcbData: ptr int32): int32 {.
  importc: "RegGetValueW", dynlib: "Advapi32.dll", stdcall.}

template call(f) =
  let err = f
  if err != 0:
    raiseOSError(err.OSErrorCode, astToStr(f))

proc getUnicodeValue*(path, key: string; handle: HKEY): string =
  result = ""
  let hh = newWideCString path
  let kk = newWideCString key
  var bufSize: int32 = int32(0)
  # try a couple of different flag settings:
  var flags: int32 = RRF_RT_ANY
  let err = regGetValue(handle, hh, kk, flags, nil, nil, addr bufSize)
  if err != 0:
    var newHandle: HKEY = default(HKEY)
    call regOpenKeyEx(handle, hh, 0, KEY_READ or KEY_WOW64_64KEY, newHandle)
    call regGetValue(newHandle, nil, kk, flags, nil, nil, addr bufSize)
    if bufSize > 0:
      var res = newWideCString(bufSize)
      call regGetValue(newHandle, nil, kk, flags, nil, addr res[0],
                    addr bufSize)
      result = res $ bufSize
    call regCloseKey(newHandle)
  else:
    if bufSize > 0:
      var res = newWideCString(bufSize)
      call regGetValue(handle, hh, kk, flags, nil, addr res[0],
                    addr bufSize)
      result = res $ bufSize

proc regSetValue(key: HKEY, lpSubKey, lpValueName: WideCString,
                 dwType: int32; lpData: WideCString; cbData: int32): int32 {.
  importc: "RegSetKeyValueW", dynlib: "Advapi32.dll", stdcall.}

proc setUnicodeValue*(path, key, val: string; handle: HKEY) =
  let hh = newWideCString path
  let kk = newWideCString key
  let vv = newWideCString val
  call regSetValue(handle, hh, kk, REG_SZ, vv, (vv.len.int32+1)*2)

