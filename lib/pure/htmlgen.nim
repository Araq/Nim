#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Do yourself a favor and import the module
## as `from std/htmlgen import nil` and then fully qualify the macros.
##
## *Note*: The Karax project (`nimble install karax`) has a better
## way to achieve the same, see https://github.com/pragmagic/karax/blob/master/tests/nativehtmlgen.nim
## for an example.
##
##
## This module implements a simple `XML`:idx: and `HTML`:idx: code
## generator. Each commonly used HTML tag has a corresponding macro
## that generates a string with its HTML representation.
##
## MathML
## ======
##
## `MathML <https://wikipedia.org/wiki/MathML>`_ is supported, MathML is part of HTML5.
## `MathML <https://wikipedia.org/wiki/MathML>`_ is an Standard ISO/IEC 40314 from year 2015.
## MathML allows you to `draw advanced math on the web <https://developer.mozilla.org/en-US/docs/Web/MathML/Element/math#Examples>`_,
## `visually similar to Latex math. <https://developer.mozilla.org/en-US/docs/Web/MathML/Element/semantics#Example>`_
##
## Examples
## ========
##
##   ```Nim
##   var nim = "Nim"
##   echo h1(a(href="https://nim-lang.org", nim))
##   ```
##
## Writes the string:
##
##     <h1><a href="https://nim-lang.org">Nim</a></h1>
##

import
  std/[macros, strutils]

const
  coreAttr* = " accesskey class contenteditable dir hidden id lang " &
    "spellcheck style tabindex title translate " ## HTML DOM Core Attributes
  eventAttr* = "onabort onblur oncancel oncanplay oncanplaythrough onchange " &
    "onclick oncuechange ondblclick ondurationchange onemptied onended " &
    "onerror onfocus oninput oninvalid onkeydown onkeypress onkeyup onload " &
    "onloadeddata onloadedmetadata onloadstart onmousedown onmouseenter " &
    "onmouseleave onmousemove onmouseout onmouseover onmouseup onmousewheel " &
    "onpause onplay onplaying onprogress onratechange onreset onresize " &
    "onscroll onseeked onseeking onselect onshow onstalled onsubmit " &
    "onsuspend ontimeupdate ontoggle onvolumechange onwaiting " ## HTML DOM Event Attributes
  ariaAttr* = " role "                           ## HTML DOM Aria Attributes
  commonAttr* = coreAttr & eventAttr & ariaAttr  ## HTML DOM Common Attributes

proc getIdent(e: NimNode): string =
  case e.kind
  of nnkIdent:
    result = e.strVal.normalize
  of nnkAccQuoted:
    result = getIdent(e[0])
    for i in 1 .. e.len-1:
      result.add getIdent(e[i])
  else: error("cannot extract identifier from node: " & toStrLit(e).strVal, e)

proc delete[T](s: var seq[T], attr: T): bool =
  var idx = find(s, attr)
  if idx >= 0:
    var L = s.len
    s[idx] = s[L-1]
    setLen(s, L-1)
    result = true
  else:
    result = false

proc xmlCheckedTag*(argsList: NimNode, tag: string, optAttr = "", reqAttr = "",
    isLeaf = false): NimNode =
  ## use this procedure to define a new XML tag

  # copy the attributes; when iterating over them these lists
  # will be modified, so that each attribute is only given one value
  var req = splitWhitespace(reqAttr)
  var opt = splitWhitespace(optAttr)
  result = newNimNode(nnkBracket)
  result.add(newStrLitNode("<"))
  result.add(newStrLitNode(tag))
  # first pass over attributes:
  for i in 0 ..< argsList.len:
    if argsList[i].kind == nnkExprEqExpr:
      var name = getIdent(argsList[i][0])
      if name.startsWith("data-") or delete(req, name) or delete(opt, name):
        result.add(newStrLitNode(" "))
        result.add(newStrLitNode(name))
        result.add(newStrLitNode("=\""))
        result.add(argsList[i][1])
        result.add(newStrLitNode("\""))
      else:
        error("invalid attribute for '" & tag & "' element: " & name, argsList[i])
  # check each required attribute exists:
  if req.len > 0:
    error(req[0] & " attribute for '" & tag & "' element expected", argsList)
  if isLeaf:
    for i in 0 ..< argsList.len:
      if argsList[i].kind != nnkExprEqExpr:
        error("element " & tag & " cannot be nested", argsList[i])
    result.add(newStrLitNode(" />"))
  else:
    result.add(newStrLitNode(">"))
    # second pass over elements:
    for i in 0 ..< argsList.len:
      if argsList[i].kind != nnkExprEqExpr: result.add(argsList[i])
    result.add(newStrLitNode("</"))
    result.add(newStrLitNode(tag))
    result.add(newStrLitNode(">"))
  result = nestList(ident"&", result)

macro a*(e: varargs[untyped]): untyped =
  ## Generates the HTML `a` element.
  result = xmlCheckedTag(e, "a", "href target download rel hreflang type " &
    commonAttr)

macro abbr*(e: varargs[untyped]): untyped =
  ## Generates the HTML `abbr` element.
  result = xmlCheckedTag(e, "abbr", commonAttr)

macro address*(e: varargs[untyped]): untyped =
  ## Generates the HTML `address` element.
  result = xmlCheckedTag(e, "address", commonAttr)

macro area*(e: varargs[untyped]): untyped =
  ## Generates the HTML `area` element.
  result = xmlCheckedTag(e, "area", "coords download href hreflang rel " &
    "shape target type" & commonAttr, "alt", true)

macro article*(e: varargs[untyped]): untyped =
  ## Generates the HTML `article` element.
  result = xmlCheckedTag(e, "article", commonAttr)

macro aside*(e: varargs[untyped]): untyped =
  ## Generates the HTML `aside` element.
  result = xmlCheckedTag(e, "aside", commonAttr)

macro audio*(e: varargs[untyped]): untyped =
  ## Generates the HTML `audio` element.
  result = xmlCheckedTag(e, "audio", "src crossorigin preload " &
    "autoplay mediagroup loop muted controls" & commonAttr)

macro b*(e: varargs[untyped]): untyped =
  ## Generates the HTML `b` element.
  result = xmlCheckedTag(e, "b", commonAttr)

macro base*(e: varargs[untyped]): untyped =
  ## Generates the HTML `base` element.
  result = xmlCheckedTag(e, "base", "href target" & commonAttr, "", true)

macro bdi*(e: varargs[untyped]): untyped =
  ## Generates the HTML `bdi` element.
  result = xmlCheckedTag(e, "bdi", commonAttr)

macro bdo*(e: varargs[untyped]): untyped =
  ## Generates the HTML `bdo` element.
  result = xmlCheckedTag(e, "bdo", commonAttr)

macro big*(e: varargs[untyped]): untyped =
  ## Generates the HTML `big` element.
  result = xmlCheckedTag(e, "big", commonAttr)

macro blockquote*(e: varargs[untyped]): untyped =
  ## Generates the HTML `blockquote` element.
  result = xmlCheckedTag(e, "blockquote", " cite" & commonAttr)

macro body*(e: varargs[untyped]): untyped =
  ## Generates the HTML `body` element.
  result = xmlCheckedTag(e, "body", "onafterprint onbeforeprint " &
    "onbeforeunload onhashchange onmessage onoffline ononline onpagehide " &
    "onpageshow onpopstate onstorage onunload" & commonAttr)

macro br*(e: varargs[untyped]): untyped =
  ## Generates the HTML `br` element.
  result = xmlCheckedTag(e, "br", commonAttr, "", true)

macro button*(e: varargs[untyped]): untyped =
  ## Generates the HTML `button` element.
  result = xmlCheckedTag(e, "button", "autofocus disabled form formaction " &
    "formenctype formmethod formnovalidate formtarget menu name type value" &
    commonAttr)

macro canvas*(e: varargs[untyped]): untyped =
  ## Generates the HTML `canvas` element.
  result = xmlCheckedTag(e, "canvas", "width height" & commonAttr)

macro caption*(e: varargs[untyped]): untyped =
  ## Generates the HTML `caption` element.
  result = xmlCheckedTag(e, "caption", commonAttr)

macro center*(e: varargs[untyped]): untyped =
  ## Generates the HTML `center` element.
  result = xmlCheckedTag(e, "center", commonAttr)

macro cite*(e: varargs[untyped]): untyped =
  ## Generates the HTML `cite` element.
  result = xmlCheckedTag(e, "cite", commonAttr)

macro code*(e: varargs[untyped]): untyped =
  ## Generates the HTML `code` element.
  result = xmlCheckedTag(e, "code", commonAttr)

macro col*(e: varargs[untyped]): untyped =
  ## Generates the HTML `col` element.
  result = xmlCheckedTag(e, "col", "span" & commonAttr, "", true)

macro colgroup*(e: varargs[untyped]): untyped =
  ## Generates the HTML `colgroup` element.
  result = xmlCheckedTag(e, "colgroup", "span" & commonAttr)

macro data*(e: varargs[untyped]): untyped =
  ## Generates the HTML `data` element.
  result = xmlCheckedTag(e, "data", "value" & commonAttr)

macro datalist*(e: varargs[untyped]): untyped =
  ## Generates the HTML `datalist` element.
  result = xmlCheckedTag(e, "datalist", commonAttr)

macro dd*(e: varargs[untyped]): untyped =
  ## Generates the HTML `dd` element.
  result = xmlCheckedTag(e, "dd", commonAttr)

macro del*(e: varargs[untyped]): untyped =
  ## Generates the HTML `del` element.
  result = xmlCheckedTag(e, "del", "cite datetime" & commonAttr)

macro details*(e: varargs[untyped]): untyped =
  ## Generates the HTML `details` element.
  result = xmlCheckedTag(e, "details", commonAttr & "open")

macro dfn*(e: varargs[untyped]): untyped =
  ## Generates the HTML `dfn` element.
  result = xmlCheckedTag(e, "dfn", commonAttr)

macro dialog*(e: varargs[untyped]): untyped =
  ## Generates the HTML `dialog` element.
  result = xmlCheckedTag(e, "dialog", commonAttr & "open")

macro `div`*(e: varargs[untyped]): untyped =
  ## Generates the HTML `div` element.
  result = xmlCheckedTag(e, "div", commonAttr)

macro dl*(e: varargs[untyped]): untyped =
  ## Generates the HTML `dl` element.
  result = xmlCheckedTag(e, "dl", commonAttr)

macro dt*(e: varargs[untyped]): untyped =
  ## Generates the HTML `dt` element.
  result = xmlCheckedTag(e, "dt", commonAttr)

macro em*(e: varargs[untyped]): untyped =
  ## Generates the HTML `em` element.
  result = xmlCheckedTag(e, "em", commonAttr)

macro embed*(e: varargs[untyped]): untyped =
  ## Generates the HTML `embed` element.
  result = xmlCheckedTag(e, "embed", "src type height width" &
    commonAttr, "", true)

macro fieldset*(e: varargs[untyped]): untyped =
  ## Generates the HTML `fieldset` element.
  result = xmlCheckedTag(e, "fieldset", "disabled form name" & commonAttr)

macro figure*(e: varargs[untyped]): untyped =
  ## Generates the HTML `figure` element.
  result = xmlCheckedTag(e, "figure", commonAttr)

macro figcaption*(e: varargs[untyped]): untyped =
  ## Generates the HTML `figcaption` element.
  result = xmlCheckedTag(e, "figcaption", commonAttr)

macro footer*(e: varargs[untyped]): untyped =
  ## Generates the HTML `footer` element.
  result = xmlCheckedTag(e, "footer", commonAttr)

macro form*(e: varargs[untyped]): untyped =
  ## Generates the HTML `form` element.
  result = xmlCheckedTag(e, "form", "accept-charset action autocomplete " &
    "enctype method name novalidate target" & commonAttr)

macro h1*(e: varargs[untyped]): untyped =
  ## Generates the HTML `h1` element.
  result = xmlCheckedTag(e, "h1", commonAttr)

macro h2*(e: varargs[untyped]): untyped =
  ## Generates the HTML `h2` element.
  result = xmlCheckedTag(e, "h2", commonAttr)

macro h3*(e: varargs[untyped]): untyped =
  ## Generates the HTML `h3` element.
  result = xmlCheckedTag(e, "h3", commonAttr)

macro h4*(e: varargs[untyped]): untyped =
  ## Generates the HTML `h4` element.
  result = xmlCheckedTag(e, "h4", commonAttr)

macro h5*(e: varargs[untyped]): untyped =
  ## Generates the HTML `h5` element.
  result = xmlCheckedTag(e, "h5", commonAttr)

macro h6*(e: varargs[untyped]): untyped =
  ## Generates the HTML `h6` element.
  result = xmlCheckedTag(e, "h6", commonAttr)

macro head*(e: varargs[untyped]): untyped =
  ## Generates the HTML `head` element.
  result = xmlCheckedTag(e, "head", commonAttr)

macro header*(e: varargs[untyped]): untyped =
  ## Generates the HTML `header` element.
  result = xmlCheckedTag(e, "header", commonAttr)

macro html*(e: varargs[untyped]): untyped =
  ## Generates the HTML `html` element.
  result = xmlCheckedTag(e, "html", "xmlns" & commonAttr, "")

macro hr*(): untyped =
  ## Generates the HTML `hr` element.
  result = xmlCheckedTag(newNimNode(nnkArgList), "hr", commonAttr, "", true)

macro i*(e: varargs[untyped]): untyped =
  ## Generates the HTML `i` element.
  result = xmlCheckedTag(e, "i", commonAttr)

macro iframe*(e: varargs[untyped]): untyped =
  ## Generates the HTML `iframe` element.
  result = xmlCheckedTag(e, "iframe", "src srcdoc name sandbox width height loading" &
    commonAttr)

macro img*(e: varargs[untyped]): untyped =
  ## Generates the HTML `img` element.
  result = xmlCheckedTag(e, "img", "crossorigin usemap ismap height width loading" &
    commonAttr, "src alt", true)

macro input*(e: varargs[untyped]): untyped =
  ## Generates the HTML `input` element.
  result = xmlCheckedTag(e, "input", "accept alt autocomplete autofocus " &
    "checked dirname disabled form formaction formenctype formmethod " &
    "formnovalidate formtarget height inputmode list max maxlength min " &
    "minlength multiple name pattern placeholder readonly required size " &
    "src step type value width" & commonAttr, "", true)

macro ins*(e: varargs[untyped]): untyped =
  ## Generates the HTML `ins` element.
  result = xmlCheckedTag(e, "ins", "cite datetime" & commonAttr)

macro kbd*(e: varargs[untyped]): untyped =
  ## Generates the HTML `kbd` element.
  result = xmlCheckedTag(e, "kbd", commonAttr)

macro keygen*(e: varargs[untyped]): untyped =
  ## Generates the HTML `keygen` element.
  result = xmlCheckedTag(e, "keygen", "autofocus challenge disabled " &
    "form keytype name" & commonAttr)

macro label*(e: varargs[untyped]): untyped =
  ## Generates the HTML `label` element.
  result = xmlCheckedTag(e, "label", "form for" & commonAttr)

macro legend*(e: varargs[untyped]): untyped =
  ## Generates the HTML `legend` element.
  result = xmlCheckedTag(e, "legend", commonAttr)

macro li*(e: varargs[untyped]): untyped =
  ## Generates the HTML `li` element.
  result = xmlCheckedTag(e, "li", "value" & commonAttr)

macro link*(e: varargs[untyped]): untyped =
  ## Generates the HTML `link` element.
  result = xmlCheckedTag(e, "link", "href crossorigin rel media hreflang " &
    "type sizes" & commonAttr, "", true)

macro main*(e: varargs[untyped]): untyped =
  ## Generates the HTML `main` element.
  result = xmlCheckedTag(e, "main", commonAttr)

macro map*(e: varargs[untyped]): untyped =
  ## Generates the HTML `map` element.
  result = xmlCheckedTag(e, "map", "name" & commonAttr)

macro mark*(e: varargs[untyped]): untyped =
  ## Generates the HTML `mark` element.
  result = xmlCheckedTag(e, "mark", commonAttr)

macro marquee*(e: varargs[untyped]): untyped =
  ## Generates the HTML `marquee` element.
  result = xmlCheckedTag(e, "marquee", coreAttr &
    "behavior bgcolor direction height hspace loop scrollamount " &
    "scrolldelay truespeed vspace width onbounce onfinish onstart")

macro meta*(e: varargs[untyped]): untyped =
  ## Generates the HTML `meta` element.
  result = xmlCheckedTag(e, "meta", "name http-equiv content charset" &
    commonAttr, "", true)

macro meter*(e: varargs[untyped]): untyped =
  ## Generates the HTML `meter` element.
  result = xmlCheckedTag(e, "meter", "value min max low high optimum" &
    commonAttr)

macro nav*(e: varargs[untyped]): untyped =
  ## Generates the HTML `nav` element.
  result = xmlCheckedTag(e, "nav", commonAttr)

macro noscript*(e: varargs[untyped]): untyped =
  ## Generates the HTML `noscript` element.
  result = xmlCheckedTag(e, "noscript", commonAttr)

macro `object`*(e: varargs[untyped]): untyped =
  ## Generates the HTML `object` element.
  result = xmlCheckedTag(e, "object", "data type typemustmatch name usemap " &
    "form width height" & commonAttr)

macro ol*(e: varargs[untyped]): untyped =
  ## Generates the HTML `ol` element.
  result = xmlCheckedTag(e, "ol", "reversed start type" & commonAttr)

macro optgroup*(e: varargs[untyped]): untyped =
  ## Generates the HTML `optgroup` element.
  result = xmlCheckedTag(e, "optgroup", "disabled" & commonAttr, "label", false)

macro option*(e: varargs[untyped]): untyped =
  ## Generates the HTML `option` element.
  result = xmlCheckedTag(e, "option", "disabled label selected value" &
    commonAttr)

macro output*(e: varargs[untyped]): untyped =
  ## Generates the HTML `output` element.
  result = xmlCheckedTag(e, "output", "for form name" & commonAttr)

macro p*(e: varargs[untyped]): untyped =
  ## Generates the HTML `p` element.
  result = xmlCheckedTag(e, "p", commonAttr)

macro param*(e: varargs[untyped]): untyped =
  ## Generates the HTML `param` element.
  result = xmlCheckedTag(e, "param", commonAttr, "name value", true)

macro picture*(e: varargs[untyped]): untyped =
  ## Generates the HTML `picture` element.
  result = xmlCheckedTag(e, "picture", commonAttr)

macro pre*(e: varargs[untyped]): untyped =
  ## Generates the HTML `pre` element.
  result = xmlCheckedTag(e, "pre", commonAttr)

macro progress*(e: varargs[untyped]): untyped =
  ## Generates the HTML `progress` element.
  result = xmlCheckedTag(e, "progress", "value max" & commonAttr)

macro q*(e: varargs[untyped]): untyped =
  ## Generates the HTML `q` element.
  result = xmlCheckedTag(e, "q", "cite" & commonAttr)

macro rb*(e: varargs[untyped]): untyped =
  ## Generates the HTML `rb` element.
  result = xmlCheckedTag(e, "rb", commonAttr)

macro rp*(e: varargs[untyped]): untyped =
  ## Generates the HTML `rp` element.
  result = xmlCheckedTag(e, "rp", commonAttr)

macro rt*(e: varargs[untyped]): untyped =
  ## Generates the HTML `rt` element.
  result = xmlCheckedTag(e, "rt", commonAttr)

macro rtc*(e: varargs[untyped]): untyped =
  ## Generates the HTML `rtc` element.
  result = xmlCheckedTag(e, "rtc", commonAttr)

macro ruby*(e: varargs[untyped]): untyped =
  ## Generates the HTML `ruby` element.
  result = xmlCheckedTag(e, "ruby", commonAttr)

macro s*(e: varargs[untyped]): untyped =
  ## Generates the HTML `s` element.
  result = xmlCheckedTag(e, "s", commonAttr)

macro samp*(e: varargs[untyped]): untyped =
  ## Generates the HTML `samp` element.
  result = xmlCheckedTag(e, "samp", commonAttr)

macro script*(e: varargs[untyped]): untyped =
  ## Generates the HTML `script` element.
  result = xmlCheckedTag(e, "script", "src type charset async defer " &
    "crossorigin" & commonAttr)

macro section*(e: varargs[untyped]): untyped =
  ## Generates the HTML `section` element.
  result = xmlCheckedTag(e, "section", commonAttr)

macro select*(e: varargs[untyped]): untyped =
  ## Generates the HTML `select` element.
  result = xmlCheckedTag(e, "select", "autofocus disabled form multiple " &
    "name required size" & commonAttr)

macro slot*(e: varargs[untyped]): untyped =
  ## Generates the HTML `slot` element.
  result = xmlCheckedTag(e, "slot", commonAttr)

macro small*(e: varargs[untyped]): untyped =
  ## Generates the HTML `small` element.
  result = xmlCheckedTag(e, "small", commonAttr)

macro source*(e: varargs[untyped]): untyped =
  ## Generates the HTML `source` element.
  result = xmlCheckedTag(e, "source", "type" & commonAttr, "src", true)

macro span*(e: varargs[untyped]): untyped =
  ## Generates the HTML `span` element.
  result = xmlCheckedTag(e, "span", commonAttr)

macro strong*(e: varargs[untyped]): untyped =
  ## Generates the HTML `strong` element.
  result = xmlCheckedTag(e, "strong", commonAttr)

macro style*(e: varargs[untyped]): untyped =
  ## Generates the HTML `style` element.
  result = xmlCheckedTag(e, "style", "media type" & commonAttr)

macro sub*(e: varargs[untyped]): untyped =
  ## Generates the HTML `sub` element.
  result = xmlCheckedTag(e, "sub", commonAttr)

macro summary*(e: varargs[untyped]): untyped =
  ## Generates the HTML `summary` element.
  result = xmlCheckedTag(e, "summary", commonAttr)

macro sup*(e: varargs[untyped]): untyped =
  ## Generates the HTML `sup` element.
  result = xmlCheckedTag(e, "sup", commonAttr)

macro table*(e: varargs[untyped]): untyped =
  ## Generates the HTML `table` element.
  result = xmlCheckedTag(e, "table", "border sortable" & commonAttr)

macro tbody*(e: varargs[untyped]): untyped =
  ## Generates the HTML `tbody` element.
  result = xmlCheckedTag(e, "tbody", commonAttr)

macro td*(e: varargs[untyped]): untyped =
  ## Generates the HTML `td` element.
  result = xmlCheckedTag(e, "td", "colspan rowspan headers" & commonAttr)

macro `template`*(e: varargs[untyped]): untyped =
  ## Generates the HTML `template` element.
  result = xmlCheckedTag(e, "template", commonAttr)

macro textarea*(e: varargs[untyped]): untyped =
  ## Generates the HTML `textarea` element.
  result = xmlCheckedTag(e, "textarea", "autocomplete autofocus cols " &
    "dirname disabled form inputmode maxlength minlength name placeholder " &
    "readonly required rows wrap" & commonAttr)

macro tfoot*(e: varargs[untyped]): untyped =
  ## Generates the HTML `tfoot` element.
  result = xmlCheckedTag(e, "tfoot", commonAttr)

macro th*(e: varargs[untyped]): untyped =
  ## Generates the HTML `th` element.
  result = xmlCheckedTag(e, "th", "colspan rowspan headers abbr scope axis" &
    " sorted" & commonAttr)

macro thead*(e: varargs[untyped]): untyped =
  ## Generates the HTML `thead` element.
  result = xmlCheckedTag(e, "thead", commonAttr)

macro time*(e: varargs[untyped]): untyped =
  ## Generates the HTML `time` element.
  result = xmlCheckedTag(e, "time", "datetime" & commonAttr)

macro title*(e: varargs[untyped]): untyped =
  ## Generates the HTML `title` element.
  result = xmlCheckedTag(e, "title", commonAttr)

macro tr*(e: varargs[untyped]): untyped =
  ## Generates the HTML `tr` element.
  result = xmlCheckedTag(e, "tr", commonAttr)

macro track*(e: varargs[untyped]): untyped =
  ## Generates the HTML `track` element.
  result = xmlCheckedTag(e, "track", "kind srclang label default" &
    commonAttr, "src", true)

macro tt*(e: varargs[untyped]): untyped =
  ## Generates the HTML `tt` element.
  result = xmlCheckedTag(e, "tt", commonAttr)

macro u*(e: varargs[untyped]): untyped =
  ## Generates the HTML `u` element.
  result = xmlCheckedTag(e, "u", commonAttr)

macro ul*(e: varargs[untyped]): untyped =
  ## Generates the HTML `ul` element.
  result = xmlCheckedTag(e, "ul", commonAttr)

macro `var`*(e: varargs[untyped]): untyped =
  ## Generates the HTML `var` element.
  result = xmlCheckedTag(e, "var", commonAttr)

macro video*(e: varargs[untyped]): untyped =
  ## Generates the HTML `video` element.
  result = xmlCheckedTag(e, "video", "src crossorigin poster preload " &
    "autoplay mediagroup loop muted controls width height" & commonAttr)

macro wbr*(e: varargs[untyped]): untyped =
  ## Generates the HTML `wbr` element.
  result = xmlCheckedTag(e, "wbr", commonAttr, "", true)

macro portal*(e: varargs[untyped]): untyped =
  ## Generates the HTML `portal` element.
  result = xmlCheckedTag(e, "portal", "width height type src disabled" & commonAttr, "", false)


macro math*(e: varargs[untyped]): untyped =
  ## Generates the HTML `math` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/math#Examples
  result = xmlCheckedTag(e, "math", "mathbackground mathcolor href overflow" & commonAttr)

macro maction*(e: varargs[untyped]): untyped =
  ## Generates the HTML `maction` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/maction
  result = xmlCheckedTag(e, "maction", "mathbackground mathcolor href" & commonAttr)

macro menclose*(e: varargs[untyped]): untyped =
  ## Generates the HTML `menclose` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/menclose
  result = xmlCheckedTag(e, "menclose", "mathbackground mathcolor href notation" & commonAttr)

macro merror*(e: varargs[untyped]): untyped =
  ## Generates the HTML `merror` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/merror
  result = xmlCheckedTag(e, "merror", "mathbackground mathcolor href" & commonAttr)

macro mfenced*(e: varargs[untyped]): untyped =
  ## Generates the HTML `mfenced` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/mfenced
  result = xmlCheckedTag(e, "mfenced", "mathbackground mathcolor href open separators" & commonAttr)

macro mfrac*(e: varargs[untyped]): untyped =
  ## Generates the HTML `mfrac` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/mfrac
  result = xmlCheckedTag(e, "mfrac", "mathbackground mathcolor href linethickness numalign" & commonAttr)

macro mglyph*(e: varargs[untyped]): untyped =
  ## Generates the HTML `mglyph` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/mglyph
  result = xmlCheckedTag(e, "mglyph", "mathbackground mathcolor href src valign" & commonAttr)

macro mi*(e: varargs[untyped]): untyped =
  ## Generates the HTML `mi` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/mi
  result = xmlCheckedTag(e, "mi", "mathbackground mathcolor href mathsize mathvariant" & commonAttr)

macro mlabeledtr*(e: varargs[untyped]): untyped =
  ## Generates the HTML `mlabeledtr` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/mlabeledtr
  result = xmlCheckedTag(e, "mlabeledtr", "mathbackground mathcolor href columnalign groupalign rowalign" & commonAttr)

macro mmultiscripts*(e: varargs[untyped]): untyped =
  ## Generates the HTML `mmultiscripts` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/mmultiscripts
  result = xmlCheckedTag(e, "mmultiscripts", "mathbackground mathcolor href subscriptshift superscriptshift" & commonAttr)

macro mn*(e: varargs[untyped]): untyped =
  ## Generates the HTML `mn` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/mn
  result = xmlCheckedTag(e, "mn", "mathbackground mathcolor href mathsize mathvariant" & commonAttr)

macro mo*(e: varargs[untyped]): untyped =
  ## Generates the HTML `mo` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/mo
  result = xmlCheckedTag(e, "mo",
    "mathbackground mathcolor fence form largeop lspace mathsize mathvariant movablelimits rspace separator stretchy symmetric" & commonAttr)

macro mover*(e: varargs[untyped]): untyped =
  ## Generates the HTML `mover` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/mover
  result = xmlCheckedTag(e, "mover", "mathbackground mathcolor accent href" & commonAttr)

macro mpadded*(e: varargs[untyped]): untyped =
  ## Generates the HTML `mpadded` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/mpadded
  result = xmlCheckedTag(e, "mpadded", "mathbackground mathcolor depth href lspace voffset" & commonAttr)

macro mphantom*(e: varargs[untyped]): untyped =
  ## Generates the HTML `mphantom` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/mphantom
  result = xmlCheckedTag(e, "mphantom", "mathbackground" & commonAttr)

macro mroot*(e: varargs[untyped]): untyped =
  ## Generates the HTML `mroot` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/mroot
  result = xmlCheckedTag(e, "mroot", "mathbackground mathcolor href" & commonAttr)

macro mrow*(e: varargs[untyped]): untyped =
  ## Generates the HTML `mrow` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/mrow
  result = xmlCheckedTag(e, "mrow", "mathbackground mathcolor href" & commonAttr)

macro ms*(e: varargs[untyped]): untyped =
  ## Generates the HTML `ms` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/ms
  result = xmlCheckedTag(e, "ms", "mathbackground mathcolor href lquote mathsize mathvariant rquote" & commonAttr)

macro mspace*(e: varargs[untyped]): untyped =
  ## Generates the HTML `mspace` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/mspace
  result = xmlCheckedTag(e, "mspace", "mathbackground mathcolor href linebreak" & commonAttr)

macro msqrt*(e: varargs[untyped]): untyped =
  ## Generates the HTML `msqrt` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/msqrt
  result = xmlCheckedTag(e, "msqrt", "mathbackground mathcolor href" & commonAttr)

macro mstyle*(e: varargs[untyped]): untyped =
  ## Generates the HTML `mstyle` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/mstyle
  result = xmlCheckedTag(e, "mstyle", ("mathbackground mathcolor href decimalpoint displaystyle " &
    "infixlinebreakstyle scriptlevel scriptminsize scriptsizemultiplier" & commonAttr))

macro msub*(e: varargs[untyped]): untyped =
  ## Generates the HTML `msub` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/msub
  result = xmlCheckedTag(e, "msub", "mathbackground mathcolor href subscriptshift" & commonAttr)

macro msubsup*(e: varargs[untyped]): untyped =
  ## Generates the HTML `msubsup` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/msubsup
  result = xmlCheckedTag(e, "msubsup", "mathbackground mathcolor href subscriptshift superscriptshift" & commonAttr)

macro msup*(e: varargs[untyped]): untyped =
  ## Generates the HTML `msup` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/msup
  result = xmlCheckedTag(e, "msup", "mathbackground mathcolor href superscriptshift" & commonAttr)

macro mtable*(e: varargs[untyped]): untyped =
  ## Generates the HTML `mtable` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/mtable
  result = xmlCheckedTag(e, "mtable", ("mathbackground mathcolor href align " &
    "alignmentscope columnalign columnlines columnspacing columnwidth " &
    "displaystyle equalcolumns equalrows frame framespacing groupalign " &
    "rowalign rowlines rowspacing side width" & commonAttr))

macro mtd*(e: varargs[untyped]): untyped =
  ## Generates the HTML `mtd` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/mtd
  result = xmlCheckedTag(e, "mtd",
    "mathbackground mathcolor href columnalign columnspan groupalign rowalign rowspan" & commonAttr)

macro mtext*(e: varargs[untyped]): untyped =
  ## Generates the HTML `mtext` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/mtext
  result = xmlCheckedTag(e, "mtext", "mathbackground mathcolor href mathsize mathvariant" & commonAttr)

macro munder*(e: varargs[untyped]): untyped =
  ## Generates the HTML `munder` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/munder
  result = xmlCheckedTag(e, "munder", "mathbackground mathcolor href accentunder align" & commonAttr)

macro munderover*(e: varargs[untyped]): untyped =
  ## Generates the HTML `munderover` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/munderover
  result = xmlCheckedTag(e, "munderover", "mathbackground mathcolor href accentunder accent align" & commonAttr)

macro semantics*(e: varargs[untyped]): untyped =
  ## Generates the HTML `semantics` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/semantics
  result = xmlCheckedTag(e, "semantics", "mathbackground mathcolor href definitionURL encoding cd src" & commonAttr)

macro annotation*(e: varargs[untyped]): untyped =
  ## Generates the HTML `annotation` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/semantics
  result = xmlCheckedTag(e, "annotation", "mathbackground mathcolor href definitionURL encoding cd src" & commonAttr)

macro `annotation-xml`*(e: varargs[untyped]): untyped =
  ## Generates the HTML `annotation-xml` element. MathML https://wikipedia.org/wiki/MathML
  ## https://developer.mozilla.org/en-US/docs/Web/MathML/Element/semantics
  result = xmlCheckedTag(e, "annotation", "mathbackground mathcolor href definitionURL encoding cd src" & commonAttr)


runnableExamples:
  let nim = "Nim"
  assert h1(a(href = "https://nim-lang.org", nim)) ==
    """<h1><a href="https://nim-lang.org">Nim</a></h1>"""
  assert form(action = "test", `accept-charset` = "Content-Type") ==
    """<form action="test" accept-charset="Content-Type"></form>"""


  assert math(
    semantics(
      mrow(
        msup(
          mi("x"),
          mn("42")
        )
      )
    )
  ) == "<math><semantics><mrow><msup><mi>x</mi><mn>42</mn></msup></mrow></semantics></math>"

  assert math(
    semantics(
      annotation(encoding = "application/x-tex", title = "Latex on Web", r"x^{2} + y")
    )
  ) == """<math><semantics><annotation encoding="application/x-tex" title="Latex on Web">x^{2} + y</annotation></semantics></math>"""
