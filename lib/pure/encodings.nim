#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Routines for converting between different character encodings. On UNIX, this uses
## the `iconv`:idx: library, on Windows the Windows API.
##
## The following example shows how to change character encodings.
runnableExamples:
  when defined(windows):
    let
      orig = "öäüß"
      # convert `orig` from "UTF-8" to "CP1252"
      cp1252 = convert(orig, "CP1252", "UTF-8")
      # convert `cp1252` from "CP1252" to "ibm850"
      ibm850 = convert(cp1252, "ibm850", "CP1252")
      current = getCurrentEncoding()
    assert orig == "\195\182\195\164\195\188\195\159"
    assert ibm850 == "\148\132\129\225"
    assert convert(ibm850, current, "ibm850") == orig

## The example below uses a reuseable `EncodingConverter` object which is
## created by `open` with `destEncoding` and `srcEncoding` specified. You can use
## `convert` on this object multiple times.
runnableExamples:
  when defined(windows):
    var fromGB2312 = open("utf-8", "gb2312")
    let first = "\203\173\197\194\163\191\210\187" &
        "\203\242\209\204\211\234\200\206\198\189\201\250"
    assert fromGB2312.convert(first) == "谁怕？一蓑烟雨任平生"

    let second = "\211\208\176\215\205\183\200\231" &
        "\208\194\163\172\199\227\184\199\200\231\185\202"
    assert fromGB2312.convert(second) == "有白头如新，倾盖如故"


import std/os
when defined(nimPreviewSlimSystem):
  import std/assertions

when not defined(windows):
  type
    ConverterObj = object
    EncodingConverter* = ptr ConverterObj ## Can convert between two character sets.

else:
  type
    CodePage = distinct int32
    EncodingConverter* = object
      dest, src: CodePage

type
  EncodingError* = object of ValueError ## Exception that is raised
                                        ## for encoding errors.

when defined(windows):
  import std/[parseutils, strutils]
  proc eqEncodingNames(a, b: string): bool =
    var i = 0
    var j = 0
    while i < a.len and j < b.len:
      if a[i] in {'-', '_'}: inc i
      if b[j] in {'-', '_'}: inc j
      if i < a.len and j < b.len and
          a[i].toLowerAscii != b[j].toLowerAscii:
        return false
      inc i
      inc j
    result = i == a.len and j == b.len

  const
    winEncodings = [
      (1, "OEMCP"),            # current OEM codepage
      (037, "IBM037"),         # IBM EBCDIC US-Canada
      (437, "IBM437"),         # OEM United States
      (500, "IBM500"),         # IBM EBCDIC International
      (708, "ASMO-708"),       # Arabic (ASMO 708)
      (709, "ASMO_449"),       # Arabic (ASMO-449+, BCON V4)
      (710, ""),               # Arabic - Transparent Arabic
      (720, "DOS-720"),        # Arabic (Transparent ASMO); Arabic (DOS)
      (737, "ibm737"),         # OEM Greek (formerly 437G); Greek (DOS)
      (775, "ibm775"),         # OEM Baltic; Baltic (DOS)
      (850, "ibm850"),         # OEM Multilingual Latin 1; Western European (DOS)
      (852, "ibm852"),         # OEM Latin 2; Central European (DOS)
      (855, "IBM855"),         # OEM Cyrillic (primarily Russian)
      (857, "ibm857"),         # OEM Turkish; Turkish (DOS)
      (858, "IBM00858"),       # OEM Multilingual Latin 1 + Euro symbol
      (860, "IBM860"),         # OEM Portuguese; Portuguese (DOS)
      (861, "ibm861"),         # OEM Icelandic; Icelandic (DOS)
      (862, "DOS-862"),        # OEM Hebrew; Hebrew (DOS)
      (863, "IBM863"),         # OEM French Canadian; French Canadian (DOS)
      (864, "IBM864"),         # OEM Arabic; Arabic (864)
      (865, "IBM865"),         # OEM Nordic; Nordic (DOS)
      (866, "cp866"),          # OEM Russian; Cyrillic (DOS)
      (869, "ibm869"),         # OEM Modern Greek; Greek, Modern (DOS)
      (870, "IBM870"),         # IBM EBCDIC Multilingual/ROECE (Latin 2); IBM EBCDIC Multilingual Latin 2
      (874, "windows-874"),    # ANSI/OEM Thai (same as 28605, ISO 8859-15); Thai (Windows)
      (875, "cp875"),          # IBM EBCDIC Greek Modern
      (932, "shift_jis"),      # ANSI/OEM Japanese; Japanese (Shift-JIS)
      (936, "gb2312"),         # ANSI/OEM Simplified Chinese (PRC, Singapore); Chinese Simplified (GB2312)
      (936, "gbk"),            # Alias for GB2312 encoding
      (949, "ks_c_5601-1987"), # ANSI/OEM Korean (Unified Hangul Code)
      (950, "big5"),           # ANSI/OEM Traditional Chinese (Taiwan; Hong Kong SAR, PRC); Chinese Traditional (Big5)
      (1026, "IBM1026"),       # IBM EBCDIC Turkish (Latin 5)
      (1047, "IBM01047"),      # IBM EBCDIC Latin 1/Open System
      (1140, "IBM01140"),      # IBM EBCDIC US-Canada (037 + Euro symbol); IBM EBCDIC (US-Canada-Euro)
      (1141, "IBM01141"),      # IBM EBCDIC Germany (20273 + Euro symbol); IBM EBCDIC (Germany-Euro)
      (1142, "IBM01142"),      # IBM EBCDIC Denmark-Norway (20277 + Euro symbol); IBM EBCDIC (Denmark-Norway-Euro)
      (1143, "IBM01143"),      # IBM EBCDIC Finland-Sweden (20278 + Euro symbol); IBM EBCDIC (Finland-Sweden-Euro)
      (1144, "IBM01144"),      # IBM EBCDIC Italy (20280 + Euro symbol); IBM EBCDIC (Italy-Euro)
      (1145, "IBM01145"),      # IBM EBCDIC Latin America-Spain (20284 + Euro symbol); IBM EBCDIC (Spain-Euro)
      (1146, "IBM01146"),      # IBM EBCDIC United Kingdom (20285 + Euro symbol); IBM EBCDIC (UK-Euro)
      (1147, "IBM01147"),      # IBM EBCDIC France (20297 + Euro symbol); IBM EBCDIC (France-Euro)
      (1148, "IBM01148"),      # IBM EBCDIC International (500 + Euro symbol); IBM EBCDIC (International-Euro)
      (1149, "IBM01149"),      # IBM EBCDIC Icelandic (20871 + Euro symbol); IBM EBCDIC (Icelandic-Euro)
      (1200, "utf-16"),        # Unicode UTF-16, little endian byte order (BMP of ISO 10646); available only to managed applications
      (1201, "unicodeFFFE"),   # Unicode UTF-16, big endian byte order; available only to managed applications
      (1250, "windows-1250"),  # ANSI Central European; Central European (Windows)
      (1251, "windows-1251"),  # ANSI Cyrillic; Cyrillic (Windows)
      (1252, "windows-1252"),  # ANSI Latin 1; Western European (Windows)
      (1253, "windows-1253"),  # ANSI Greek; Greek (Windows)
      (1254, "windows-1254"),  # ANSI Turkish; Turkish (Windows)
      (1255, "windows-1255"),  # ANSI Hebrew; Hebrew (Windows)
      (1256, "windows-1256"),  # ANSI Arabic; Arabic (Windows)
      (1257, "windows-1257"),  # ANSI Baltic; Baltic (Windows)
      (1258, "windows-1258"),  # ANSI/OEM Vietnamese; Vietnamese (Windows)

      (1250, "cp-1250"), # ANSI Central European; Central European (Windows)
      (1251, "cp-1251"), # ANSI Cyrillic; Cyrillic (Windows)
      (1252, "cp-1252"), # ANSI Latin 1; Western European (Windows)
      (1253, "cp-1253"), # ANSI Greek; Greek (Windows)
      (1254, "cp-1254"), # ANSI Turkish; Turkish (Windows)
      (1255, "cp-1255"), # ANSI Hebrew; Hebrew (Windows)
      (1256, "cp-1256"), # ANSI Arabic; Arabic (Windows)
      (1257, "cp-1257"), # ANSI Baltic; Baltic (Windows)
      (1258, "cp-1258"), # ANSI/OEM Vietnamese; Vietnamese (Windows)

      (1361, "Johab"),                    # Korean (Johab)
      (10000, "macintosh"),               # MAC Roman; Western European (Mac)
      (10001, "x-mac-japanese"),          # Japanese (Mac)
      (10002, "x-mac-chinesetrad"),       # MAC Traditional Chinese (Big5); Chinese Traditional (Mac)
      (10003, "x-mac-korean"),            # Korean (Mac)
      (10004, "x-mac-arabic"),            # Arabic (Mac)
      (10005, "x-mac-hebrew"),            # Hebrew (Mac)
      (10006, "x-mac-greek"),             # Greek (Mac)
      (10007, "x-mac-cyrillic"),          # Cyrillic (Mac)
      (10008, "x-mac-chinesesimp"),       # MAC Simplified Chinese (GB 2312); Chinese Simplified (Mac)
      (10010, "x-mac-romanian"),          # Romanian (Mac)
      (10017, "x-mac-ukrainian"),         # Ukrainian (Mac)
      (10021, "x-mac-thai"),              # Thai (Mac)
      (10029, "x-mac-ce"),                # MAC Latin 2; Central European (Mac)
      (10079, "x-mac-icelandic"),         # Icelandic (Mac)
      (10081, "x-mac-turkish"),           # Turkish (Mac)
      (10082, "x-mac-croatian"),          # Croatian (Mac)
      (12000, "utf-32"),                  # Unicode UTF-32, little endian byte order; available only to managed applications
      (12001, "utf-32BE"),                # Unicode UTF-32, big endian byte order; available only to managed applications
      (20000, "x-Chinese_CNS"),           # CNS Taiwan; Chinese Traditional (CNS)
      (20001, "x-cp20001"),               # TCA Taiwan
      (20002, "x_Chinese-Eten"),          # Eten Taiwan; Chinese Traditional (Eten)
      (20003, "x-cp20003"),               # IBM5550 Taiwan
      (20004, "x-cp20004"),               # TeleText Taiwan
      (20005, "x-cp20005"),               # Wang Taiwan
      (20105, "x-IA5"),                   # IA5 (IRV International Alphabet No. 5, 7-bit); Western European (IA5)
      (20106, "x-IA5-German"),            # IA5 German (7-bit)
      (20107, "x-IA5-Swedish"),           # IA5 Swedish (7-bit)
      (20108, "x-IA5-Norwegian"),         # IA5 Norwegian (7-bit)
      (20127, "us-ascii"),                # US-ASCII (7-bit)
      (20261, "x-cp20261"),               # T.61
      (20269, "x-cp20269"),               # ISO 6937 Non-Spacing Accent
      (20273, "IBM273"),                  # IBM EBCDIC Germany
      (20277, "IBM277"),                  # IBM EBCDIC Denmark-Norway
      (20278, "IBM278"),                  # IBM EBCDIC Finland-Sweden
      (20280, "IBM280"),                  # IBM EBCDIC Italy
      (20284, "IBM284"),                  # IBM EBCDIC Latin America-Spain
      (20285, "IBM285"),                  # IBM EBCDIC United Kingdom
      (20290, "IBM290"),                  # IBM EBCDIC Japanese Katakana Extended
      (20297, "IBM297"),                  # IBM EBCDIC France
      (20420, "IBM420"),                  # IBM EBCDIC Arabic
      (20423, "IBM423"),                  # IBM EBCDIC Greek
      (20424, "IBM424"),                  # IBM EBCDIC Hebrew
      (20833, "x-EBCDIC-KoreanExtended"), # IBM EBCDIC Korean Extended
      (20838, "IBM-Thai"),                # IBM EBCDIC Thai
      (20866, "koi8-r"),                  # Russian (KOI8-R); Cyrillic (KOI8-R)
      (20871, "IBM871"),                  # IBM EBCDIC Icelandic
      (20880, "IBM880"),                  # IBM EBCDIC Cyrillic Russian
      (20905, "IBM905"),                  # IBM EBCDIC Turkish
      (20924, "IBM00924"),                # IBM EBCDIC Latin 1/Open System (1047 + Euro symbol)
      (20932, "EUC-JP"),                  # Japanese (JIS 0208-1990 and 0121-1990)
      (20936, "x-cp20936"),               # Simplified Chinese (GB2312); Chinese Simplified (GB2312-80)
      (20949, "x-cp20949"),               # Korean Wansung
      (21025, "cp1025"),                  # IBM EBCDIC Cyrillic Serbian-Bulgarian
      (21027, ""),                        # (deprecated)
      (21866, "koi8-u"),                  # Ukrainian (KOI8-U); Cyrillic (KOI8-U)
      (28591, "iso-8859-1"),              # ISO 8859-1 Latin 1; Western European (ISO)
      (28592, "iso-8859-2"),              # ISO 8859-2 Central European; Central European (ISO)
      (28593, "iso-8859-3"),              # ISO 8859-3 Latin 3
      (28594, "iso-8859-4"),              # ISO 8859-4 Baltic
      (28595, "iso-8859-5"),              # ISO 8859-5 Cyrillic
      (28596, "iso-8859-6"),              # ISO 8859-6 Arabic
      (28597, "iso-8859-7"),              # ISO 8859-7 Greek
      (28598, "iso-8859-8"),              # ISO 8859-8 Hebrew; Hebrew (ISO-Visual)
      (28599, "iso-8859-9"),              # ISO 8859-9 Turkish
      (28603, "iso-8859-13"),             # ISO 8859-13 Estonian
      (28605, "iso-8859-15"),             # ISO 8859-15 Latin 9
      (29001, "x-Europa"),                # Europa 3
      (38598, "iso-8859-8-i"),            # ISO 8859-8 Hebrew; Hebrew (ISO-Logical)
      (50220, "iso-2022-jp"),             # ISO 2022 Japanese with no halfwidth Katakana; Japanese (JIS)
      (50221, "csISO2022JP"),             # ISO 2022 Japanese with halfwidth Katakana; Japanese (JIS-Allow 1 byte Kana)
      (50222, "iso-2022-jp"),             # ISO 2022 Japanese JIS X 0201-1989; Japanese (JIS-Allow 1 byte Kana - SO/SI)
      (50225, "iso-2022-kr"),             # ISO 2022 Korean
      (50227, "x-cp50227"),               # ISO 2022 Simplified Chinese; Chinese Simplified (ISO 2022)
      (50229, ""),                        # ISO 2022 Traditional Chinese
      (50930, ""),                        # EBCDIC Japanese (Katakana) Extended
      (50931, ""),                        # EBCDIC US-Canada and Japanese
      (50933, ""),                        # EBCDIC Korean Extended and Korean
      (50935, ""),                        # EBCDIC Simplified Chinese Extended and Simplified Chinese
      (50936, ""),                        # EBCDIC Simplified Chinese
      (50937, ""),                        # EBCDIC US-Canada and Traditional Chinese
      (50939, ""),                        # EBCDIC Japanese (Latin) Extended and Japanese
      (51932, "euc-jp"),                  # EUC Japanese
      (51936, "EUC-CN"),                  # EUC Simplified Chinese; Chinese Simplified (EUC)
      (51949, "euc-kr"),                  # EUC Korean
      (51950, ""),                        # EUC Traditional Chinese
      (52936, "hz-gb-2312"),              # HZ-GB2312 Simplified Chinese; Chinese Simplified (HZ)
      (54936, "GB18030"),                 # Windows XP and later: GB18030 Simplified Chinese (4 byte); Chinese Simplified (GB18030)
      (57002, "x-iscii-de"),              # ISCII Devanagari
      (57003, "x-iscii-be"),              # ISCII Bengali
      (57004, "x-iscii-ta"),              # ISCII Tamil
      (57005, "x-iscii-te"),              # ISCII Telugu
      (57006, "x-iscii-as"),              # ISCII Assamese
      (57007, "x-iscii-or"),              # ISCII Oriya
      (57008, "x-iscii-ka"),              # ISCII Kannada
      (57009, "x-iscii-ma"),              # ISCII Malayalam
      (57010, "x-iscii-gu"),              # ISCII Gujarati
      (57011, "x-iscii-pa"),              # ISCII Punjabi
      (65000, "utf-7"),                   # Unicode (UTF-7)
      (65001, "utf-8")]                   # Unicode (UTF-8)

  when false:
    # not needed yet:
    type
      CpInfo = object
        maxCharSize: int32
        defaultChar: array[0..1, char]
        leadByte: array[0..12-1, char]

    proc getCPInfo(codePage: CodePage, lpCPInfo: var CpInfo): int32 {.
      stdcall, importc: "GetCPInfo", dynlib: "kernel32".}

  proc nameToCodePage*(name: string): CodePage =
    var nameAsInt: int
    if parseInt(name, nameAsInt) == 0: nameAsInt = -1
    for no, na in items(winEncodings):
      if no == nameAsInt or eqEncodingNames(na, name): return CodePage(no)
    result = CodePage(-1)

  proc codePageToName*(c: CodePage): string =
    for no, na in items(winEncodings):
      if no == int(c):
        return if na.len != 0: na else: $no
    result = ""

  proc getACP(): CodePage {.stdcall, importc: "GetACP", dynlib: "kernel32".}
  proc getGetConsoleCP(): CodePage {.stdcall, importc: "GetConsoleCP",
      dynlib: "kernel32".}

  proc multiByteToWideChar(
    codePage: CodePage,
    dwFlags: int32,
    lpMultiByteStr: cstring,
    cbMultiByte: cint,
    lpWideCharStr: cstring,
    cchWideChar: cint): cint {.
      stdcall, importc: "MultiByteToWideChar", dynlib: "kernel32".}

  proc wideCharToMultiByte(
    codePage: CodePage,
    dwFlags: int32,
    lpWideCharStr: cstring,
    cchWideChar: cint,
    lpMultiByteStr: cstring,
    cbMultiByte: cint,
    lpDefaultChar: cstring = nil,
    lpUsedDefaultChar: pointer = nil): cint {.
      stdcall, importc: "WideCharToMultiByte", dynlib: "kernel32".}

else:
  when defined(haiku):
    const iconvDll = "libiconv.so"
  elif defined(macosx):
    const iconvDll = "libiconv.dylib"
  else:
    const iconvDll = "(libc.so.6|libiconv.so)"

  const
    E2BIG = 7.cint
    EINVAL = 22.cint
  when defined(linux):
    const EILSEQ = 84.cint
  elif defined(macosx):
    const EILSEQ = 92.cint
  elif defined(bsd):
    const EILSEQ = 86.cint
  elif defined(solaris):
    const EILSEQ = 88.cint
  elif defined(haiku):
    const EILSEQ = -2147454938.cint

  var errno {.importc, header: "<errno.h>".}: cint

  when defined(bsd):
    {.pragma: importIconv, cdecl, header: "<iconv.h>".}
    when defined(openbsd):
      {.passL: "-liconv".}
  else:
    {.pragma: importIconv, cdecl, dynlib: iconvDll.}

  proc iconvOpen(tocode, fromcode: cstring): EncodingConverter {.
    importc: "iconv_open", importIconv.}
  proc iconvClose(c: EncodingConverter) {.
    importc: "iconv_close", importIconv.}
  proc iconv(c: EncodingConverter, inbuf: ptr cstring, inbytesLeft: ptr csize_t,
             outbuf: ptr cstring, outbytesLeft: ptr csize_t): csize_t {.
    importc: "iconv", importIconv.}

proc getCurrentEncoding*(uiApp = false): string =
  ## Retrieves the current encoding. On Unix, "UTF-8" is always returned.
  ## The `uiApp` parameter is Windows specific. If true, the UI's code-page
  ## is returned, if false, the Console's code-page is returned.
  when defined(windows):
    result = codePageToName(if uiApp: getACP() else: getGetConsoleCP())
  else:
    result = "UTF-8"

proc open*(destEncoding = "UTF-8", srcEncoding = "CP1252"): EncodingConverter =
  ## Opens a converter that can convert from `srcEncoding` to `destEncoding`.
  ## Raises `EncodingError` if it cannot fulfill the request.
  when not defined(windows):
    result = iconvOpen(destEncoding, srcEncoding)
    if result == cast[EncodingConverter](-1):
      raise newException(EncodingError,
        "cannot create encoding converter from " &
        srcEncoding & " to " & destEncoding)
  else:
    result.dest = nameToCodePage(destEncoding)
    result.src = nameToCodePage(srcEncoding)
    if int(result.dest) == -1:
      raise newException(EncodingError,
        "cannot find encoding " & destEncoding)
    if int(result.src) == -1:
      raise newException(EncodingError,
        "cannot find encoding " & srcEncoding)

proc close*(c: EncodingConverter) =
  ## Frees the resources the converter `c` holds.
  when not defined(windows):
    iconvClose(c)

when defined(windows):
  proc convertToWideString(codePage: CodePage, s: string): string =
    # educated guess of capacity:
    var cap = s.len + s.len shr 2
    result = newString(cap*2)
    # convert to utf-16 LE
    var m = multiByteToWideChar(codePage,
                                dwFlags = 0'i32,
                                lpMultiByteStr = cstring(s),
                                cbMultiByte = cint(s.len),
                                lpWideCharStr = cstring(result),
                                cchWideChar = cint(cap))
    if m == 0:
      # try again; ask for capacity:
      cap = multiByteToWideChar(codePage,
                                dwFlags = 0'i32,
                                lpMultiByteStr = cstring(s),
                                cbMultiByte = cint(s.len),
                                lpWideCharStr = nil,
                                cchWideChar = cint(0))
      # and do the conversion properly:
      result = newString(cap*2)
      m = multiByteToWideChar(codePage,
                              dwFlags = 0'i32,
                              lpMultiByteStr = cstring(s),
                              cbMultiByte = cint(s.len),
                              lpWideCharStr = cstring(result),
                              cchWideChar = cint(cap))
      if m == 0: raiseOSError(osLastError())
      setLen(result, m*2)
    elif m <= cap:
      setLen(result, m*2)
    else:
      assert(false) # cannot happen

  proc convertFromWideString(codePage: CodePage, s: string): string =
    let charCount = s.len div 2
    var cap = s.len + s.len shr 2
    result = newString(cap)
    var m = wideCharToMultiByte(codePage,
                                dwFlags = 0'i32,
                                lpWideCharStr = cstring(s),
                                cchWideChar = cint(charCount),
                                lpMultiByteStr = cstring(result),
                                cbMultiByte = cap.cint)
    if m == 0:
      # try again; ask for capacity:
      cap = wideCharToMultiByte(codePage,
                                dwFlags = 0'i32,
                                lpWideCharStr = cstring(s),
                                cchWideChar = cint(charCount),
                                lpMultiByteStr = nil,
                                cbMultiByte = cint(0))
      # and do the conversion properly:
      result = newString(cap)
      m = wideCharToMultiByte(codePage,
                              dwFlags = 0'i32,
                              lpWideCharStr = cstring(s),
                              cchWideChar = cint(charCount),
                              lpMultiByteStr = cstring(result),
                              cbMultiByte = cap.cint)
      if m == 0: raiseOSError(osLastError())
      setLen(result, m)
    elif m <= cap:
      setLen(result, m)
    else:
      assert(false) # cannot happen

  proc convertWin(codePageFrom: CodePage, codePageTo: CodePage,
      s: string): string =
    # special case: empty string: needed because MultiByteToWideChar, WideCharToMultiByte
    # return 0 in case of error
    if s.len == 0: return ""
    # multiByteToWideChar does not support encoding from code pages below
    let unsupported = [1201, 12000, 12001]

    if int(codePageFrom) in unsupported:
      let message = "encoding from " & codePageToName(codePageFrom) & " is not supported on windows"
      raise newException(EncodingError, message)

    if int(codePageTo) in unsupported:
      let message = "encoding to " & codePageToName(codePageTo) & " is not supported on windows"
      raise newException(EncodingError, message)

    # in case it's already UTF-16 little endian - conversion can be simplified
    let wideString = if int(codePageFrom) == 1200: s
                     else: convertToWideString(codePageFrom, s)
    return if int(codePageTo) == 1200: wideString
           else: convertFromWideString(codePageTo, wideString)

  proc convert*(c: EncodingConverter, s: string): string =
    result = convertWin(c.src, c.dest, s)
else:
  proc convert*(c: EncodingConverter, s: string): string =
    ## Converts `s` to `destEncoding` that was given to the converter `c`. It
    ## assumes that `s` is in `srcEncoding`.
    ##
    ## .. warning:: UTF-16BE and UTF-32 conversions are not supported on Windows.
    result = newString(s.len)
    var inLen = csize_t len(s)
    var outLen = csize_t len(result)
    var src = cstring(s)
    var dst = cstring(result)
    var iconvres: csize_t = csize_t(0)
    while inLen > 0:
      iconvres = iconv(c, addr src, addr inLen, addr dst, addr outLen)
      if iconvres == high(csize_t):
        var lerr = errno
        if lerr == EILSEQ or lerr == EINVAL:
          # unknown char, skip
          dst[0] = src[0]
          src = cast[cstring](cast[int](src) + 1)
          dst = cast[cstring](cast[int](dst) + 1)
          dec(inLen)
          dec(outLen)
        elif lerr == E2BIG:
          var offset = cast[int](dst) - cast[int](cstring(result))
          setLen(result, len(result) + inLen.int * 2 + 5)
          # 5 is minimally one utf-8 char
          dst = cast[cstring](cast[int](cstring(result)) + offset)
          outLen = csize_t(len(result) - offset)
        else:
          raiseOSError(lerr.OSErrorCode)
    # iconv has a buffer that needs flushing, specially if the last char is
    # not '\0'
    discard iconv(c, nil, nil, addr dst, addr outLen)
    if iconvres == high(csize_t) and errno == E2BIG:
      var offset = cast[int](dst) - cast[int](cstring(result))
      setLen(result, len(result) + inLen.int * 2 + 5)
      # 5 is minimally one utf-8 char
      dst = cast[cstring](cast[int](cstring(result)) + offset)
      outLen = csize_t(len(result) - offset)
      discard iconv(c, nil, nil, addr dst, addr outLen)
    # trim output buffer
    setLen(result, len(result) - outLen.int)

proc convert*(s: string, destEncoding = "UTF-8",
                         srcEncoding = "CP1252"): string =
  ## Converts `s` to `destEncoding`. It assumed that `s` is in `srcEncoding`.
  ## This opens a converter, uses it and closes it again and is thus more
  ## convenient but also likely less efficient than re-using a converter.
  ##
  ## .. warning:: UTF-16BE and UTF-32 conversions are not supported on Windows.
  var c = open(destEncoding, srcEncoding)
  try:
    result = convert(c, s)
  finally:
    close(c)
