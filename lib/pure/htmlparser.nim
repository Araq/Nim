#
#
#            Nim's Runtime Library
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## **NOTE**: The behaviour might change in future versions as it is not
## clear what "*wild* HTML the real world uses" really implies.
##
## It can be used to parse a wild HTML document and output it as valid XHTML
## document (well, if you are lucky):
##   ```Nim
##   echo loadHtml("mydirty.html")
##   ```
##
## Every tag in the resulting tree is in lower case.
##
## **Note:** The resulting `XmlNode` already uses the `clientData` field,
## so it cannot be used by clients of this library.
##
## Example: Transforming hyperlinks
## ================================
##
## This code demonstrates how you can iterate over all the tags in an HTML file
## and write back the modified version. In this case we look for hyperlinks
## ending with the extension `.rst` and convert them to `.html`.
##
##   ```Nim test
##   import std/htmlparser
##   import std/xmltree  # To use '$' for XmlNode
##   import std/strtabs  # To access XmlAttributes
##   import std/os       # To use splitFile
##   import std/strutils # To use cmpIgnoreCase
##
##   proc transformHyperlinks() =
##     let html = loadHtml("input.html")
##
##     for a in html.findAll("a"):
##       if a.attrs.hasKey "href":
##         let (dir, filename, ext) = splitFile(a.attrs["href"])
##         if cmpIgnoreCase(ext, ".rst") == 0:
##           a.attrs["href"] = dir / filename & ".html"
##
##     writeFile("output.html", $html)
##   ```

{.deprecated: "use `nimble install htmlparser` and import `pkg/htmlparser` instead".}

import std/[strutils, streams, parsexml, xmltree, unicode, strtabs]

when defined(nimPreviewSlimSystem):
  import std/syncio

type
  HtmlTag* = enum  ## list of all supported HTML tags; order will always be
                   ## alphabetically
    tagUnknown,    ## unknown HTML element
    tagA,          ## the HTML `a` element
    tagAbbr,       ## the deprecated HTML `abbr` element
    tagAcronym,    ## the HTML `acronym` element
    tagAddress,    ## the HTML `address` element
    tagApplet,     ## the deprecated HTML `applet` element
    tagArea,       ## the HTML `area` element
    tagArticle,    ## the HTML `article` element
    tagAside,      ## the HTML `aside` element
    tagAudio,      ## the HTML `audio` element
    tagB,          ## the HTML `b` element
    tagBase,       ## the HTML `base` element
    tagBdi,        ## the HTML `bdi` element
    tagBdo,        ## the deprecated HTML `dbo` element
    tagBasefont,   ## the deprecated HTML `basefont` element
    tagBig,        ## the HTML `big` element
    tagBlockquote, ## the HTML `blockquote` element
    tagBody,       ## the HTML `body` element
    tagBr,         ## the HTML `br` element
    tagButton,     ## the HTML `button` element
    tagCanvas,     ## the HTML `canvas` element
    tagCaption,    ## the HTML `caption` element
    tagCenter,     ## the deprecated HTML `center` element
    tagCite,       ## the HTML `cite` element
    tagCode,       ## the HTML `code` element
    tagCol,        ## the HTML `col` element
    tagColgroup,   ## the HTML `colgroup` element
    tagCommand,    ## the HTML `command` element
    tagDatalist,   ## the HTML `datalist` element
    tagDd,         ## the HTML `dd` element
    tagDel,        ## the HTML `del` element
    tagDetails,    ## the HTML `details` element
    tagDfn,        ## the HTML `dfn` element
    tagDialog,     ## the HTML `dialog` element
    tagDiv,        ## the HTML `div` element
    tagDir,        ## the deprecated HTLM `dir` element
    tagDl,         ## the HTML `dl` element
    tagDt,         ## the HTML `dt` element
    tagEm,         ## the HTML `em` element
    tagEmbed,      ## the HTML `embed` element
    tagFieldset,   ## the HTML `fieldset` element
    tagFigcaption, ## the HTML `figcaption` element
    tagFigure,     ## the HTML `figure` element
    tagFont,       ## the deprecated HTML `font` element
    tagFooter,     ## the HTML `footer` element
    tagForm,       ## the HTML `form` element
    tagFrame,      ## the HTML `frame` element
    tagFrameset,   ## the deprecated HTML `frameset` element
    tagH1,         ## the HTML `h1` element
    tagH2,         ## the HTML `h2` element
    tagH3,         ## the HTML `h3` element
    tagH4,         ## the HTML `h4` element
    tagH5,         ## the HTML `h5` element
    tagH6,         ## the HTML `h6` element
    tagHead,       ## the HTML `head` element
    tagHeader,     ## the HTML `header` element
    tagHgroup,     ## the HTML `hgroup` element
    tagHtml,       ## the HTML `html` element
    tagHr,         ## the HTML `hr` element
    tagI,          ## the HTML `i` element
    tagIframe,     ## the deprecated HTML `iframe` element
    tagImg,        ## the HTML `img` element
    tagInput,      ## the HTML `input` element
    tagIns,        ## the HTML `ins` element
    tagIsindex,    ## the deprecated HTML `isindex` element
    tagKbd,        ## the HTML `kbd` element
    tagKeygen,     ## the HTML `keygen` element
    tagLabel,      ## the HTML `label` element
    tagLegend,     ## the HTML `legend` element
    tagLi,         ## the HTML `li` element
    tagLink,       ## the HTML `link` element
    tagMap,        ## the HTML `map` element
    tagMark,       ## the HTML `mark` element
    tagMenu,       ## the deprecated HTML `menu` element
    tagMeta,       ## the HTML `meta` element
    tagMeter,      ## the HTML `meter` element
    tagNav,        ## the HTML `nav` element
    tagNobr,       ## the deprecated HTML `nobr` element
    tagNoframes,   ## the deprecated HTML `noframes` element
    tagNoscript,   ## the HTML `noscript` element
    tagObject,     ## the HTML `object` element
    tagOl,         ## the HTML `ol` element
    tagOptgroup,   ## the HTML `optgroup` element
    tagOption,     ## the HTML `option` element
    tagOutput,     ## the HTML `output` element
    tagP,          ## the HTML `p` element
    tagParam,      ## the HTML `param` element
    tagPre,        ## the HTML `pre` element
    tagProgress,   ## the HTML `progress` element
    tagQ,          ## the HTML `q` element
    tagRp,         ## the HTML `rp` element
    tagRt,         ## the HTML `rt` element
    tagRuby,       ## the HTML `ruby` element
    tagS,          ## the deprecated HTML `s` element
    tagSamp,       ## the HTML `samp` element
    tagScript,     ## the HTML `script` element
    tagSection,    ## the HTML `section` element
    tagSelect,     ## the HTML `select` element
    tagSmall,      ## the HTML `small` element
    tagSource,     ## the HTML `source` element
    tagSpan,       ## the HTML `span` element
    tagStrike,     ## the deprecated HTML `strike` element
    tagStrong,     ## the HTML `strong` element
    tagStyle,      ## the HTML `style` element
    tagSub,        ## the HTML `sub` element
    tagSummary,    ## the HTML `summary` element
    tagSup,        ## the HTML `sup` element
    tagTable,      ## the HTML `table` element
    tagTbody,      ## the HTML `tbody` element
    tagTd,         ## the HTML `td` element
    tagTextarea,   ## the HTML `textarea` element
    tagTfoot,      ## the HTML `tfoot` element
    tagTh,         ## the HTML `th` element
    tagThead,      ## the HTML `thead` element
    tagTime,       ## the HTML `time` element
    tagTitle,      ## the HTML `title` element
    tagTr,         ## the HTML `tr` element
    tagTrack,      ## the HTML `track` element
    tagTt,         ## the HTML `tt` element
    tagU,          ## the deprecated HTML `u` element
    tagUl,         ## the HTML `ul` element
    tagVar,        ## the HTML `var` element
    tagVideo,      ## the HTML `video` element
    tagWbr         ## the HTML `wbr` element

const
  tagToStr* = [
    "a", "abbr", "acronym", "address", "applet", "area", "article",
    "aside", "audio",
    "b", "base", "basefont", "bdi", "bdo", "big", "blockquote", "body",
    "br", "button", "canvas", "caption", "center", "cite", "code",
    "col", "colgroup", "command",
    "datalist", "dd", "del", "details", "dfn", "dialog", "div",
    "dir", "dl", "dt", "em", "embed", "fieldset",
    "figcaption", "figure", "font", "footer",
    "form", "frame", "frameset", "h1", "h2", "h3",
    "h4", "h5", "h6", "head", "header", "hgroup", "html", "hr",
    "i", "iframe", "img", "input", "ins", "isindex",
    "kbd", "keygen", "label", "legend", "li", "link", "map", "mark",
    "menu", "meta", "meter", "nav", "nobr", "noframes", "noscript",
    "object", "ol",
    "optgroup", "option", "output", "p", "param", "pre", "progress", "q",
    "rp", "rt", "ruby", "s", "samp", "script", "section", "select", "small",
    "source", "span", "strike", "strong", "style",
    "sub", "summary", "sup", "table",
    "tbody", "td", "textarea", "tfoot", "th", "thead", "time",
    "title", "tr", "track", "tt", "u", "ul", "var", "video", "wbr"]
  InlineTags* = {tagA, tagAbbr, tagAcronym, tagApplet, tagB, tagBasefont,
    tagBdo, tagBig, tagBr, tagButton, tagCite, tagCode, tagDel, tagDfn,
    tagEm, tagFont, tagI, tagImg, tagIns, tagInput, tagIframe, tagKbd,
    tagLabel, tagMap, tagObject, tagQ, tagSamp, tagScript, tagSelect,
    tagSmall, tagSpan, tagStrong, tagSub, tagSup, tagTextarea, tagTt,
    tagVar, tagApplet, tagBasefont, tagFont, tagIframe, tagU, tagS,
    tagStrike, tagWbr}
  BlockTags* = {tagAddress, tagBlockquote, tagCenter, tagDel, tagDir, tagDiv,
    tagDl, tagFieldset, tagForm, tagH1, tagH2, tagH3, tagH4,
    tagH5, tagH6, tagHr, tagIns, tagIsindex, tagMenu, tagNoframes, tagNoscript,
    tagOl, tagP, tagPre, tagTable, tagUl, tagCenter, tagDir, tagIsindex,
    tagMenu, tagNoframes}
  SingleTags* = {tagArea, tagBase, tagBasefont,
    tagBr, tagCol, tagFrame, tagHr, tagImg, tagIsindex,
    tagLink, tagMeta, tagParam, tagWbr, tagSource}

proc allLower(s: string): bool =
  for c in s:
    if c < 'a' or c > 'z': return false
  return true

proc toHtmlTag(s: string): HtmlTag =
  case s
  of "a": tagA
  of "abbr": tagAbbr
  of "acronym": tagAcronym
  of "address": tagAddress
  of "applet": tagApplet
  of "area": tagArea
  of "article": tagArticle
  of "aside": tagAside
  of "audio": tagAudio
  of "b": tagB
  of "base": tagBase
  of "basefont": tagBasefont
  of "bdi": tagBdi
  of "bdo": tagBdo
  of "big": tagBig
  of "blockquote": tagBlockquote
  of "body": tagBody
  of "br": tagBr
  of "button": tagButton
  of "canvas": tagCanvas
  of "caption": tagCaption
  of "center": tagCenter
  of "cite": tagCite
  of "code": tagCode
  of "col": tagCol
  of "colgroup": tagColgroup
  of "command": tagCommand
  of "datalist": tagDatalist
  of "dd": tagDd
  of "del": tagDel
  of "details": tagDetails
  of "dfn": tagDfn
  of "dialog": tagDialog
  of "div": tagDiv
  of "dir": tagDir
  of "dl": tagDl
  of "dt": tagDt
  of "em": tagEm
  of "embed": tagEmbed
  of "fieldset": tagFieldset
  of "figcaption": tagFigcaption
  of "figure": tagFigure
  of "font": tagFont
  of "footer": tagFooter
  of "form": tagForm
  of "frame": tagFrame
  of "frameset": tagFrameset
  of "h1": tagH1
  of "h2": tagH2
  of "h3": tagH3
  of "h4": tagH4
  of "h5": tagH5
  of "h6": tagH6
  of "head": tagHead
  of "header": tagHeader
  of "hgroup": tagHgroup
  of "html": tagHtml
  of "hr": tagHr
  of "i": tagI
  of "iframe": tagIframe
  of "img": tagImg
  of "input": tagInput
  of "ins": tagIns
  of "isindex": tagIsindex
  of "kbd": tagKbd
  of "keygen": tagKeygen
  of "label": tagLabel
  of "legend": tagLegend
  of "li": tagLi
  of "link": tagLink
  of "map": tagMap
  of "mark": tagMark
  of "menu": tagMenu
  of "meta": tagMeta
  of "meter": tagMeter
  of "nav": tagNav
  of "nobr": tagNobr
  of "noframes": tagNoframes
  of "noscript": tagNoscript
  of "object": tagObject
  of "ol": tagOl
  of "optgroup": tagOptgroup
  of "option": tagOption
  of "output": tagOutput
  of "p": tagP
  of "param": tagParam
  of "pre": tagPre
  of "progress": tagProgress
  of "q": tagQ
  of "rp": tagRp
  of "rt": tagRt
  of "ruby": tagRuby
  of "s": tagS
  of "samp": tagSamp
  of "script": tagScript
  of "section": tagSection
  of "select": tagSelect
  of "small": tagSmall
  of "source": tagSource
  of "span": tagSpan
  of "strike": tagStrike
  of "strong": tagStrong
  of "style": tagStyle
  of "sub": tagSub
  of "summary": tagSummary
  of "sup": tagSup
  of "table": tagTable
  of "tbody": tagTbody
  of "td": tagTd
  of "textarea": tagTextarea
  of "tfoot": tagTfoot
  of "th": tagTh
  of "thead": tagThead
  of "time": tagTime
  of "title": tagTitle
  of "tr": tagTr
  of "track": tagTrack
  of "tt": tagTt
  of "u": tagU
  of "ul": tagUl
  of "var": tagVar
  of "video": tagVideo
  of "wbr": tagWbr
  else: tagUnknown


proc htmlTag*(n: XmlNode): HtmlTag =
  ## Gets `n`'s tag as a `HtmlTag`.
  if n.clientData == 0:
    n.clientData = toHtmlTag(n.tag).ord
  result = HtmlTag(n.clientData)

proc htmlTag*(s: string): HtmlTag =
  ## Converts `s` to a `HtmlTag`. If `s` is no HTML tag, `tagUnknown` is
  ## returned.
  let s = if allLower(s): s else: toLowerAscii(s)
  result = toHtmlTag(s)

proc runeToEntity*(rune: Rune): string =
  ## converts a Rune to its numeric HTML entity equivalent.
  runnableExamples:
    import std/unicode
    doAssert runeToEntity(Rune(0)) == ""
    doAssert runeToEntity(Rune(-1)) == ""
    doAssert runeToEntity("Ü".runeAt(0)) == "#220"
    doAssert runeToEntity("∈".runeAt(0)) == "#8712"
  if rune.ord <= 0: result = ""
  else: result = '#' & $rune.ord

proc entityToRune*(entity: string): Rune =
  ## Converts an HTML entity name like `&Uuml;` or values like `&#220;`
  ## or `&#x000DC;` to its UTF-8 equivalent.
  ## Rune(0) is returned if the entity name is unknown.
  runnableExamples:
    import std/unicode
    doAssert entityToRune("") == Rune(0)
    doAssert entityToRune("a") == Rune(0)
    doAssert entityToRune("gt") == ">".runeAt(0)
    doAssert entityToRune("Uuml") == "Ü".runeAt(0)
    doAssert entityToRune("quest") == "?".runeAt(0)
    doAssert entityToRune("#x0003F") == "?".runeAt(0)
  if entity.len < 2: return # smallest entity has length 2
  if entity[0] == '#':
    var runeValue = 0
    case entity[1]
    of '0'..'9':
      try: runeValue = parseInt(entity[1..^1])
      except ValueError: discard
    of 'x', 'X': # not case sensitive here
      try: runeValue = parseHexInt(entity[2..^1])
      except ValueError: discard
    else: discard # other entities are not defined with prefix `#`
    if runeValue notin 0..0x10FFFF: runeValue = 0 # only return legal values
    return Rune(runeValue)
  case entity # entity names are case sensitive
  of "Tab": Rune(0x00009)
  of "NewLine": Rune(0x0000A)
  of "excl": Rune(0x00021)
  of "quot", "QUOT": Rune(0x00022)
  of "num": Rune(0x00023)
  of "dollar": Rune(0x00024)
  of "percnt": Rune(0x00025)
  of "amp", "AMP": Rune(0x00026)
  of "apos": Rune(0x00027)
  of "lpar": Rune(0x00028)
  of "rpar": Rune(0x00029)
  of "ast", "midast": Rune(0x0002A)
  of "plus": Rune(0x0002B)
  of "comma": Rune(0x0002C)
  of "period": Rune(0x0002E)
  of "sol": Rune(0x0002F)
  of "colon": Rune(0x0003A)
  of "semi": Rune(0x0003B)
  of "lt", "LT": Rune(0x0003C)
  of "equals": Rune(0x0003D)
  of "gt", "GT": Rune(0x0003E)
  of "quest": Rune(0x0003F)
  of "commat": Rune(0x00040)
  of "lsqb", "lbrack": Rune(0x0005B)
  of "bsol": Rune(0x0005C)
  of "rsqb", "rbrack": Rune(0x0005D)
  of "Hat": Rune(0x0005E)
  of "lowbar": Rune(0x0005F)
  of "grave", "DiacriticalGrave": Rune(0x00060)
  of "lcub", "lbrace": Rune(0x0007B)
  of "verbar", "vert", "VerticalLine": Rune(0x0007C)
  of "rcub", "rbrace": Rune(0x0007D)
  of "nbsp", "NonBreakingSpace": Rune(0x000A0)
  of "iexcl": Rune(0x000A1)
  of "cent": Rune(0x000A2)
  of "pound": Rune(0x000A3)
  of "curren": Rune(0x000A4)
  of "yen": Rune(0x000A5)
  of "brvbar": Rune(0x000A6)
  of "sect": Rune(0x000A7)
  of "Dot", "die", "DoubleDot", "uml": Rune(0x000A8)
  of "copy", "COPY": Rune(0x000A9)
  of "ordf": Rune(0x000AA)
  of "laquo": Rune(0x000AB)
  of "not": Rune(0x000AC)
  of "shy": Rune(0x000AD)
  of "reg", "circledR", "REG": Rune(0x000AE)
  of "macr", "OverBar", "strns": Rune(0x000AF)
  of "deg": Rune(0x000B0)
  of "plusmn", "pm", "PlusMinus": Rune(0x000B1)
  of "sup2": Rune(0x000B2)
  of "sup3": Rune(0x000B3)
  of "acute", "DiacriticalAcute": Rune(0x000B4)
  of "micro": Rune(0x000B5)
  of "para": Rune(0x000B6)
  of "middot", "centerdot", "CenterDot": Rune(0x000B7)
  of "cedil", "Cedilla": Rune(0x000B8)
  of "sup1": Rune(0x000B9)
  of "ordm": Rune(0x000BA)
  of "raquo": Rune(0x000BB)
  of "frac14": Rune(0x000BC)
  of "frac12", "half": Rune(0x000BD)
  of "frac34": Rune(0x000BE)
  of "iquest": Rune(0x000BF)
  of "Agrave": Rune(0x000C0)
  of "Aacute": Rune(0x000C1)
  of "Acirc": Rune(0x000C2)
  of "Atilde": Rune(0x000C3)
  of "Auml": Rune(0x000C4)
  of "Aring": Rune(0x000C5)
  of "AElig": Rune(0x000C6)
  of "Ccedil": Rune(0x000C7)
  of "Egrave": Rune(0x000C8)
  of "Eacute": Rune(0x000C9)
  of "Ecirc": Rune(0x000CA)
  of "Euml": Rune(0x000CB)
  of "Igrave": Rune(0x000CC)
  of "Iacute": Rune(0x000CD)
  of "Icirc": Rune(0x000CE)
  of "Iuml": Rune(0x000CF)
  of "ETH": Rune(0x000D0)
  of "Ntilde": Rune(0x000D1)
  of "Ograve": Rune(0x000D2)
  of "Oacute": Rune(0x000D3)
  of "Ocirc": Rune(0x000D4)
  of "Otilde": Rune(0x000D5)
  of "Ouml": Rune(0x000D6)
  of "times": Rune(0x000D7)
  of "Oslash": Rune(0x000D8)
  of "Ugrave": Rune(0x000D9)
  of "Uacute": Rune(0x000DA)
  of "Ucirc": Rune(0x000DB)
  of "Uuml": Rune(0x000DC)
  of "Yacute": Rune(0x000DD)
  of "THORN": Rune(0x000DE)
  of "szlig": Rune(0x000DF)
  of "agrave": Rune(0x000E0)
  of "aacute": Rune(0x000E1)
  of "acirc": Rune(0x000E2)
  of "atilde": Rune(0x000E3)
  of "auml": Rune(0x000E4)
  of "aring": Rune(0x000E5)
  of "aelig": Rune(0x000E6)
  of "ccedil": Rune(0x000E7)
  of "egrave": Rune(0x000E8)
  of "eacute": Rune(0x000E9)
  of "ecirc": Rune(0x000EA)
  of "euml": Rune(0x000EB)
  of "igrave": Rune(0x000EC)
  of "iacute": Rune(0x000ED)
  of "icirc": Rune(0x000EE)
  of "iuml": Rune(0x000EF)
  of "eth": Rune(0x000F0)
  of "ntilde": Rune(0x000F1)
  of "ograve": Rune(0x000F2)
  of "oacute": Rune(0x000F3)
  of "ocirc": Rune(0x000F4)
  of "otilde": Rune(0x000F5)
  of "ouml": Rune(0x000F6)
  of "divide", "div": Rune(0x000F7)
  of "oslash": Rune(0x000F8)
  of "ugrave": Rune(0x000F9)
  of "uacute": Rune(0x000FA)
  of "ucirc": Rune(0x000FB)
  of "uuml": Rune(0x000FC)
  of "yacute": Rune(0x000FD)
  of "thorn": Rune(0x000FE)
  of "yuml": Rune(0x000FF)
  of "Amacr": Rune(0x00100)
  of "amacr": Rune(0x00101)
  of "Abreve": Rune(0x00102)
  of "abreve": Rune(0x00103)
  of "Aogon": Rune(0x00104)
  of "aogon": Rune(0x00105)
  of "Cacute": Rune(0x00106)
  of "cacute": Rune(0x00107)
  of "Ccirc": Rune(0x00108)
  of "ccirc": Rune(0x00109)
  of "Cdot": Rune(0x0010A)
  of "cdot": Rune(0x0010B)
  of "Ccaron": Rune(0x0010C)
  of "ccaron": Rune(0x0010D)
  of "Dcaron": Rune(0x0010E)
  of "dcaron": Rune(0x0010F)
  of "Dstrok": Rune(0x00110)
  of "dstrok": Rune(0x00111)
  of "Emacr": Rune(0x00112)
  of "emacr": Rune(0x00113)
  of "Edot": Rune(0x00116)
  of "edot": Rune(0x00117)
  of "Eogon": Rune(0x00118)
  of "eogon": Rune(0x00119)
  of "Ecaron": Rune(0x0011A)
  of "ecaron": Rune(0x0011B)
  of "Gcirc": Rune(0x0011C)
  of "gcirc": Rune(0x0011D)
  of "Gbreve": Rune(0x0011E)
  of "gbreve": Rune(0x0011F)
  of "Gdot": Rune(0x00120)
  of "gdot": Rune(0x00121)
  of "Gcedil": Rune(0x00122)
  of "Hcirc": Rune(0x00124)
  of "hcirc": Rune(0x00125)
  of "Hstrok": Rune(0x00126)
  of "hstrok": Rune(0x00127)
  of "Itilde": Rune(0x00128)
  of "itilde": Rune(0x00129)
  of "Imacr": Rune(0x0012A)
  of "imacr": Rune(0x0012B)
  of "Iogon": Rune(0x0012E)
  of "iogon": Rune(0x0012F)
  of "Idot": Rune(0x00130)
  of "imath", "inodot": Rune(0x00131)
  of "IJlig": Rune(0x00132)
  of "ijlig": Rune(0x00133)
  of "Jcirc": Rune(0x00134)
  of "jcirc": Rune(0x00135)
  of "Kcedil": Rune(0x00136)
  of "kcedil": Rune(0x00137)
  of "kgreen": Rune(0x00138)
  of "Lacute": Rune(0x00139)
  of "lacute": Rune(0x0013A)
  of "Lcedil": Rune(0x0013B)
  of "lcedil": Rune(0x0013C)
  of "Lcaron": Rune(0x0013D)
  of "lcaron": Rune(0x0013E)
  of "Lmidot": Rune(0x0013F)
  of "lmidot": Rune(0x00140)
  of "Lstrok": Rune(0x00141)
  of "lstrok": Rune(0x00142)
  of "Nacute": Rune(0x00143)
  of "nacute": Rune(0x00144)
  of "Ncedil": Rune(0x00145)
  of "ncedil": Rune(0x00146)
  of "Ncaron": Rune(0x00147)
  of "ncaron": Rune(0x00148)
  of "napos": Rune(0x00149)
  of "ENG": Rune(0x0014A)
  of "eng": Rune(0x0014B)
  of "Omacr": Rune(0x0014C)
  of "omacr": Rune(0x0014D)
  of "Odblac": Rune(0x00150)
  of "odblac": Rune(0x00151)
  of "OElig": Rune(0x00152)
  of "oelig": Rune(0x00153)
  of "Racute": Rune(0x00154)
  of "racute": Rune(0x00155)
  of "Rcedil": Rune(0x00156)
  of "rcedil": Rune(0x00157)
  of "Rcaron": Rune(0x00158)
  of "rcaron": Rune(0x00159)
  of "Sacute": Rune(0x0015A)
  of "sacute": Rune(0x0015B)
  of "Scirc": Rune(0x0015C)
  of "scirc": Rune(0x0015D)
  of "Scedil": Rune(0x0015E)
  of "scedil": Rune(0x0015F)
  of "Scaron": Rune(0x00160)
  of "scaron": Rune(0x00161)
  of "Tcedil": Rune(0x00162)
  of "tcedil": Rune(0x00163)
  of "Tcaron": Rune(0x00164)
  of "tcaron": Rune(0x00165)
  of "Tstrok": Rune(0x00166)
  of "tstrok": Rune(0x00167)
  of "Utilde": Rune(0x00168)
  of "utilde": Rune(0x00169)
  of "Umacr": Rune(0x0016A)
  of "umacr": Rune(0x0016B)
  of "Ubreve": Rune(0x0016C)
  of "ubreve": Rune(0x0016D)
  of "Uring": Rune(0x0016E)
  of "uring": Rune(0x0016F)
  of "Udblac": Rune(0x00170)
  of "udblac": Rune(0x00171)
  of "Uogon": Rune(0x00172)
  of "uogon": Rune(0x00173)
  of "Wcirc": Rune(0x00174)
  of "wcirc": Rune(0x00175)
  of "Ycirc": Rune(0x00176)
  of "ycirc": Rune(0x00177)
  of "Yuml": Rune(0x00178)
  of "Zacute": Rune(0x00179)
  of "zacute": Rune(0x0017A)
  of "Zdot": Rune(0x0017B)
  of "zdot": Rune(0x0017C)
  of "Zcaron": Rune(0x0017D)
  of "zcaron": Rune(0x0017E)
  of "fnof": Rune(0x00192)
  of "imped": Rune(0x001B5)
  of "gacute": Rune(0x001F5)
  of "jmath": Rune(0x00237)
  of "circ": Rune(0x002C6)
  of "caron", "Hacek": Rune(0x002C7)
  of "breve", "Breve": Rune(0x002D8)
  of "dot", "DiacriticalDot": Rune(0x002D9)
  of "ring": Rune(0x002DA)
  of "ogon": Rune(0x002DB)
  of "tilde", "DiacriticalTilde": Rune(0x002DC)
  of "dblac", "DiacriticalDoubleAcute": Rune(0x002DD)
  of "DownBreve": Rune(0x00311)
  of "UnderBar": Rune(0x00332)
  of "Alpha": Rune(0x00391)
  of "Beta": Rune(0x00392)
  of "Gamma": Rune(0x00393)
  of "Delta": Rune(0x00394)
  of "Epsilon": Rune(0x00395)
  of "Zeta": Rune(0x00396)
  of "Eta": Rune(0x00397)
  of "Theta": Rune(0x00398)
  of "Iota": Rune(0x00399)
  of "Kappa": Rune(0x0039A)
  of "Lambda": Rune(0x0039B)
  of "Mu": Rune(0x0039C)
  of "Nu": Rune(0x0039D)
  of "Xi": Rune(0x0039E)
  of "Omicron": Rune(0x0039F)
  of "Pi": Rune(0x003A0)
  of "Rho": Rune(0x003A1)
  of "Sigma": Rune(0x003A3)
  of "Tau": Rune(0x003A4)
  of "Upsilon": Rune(0x003A5)
  of "Phi": Rune(0x003A6)
  of "Chi": Rune(0x003A7)
  of "Psi": Rune(0x003A8)
  of "Omega": Rune(0x003A9)
  of "alpha": Rune(0x003B1)
  of "beta": Rune(0x003B2)
  of "gamma": Rune(0x003B3)
  of "delta": Rune(0x003B4)
  of "epsiv", "varepsilon", "epsilon": Rune(0x003B5)
  of "zeta": Rune(0x003B6)
  of "eta": Rune(0x003B7)
  of "theta": Rune(0x003B8)
  of "iota": Rune(0x003B9)
  of "kappa": Rune(0x003BA)
  of "lambda": Rune(0x003BB)
  of "mu": Rune(0x003BC)
  of "nu": Rune(0x003BD)
  of "xi": Rune(0x003BE)
  of "omicron": Rune(0x003BF)
  of "pi": Rune(0x003C0)
  of "rho": Rune(0x003C1)
  of "sigmav", "varsigma", "sigmaf": Rune(0x003C2)
  of "sigma": Rune(0x003C3)
  of "tau": Rune(0x003C4)
  of "upsi", "upsilon": Rune(0x003C5)
  of "phi", "phiv", "varphi": Rune(0x003C6)
  of "chi": Rune(0x003C7)
  of "psi": Rune(0x003C8)
  of "omega": Rune(0x003C9)
  of "thetav", "vartheta", "thetasym": Rune(0x003D1)
  of "Upsi", "upsih": Rune(0x003D2)
  of "straightphi": Rune(0x003D5)
  of "piv", "varpi": Rune(0x003D6)
  of "Gammad": Rune(0x003DC)
  of "gammad", "digamma": Rune(0x003DD)
  of "kappav", "varkappa": Rune(0x003F0)
  of "rhov", "varrho": Rune(0x003F1)
  of "epsi", "straightepsilon": Rune(0x003F5)
  of "bepsi", "backepsilon": Rune(0x003F6)
  of "IOcy": Rune(0x00401)
  of "DJcy": Rune(0x00402)
  of "GJcy": Rune(0x00403)
  of "Jukcy": Rune(0x00404)
  of "DScy": Rune(0x00405)
  of "Iukcy": Rune(0x00406)
  of "YIcy": Rune(0x00407)
  of "Jsercy": Rune(0x00408)
  of "LJcy": Rune(0x00409)
  of "NJcy": Rune(0x0040A)
  of "TSHcy": Rune(0x0040B)
  of "KJcy": Rune(0x0040C)
  of "Ubrcy": Rune(0x0040E)
  of "DZcy": Rune(0x0040F)
  of "Acy": Rune(0x00410)
  of "Bcy": Rune(0x00411)
  of "Vcy": Rune(0x00412)
  of "Gcy": Rune(0x00413)
  of "Dcy": Rune(0x00414)
  of "IEcy": Rune(0x00415)
  of "ZHcy": Rune(0x00416)
  of "Zcy": Rune(0x00417)
  of "Icy": Rune(0x00418)
  of "Jcy": Rune(0x00419)
  of "Kcy": Rune(0x0041A)
  of "Lcy": Rune(0x0041B)
  of "Mcy": Rune(0x0041C)
  of "Ncy": Rune(0x0041D)
  of "Ocy": Rune(0x0041E)
  of "Pcy": Rune(0x0041F)
  of "Rcy": Rune(0x00420)
  of "Scy": Rune(0x00421)
  of "Tcy": Rune(0x00422)
  of "Ucy": Rune(0x00423)
  of "Fcy": Rune(0x00424)
  of "KHcy": Rune(0x00425)
  of "TScy": Rune(0x00426)
  of "CHcy": Rune(0x00427)
  of "SHcy": Rune(0x00428)
  of "SHCHcy": Rune(0x00429)
  of "HARDcy": Rune(0x0042A)
  of "Ycy": Rune(0x0042B)
  of "SOFTcy": Rune(0x0042C)
  of "Ecy": Rune(0x0042D)
  of "YUcy": Rune(0x0042E)
  of "YAcy": Rune(0x0042F)
  of "acy": Rune(0x00430)
  of "bcy": Rune(0x00431)
  of "vcy": Rune(0x00432)
  of "gcy": Rune(0x00433)
  of "dcy": Rune(0x00434)
  of "iecy": Rune(0x00435)
  of "zhcy": Rune(0x00436)
  of "zcy": Rune(0x00437)
  of "icy": Rune(0x00438)
  of "jcy": Rune(0x00439)
  of "kcy": Rune(0x0043A)
  of "lcy": Rune(0x0043B)
  of "mcy": Rune(0x0043C)
  of "ncy": Rune(0x0043D)
  of "ocy": Rune(0x0043E)
  of "pcy": Rune(0x0043F)
  of "rcy": Rune(0x00440)
  of "scy": Rune(0x00441)
  of "tcy": Rune(0x00442)
  of "ucy": Rune(0x00443)
  of "fcy": Rune(0x00444)
  of "khcy": Rune(0x00445)
  of "tscy": Rune(0x00446)
  of "chcy": Rune(0x00447)
  of "shcy": Rune(0x00448)
  of "shchcy": Rune(0x00449)
  of "hardcy": Rune(0x0044A)
  of "ycy": Rune(0x0044B)
  of "softcy": Rune(0x0044C)
  of "ecy": Rune(0x0044D)
  of "yucy": Rune(0x0044E)
  of "yacy": Rune(0x0044F)
  of "iocy": Rune(0x00451)
  of "djcy": Rune(0x00452)
  of "gjcy": Rune(0x00453)
  of "jukcy": Rune(0x00454)
  of "dscy": Rune(0x00455)
  of "iukcy": Rune(0x00456)
  of "yicy": Rune(0x00457)
  of "jsercy": Rune(0x00458)
  of "ljcy": Rune(0x00459)
  of "njcy": Rune(0x0045A)
  of "tshcy": Rune(0x0045B)
  of "kjcy": Rune(0x0045C)
  of "ubrcy": Rune(0x0045E)
  of "dzcy": Rune(0x0045F)
  of "ensp": Rune(0x02002)
  of "emsp": Rune(0x02003)
  of "emsp13": Rune(0x02004)
  of "emsp14": Rune(0x02005)
  of "numsp": Rune(0x02007)
  of "puncsp": Rune(0x02008)
  of "thinsp", "ThinSpace": Rune(0x02009)
  of "hairsp", "VeryThinSpace": Rune(0x0200A)
  of "ZeroWidthSpace", "NegativeVeryThinSpace", "NegativeThinSpace",
    "NegativeMediumSpace", "NegativeThickSpace": Rune(0x0200B)
  of "zwnj": Rune(0x0200C)
  of "zwj": Rune(0x0200D)
  of "lrm": Rune(0x0200E)
  of "rlm": Rune(0x0200F)
  of "hyphen", "dash": Rune(0x02010)
  of "ndash": Rune(0x02013)
  of "mdash": Rune(0x02014)
  of "horbar": Rune(0x02015)
  of "Verbar", "Vert": Rune(0x02016)
  of "lsquo", "OpenCurlyQuote": Rune(0x02018)
  of "rsquo", "rsquor", "CloseCurlyQuote": Rune(0x02019)
  of "lsquor", "sbquo": Rune(0x0201A)
  of "ldquo", "OpenCurlyDoubleQuote": Rune(0x0201C)
  of "rdquo", "rdquor", "CloseCurlyDoubleQuote": Rune(0x0201D)
  of "ldquor", "bdquo": Rune(0x0201E)
  of "dagger": Rune(0x02020)
  of "Dagger", "ddagger": Rune(0x02021)
  of "bull", "bullet": Rune(0x02022)
  of "nldr": Rune(0x02025)
  of "hellip", "mldr": Rune(0x02026)
  of "permil": Rune(0x02030)
  of "pertenk": Rune(0x02031)
  of "prime": Rune(0x02032)
  of "Prime": Rune(0x02033)
  of "tprime": Rune(0x02034)
  of "bprime", "backprime": Rune(0x02035)
  of "lsaquo": Rune(0x02039)
  of "rsaquo": Rune(0x0203A)
  of "oline": Rune(0x0203E)
  of "caret": Rune(0x02041)
  of "hybull": Rune(0x02043)
  of "frasl": Rune(0x02044)
  of "bsemi": Rune(0x0204F)
  of "qprime": Rune(0x02057)
  of "MediumSpace": Rune(0x0205F)
  of "NoBreak": Rune(0x02060)
  of "ApplyFunction", "af": Rune(0x02061)
  of "InvisibleTimes", "it": Rune(0x02062)
  of "InvisibleComma", "ic": Rune(0x02063)
  of "euro": Rune(0x020AC)
  of "tdot", "TripleDot": Rune(0x020DB)
  of "DotDot": Rune(0x020DC)
  of "Copf", "complexes": Rune(0x02102)
  of "incare": Rune(0x02105)
  of "gscr": Rune(0x0210A)
  of "hamilt", "HilbertSpace", "Hscr": Rune(0x0210B)
  of "Hfr", "Poincareplane": Rune(0x0210C)
  of "quaternions", "Hopf": Rune(0x0210D)
  of "planckh": Rune(0x0210E)
  of "planck", "hbar", "plankv", "hslash": Rune(0x0210F)
  of "Iscr", "imagline": Rune(0x02110)
  of "image", "Im", "imagpart", "Ifr": Rune(0x02111)
  of "Lscr", "lagran", "Laplacetrf": Rune(0x02112)
  of "ell": Rune(0x02113)
  of "Nopf", "naturals": Rune(0x02115)
  of "numero": Rune(0x02116)
  of "copysr": Rune(0x02117)
  of "weierp", "wp": Rune(0x02118)
  of "Popf", "primes": Rune(0x02119)
  of "rationals", "Qopf": Rune(0x0211A)
  of "Rscr", "realine": Rune(0x0211B)
  of "real", "Re", "realpart", "Rfr": Rune(0x0211C)
  of "reals", "Ropf": Rune(0x0211D)
  of "rx": Rune(0x0211E)
  of "trade", "TRADE": Rune(0x02122)
  of "integers", "Zopf": Rune(0x02124)
  of "ohm": Rune(0x02126)
  of "mho": Rune(0x02127)
  of "Zfr", "zeetrf": Rune(0x02128)
  of "iiota": Rune(0x02129)
  of "angst": Rune(0x0212B)
  of "bernou", "Bernoullis", "Bscr": Rune(0x0212C)
  of "Cfr", "Cayleys": Rune(0x0212D)
  of "escr": Rune(0x0212F)
  of "Escr", "expectation": Rune(0x02130)
  of "Fscr", "Fouriertrf": Rune(0x02131)
  of "phmmat", "Mellintrf", "Mscr": Rune(0x02133)
  of "order", "orderof", "oscr": Rune(0x02134)
  of "alefsym", "aleph": Rune(0x02135)
  of "beth": Rune(0x02136)
  of "gimel": Rune(0x02137)
  of "daleth": Rune(0x02138)
  of "CapitalDifferentialD", "DD": Rune(0x02145)
  of "DifferentialD", "dd": Rune(0x02146)
  of "ExponentialE", "exponentiale", "ee": Rune(0x02147)
  of "ImaginaryI", "ii": Rune(0x02148)
  of "frac13": Rune(0x02153)
  of "frac23": Rune(0x02154)
  of "frac15": Rune(0x02155)
  of "frac25": Rune(0x02156)
  of "frac35": Rune(0x02157)
  of "frac45": Rune(0x02158)
  of "frac16": Rune(0x02159)
  of "frac56": Rune(0x0215A)
  of "frac18": Rune(0x0215B)
  of "frac38": Rune(0x0215C)
  of "frac58": Rune(0x0215D)
  of "frac78": Rune(0x0215E)
  of "larr", "leftarrow", "LeftArrow", "slarr",
    "ShortLeftArrow": Rune(0x02190)
  of "uarr", "uparrow", "UpArrow", "ShortUpArrow": Rune(0x02191)
  of "rarr", "rightarrow", "RightArrow", "srarr",
    "ShortRightArrow": Rune(0x02192)
  of "darr", "downarrow", "DownArrow",
    "ShortDownArrow": Rune(0x02193)
  of "harr", "leftrightarrow", "LeftRightArrow": Rune(0x02194)
  of "varr", "updownarrow", "UpDownArrow": Rune(0x02195)
  of "nwarr", "UpperLeftArrow", "nwarrow": Rune(0x02196)
  of "nearr", "UpperRightArrow", "nearrow": Rune(0x02197)
  of "searr", "searrow", "LowerRightArrow": Rune(0x02198)
  of "swarr", "swarrow", "LowerLeftArrow": Rune(0x02199)
  of "nlarr", "nleftarrow": Rune(0x0219A)
  of "nrarr", "nrightarrow": Rune(0x0219B)
  of "rarrw", "rightsquigarrow": Rune(0x0219D)
  of "Larr", "twoheadleftarrow": Rune(0x0219E)
  of "Uarr": Rune(0x0219F)
  of "Rarr", "twoheadrightarrow": Rune(0x021A0)
  of "Darr": Rune(0x021A1)
  of "larrtl", "leftarrowtail": Rune(0x021A2)
  of "rarrtl", "rightarrowtail": Rune(0x021A3)
  of "LeftTeeArrow", "mapstoleft": Rune(0x021A4)
  of "UpTeeArrow", "mapstoup": Rune(0x021A5)
  of "map", "RightTeeArrow", "mapsto": Rune(0x021A6)
  of "DownTeeArrow", "mapstodown": Rune(0x021A7)
  of "larrhk", "hookleftarrow": Rune(0x021A9)
  of "rarrhk", "hookrightarrow": Rune(0x021AA)
  of "larrlp", "looparrowleft": Rune(0x021AB)
  of "rarrlp", "looparrowright": Rune(0x021AC)
  of "harrw", "leftrightsquigarrow": Rune(0x021AD)
  of "nharr", "nleftrightarrow": Rune(0x021AE)
  of "lsh", "Lsh": Rune(0x021B0)
  of "rsh", "Rsh": Rune(0x021B1)
  of "ldsh": Rune(0x021B2)
  of "rdsh": Rune(0x021B3)
  of "crarr": Rune(0x021B5)
  of "cularr", "curvearrowleft": Rune(0x021B6)
  of "curarr", "curvearrowright": Rune(0x021B7)
  of "olarr", "circlearrowleft": Rune(0x021BA)
  of "orarr", "circlearrowright": Rune(0x021BB)
  of "lharu", "LeftVector", "leftharpoonup": Rune(0x021BC)
  of "lhard", "leftharpoondown", "DownLeftVector": Rune(0x021BD)
  of "uharr", "upharpoonright", "RightUpVector": Rune(0x021BE)
  of "uharl", "upharpoonleft", "LeftUpVector": Rune(0x021BF)
  of "rharu", "RightVector", "rightharpoonup": Rune(0x021C0)
  of "rhard", "rightharpoondown", "DownRightVector": Rune(0x021C1)
  of "dharr", "RightDownVector", "downharpoonright": Rune(0x021C2)
  of "dharl", "LeftDownVector", "downharpoonleft": Rune(0x021C3)
  of "rlarr", "rightleftarrows", "RightArrowLeftArrow": Rune(0x021C4)
  of "udarr", "UpArrowDownArrow": Rune(0x021C5)
  of "lrarr", "leftrightarrows", "LeftArrowRightArrow": Rune(0x021C6)
  of "llarr", "leftleftarrows": Rune(0x021C7)
  of "uuarr", "upuparrows": Rune(0x021C8)
  of "rrarr", "rightrightarrows": Rune(0x021C9)
  of "ddarr", "downdownarrows": Rune(0x021CA)
  of "lrhar", "ReverseEquilibrium",
    "leftrightharpoons": Rune(0x021CB)
  of "rlhar", "rightleftharpoons", "Equilibrium": Rune(0x021CC)
  of "nlArr", "nLeftarrow": Rune(0x021CD)
  of "nhArr", "nLeftrightarrow": Rune(0x021CE)
  of "nrArr", "nRightarrow": Rune(0x021CF)
  of "lArr", "Leftarrow", "DoubleLeftArrow": Rune(0x021D0)
  of "uArr", "Uparrow", "DoubleUpArrow": Rune(0x021D1)
  of "rArr", "Rightarrow", "Implies",
    "DoubleRightArrow": Rune(0x021D2)
  of "dArr", "Downarrow", "DoubleDownArrow": Rune(0x021D3)
  of "hArr", "Leftrightarrow", "DoubleLeftRightArrow",
    "iff": Rune(0x021D4)
  of "vArr", "Updownarrow", "DoubleUpDownArrow": Rune(0x021D5)
  of "nwArr": Rune(0x021D6)
  of "neArr": Rune(0x021D7)
  of "seArr": Rune(0x021D8)
  of "swArr": Rune(0x021D9)
  of "lAarr", "Lleftarrow": Rune(0x021DA)
  of "rAarr", "Rrightarrow": Rune(0x021DB)
  of "zigrarr": Rune(0x021DD)
  of "larrb", "LeftArrowBar": Rune(0x021E4)
  of "rarrb", "RightArrowBar": Rune(0x021E5)
  of "duarr", "DownArrowUpArrow": Rune(0x021F5)
  of "loarr": Rune(0x021FD)
  of "roarr": Rune(0x021FE)
  of "hoarr": Rune(0x021FF)
  of "forall", "ForAll": Rune(0x02200)
  of "comp", "complement": Rune(0x02201)
  of "part", "PartialD": Rune(0x02202)
  of "exist", "Exists": Rune(0x02203)
  of "nexist", "NotExists", "nexists": Rune(0x02204)
  of "empty", "emptyset", "emptyv", "varnothing": Rune(0x02205)
  of "nabla", "Del": Rune(0x02207)
  of "isin", "isinv", "Element", "in": Rune(0x02208)
  of "notin", "NotElement", "notinva": Rune(0x02209)
  of "niv", "ReverseElement", "ni", "SuchThat": Rune(0x0220B)
  of "notni", "notniva", "NotReverseElement": Rune(0x0220C)
  of "prod", "Product": Rune(0x0220F)
  of "coprod", "Coproduct": Rune(0x02210)
  of "sum", "Sum": Rune(0x02211)
  of "minus": Rune(0x02212)
  of "mnplus", "mp", "MinusPlus": Rune(0x02213)
  of "plusdo", "dotplus": Rune(0x02214)
  of "setmn", "setminus", "Backslash", "ssetmn",
    "smallsetminus": Rune(0x02216)
  of "lowast": Rune(0x02217)
  of "compfn", "SmallCircle": Rune(0x02218)
  of "radic", "Sqrt": Rune(0x0221A)
  of "prop", "propto", "Proportional", "vprop",
    "varpropto": Rune(0x0221D)
  of "infin": Rune(0x0221E)
  of "angrt": Rune(0x0221F)
  of "ang", "angle": Rune(0x02220)
  of "angmsd", "measuredangle": Rune(0x02221)
  of "angsph": Rune(0x02222)
  of "mid", "VerticalBar", "smid", "shortmid": Rune(0x02223)
  of "nmid", "NotVerticalBar", "nsmid", "nshortmid": Rune(0x02224)
  of "par", "parallel", "DoubleVerticalBar", "spar",
    "shortparallel": Rune(0x02225)
  of "npar", "nparallel", "NotDoubleVerticalBar", "nspar",
    "nshortparallel": Rune(0x02226)
  of "and", "wedge": Rune(0x02227)
  of "or", "vee": Rune(0x02228)
  of "cap": Rune(0x02229)
  of "cup": Rune(0x0222A)
  of "int", "Integral": Rune(0x0222B)
  of "Int": Rune(0x0222C)
  of "tint", "iiint": Rune(0x0222D)
  of "conint", "oint", "ContourIntegral": Rune(0x0222E)
  of "Conint", "DoubleContourIntegral": Rune(0x0222F)
  of "Cconint": Rune(0x02230)
  of "cwint": Rune(0x02231)
  of "cwconint", "ClockwiseContourIntegral": Rune(0x02232)
  of "awconint", "CounterClockwiseContourIntegral": Rune(0x02233)
  of "there4", "therefore", "Therefore": Rune(0x02234)
  of "becaus", "because", "Because": Rune(0x02235)
  of "ratio": Rune(0x02236)
  of "Colon", "Proportion": Rune(0x02237)
  of "minusd", "dotminus": Rune(0x02238)
  of "mDDot": Rune(0x0223A)
  of "homtht": Rune(0x0223B)
  of "sim", "Tilde", "thksim", "thicksim": Rune(0x0223C)
  of "bsim", "backsim": Rune(0x0223D)
  of "ac", "mstpos": Rune(0x0223E)
  of "acd": Rune(0x0223F)
  of "wreath", "VerticalTilde", "wr": Rune(0x02240)
  of "nsim", "NotTilde": Rune(0x02241)
  of "esim", "EqualTilde", "eqsim": Rune(0x02242)
  of "sime", "TildeEqual", "simeq": Rune(0x02243)
  of "nsime", "nsimeq", "NotTildeEqual": Rune(0x02244)
  of "cong", "TildeFullEqual": Rune(0x02245)
  of "simne": Rune(0x02246)
  of "ncong", "NotTildeFullEqual": Rune(0x02247)
  of "asymp", "ap", "TildeTilde", "approx", "thkap",
    "thickapprox": Rune(0x02248)
  of "nap", "NotTildeTilde", "napprox": Rune(0x02249)
  of "ape", "approxeq": Rune(0x0224A)
  of "apid": Rune(0x0224B)
  of "bcong", "backcong": Rune(0x0224C)
  of "asympeq", "CupCap": Rune(0x0224D)
  of "bump", "HumpDownHump", "Bumpeq": Rune(0x0224E)
  of "bumpe", "HumpEqual", "bumpeq": Rune(0x0224F)
  of "esdot", "DotEqual", "doteq": Rune(0x02250)
  of "eDot", "doteqdot": Rune(0x02251)
  of "efDot", "fallingdotseq": Rune(0x02252)
  of "erDot", "risingdotseq": Rune(0x02253)
  of "colone", "coloneq", "Assign": Rune(0x02254)
  of "ecolon", "eqcolon": Rune(0x02255)
  of "ecir", "eqcirc": Rune(0x02256)
  of "cire", "circeq": Rune(0x02257)
  of "wedgeq": Rune(0x02259)
  of "veeeq": Rune(0x0225A)
  of "trie", "triangleq": Rune(0x0225C)
  of "equest", "questeq": Rune(0x0225F)
  of "ne", "NotEqual": Rune(0x02260)
  of "equiv", "Congruent": Rune(0x02261)
  of "nequiv", "NotCongruent": Rune(0x02262)
  of "le", "leq": Rune(0x02264)
  of "ge", "GreaterEqual", "geq": Rune(0x02265)
  of "lE", "LessFullEqual", "leqq": Rune(0x02266)
  of "gE", "GreaterFullEqual", "geqq": Rune(0x02267)
  of "lnE", "lneqq": Rune(0x02268)
  of "gnE", "gneqq": Rune(0x02269)
  of "Lt", "NestedLessLess", "ll": Rune(0x0226A)
  of "Gt", "NestedGreaterGreater", "gg": Rune(0x0226B)
  of "twixt", "between": Rune(0x0226C)
  of "NotCupCap": Rune(0x0226D)
  of "nlt", "NotLess", "nless": Rune(0x0226E)
  of "ngt", "NotGreater", "ngtr": Rune(0x0226F)
  of "nle", "NotLessEqual", "nleq": Rune(0x02270)
  of "nge", "NotGreaterEqual", "ngeq": Rune(0x02271)
  of "lsim", "LessTilde", "lesssim": Rune(0x02272)
  of "gsim", "gtrsim", "GreaterTilde": Rune(0x02273)
  of "nlsim", "NotLessTilde": Rune(0x02274)
  of "ngsim", "NotGreaterTilde": Rune(0x02275)
  of "lg", "lessgtr", "LessGreater": Rune(0x02276)
  of "gl", "gtrless", "GreaterLess": Rune(0x02277)
  of "ntlg", "NotLessGreater": Rune(0x02278)
  of "ntgl", "NotGreaterLess": Rune(0x02279)
  of "pr", "Precedes", "prec": Rune(0x0227A)
  of "sc", "Succeeds", "succ": Rune(0x0227B)
  of "prcue", "PrecedesSlantEqual", "preccurlyeq": Rune(0x0227C)
  of "sccue", "SucceedsSlantEqual", "succcurlyeq": Rune(0x0227D)
  of "prsim", "precsim", "PrecedesTilde": Rune(0x0227E)
  of "scsim", "succsim", "SucceedsTilde": Rune(0x0227F)
  of "npr", "nprec", "NotPrecedes": Rune(0x02280)
  of "nsc", "nsucc", "NotSucceeds": Rune(0x02281)
  of "sub", "subset": Rune(0x02282)
  of "sup", "supset", "Superset": Rune(0x02283)
  of "nsub": Rune(0x02284)
  of "nsup": Rune(0x02285)
  of "sube", "SubsetEqual", "subseteq": Rune(0x02286)
  of "supe", "supseteq", "SupersetEqual": Rune(0x02287)
  of "nsube", "nsubseteq", "NotSubsetEqual": Rune(0x02288)
  of "nsupe", "nsupseteq", "NotSupersetEqual": Rune(0x02289)
  of "subne", "subsetneq": Rune(0x0228A)
  of "supne", "supsetneq": Rune(0x0228B)
  of "cupdot": Rune(0x0228D)
  of "uplus", "UnionPlus": Rune(0x0228E)
  of "sqsub", "SquareSubset", "sqsubset": Rune(0x0228F)
  of "sqsup", "SquareSuperset", "sqsupset": Rune(0x02290)
  of "sqsube", "SquareSubsetEqual", "sqsubseteq": Rune(0x02291)
  of "sqsupe", "SquareSupersetEqual", "sqsupseteq": Rune(0x02292)
  of "sqcap", "SquareIntersection": Rune(0x02293)
  of "sqcup", "SquareUnion": Rune(0x02294)
  of "oplus", "CirclePlus": Rune(0x02295)
  of "ominus", "CircleMinus": Rune(0x02296)
  of "otimes", "CircleTimes": Rune(0x02297)
  of "osol": Rune(0x02298)
  of "odot", "CircleDot": Rune(0x02299)
  of "ocir", "circledcirc": Rune(0x0229A)
  of "oast", "circledast": Rune(0x0229B)
  of "odash", "circleddash": Rune(0x0229D)
  of "plusb", "boxplus": Rune(0x0229E)
  of "minusb", "boxminus": Rune(0x0229F)
  of "timesb", "boxtimes": Rune(0x022A0)
  of "sdotb", "dotsquare": Rune(0x022A1)
  of "vdash", "RightTee": Rune(0x022A2)
  of "dashv", "LeftTee": Rune(0x022A3)
  of "top", "DownTee": Rune(0x022A4)
  of "bottom", "bot", "perp", "UpTee": Rune(0x022A5)
  of "models": Rune(0x022A7)
  of "vDash", "DoubleRightTee": Rune(0x022A8)
  of "Vdash": Rune(0x022A9)
  of "Vvdash": Rune(0x022AA)
  of "VDash": Rune(0x022AB)
  of "nvdash": Rune(0x022AC)
  of "nvDash": Rune(0x022AD)
  of "nVdash": Rune(0x022AE)
  of "nVDash": Rune(0x022AF)
  of "prurel": Rune(0x022B0)
  of "vltri", "vartriangleleft", "LeftTriangle": Rune(0x022B2)
  of "vrtri", "vartriangleright", "RightTriangle": Rune(0x022B3)
  of "ltrie", "trianglelefteq", "LeftTriangleEqual": Rune(0x022B4)
  of "rtrie", "trianglerighteq", "RightTriangleEqual": Rune(0x022B5)
  of "origof": Rune(0x022B6)
  of "imof": Rune(0x022B7)
  of "mumap", "multimap": Rune(0x022B8)
  of "hercon": Rune(0x022B9)
  of "intcal", "intercal": Rune(0x022BA)
  of "veebar": Rune(0x022BB)
  of "barvee": Rune(0x022BD)
  of "angrtvb": Rune(0x022BE)
  of "lrtri": Rune(0x022BF)
  of "xwedge", "Wedge", "bigwedge": Rune(0x022C0)
  of "xvee", "Vee", "bigvee": Rune(0x022C1)
  of "xcap", "Intersection", "bigcap": Rune(0x022C2)
  of "xcup", "Union", "bigcup": Rune(0x022C3)
  of "diam", "diamond", "Diamond": Rune(0x022C4)
  of "sdot": Rune(0x022C5)
  of "sstarf", "Star": Rune(0x022C6)
  of "divonx", "divideontimes": Rune(0x022C7)
  of "bowtie": Rune(0x022C8)
  of "ltimes": Rune(0x022C9)
  of "rtimes": Rune(0x022CA)
  of "lthree", "leftthreetimes": Rune(0x022CB)
  of "rthree", "rightthreetimes": Rune(0x022CC)
  of "bsime", "backsimeq": Rune(0x022CD)
  of "cuvee", "curlyvee": Rune(0x022CE)
  of "cuwed", "curlywedge": Rune(0x022CF)
  of "Sub", "Subset": Rune(0x022D0)
  of "Sup", "Supset": Rune(0x022D1)
  of "Cap": Rune(0x022D2)
  of "Cup": Rune(0x022D3)
  of "fork", "pitchfork": Rune(0x022D4)
  of "epar": Rune(0x022D5)
  of "ltdot", "lessdot": Rune(0x022D6)
  of "gtdot", "gtrdot": Rune(0x022D7)
  of "Ll": Rune(0x022D8)
  of "Gg", "ggg": Rune(0x022D9)
  of "leg", "LessEqualGreater", "lesseqgtr": Rune(0x022DA)
  of "gel", "gtreqless", "GreaterEqualLess": Rune(0x022DB)
  of "cuepr", "curlyeqprec": Rune(0x022DE)
  of "cuesc", "curlyeqsucc": Rune(0x022DF)
  of "nprcue", "NotPrecedesSlantEqual": Rune(0x022E0)
  of "nsccue", "NotSucceedsSlantEqual": Rune(0x022E1)
  of "nsqsube", "NotSquareSubsetEqual": Rune(0x022E2)
  of "nsqsupe", "NotSquareSupersetEqual": Rune(0x022E3)
  of "lnsim": Rune(0x022E6)
  of "gnsim": Rune(0x022E7)
  of "prnsim", "precnsim": Rune(0x022E8)
  of "scnsim", "succnsim": Rune(0x022E9)
  of "nltri", "ntriangleleft", "NotLeftTriangle": Rune(0x022EA)
  of "nrtri", "ntriangleright", "NotRightTriangle": Rune(0x022EB)
  of "nltrie", "ntrianglelefteq",
    "NotLeftTriangleEqual": Rune(0x022EC)
  of "nrtrie", "ntrianglerighteq",
    "NotRightTriangleEqual": Rune(0x022ED)
  of "vellip": Rune(0x022EE)
  of "ctdot": Rune(0x022EF)
  of "utdot": Rune(0x022F0)
  of "dtdot": Rune(0x022F1)
  of "disin": Rune(0x022F2)
  of "isinsv": Rune(0x022F3)
  of "isins": Rune(0x022F4)
  of "isindot": Rune(0x022F5)
  of "notinvc": Rune(0x022F6)
  of "notinvb": Rune(0x022F7)
  of "isinE": Rune(0x022F9)
  of "nisd": Rune(0x022FA)
  of "xnis": Rune(0x022FB)
  of "nis": Rune(0x022FC)
  of "notnivc": Rune(0x022FD)
  of "notnivb": Rune(0x022FE)
  of "barwed", "barwedge": Rune(0x02305)
  of "Barwed", "doublebarwedge": Rune(0x02306)
  of "lceil", "LeftCeiling": Rune(0x02308)
  of "rceil", "RightCeiling": Rune(0x02309)
  of "lfloor", "LeftFloor": Rune(0x0230A)
  of "rfloor", "RightFloor": Rune(0x0230B)
  of "drcrop": Rune(0x0230C)
  of "dlcrop": Rune(0x0230D)
  of "urcrop": Rune(0x0230E)
  of "ulcrop": Rune(0x0230F)
  of "bnot": Rune(0x02310)
  of "profline": Rune(0x02312)
  of "profsurf": Rune(0x02313)
  of "telrec": Rune(0x02315)
  of "target": Rune(0x02316)
  of "ulcorn", "ulcorner": Rune(0x0231C)
  of "urcorn", "urcorner": Rune(0x0231D)
  of "dlcorn", "llcorner": Rune(0x0231E)
  of "drcorn", "lrcorner": Rune(0x0231F)
  of "frown", "sfrown": Rune(0x02322)
  of "smile", "ssmile": Rune(0x02323)
  of "cylcty": Rune(0x0232D)
  of "profalar": Rune(0x0232E)
  of "topbot": Rune(0x02336)
  of "ovbar": Rune(0x0233D)
  of "solbar": Rune(0x0233F)
  of "angzarr": Rune(0x0237C)
  of "lmoust", "lmoustache": Rune(0x023B0)
  of "rmoust", "rmoustache": Rune(0x023B1)
  of "tbrk", "OverBracket": Rune(0x023B4)
  of "bbrk", "UnderBracket": Rune(0x023B5)
  of "bbrktbrk": Rune(0x023B6)
  of "OverParenthesis": Rune(0x023DC)
  of "UnderParenthesis": Rune(0x023DD)
  of "OverBrace": Rune(0x023DE)
  of "UnderBrace": Rune(0x023DF)
  of "trpezium": Rune(0x023E2)
  of "elinters": Rune(0x023E7)
  of "blank": Rune(0x02423)
  of "oS", "circledS": Rune(0x024C8)
  of "boxh", "HorizontalLine": Rune(0x02500)
  of "boxv": Rune(0x02502)
  of "boxdr": Rune(0x0250C)
  of "boxdl": Rune(0x02510)
  of "boxur": Rune(0x02514)
  of "boxul": Rune(0x02518)
  of "boxvr": Rune(0x0251C)
  of "boxvl": Rune(0x02524)
  of "boxhd": Rune(0x0252C)
  of "boxhu": Rune(0x02534)
  of "boxvh": Rune(0x0253C)
  of "boxH": Rune(0x02550)
  of "boxV": Rune(0x02551)
  of "boxdR": Rune(0x02552)
  of "boxDr": Rune(0x02553)
  of "boxDR": Rune(0x02554)
  of "boxdL": Rune(0x02555)
  of "boxDl": Rune(0x02556)
  of "boxDL": Rune(0x02557)
  of "boxuR": Rune(0x02558)
  of "boxUr": Rune(0x02559)
  of "boxUR": Rune(0x0255A)
  of "boxuL": Rune(0x0255B)
  of "boxUl": Rune(0x0255C)
  of "boxUL": Rune(0x0255D)
  of "boxvR": Rune(0x0255E)
  of "boxVr": Rune(0x0255F)
  of "boxVR": Rune(0x02560)
  of "boxvL": Rune(0x02561)
  of "boxVl": Rune(0x02562)
  of "boxVL": Rune(0x02563)
  of "boxHd": Rune(0x02564)
  of "boxhD": Rune(0x02565)
  of "boxHD": Rune(0x02566)
  of "boxHu": Rune(0x02567)
  of "boxhU": Rune(0x02568)
  of "boxHU": Rune(0x02569)
  of "boxvH": Rune(0x0256A)
  of "boxVh": Rune(0x0256B)
  of "boxVH": Rune(0x0256C)
  of "uhblk": Rune(0x02580)
  of "lhblk": Rune(0x02584)
  of "block": Rune(0x02588)
  of "blk14": Rune(0x02591)
  of "blk12": Rune(0x02592)
  of "blk34": Rune(0x02593)
  of "squ", "square", "Square": Rune(0x025A1)
  of "squf", "squarf", "blacksquare",
    "FilledVerySmallSquare": Rune(0x025AA)
  of "EmptyVerySmallSquare": Rune(0x025AB)
  of "rect": Rune(0x025AD)
  of "marker": Rune(0x025AE)
  of "fltns": Rune(0x025B1)
  of "xutri", "bigtriangleup": Rune(0x025B3)
  of "utrif", "blacktriangle": Rune(0x025B4)
  of "utri", "triangle": Rune(0x025B5)
  of "rtrif", "blacktriangleright": Rune(0x025B8)
  of "rtri", "triangleright": Rune(0x025B9)
  of "xdtri", "bigtriangledown": Rune(0x025BD)
  of "dtrif", "blacktriangledown": Rune(0x025BE)
  of "dtri", "triangledown": Rune(0x025BF)
  of "ltrif", "blacktriangleleft": Rune(0x025C2)
  of "ltri", "triangleleft": Rune(0x025C3)
  of "loz", "lozenge": Rune(0x025CA)
  of "cir": Rune(0x025CB)
  of "tridot": Rune(0x025EC)
  of "xcirc", "bigcirc": Rune(0x025EF)
  of "ultri": Rune(0x025F8)
  of "urtri": Rune(0x025F9)
  of "lltri": Rune(0x025FA)
  of "EmptySmallSquare": Rune(0x025FB)
  of "FilledSmallSquare": Rune(0x025FC)
  of "starf", "bigstar": Rune(0x02605)
  of "star": Rune(0x02606)
  of "phone": Rune(0x0260E)
  of "female": Rune(0x02640)
  of "male": Rune(0x02642)
  of "spades", "spadesuit": Rune(0x02660)
  of "clubs", "clubsuit": Rune(0x02663)
  of "hearts", "heartsuit": Rune(0x02665)
  of "diams", "diamondsuit": Rune(0x02666)
  of "sung": Rune(0x0266A)
  of "flat": Rune(0x0266D)
  of "natur", "natural": Rune(0x0266E)
  of "sharp": Rune(0x0266F)
  of "check", "checkmark": Rune(0x02713)
  of "cross": Rune(0x02717)
  of "malt", "maltese": Rune(0x02720)
  of "sext": Rune(0x02736)
  of "VerticalSeparator": Rune(0x02758)
  of "lbbrk": Rune(0x02772)
  of "rbbrk": Rune(0x02773)
  of "lobrk", "LeftDoubleBracket": Rune(0x027E6)
  of "robrk", "RightDoubleBracket": Rune(0x027E7)
  of "lang", "LeftAngleBracket", "langle": Rune(0x027E8)
  of "rang", "RightAngleBracket", "rangle": Rune(0x027E9)
  of "Lang": Rune(0x027EA)
  of "Rang": Rune(0x027EB)
  of "loang": Rune(0x027EC)
  of "roang": Rune(0x027ED)
  of "xlarr", "longleftarrow", "LongLeftArrow": Rune(0x027F5)
  of "xrarr", "longrightarrow", "LongRightArrow": Rune(0x027F6)
  of "xharr", "longleftrightarrow",
    "LongLeftRightArrow": Rune(0x027F7)
  of "xlArr", "Longleftarrow", "DoubleLongLeftArrow": Rune(0x027F8)
  of "xrArr", "Longrightarrow", "DoubleLongRightArrow": Rune(0x027F9)
  of "xhArr", "Longleftrightarrow",
    "DoubleLongLeftRightArrow": Rune(0x027FA)
  of "xmap", "longmapsto": Rune(0x027FC)
  of "dzigrarr": Rune(0x027FF)
  of "nvlArr": Rune(0x02902)
  of "nvrArr": Rune(0x02903)
  of "nvHarr": Rune(0x02904)
  of "Map": Rune(0x02905)
  of "lbarr": Rune(0x0290C)
  of "rbarr", "bkarow": Rune(0x0290D)
  of "lBarr": Rune(0x0290E)
  of "rBarr", "dbkarow": Rune(0x0290F)
  of "RBarr", "drbkarow": Rune(0x02910)
  of "DDotrahd": Rune(0x02911)
  of "UpArrowBar": Rune(0x02912)
  of "DownArrowBar": Rune(0x02913)
  of "Rarrtl": Rune(0x02916)
  of "latail": Rune(0x02919)
  of "ratail": Rune(0x0291A)
  of "lAtail": Rune(0x0291B)
  of "rAtail": Rune(0x0291C)
  of "larrfs": Rune(0x0291D)
  of "rarrfs": Rune(0x0291E)
  of "larrbfs": Rune(0x0291F)
  of "rarrbfs": Rune(0x02920)
  of "nwarhk": Rune(0x02923)
  of "nearhk": Rune(0x02924)
  of "searhk", "hksearow": Rune(0x02925)
  of "swarhk", "hkswarow": Rune(0x02926)
  of "nwnear": Rune(0x02927)
  of "nesear", "toea": Rune(0x02928)
  of "seswar", "tosa": Rune(0x02929)
  of "swnwar": Rune(0x0292A)
  of "rarrc": Rune(0x02933)
  of "cudarrr": Rune(0x02935)
  of "ldca": Rune(0x02936)
  of "rdca": Rune(0x02937)
  of "cudarrl": Rune(0x02938)
  of "larrpl": Rune(0x02939)
  of "curarrm": Rune(0x0293C)
  of "cularrp": Rune(0x0293D)
  of "rarrpl": Rune(0x02945)
  of "harrcir": Rune(0x02948)
  of "Uarrocir": Rune(0x02949)
  of "lurdshar": Rune(0x0294A)
  of "ldrushar": Rune(0x0294B)
  of "LeftRightVector": Rune(0x0294E)
  of "RightUpDownVector": Rune(0x0294F)
  of "DownLeftRightVector": Rune(0x02950)
  of "LeftUpDownVector": Rune(0x02951)
  of "LeftVectorBar": Rune(0x02952)
  of "RightVectorBar": Rune(0x02953)
  of "RightUpVectorBar": Rune(0x02954)
  of "RightDownVectorBar": Rune(0x02955)
  of "DownLeftVectorBar": Rune(0x02956)
  of "DownRightVectorBar": Rune(0x02957)
  of "LeftUpVectorBar": Rune(0x02958)
  of "LeftDownVectorBar": Rune(0x02959)
  of "LeftTeeVector": Rune(0x0295A)
  of "RightTeeVector": Rune(0x0295B)
  of "RightUpTeeVector": Rune(0x0295C)
  of "RightDownTeeVector": Rune(0x0295D)
  of "DownLeftTeeVector": Rune(0x0295E)
  of "DownRightTeeVector": Rune(0x0295F)
  of "LeftUpTeeVector": Rune(0x02960)
  of "LeftDownTeeVector": Rune(0x02961)
  of "lHar": Rune(0x02962)
  of "uHar": Rune(0x02963)
  of "rHar": Rune(0x02964)
  of "dHar": Rune(0x02965)
  of "luruhar": Rune(0x02966)
  of "ldrdhar": Rune(0x02967)
  of "ruluhar": Rune(0x02968)
  of "rdldhar": Rune(0x02969)
  of "lharul": Rune(0x0296A)
  of "llhard": Rune(0x0296B)
  of "rharul": Rune(0x0296C)
  of "lrhard": Rune(0x0296D)
  of "udhar", "UpEquilibrium": Rune(0x0296E)
  of "duhar", "ReverseUpEquilibrium": Rune(0x0296F)
  of "RoundImplies": Rune(0x02970)
  of "erarr": Rune(0x02971)
  of "simrarr": Rune(0x02972)
  of "larrsim": Rune(0x02973)
  of "rarrsim": Rune(0x02974)
  of "rarrap": Rune(0x02975)
  of "ltlarr": Rune(0x02976)
  of "gtrarr": Rune(0x02978)
  of "subrarr": Rune(0x02979)
  of "suplarr": Rune(0x0297B)
  of "lfisht": Rune(0x0297C)
  of "rfisht": Rune(0x0297D)
  of "ufisht": Rune(0x0297E)
  of "dfisht": Rune(0x0297F)
  of "lopar": Rune(0x02985)
  of "ropar": Rune(0x02986)
  of "lbrke": Rune(0x0298B)
  of "rbrke": Rune(0x0298C)
  of "lbrkslu": Rune(0x0298D)
  of "rbrksld": Rune(0x0298E)
  of "lbrksld": Rune(0x0298F)
  of "rbrkslu": Rune(0x02990)
  of "langd": Rune(0x02991)
  of "rangd": Rune(0x02992)
  of "lparlt": Rune(0x02993)
  of "rpargt": Rune(0x02994)
  of "gtlPar": Rune(0x02995)
  of "ltrPar": Rune(0x02996)
  of "vzigzag": Rune(0x0299A)
  of "vangrt": Rune(0x0299C)
  of "angrtvbd": Rune(0x0299D)
  of "ange": Rune(0x029A4)
  of "range": Rune(0x029A5)
  of "dwangle": Rune(0x029A6)
  of "uwangle": Rune(0x029A7)
  of "angmsdaa": Rune(0x029A8)
  of "angmsdab": Rune(0x029A9)
  of "angmsdac": Rune(0x029AA)
  of "angmsdad": Rune(0x029AB)
  of "angmsdae": Rune(0x029AC)
  of "angmsdaf": Rune(0x029AD)
  of "angmsdag": Rune(0x029AE)
  of "angmsdah": Rune(0x029AF)
  of "bemptyv": Rune(0x029B0)
  of "demptyv": Rune(0x029B1)
  of "cemptyv": Rune(0x029B2)
  of "raemptyv": Rune(0x029B3)
  of "laemptyv": Rune(0x029B4)
  of "ohbar": Rune(0x029B5)
  of "omid": Rune(0x029B6)
  of "opar": Rune(0x029B7)
  of "operp": Rune(0x029B9)
  of "olcross": Rune(0x029BB)
  of "odsold": Rune(0x029BC)
  of "olcir": Rune(0x029BE)
  of "ofcir": Rune(0x029BF)
  of "olt": Rune(0x029C0)
  of "ogt": Rune(0x029C1)
  of "cirscir": Rune(0x029C2)
  of "cirE": Rune(0x029C3)
  of "solb": Rune(0x029C4)
  of "bsolb": Rune(0x029C5)
  of "boxbox": Rune(0x029C9)
  of "trisb": Rune(0x029CD)
  of "rtriltri": Rune(0x029CE)
  of "LeftTriangleBar": Rune(0x029CF)
  of "RightTriangleBar": Rune(0x029D0)
  of "race": Rune(0x029DA)
  of "iinfin": Rune(0x029DC)
  of "infintie": Rune(0x029DD)
  of "nvinfin": Rune(0x029DE)
  of "eparsl": Rune(0x029E3)
  of "smeparsl": Rune(0x029E4)
  of "eqvparsl": Rune(0x029E5)
  of "lozf", "blacklozenge": Rune(0x029EB)
  of "RuleDelayed": Rune(0x029F4)
  of "dsol": Rune(0x029F6)
  of "xodot", "bigodot": Rune(0x02A00)
  of "xoplus", "bigoplus": Rune(0x02A01)
  of "xotime", "bigotimes": Rune(0x02A02)
  of "xuplus", "biguplus": Rune(0x02A04)
  of "xsqcup", "bigsqcup": Rune(0x02A06)
  of "qint", "iiiint": Rune(0x02A0C)
  of "fpartint": Rune(0x02A0D)
  of "cirfnint": Rune(0x02A10)
  of "awint": Rune(0x02A11)
  of "rppolint": Rune(0x02A12)
  of "scpolint": Rune(0x02A13)
  of "npolint": Rune(0x02A14)
  of "pointint": Rune(0x02A15)
  of "quatint": Rune(0x02A16)
  of "intlarhk": Rune(0x02A17)
  of "pluscir": Rune(0x02A22)
  of "plusacir": Rune(0x02A23)
  of "simplus": Rune(0x02A24)
  of "plusdu": Rune(0x02A25)
  of "plussim": Rune(0x02A26)
  of "plustwo": Rune(0x02A27)
  of "mcomma": Rune(0x02A29)
  of "minusdu": Rune(0x02A2A)
  of "loplus": Rune(0x02A2D)
  of "roplus": Rune(0x02A2E)
  of "Cross": Rune(0x02A2F)
  of "timesd": Rune(0x02A30)
  of "timesbar": Rune(0x02A31)
  of "smashp": Rune(0x02A33)
  of "lotimes": Rune(0x02A34)
  of "rotimes": Rune(0x02A35)
  of "otimesas": Rune(0x02A36)
  of "Otimes": Rune(0x02A37)
  of "odiv": Rune(0x02A38)
  of "triplus": Rune(0x02A39)
  of "triminus": Rune(0x02A3A)
  of "tritime": Rune(0x02A3B)
  of "iprod", "intprod": Rune(0x02A3C)
  of "amalg": Rune(0x02A3F)
  of "capdot": Rune(0x02A40)
  of "ncup": Rune(0x02A42)
  of "ncap": Rune(0x02A43)
  of "capand": Rune(0x02A44)
  of "cupor": Rune(0x02A45)
  of "cupcap": Rune(0x02A46)
  of "capcup": Rune(0x02A47)
  of "cupbrcap": Rune(0x02A48)
  of "capbrcup": Rune(0x02A49)
  of "cupcup": Rune(0x02A4A)
  of "capcap": Rune(0x02A4B)
  of "ccups": Rune(0x02A4C)
  of "ccaps": Rune(0x02A4D)
  of "ccupssm": Rune(0x02A50)
  of "And": Rune(0x02A53)
  of "Or": Rune(0x02A54)
  of "andand": Rune(0x02A55)
  of "oror": Rune(0x02A56)
  of "orslope": Rune(0x02A57)
  of "andslope": Rune(0x02A58)
  of "andv": Rune(0x02A5A)
  of "orv": Rune(0x02A5B)
  of "andd": Rune(0x02A5C)
  of "ord": Rune(0x02A5D)
  of "wedbar": Rune(0x02A5F)
  of "sdote": Rune(0x02A66)
  of "simdot": Rune(0x02A6A)
  of "congdot": Rune(0x02A6D)
  of "easter": Rune(0x02A6E)
  of "apacir": Rune(0x02A6F)
  of "apE": Rune(0x02A70)
  of "eplus": Rune(0x02A71)
  of "pluse": Rune(0x02A72)
  of "Esim": Rune(0x02A73)
  of "Colone": Rune(0x02A74)
  of "Equal": Rune(0x02A75)
  of "eDDot", "ddotseq": Rune(0x02A77)
  of "equivDD": Rune(0x02A78)
  of "ltcir": Rune(0x02A79)
  of "gtcir": Rune(0x02A7A)
  of "ltquest": Rune(0x02A7B)
  of "gtquest": Rune(0x02A7C)
  of "les", "LessSlantEqual", "leqslant": Rune(0x02A7D)
  of "ges", "GreaterSlantEqual", "geqslant": Rune(0x02A7E)
  of "lesdot": Rune(0x02A7F)
  of "gesdot": Rune(0x02A80)
  of "lesdoto": Rune(0x02A81)
  of "gesdoto": Rune(0x02A82)
  of "lesdotor": Rune(0x02A83)
  of "gesdotol": Rune(0x02A84)
  of "lap", "lessapprox": Rune(0x02A85)
  of "gap", "gtrapprox": Rune(0x02A86)
  of "lne", "lneq": Rune(0x02A87)
  of "gne", "gneq": Rune(0x02A88)
  of "lnap", "lnapprox": Rune(0x02A89)
  of "gnap", "gnapprox": Rune(0x02A8A)
  of "lEg", "lesseqqgtr": Rune(0x02A8B)
  of "gEl", "gtreqqless": Rune(0x02A8C)
  of "lsime": Rune(0x02A8D)
  of "gsime": Rune(0x02A8E)
  of "lsimg": Rune(0x02A8F)
  of "gsiml": Rune(0x02A90)
  of "lgE": Rune(0x02A91)
  of "glE": Rune(0x02A92)
  of "lesges": Rune(0x02A93)
  of "gesles": Rune(0x02A94)
  of "els", "eqslantless": Rune(0x02A95)
  of "egs", "eqslantgtr": Rune(0x02A96)
  of "elsdot": Rune(0x02A97)
  of "egsdot": Rune(0x02A98)
  of "el": Rune(0x02A99)
  of "eg": Rune(0x02A9A)
  of "siml": Rune(0x02A9D)
  of "simg": Rune(0x02A9E)
  of "simlE": Rune(0x02A9F)
  of "simgE": Rune(0x02AA0)
  of "LessLess": Rune(0x02AA1)
  of "GreaterGreater": Rune(0x02AA2)
  of "glj": Rune(0x02AA4)
  of "gla": Rune(0x02AA5)
  of "ltcc": Rune(0x02AA6)
  of "gtcc": Rune(0x02AA7)
  of "lescc": Rune(0x02AA8)
  of "gescc": Rune(0x02AA9)
  of "smt": Rune(0x02AAA)
  of "lat": Rune(0x02AAB)
  of "smte": Rune(0x02AAC)
  of "late": Rune(0x02AAD)
  of "bumpE": Rune(0x02AAE)
  of "pre", "preceq", "PrecedesEqual": Rune(0x02AAF)
  of "sce", "succeq", "SucceedsEqual": Rune(0x02AB0)
  of "prE": Rune(0x02AB3)
  of "scE": Rune(0x02AB4)
  of "prnE", "precneqq": Rune(0x02AB5)
  of "scnE", "succneqq": Rune(0x02AB6)
  of "prap", "precapprox": Rune(0x02AB7)
  of "scap", "succapprox": Rune(0x02AB8)
  of "prnap", "precnapprox": Rune(0x02AB9)
  of "scnap", "succnapprox": Rune(0x02ABA)
  of "Pr": Rune(0x02ABB)
  of "Sc": Rune(0x02ABC)
  of "subdot": Rune(0x02ABD)
  of "supdot": Rune(0x02ABE)
  of "subplus": Rune(0x02ABF)
  of "supplus": Rune(0x02AC0)
  of "submult": Rune(0x02AC1)
  of "supmult": Rune(0x02AC2)
  of "subedot": Rune(0x02AC3)
  of "supedot": Rune(0x02AC4)
  of "subE", "subseteqq": Rune(0x02AC5)
  of "supE", "supseteqq": Rune(0x02AC6)
  of "subsim": Rune(0x02AC7)
  of "supsim": Rune(0x02AC8)
  of "subnE", "subsetneqq": Rune(0x02ACB)
  of "supnE", "supsetneqq": Rune(0x02ACC)
  of "csub": Rune(0x02ACF)
  of "csup": Rune(0x02AD0)
  of "csube": Rune(0x02AD1)
  of "csupe": Rune(0x02AD2)
  of "subsup": Rune(0x02AD3)
  of "supsub": Rune(0x02AD4)
  of "subsub": Rune(0x02AD5)
  of "supsup": Rune(0x02AD6)
  of "suphsub": Rune(0x02AD7)
  of "supdsub": Rune(0x02AD8)
  of "forkv": Rune(0x02AD9)
  of "topfork": Rune(0x02ADA)
  of "mlcp": Rune(0x02ADB)
  of "Dashv", "DoubleLeftTee": Rune(0x02AE4)
  of "Vdashl": Rune(0x02AE6)
  of "Barv": Rune(0x02AE7)
  of "vBar": Rune(0x02AE8)
  of "vBarv": Rune(0x02AE9)
  of "Vbar": Rune(0x02AEB)
  of "Not": Rune(0x02AEC)
  of "bNot": Rune(0x02AED)
  of "rnmid": Rune(0x02AEE)
  of "cirmid": Rune(0x02AEF)
  of "midcir": Rune(0x02AF0)
  of "topcir": Rune(0x02AF1)
  of "nhpar": Rune(0x02AF2)
  of "parsim": Rune(0x02AF3)
  of "parsl": Rune(0x02AFD)
  of "fflig": Rune(0x0FB00)
  of "filig": Rune(0x0FB01)
  of "fllig": Rune(0x0FB02)
  of "ffilig": Rune(0x0FB03)
  of "ffllig": Rune(0x0FB04)
  of "Ascr": Rune(0x1D49C)
  of "Cscr": Rune(0x1D49E)
  of "Dscr": Rune(0x1D49F)
  of "Gscr": Rune(0x1D4A2)
  of "Jscr": Rune(0x1D4A5)
  of "Kscr": Rune(0x1D4A6)
  of "Nscr": Rune(0x1D4A9)
  of "Oscr": Rune(0x1D4AA)
  of "Pscr": Rune(0x1D4AB)
  of "Qscr": Rune(0x1D4AC)
  of "Sscr": Rune(0x1D4AE)
  of "Tscr": Rune(0x1D4AF)
  of "Uscr": Rune(0x1D4B0)
  of "Vscr": Rune(0x1D4B1)
  of "Wscr": Rune(0x1D4B2)
  of "Xscr": Rune(0x1D4B3)
  of "Yscr": Rune(0x1D4B4)
  of "Zscr": Rune(0x1D4B5)
  of "ascr": Rune(0x1D4B6)
  of "bscr": Rune(0x1D4B7)
  of "cscr": Rune(0x1D4B8)
  of "dscr": Rune(0x1D4B9)
  of "fscr": Rune(0x1D4BB)
  of "hscr": Rune(0x1D4BD)
  of "iscr": Rune(0x1D4BE)
  of "jscr": Rune(0x1D4BF)
  of "kscr": Rune(0x1D4C0)
  of "lscr": Rune(0x1D4C1)
  of "mscr": Rune(0x1D4C2)
  of "nscr": Rune(0x1D4C3)
  of "pscr": Rune(0x1D4C5)
  of "qscr": Rune(0x1D4C6)
  of "rscr": Rune(0x1D4C7)
  of "sscr": Rune(0x1D4C8)
  of "tscr": Rune(0x1D4C9)
  of "uscr": Rune(0x1D4CA)
  of "vscr": Rune(0x1D4CB)
  of "wscr": Rune(0x1D4CC)
  of "xscr": Rune(0x1D4CD)
  of "yscr": Rune(0x1D4CE)
  of "zscr": Rune(0x1D4CF)
  of "Afr": Rune(0x1D504)
  of "Bfr": Rune(0x1D505)
  of "Dfr": Rune(0x1D507)
  of "Efr": Rune(0x1D508)
  of "Ffr": Rune(0x1D509)
  of "Gfr": Rune(0x1D50A)
  of "Jfr": Rune(0x1D50D)
  of "Kfr": Rune(0x1D50E)
  of "Lfr": Rune(0x1D50F)
  of "Mfr": Rune(0x1D510)
  of "Nfr": Rune(0x1D511)
  of "Ofr": Rune(0x1D512)
  of "Pfr": Rune(0x1D513)
  of "Qfr": Rune(0x1D514)
  of "Sfr": Rune(0x1D516)
  of "Tfr": Rune(0x1D517)
  of "Ufr": Rune(0x1D518)
  of "Vfr": Rune(0x1D519)
  of "Wfr": Rune(0x1D51A)
  of "Xfr": Rune(0x1D51B)
  of "Yfr": Rune(0x1D51C)
  of "afr": Rune(0x1D51E)
  of "bfr": Rune(0x1D51F)
  of "cfr": Rune(0x1D520)
  of "dfr": Rune(0x1D521)
  of "efr": Rune(0x1D522)
  of "ffr": Rune(0x1D523)
  of "gfr": Rune(0x1D524)
  of "hfr": Rune(0x1D525)
  of "ifr": Rune(0x1D526)
  of "jfr": Rune(0x1D527)
  of "kfr": Rune(0x1D528)
  of "lfr": Rune(0x1D529)
  of "mfr": Rune(0x1D52A)
  of "nfr": Rune(0x1D52B)
  of "ofr": Rune(0x1D52C)
  of "pfr": Rune(0x1D52D)
  of "qfr": Rune(0x1D52E)
  of "rfr": Rune(0x1D52F)
  of "sfr": Rune(0x1D530)
  of "tfr": Rune(0x1D531)
  of "ufr": Rune(0x1D532)
  of "vfr": Rune(0x1D533)
  of "wfr": Rune(0x1D534)
  of "xfr": Rune(0x1D535)
  of "yfr": Rune(0x1D536)
  of "zfr": Rune(0x1D537)
  of "Aopf": Rune(0x1D538)
  of "Bopf": Rune(0x1D539)
  of "Dopf": Rune(0x1D53B)
  of "Eopf": Rune(0x1D53C)
  of "Fopf": Rune(0x1D53D)
  of "Gopf": Rune(0x1D53E)
  of "Iopf": Rune(0x1D540)
  of "Jopf": Rune(0x1D541)
  of "Kopf": Rune(0x1D542)
  of "Lopf": Rune(0x1D543)
  of "Mopf": Rune(0x1D544)
  of "Oopf": Rune(0x1D546)
  of "Sopf": Rune(0x1D54A)
  of "Topf": Rune(0x1D54B)
  of "Uopf": Rune(0x1D54C)
  of "Vopf": Rune(0x1D54D)
  of "Wopf": Rune(0x1D54E)
  of "Xopf": Rune(0x1D54F)
  of "Yopf": Rune(0x1D550)
  of "aopf": Rune(0x1D552)
  of "bopf": Rune(0x1D553)
  of "copf": Rune(0x1D554)
  of "dopf": Rune(0x1D555)
  of "eopf": Rune(0x1D556)
  of "fopf": Rune(0x1D557)
  of "gopf": Rune(0x1D558)
  of "hopf": Rune(0x1D559)
  of "iopf": Rune(0x1D55A)
  of "jopf": Rune(0x1D55B)
  of "kopf": Rune(0x1D55C)
  of "lopf": Rune(0x1D55D)
  of "mopf": Rune(0x1D55E)
  of "nopf": Rune(0x1D55F)
  of "oopf": Rune(0x1D560)
  of "popf": Rune(0x1D561)
  of "qopf": Rune(0x1D562)
  of "ropf": Rune(0x1D563)
  of "sopf": Rune(0x1D564)
  of "topf": Rune(0x1D565)
  of "uopf": Rune(0x1D566)
  of "vopf": Rune(0x1D567)
  of "wopf": Rune(0x1D568)
  of "xopf": Rune(0x1D569)
  of "yopf": Rune(0x1D56A)
  of "zopf": Rune(0x1D56B)
  else: Rune(0)

proc entityToUtf8*(entity: string): string =
  ## Converts an HTML entity name like `&Uuml;` or values like `&#220;`
  ## or `&#x000DC;` to its UTF-8 equivalent.
  ## "" is returned if the entity name is unknown. The HTML parser
  ## already converts entities to UTF-8.
  runnableExamples:
    const sigma = "Σ"
    doAssert entityToUtf8("") == ""
    doAssert entityToUtf8("a") == ""
    doAssert entityToUtf8("gt") == ">"
    doAssert entityToUtf8("Uuml") == "Ü"
    doAssert entityToUtf8("quest") == "?"
    doAssert entityToUtf8("#63") == "?"
    doAssert entityToUtf8("Sigma") == sigma
    doAssert entityToUtf8("#931") == sigma
    doAssert entityToUtf8("#0931") == sigma
    doAssert entityToUtf8("#x3A3") == sigma
    doAssert entityToUtf8("#x03A3") == sigma
    doAssert entityToUtf8("#x3a3") == sigma
    doAssert entityToUtf8("#X3a3") == sigma
  let rune = entityToRune(entity)
  if rune.ord <= 0: result = ""
  else: result = toUTF8(rune)

proc addNode(father, son: XmlNode) =
  if son != nil: add(father, son)

proc parse(x: var XmlParser, errors: var seq[string]): XmlNode {.gcsafe.}

proc expected(x: var XmlParser, n: XmlNode): string =
  result = errorMsg(x, "</" & n.tag & "> expected")

template elemName(x: untyped): untyped = rawData(x)

template adderr(x: untyped) =
  errors.add(x)

proc untilElementEnd(x: var XmlParser, result: XmlNode,
                     errors: var seq[string]) =
  # we parsed e.g. `<br>` and don't really expect a `</br>`:
  if result.htmlTag in SingleTags:
    if x.kind != xmlElementEnd or cmpIgnoreCase(x.elemName, result.tag) != 0:
      return
  while true:
    case x.kind
    of xmlElementStart, xmlElementOpen:
      case result.htmlTag
      of tagP, tagInput, tagOption:
        # some tags are common to have no `</end>`, like `<li>` but
        # allow `<p>` in `<dd>`, `<dt>` and `<li>` in next case
        if htmlTag(x.elemName) in {tagLi, tagP, tagDt, tagDd, tagInput,
                                   tagOption}:
          adderr(expected(x, result))
          break
      of tagDd, tagDt, tagLi:
        if htmlTag(x.elemName) in {tagLi, tagDt, tagDd, tagInput,
                                   tagOption}:
          adderr(expected(x, result))
          break
      of tagTd, tagTh:
        if htmlTag(x.elemName) in {tagTr, tagTd, tagTh, tagTfoot, tagThead}:
          adderr(expected(x, result))
          break
      of tagTr:
        if htmlTag(x.elemName) == tagTr:
          adderr(expected(x, result))
          break
      of tagOptgroup:
        if htmlTag(x.elemName) in {tagOption, tagOptgroup}:
          adderr(expected(x, result))
          break
      else: discard
      result.addNode(parse(x, errors))
    of xmlElementEnd:
      if cmpIgnoreCase(x.elemName, result.tag) != 0:
        #echo "5; expected: ", result.htmltag, " ", x.elemName
        adderr(expected(x, result))
        # this seems to do better match error corrections in browsers:
        while x.kind in {xmlElementEnd, xmlWhitespace}:
          if x.kind == xmlElementEnd and cmpIgnoreCase(x.elemName,
              result.tag) == 0:
            break
          next(x)
      next(x)
      break
    of xmlEof:
      adderr(expected(x, result))
      break
    else:
      result.addNode(parse(x, errors))

proc parse(x: var XmlParser, errors: var seq[string]): XmlNode =
  result = nil
  case x.kind
  of xmlComment:
    result = newComment(x.rawData)
    next(x)
  of xmlCharData, xmlWhitespace:
    result = newText(x.rawData)
    next(x)
  of xmlPI, xmlSpecial:
    # we just ignore processing instructions for now
    next(x)
  of xmlError:
    adderr(errorMsg(x))
    next(x)
  of xmlElementStart:
    result = newElement(toLowerAscii(x.elemName))
    next(x)
    untilElementEnd(x, result, errors)
  of xmlElementEnd:
    adderr(errorMsg(x, "unexpected ending tag: " & x.elemName))
  of xmlElementOpen:
    result = newElement(toLowerAscii(x.elemName))
    next(x)
    result.attrs = newStringTable()
    while true:
      case x.kind
      of xmlAttribute:
        result.attrs[x.rawData] = x.rawData2
        next(x)
      of xmlElementClose:
        next(x)
        break
      of xmlError:
        adderr(errorMsg(x))
        next(x)
        break
      else:
        adderr(errorMsg(x, "'>' expected"))
        next(x)
        break
    untilElementEnd(x, result, errors)
  of xmlAttribute, xmlElementClose:
    adderr(errorMsg(x, "<some_tag> expected"))
    next(x)
  of xmlCData:
    result = newCData(x.rawData)
    next(x)
  of xmlEntity:
    var u = entityToUtf8(x.rawData)
    if u.len != 0: result = newText(u)
    next(x)
  of xmlEof: discard

proc parseHtml*(s: Stream, filename: string,
                errors: var seq[string]): XmlNode =
  ## Parses the XML from stream `s` and returns a `XmlNode`. Every
  ## occurred parsing error is added to the `errors` sequence.
  var x: XmlParser = default(XmlParser)
  open(x, s, filename, {reportComments, reportWhitespace, allowUnquotedAttribs,
    allowEmptyAttribs})
  next(x)
  # skip the DOCTYPE:
  if x.kind == xmlSpecial: next(x)

  result = newElement("document")
  result.addNode(parse(x, errors))
  #if x.kind != xmlEof:
  #  adderr(errorMsg(x, "EOF expected"))
  while x.kind != xmlEof:
    var oldPos = x.bufpos # little hack to see if we made any progress
    result.addNode(parse(x, errors))
    if x.bufpos == oldPos:
      # force progress!
      next(x)
  close(x)
  if result.len == 1:
    result = result[0]

proc parseHtml*(s: Stream): XmlNode =
  ## Parses the HTML from stream `s` and returns a `XmlNode`. All parsing
  ## errors are ignored.
  var errors: seq[string] = @[]
  result = parseHtml(s, "unknown_html_doc", errors)

proc parseHtml*(html: string): XmlNode =
  ## Parses the HTML from string `html` and returns a `XmlNode`. All parsing
  ## errors are ignored.
  parseHtml(newStringStream(html))

proc loadHtml*(path: string, errors: var seq[string]): XmlNode =
  ## Loads and parses HTML from file specified by `path`, and returns
  ## a `XmlNode`. Every occurred parsing error is added to
  ## the `errors` sequence.
  var s = newFileStream(path, fmRead)
  if s == nil: raise newException(IOError, "Unable to read file: " & path)
  result = parseHtml(s, path, errors)

proc loadHtml*(path: string): XmlNode =
  ## Loads and parses HTML from file specified by `path`, and returns
  ## a `XmlNode`. All parsing errors are ignored.
  var errors: seq[string] = @[]
  result = loadHtml(path, errors)

when not defined(testing) and isMainModule:
  import std/os

  var errors: seq[string] = @[]
  var x = loadHtml(paramStr(1), errors)
  for e in items(errors): echo e

  var f: File
  if open(f, "test.txt", fmWrite):
    f.write($x)
    f.close()
  else:
    quit("cannot write test.txt")
