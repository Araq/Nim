#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements a generator of HTML/Latex from
## `reStructuredText`:idx: (see https://docutils.sourceforge.net/rst.html for
## information on this markup syntax) and is used by the compiler's `docgen
## tools <docgen.html>`_.
##
## You can generate HTML output through the convenience proc ``rstToHtml``,
## which provided an input string with rst markup returns a string with the
## generated HTML. The final output is meant to be embedded inside a full
## document you provide yourself, so it won't contain the usual ``<header>`` or
## ``<body>`` parts.
##
## You can also create a ``RstGenerator`` structure and populate it with the
## other lower level methods to finally build complete documents. This requires
## many options and tweaking, but you are not limited to snippets and can
## generate `LaTeX documents <https://en.wikipedia.org/wiki/LaTeX>`_ too.
##
## `Docutils configuration files`_ are not supported. Instead HTML generation
## can be tweaked by editing file ``config/nimdoc.cfg``.
##
## .. _Docutils configuration files: https://docutils.sourceforge.io/docs/user/config.htm
##
## There are stylistic difference between how this module renders some elements
## and how original Python Docutils does:
##
## * Backreferences to TOC in section headings are not generated.
##   In HTML each section is also a link that points to the section itself:
##   this is done for user to be able to copy the link into clipboard.
##
## * The same goes for footnotes/citations links: they point to themselves.
##   No backreferences are generated since finding all references of a footnote
##   can be done by simply searching for ``[footnoteName]``.

import std/[strutils, os, hashes, strtabs, tables, sequtils,
  algorithm, parseutils, strbasics]

import rstast, rst, rstidx, highlite

when defined(nimPreviewSlimSystem):
  import std/[assertions, syncio, formatfloat]


import ../../std/private/since

const
  HtmlExt = "html"
  IndexExt* = ".idx"

type
  OutputTarget* = enum ## which document type to generate
    outHtml,            # output is HTML
    outLatex            # output is Latex

  MetaEnum* = enum
    metaNone, metaTitleRaw, metaTitle, metaSubtitle, metaAuthor, metaVersion

  EscapeMode* = enum  # in Latex text inside options [] and URLs is
                      # escaped slightly differently than in normal text
    emText, emOption, emUrl  # emText is currently used for code also

  RstGenerator* = object of RootObj
    target*: OutputTarget
    config*: StringTableRef
    splitAfter*: int          # split too long entries in the TOC
    listingCounter*: int
    tocPart*: seq[PRstNode]   # headings for Table of Contents
    hasToc*: bool
    theIndex: string # Contents of the index file to be dumped at the end.
    findFile*: FindFileHandler
    msgHandler*: MsgHandler
    outDir*: string      ## output directory, initialized by docgen.nim
    destFile*: string    ## output (HTML) file, initialized by docgen.nim
    filenames*: RstFileTable
    filename*: string         ## source Nim or Rst file
    meta*: array[MetaEnum, string]
    currentSection: string ## \
    ## Stores the empty string or the last headline/overline found in the rst
    ## document, so it can be used as a prettier name for term index generation.
    seenIndexTerms: Table[string, int] ## \
    ## Keeps count of same text index terms to generate different identifiers
    ## for hyperlinks. See renderIndexTerm proc for details.
    id*: int               ## A counter useful for generating IDs.
    onTestSnippet*: proc (d: var RstGenerator; filename, cmd: string; status: int;
                          content: string) {.gcsafe.}
    escMode*: EscapeMode
    curQuotationDepth: int

  PDoc = var RstGenerator ## Alias to type less.

  CodeBlockParams = object ## Stores code block params.
    numberLines: bool ## True if the renderer has to show line numbers.
    startLine: int ## The starting line of the code block, by default 1.
    langStr: string ## Input string used to specify the language.
    lang: SourceLanguage ## Type of highlighting, by default none.
    filename: string
    testCmd: string
    status: int

proc prettyLink*(file: string): string =
  changeFileExt(file, "").replace("_._", "..")

proc init(p: var CodeBlockParams) =
  ## Default initialisation of CodeBlockParams to sane values.
  p.startLine = 1
  p.lang = langNone
  p.langStr = ""

proc initRstGenerator*(g: var RstGenerator, target: OutputTarget,
                       config: StringTableRef, filename: string,
                       findFile: FindFileHandler = nil,
                       msgHandler: MsgHandler = nil,
                       filenames = default(RstFileTable),
                       hasToc = false) =
  ## Initializes a ``RstGenerator``.
  ##
  ## You need to call this before using a ``RstGenerator`` with any other
  ## procs in this module. Pass a non ``nil`` ``StringTableRef`` value as
  ## `config` with parameters used by the HTML output generator.  If you don't
  ## know what to use, pass the results of the `defaultConfig()
  ## <#defaultConfig>_` proc.
  ##
  ## The `filename` parameter will be used for error reporting and creating
  ## index hyperlinks to the file, but you can pass an empty string here if you
  ## are parsing a stream in memory. If `filename` ends with the ``.nim``
  ## extension, the title for the document will be set by default to ``Module
  ## filename``.  This default title can be overridden by the embedded rst, but
  ## it helps to prettify the generated index if no title is found.
  ##
  ## The ``RstParseOptions``, ``FindFileHandler`` and ``MsgHandler`` types
  ## are defined in the `packages/docutils/rst module <rst.html>`_.
  ## ``options`` selects the behaviour of the rst parser.
  ##
  ## ``findFile`` is a proc used by the rst ``include`` directive among others.
  ## The purpose of this proc is to mangle or filter paths. It receives paths
  ## specified in the rst document and has to return a valid path to existing
  ## files or the empty string otherwise.  If you pass ``nil``, a default proc
  ## will be used which given a path returns the input path only if the file
  ## exists. One use for this proc is to transform relative paths found in the
  ## document to absolute path, useful if the rst file and the resources it
  ## references are not in the same directory as the current working directory.
  ##
  ## The ``msgHandler`` is a proc used for user error reporting. It will be
  ## called with the filename, line, col, and type of any error found during
  ## parsing. If you pass ``nil``, a default message handler will be used which
  ## writes the messages to the standard output.
  ##
  ## Example:
  ##
  ##   ```nim
  ##   import packages/docutils/rstgen
  ##
  ##   var gen: RstGenerator
  ##   gen.initRstGenerator(outHtml, defaultConfig(), "filename", {})
  ##   ```
  g.config = config
  g.target = target
  g.tocPart = @[]
  g.hasToc = hasToc
  g.filename = filename
  g.filenames = filenames
  g.splitAfter = 20
  g.theIndex = ""
  g.findFile = findFile
  g.currentSection = ""
  g.id = 0
  g.escMode = emText
  g.curQuotationDepth = 0
  let fileParts = filename.splitFile
  if fileParts.ext == ".nim":
    g.currentSection = "Module " & fileParts.name
  g.seenIndexTerms = initTable[string, int]()
  g.msgHandler = msgHandler

  let s = config.getOrDefault"split.item.toc"
  if s != "": g.splitAfter = parseInt(s)
  for i in low(g.meta)..high(g.meta): g.meta[i] = ""

proc writeIndexFile*(g: var RstGenerator, outfile: string) =
  ## Writes the current index buffer to the specified output file.
  ##
  ## You previously need to add entries to the index with the `setIndexTerm()
  ## <#setIndexTerm,RstGenerator,string,string,string,string,string>`_ proc.
  ## If the index is empty the file won't be created.
  if g.theIndex.len > 0: writeFile(outfile, g.theIndex)

proc addHtmlChar(dest: var string, c: char) =
  # Escapes HTML characters. Note that single quote ' is not escaped as
  # &apos; -- unlike XML (for standards pre HTML5 it was even forbidden).
  case c
  of '&': add(dest, "&amp;")
  of '<': add(dest, "&lt;")
  of '>': add(dest, "&gt;")
  of '\"': add(dest, "&quot;")
  else: add(dest, c)

proc addTexChar(dest: var string, c: char, escMode: EscapeMode) =
  ## Escapes 10 special Latex characters and sometimes ` and [, ].
  ## TODO: @ is always a normal symbol (besides the header), am I wrong?
  ## All escapes that need to work in text and code blocks (`emText` mode)
  ## should start from \ (to be compatible with fancyvrb/fvextra).
  case c
  of '_', '&', '#', '%': add(dest, "\\" & c)
  # commands \label and \pageref don't accept \$ by some reason but OK with $:
  of '$': (if escMode == emUrl: add(dest, c) else: add(dest, "\\" & c))
  # \~ and \^ have a special meaning unless they are followed by {}
  of '~', '^': add(dest, "\\" & c & "{}")
  # Latex loves to substitute ` to opening quote, even in texttt mode!
  of '`': add(dest, "\\textasciigrave{}")
  # add {} to avoid gobbling up space by \textbackslash
  of '\\': add(dest, "\\textbackslash{}")
  # Using { and } in URL in Latex: https://tex.stackexchange.com/a/469175
  of '{':
    add(dest, if escMode == emUrl: "\\%7B" else: "\\{")
  of '}':
    add(dest, if escMode == emUrl: "\\%7D" else: "\\}")
  of ']':
    # escape ] inside an optional argument in e.g. \section[static[T]]{..
    add(dest, if escMode == emOption: "\\text{]}" else: "]")
  else: add(dest, c)

proc escChar*(target: OutputTarget, dest: var string,
              c: char, escMode: EscapeMode) {.inline.} =
  case target
  of outHtml:  addHtmlChar(dest, c)
  of outLatex: addTexChar(dest, c, escMode)

proc addSplitter(target: OutputTarget; dest: var string) {.inline.} =
  case target
  of outHtml: add(dest, "<wbr />")
  of outLatex: add(dest, "\\-")

proc nextSplitPoint*(s: string, start: int): int =
  result = start
  while result < len(s) + 0:
    case s[result]
    of '_': return
    of 'a'..'z':
      if result + 1 < len(s) + 0:
        if s[result + 1] in {'A'..'Z'}: return
    else: discard
    inc(result)
  dec(result)                 # last valid index

proc esc*(target: OutputTarget, s: string, splitAfter = -1, escMode = emText): string =
  ## Escapes the HTML.
  result = ""
  if splitAfter >= 0:
    var partLen = 0
    var j = 0
    while j < len(s):
      var k = nextSplitPoint(s, j)
      #if (splitter != " ") or (partLen + k - j + 1 > splitAfter):
      partLen = 0
      addSplitter(target, result)
      for i in countup(j, k): escChar(target, result, s[i], escMode)
      inc(partLen, k - j + 1)
      j = k + 1
  else:
    for i in countup(0, len(s) - 1): escChar(target, result, s[i], escMode)


proc disp(target: OutputTarget, xml, tex: string): string =
  if target != outLatex: result = xml
  else: result = tex

proc dispF(target: OutputTarget, xml, tex: string,
           args: varargs[string]): string =
  if target != outLatex: result = xml % args
  else: result = tex % args

proc dispA(target: OutputTarget, dest: var string,
           xml, tex: string, args: varargs[string]) =
  if target != outLatex: addf(dest, xml, args)
  else: addf(dest, tex, args)

proc `or`(x, y: string): string {.inline.} =
  result = if x.len == 0: y else: x

proc renderRstToOut*(d: var RstGenerator, n: PRstNode, result: var string) {.gcsafe.}
  ## Writes into ``result`` the rst ast ``n`` using the ``d`` configuration.
  ##
  ## Before using this proc you need to initialise a ``RstGenerator`` with
  ## ``initRstGenerator`` and parse a rst file with ``rstParse`` from the
  ## `packages/docutils/rst module <rst.html>`_. Example:
  ##   ```nim
  ##   # ...configure gen and rst vars...
  ##   var generatedHtml = ""
  ##   renderRstToOut(gen, rst, generatedHtml)
  ##   echo generatedHtml
  ##   ```

proc renderAux(d: PDoc, n: PRstNode, result: var string) =
  for i in countup(0, len(n)-1): renderRstToOut(d, n.sons[i], result)

template idS(txt: string): string =
  if txt == "": ""
  else:
    case d.target
    of outHtml:
      " id=\"" & txt & "\""
    of outLatex:
      "\\label{" & txt & "}\\hypertarget{" & txt & "}{}"
        # we add \label for page number references via \pageref, while
        # \hypertarget is for clickable links via \hyperlink.

proc renderAux(d: PDoc, n: PRstNode, html, tex: string, result: var string) =
  # formats sons of `n` as substitution variable $1 inside strings `html` and
  # `tex`, internal target (anchor) is provided as substitute $2.
  var tmp = ""
  for i in countup(0, len(n)-1): renderRstToOut(d, n.sons[i], tmp)
  case d.target
  of outHtml:  result.addf(html, [tmp, n.anchor.idS])
  of outLatex: result.addf(tex,  [tmp, n.anchor.idS])

# ---------------- index handling --------------------------------------------

proc setIndexTerm*(d: var RstGenerator; k: IndexEntryKind, htmlFile, id, term: string,
                   linkTitle, linkDesc = "", line = 0) =
  ## Adds a `term` to the index using the specified hyperlink identifier.
  ##
  ## A new entry will be added to the index using the format
  ## ``term<tab>file#id``. The file part will come from the `htmlFile`
  ## parameter.
  ##
  ## The `id` will be appended with a hash character only if its length is not
  ## zero, otherwise no specific anchor will be generated. In general you
  ## should only pass an empty `id` value for the title of standalone rst
  ## documents (they are special for the `mergeIndexes() <#mergeIndexes,string>`_
  ## proc, see `Index (idx) file format <docgen.html#index-idx-file-format>`_
  ## for more information). Unlike other index terms, title entries are
  ## inserted at the beginning of the accumulated buffer to maintain a logical
  ## order of entries.
  ##
  ## If `linkTitle` or `linkDesc` are not the empty string, two additional
  ## columns with their contents will be added.
  ##
  ## The index won't be written to disk unless you call `writeIndexFile()
  ## <#writeIndexFile,RstGenerator,string>`_. The purpose of the index is
  ## documented in the `docgen tools guide
  ## <docgen.html#related-options-index-switch>`_.
  let (entry, isTitle) = formatIndexEntry(k, htmlFile, id, term,
                                          linkTitle, linkDesc, line)
  if isTitle: d.theIndex.insert(entry)
  else: d.theIndex.add(entry)

proc hash(n: PRstNode): int =
  if n.kind == rnLeaf:
    result = hash(n.text)
  elif n.len > 0:
    result = hash(n.sons[0])
    for i in 1 ..< len(n):
      result = result !& hash(n.sons[i])
    result = !$result

proc htmlFileRelPath(d: PDoc): string =
  if d.outDir.len == 0:
    # /foo/bar/zoo.nim -> zoo.html
    changeFileExt(extractFilename(d.filename), HtmlExt)
  else: # d is initialized in docgen.nim
    # outDir   = /foo              -\
    # destFile = /foo/bar/zoo.html -|-> bar/zoo.html
    d.destFile.relativePath(d.outDir, '/')

proc renderIndexTerm*(d: PDoc, n: PRstNode, result: var string) =
  ## Renders the string decorated within \`foobar\`\:idx\: markers.
  ##
  ## Additionally adds the enclosed text to the index as a term. Since we are
  ## interested in different instances of the same term to have different
  ## entries, a table is used to keep track of the amount of times a term has
  ## previously appeared to give a different identifier value for each.
  let refname = n.rstnodeToRefname
  if d.seenIndexTerms.hasKey(refname):
    d.seenIndexTerms[refname] = d.seenIndexTerms.getOrDefault(refname) + 1
  else:
    d.seenIndexTerms[refname] = 1
  let id = refname & '_' & $d.seenIndexTerms.getOrDefault(refname)

  var term = ""
  renderAux(d, n, term)
  setIndexTerm(d, ieIdxRole,
  htmlFileRelPath(d), id, term, d.currentSection)
  dispA(d.target, result, "<span id=\"$1\">$2</span>", "\\nimindexterm{$1}{$2}",
        [id, term])

type
  IndexedDocs* = Table[IndexEntry, seq[IndexEntry]] ## \
    ## Contains the index sequences for doc types.
    ##
    ## The key is a *fake* IndexEntry which will contain the title of the
    ## document in the `keyword` field and `link` will contain the html
    ## filename for the document. `linkTitle` and `linkDesc` will be empty.
    ##
    ## The value indexed by this IndexEntry is a sequence with the real index
    ## entries found in the ``.idx`` file.

when defined(gcDestructors):
  template `<-`(a, b: var IndexEntry) = a = move(b)
else:
  proc `<-`(a: var IndexEntry, b: IndexEntry) =
    shallowCopy a.keyword, b.keyword
    shallowCopy a.link, b.link
    shallowCopy a.linkTitle, b.linkTitle
    shallowCopy a.linkDesc, b.linkDesc
    shallowCopy a.module, b.module

proc sortIndex(a: var openArray[IndexEntry]) =
  # we use shellsort here; fast and simple
  let n = len(a)
  var h = 1
  while true:
    h = 3 * h + 1
    if h > n: break
  while true:
    h = h div 3
    for i in countup(h, n - 1):
      var v: IndexEntry
      v <- a[i]
      var j = i
      while cmp(a[j-h], v) >= 0:
        a[j] <- a[j-h]
        j = j-h
        if j < h: break
      a[j] <- v
    if h == 1: break

proc escapeLink(s: string): string =
  ## This proc is mostly copied from uri/encodeUrl except that
  ## these chars are also left unencoded: '#', '/'.
  result = newStringOfCap(s.len + s.len shr 2)
  for c in items(s):
    case c
    of 'a'..'z', 'A'..'Z', '0'..'9', '-', '.', '_', '~': # same as that in uri/encodeUrl
      add(result, c)
    of '#', '/': # example.com/foo/#bar (don't escape the '/' and '#' in such links)
      add(result, c)
    else:
      add(result, "%")
      add(result, toHex(ord(c), 2))

proc generateSymbolIndex(symbols: seq[IndexEntry]): string =
  result = "<dl>"
  var i = 0
  while i < symbols.len:
    let keyword = esc(outHtml, symbols[i].keyword)
    let cleanedKeyword = keyword.escapeLink
    result.addf("<dt><a name=\"$2\" href=\"#$2\"><span>$1:</span></a></dt><dd><ul class=\"simple\">\n",
                [keyword, cleanedKeyword])
    var j = i
    while j < symbols.len and symbols[i].keyword == symbols[j].keyword:
      let
        url = symbols[j].link.escapeLink
        module = symbols[j].module
        text =
          if symbols[j].linkTitle.len > 0:
            esc(outHtml, module & ": " & symbols[j].linkTitle)
          else: url
        desc = symbols[j].linkDesc
      if desc.len > 0:
        result.addf("""<li><a class="reference external"
          title="$3" data-doc-search-tag="$2" href="$1">$2</a></li>
          """, [url, text, desc])
      else:
        result.addf("""<li><a class="reference external"
          data-doc-search-tag="$2" href="$1">$2</a></li>
          """, [url, text])
      inc j
    result.add("</ul></dd>\n")
    i = j
  result.add("</dl>")

proc stripTocLevel(s: string): tuple[level: int, text: string] =
  ## Returns the *level* of the toc along with the text without it.
  for c in 0 ..< s.len:
    result.level = c
    if s[c] != ' ': break
  result.text = s[result.level ..< s.len]

proc indentToLevel(level: var int, newLevel: int): string =
  ## Returns the sequence of <ul>|</ul> characters to switch to `newLevel`.
  ##
  ## The amount of lists added/removed will be based on the `level` variable,
  ## which will be reset to `newLevel` at the end of the proc.
  result = ""
  if level == newLevel:
    return
  if newLevel > level:
    result = repeat("<li><ul>", newLevel - level)
  else:
    result = repeat("</ul></li>", level - newLevel)
  level = newLevel

proc generateDocumentationToc(entries: seq[IndexEntry]): string =
  ## Returns the sequence of index entries in an HTML hierarchical list.
  result = ""
  # Build a list of levels and extracted titles to make processing easier.
  var
    titleRef: string
    titleTag: string
    levels: seq[tuple[level: int, text: string]]
    L = 0
    level = 1
  levels.newSeq(entries.len)
  for entry in entries:
    let (rawLevel, rawText) = stripTocLevel(entry.linkTitle)
    if rawLevel < 1:
      # This is a normal symbol, push it *inside* one level from the last one.
      levels[L].level = level + 1
    else:
      # The level did change, update the level indicator.
      level = rawLevel
      levels[L].level = rawLevel
    levels[L].text = rawText
    inc L

  # Now generate hierarchical lists based on the precalculated levels.
  result = "<ul>\n"
  level = 1
  L = 0
  while L < entries.len:
    let link = entries[L].link
    if link.isDocumentationTitle:
      titleRef = link
      titleTag = levels[L].text
    else:
      result.add(level.indentToLevel(levels[L].level))
      result.addf("""<li><a class="reference" data-doc-search-tag="$1: $2" href="$3">
        $3</a></li>
        """, [titleTag, levels[L].text, link, levels[L].text])
    inc L
  result.add(level.indentToLevel(1) & "</ul>\n")

proc generateDocumentationIndex(docs: IndexedDocs): string =
  ## Returns all the documentation TOCs in an HTML hierarchical list.
  result = ""

  # Sort the titles to generate their toc in alphabetical order.
  var titles = toSeq(keys[IndexEntry, seq[IndexEntry]](docs))
  sort(titles, cmp)

  for title in titles:
    let tocList = generateDocumentationToc(docs.getOrDefault(title))
    result.add("<ul><li><a href=\"" &
      title.link & "\">" & title.linkTitle & "</a>\n" & tocList & "</li></ul>\n")

proc generateDocumentationJumps(docs: IndexedDocs): string =
  ## Returns a plain list of hyperlinks to documentation TOCs in HTML.
  result = "Documents: "

  # Sort the titles to generate their toc in alphabetical order.
  var titles = toSeq(keys[IndexEntry, seq[IndexEntry]](docs))
  sort(titles, cmp)

  var chunks: seq[string] = @[]
  for title in titles:
    chunks.add("<a href=\"" & title.link & "\">" & title.linkTitle & "</a>")

  result.add(chunks.join(", ") & ".<br/>")

proc generateModuleJumps(modules: seq[string]): string =
  ## Returns a plain list of hyperlinks to the list of modules.
  result = "Modules: "

  var chunks: seq[string] = @[]
  for name in modules:
    chunks.add("<a href=\"$1.html\">$2</a>" % [name, name.prettyLink])

  result.add(chunks.join(", ") & ".<br/>")

proc readIndexDir*(dir: string):
    tuple[modules: seq[string], symbols: seq[IndexEntry], docs: IndexedDocs] =
  ## Walks `dir` reading ``.idx`` files converting them in IndexEntry items.
  ##
  ## Returns the list of found module names, the list of free symbol entries
  ## and the different documentation indexes. The list of modules is sorted.
  ## See the documentation of ``mergeIndexes`` for details.
  result.modules = @[]
  result.docs = initTable[IndexEntry, seq[IndexEntry]](32)
  newSeq(result.symbols, 15_000)
  setLen(result.symbols, 0)
  var L = 0
  # Scan index files and build the list of symbols.
  for path in walkDirRec(dir):
    if path.endsWith(IndexExt):
      var (fileEntries, title) = parseIdxFile(path)
      # Depending on type add this to the list of symbols or table of APIs.

      if title.kind == ieNimTitle:
        for i in 0 ..< fileEntries.len:
          if fileEntries[i].kind != ieNim:
            continue
          # Ok, non TOC entry, add it.
          setLen(result.symbols, L + 1)
          result.symbols[L] = fileEntries[i]
          inc L
        if fileEntries.len > 0:
          var x = fileEntries[0].link
          let i = find(x, '#')
          if i > 0:
            x.setLen(i)
          if i != 0:
            # don't add entries starting with '#'
            result.modules.add(x.changeFileExt(""))
      else:
        # Generate the symbolic anchor for index quickjumps.
        title.aux = "doc_toc_" & $result.docs.len
        result.docs[title] = fileEntries

      for i in 0 ..< fileEntries.len:
        if fileEntries[i].kind != ieIdxRole:
          continue

        setLen(result.symbols, L + 1)
        result.symbols[L] = fileEntries[i]
        inc L

proc mergeIndexes*(dir: string): string =
  ## Merges all index files in `dir` and returns the generated index as HTML.
  ##
  ## This proc will first scan `dir` for index files with the ``.idx``
  ## extension previously created by commands like ``nim doc|rst2html``
  ## which use the ``--index:on`` switch. These index files are the result of
  ## calls to `setIndexTerm()
  ## <#setIndexTerm,RstGenerator,string,string,string,string,string>`_
  ## and `writeIndexFile() <#writeIndexFile,RstGenerator,string>`_, so they are
  ## simple tab separated files.
  ##
  ## As convention this proc will split index files into two categories:
  ## documentation and API. API indices will be all joined together into a
  ## single big sorted index, making the bulk of the final index. This is good
  ## for API documentation because many symbols are repeated in different
  ## modules. On the other hand, documentation indices are essentially table of
  ## contents plus a few special markers. These documents will be rendered in a
  ## separate section which tries to maintain the order and hierarchy of the
  ## symbols in the index file.
  ##
  ## To differentiate between a documentation and API file a convention is
  ## used: indices which contain one entry without the HTML hash character (#)
  ## will be considered `documentation`, since this hash-less entry is the
  ## explicit title of the document.  Indices without this explicit entry will
  ## be considered `generated API` extracted out of a source ``.nim`` file.
  ##
  ## Returns the merged and sorted indices into a single HTML block which can
  ## be further embedded into nimdoc templates.
  var (modules, symbols, docs) = readIndexDir(dir)
  sort(modules, system.cmp)

  result = ""
  # Generate a quick jump list of documents.
  if docs.len > 0:
    result.add(generateDocumentationJumps(docs))
    result.add("<p />")

  # Generate hyperlinks to all the linked modules.
  if modules.len > 0:
    result.add(generateModuleJumps(modules))
    result.add("<p />")

  when false:
    # Generate the HTML block with API documents.
    if docs.len > 0:
      result.add("<h2>Documentation files</h2>\n")
      result.add(generateDocumentationIndex(docs))

  # Generate the HTML block with symbols.
  if symbols.len > 0:
    sortIndex(symbols)
    result.add("<h2>API symbols</h2>\n")
    result.add(generateSymbolIndex(symbols))


# ----------------------------------------------------------------------------

proc renderHeadline(d: PDoc, n: PRstNode, result: var string) =
  var tmp = ""
  for i in countup(0, len(n) - 1): renderRstToOut(d, n.sons[i], tmp)
  d.currentSection = tmp
  var tocName = esc(d.target, renderRstToText(n), escMode = emOption)
    # for Latex: simple text without commands that may break TOC/hyperref
  if d.hasToc:
    d.tocPart.add n
    dispA(d.target, result, "\n<h$1><a class=\"toc-backref\"" &
      "$2 href=\"#$5\">$3</a></h$1>", "\\rsth$4[$6]{$3}$2\n",
      [$n.level, n.anchor.idS, tmp,
       $chr(n.level - 1 + ord('A')), n.anchor, tocName])
  else:
    dispA(d.target, result, "\n<h$1$2>$3</h$1>",
                            "\\rsth$4[$5]{$3}$2\n", [
        $n.level, n.anchor.idS, tmp,
        $chr(n.level - 1 + ord('A')), tocName])

  # Generate index entry using spaces to indicate TOC level for the output HTML.
  assert n.level >= 0
  setIndexTerm(d, ieHeading, htmlFile = d.htmlFileRelPath, id = n.anchor,
               term = n.addNodes, linkTitle = spaces(max(0, n.level)) & tmp)

proc renderOverline(d: PDoc, n: PRstNode, result: var string) =
  if n.level == 0 and d.meta[metaTitle].len == 0:
    d.meta[metaTitleRaw] = n.addNodes
    for i in countup(0, len(n)-1):
      renderRstToOut(d, n.sons[i], d.meta[metaTitle])
    d.currentSection = d.meta[metaTitle]
  elif n.level == 0 and d.meta[metaSubtitle].len == 0:
    for i in countup(0, len(n)-1):
      renderRstToOut(d, n.sons[i], d.meta[metaSubtitle])
    d.currentSection = d.meta[metaSubtitle]
  else:
    var tmp = ""
    for i in countup(0, len(n) - 1): renderRstToOut(d, n.sons[i], tmp)
    d.currentSection = tmp
    var tocName = esc(d.target, renderRstToText(n), escMode=emOption)
    dispA(d.target, result, "<h$1$2><center>$3</center></h$1>",
                   "\\rstov$4[$5]{$3}$2\n", [$n.level,
                   n.anchor.idS, tmp, $chr(n.level - 1 + ord('A')), tocName])
    setIndexTerm(d, ieHeading, htmlFile = d.htmlFileRelPath, id = n.anchor,
                 term = n.addNodes, linkTitle = spaces(max(0, n.level)) & tmp)

proc renderTocEntry(d: PDoc, n: PRstNode, result: var string) =
  var header = ""
  for i in countup(0, len(n) - 1): renderRstToOut(d, n.sons[i], header)
  dispA(d.target, result,
    "<li><a class=\"reference\" id=\"$1_toc\" href=\"#$1\">$2</a></li>\n",
    "\\item\\label{$1_toc} $2\\ref{$1}\n", [n.anchor, header])

proc renderTocEntries*(d: var RstGenerator, j: var int, lvl: int,
                       result: var string) =
  var tmp = ""
  while j <= high(d.tocPart):
    var a = abs(d.tocPart[j].level)
    if a == lvl:
      renderTocEntry(d, d.tocPart[j], tmp)
      inc(j)
    elif a > lvl:
      renderTocEntries(d, j, a, tmp)
    else:
      break
  if lvl > 1:
    dispA(d.target, result, "<ul class=\"simple\">$1</ul>",
                            "\\begin{enumerate}$1\\end{enumerate}", [tmp])
  else:
    result.add(tmp)

proc renderImage(d: PDoc, n: PRstNode, result: var string) =
  let
    arg = getArgument(n)
  var
    options = ""

  var s = esc(d.target, getFieldValue(n, "scale").strip())
  if s.len > 0:
    dispA(d.target, options, " scale=\"$1\"", " scale=$1", [s])

  s = esc(d.target, getFieldValue(n, "height").strip())
  if s.len > 0:
    dispA(d.target, options, " height=\"$1\"", " height=$1", [s])

  s = esc(d.target, getFieldValue(n, "width").strip())
  if s.len > 0:
    dispA(d.target, options, " width=\"$1\"", " width=$1", [s])

  s = esc(d.target, getFieldValue(n, "alt").strip())
  if s.len > 0:
    dispA(d.target, options, " alt=\"$1\"", "", [s])

  s = esc(d.target, getFieldValue(n, "align").strip())
  if s.len > 0:
    dispA(d.target, options, " align=\"$1\"", "", [s])

  if options.len > 0: options = dispF(d.target, "$1", "[$1]", [options])

  var htmlOut = ""
  if arg.endsWith(".mp4") or arg.endsWith(".ogg") or
     arg.endsWith(".webm"):
    htmlOut = """
      <video$3 src="$1"$2 autoPlay='true' loop='true' muted='true'>
      Sorry, your browser doesn't support embedded videos
      </video>
    """
  else:
    htmlOut = "<img$3 src=\"$1\"$2/>"

  # support for `:target:` links for images:
  var target = esc(d.target, getFieldValue(n, "target").strip(), escMode=emUrl)
  discard safeProtocol(target)

  if target.len > 0:
    # `htmlOut` needs to be of the following format for link to work for images:
    # <a class="reference external" href="target"><img src=\"$1\"$2/></a>
    var htmlOutWithLink = ""
    dispA(d.target, htmlOutWithLink,
      "<a class=\"reference external\" href=\"$2\">$1</a>",
      "\\href{$2}{$1}", [htmlOut, target])
    htmlOut = htmlOutWithLink

  dispA(d.target, result, htmlOut, "$3\\includegraphics$2{$1}",
        [esc(d.target, arg), options, n.anchor.idS])
  if len(n) >= 3: renderRstToOut(d, n.sons[2], result)

proc renderSmiley(d: PDoc, n: PRstNode, result: var string) =
  dispA(d.target, result,
    """<img src="$1" width="15"
        height="17" hspace="2" vspace="2" class="smiley" />""",
    "\\includegraphics{$1}",
    [d.config.getOrDefault"doc.smiley_format" % n.text])

proc getField1Int(d: PDoc, n: PRstNode, fieldName: string): int =
  template err(msg: string) =
    rstMessage(d.filenames, d.msgHandler, n.info, meInvalidField, msg)
  let value = n.getFieldValue
  var number: int
  let nChars = parseInt(value, number)
  if nChars == 0:
    if value.len == 0:
      # use a good default value:
      result = 1
    else:
      err("field $1 requires an integer, but '$2' was given" %
          [fieldName, value])
  elif nChars < value.len:
    err("extra arguments were given to $1: '$2'" %
        [fieldName, value[nChars..^1]])
  else:
    result = number

proc parseCodeBlockField(d: PDoc, n: PRstNode, params: var CodeBlockParams) =
  ## Parses useful fields which can appear before a code block.
  ##
  ## This supports the special ``default-language`` internal string generated
  ## by the ``rst`` module to communicate a specific default language.
  case n.getArgument.toLowerAscii
  of "number-lines":
    params.numberLines = true
    # See if the field has a parameter specifying a different line than 1.
    params.startLine = getField1Int(d, n, "number-lines")
  of "file", "filename":
    # The ``file`` option is a Nim extension to the official spec, it acts
    # like it would for other directives like ``raw`` or ``cvs-table``. This
    # field is dealt with in ``rst.nim`` which replaces the existing block with
    # the referenced file, so we only need to ignore it here to avoid incorrect
    # warning messages.
    params.filename = n.getFieldValue.strip
  of "test":
    params.testCmd = n.getFieldValue.strip
    if params.testCmd.len == 0:
      # factor with D20210224T221756. Note that `$docCmd` should appear before `$file`
      # but after all other options, but currently `$options` merges both options and `$file` so it's tricky.
      params.testCmd = "$nim r --backend:$backend --lib:$libpath $docCmd $options"
    else:
      # consider whether `$docCmd` should be appended here too
      params.testCmd = unescape(params.testCmd)
  of "status", "exitcode":
    params.status = getField1Int(d, n, n.getArgument)
  of "default-language":
    params.langStr = n.getFieldValue.strip
    params.lang = params.langStr.getSourceLanguage
  else:
    rstMessage(d.filenames, d.msgHandler, n.info, mwUnsupportedField,
               n.getArgument)

proc parseCodeBlockParams(d: PDoc, n: PRstNode): CodeBlockParams =
  ## Iterates over all code block fields and returns processed params.
  ##
  ## Also processes the argument of the directive as the default language. This
  ## is done last so as to override any internal communication field variables.
  result.init
  if n.isNil:
    return
  assert n.kind in {rnCodeBlock, rnInlineCode}

  # Parse the field list for rendering parameters if there are any.
  if not n.sons[1].isNil:
    for son in n.sons[1].sons: d.parseCodeBlockField(son, result)

  # Parse the argument and override the language.
  result.langStr = strip(getArgument(n))
  if result.langStr != "":
    result.lang = getSourceLanguage(result.langStr)

proc buildLinesHtmlTable(d: PDoc; params: CodeBlockParams, code: string,
                         idStr: string):
    tuple[beginTable, endTable: string] =
  ## Returns the necessary tags to start/end a code block in HTML.
  ##
  ## If the numberLines has not been used, the tags will default to a simple
  ## <pre> pair. Otherwise it will build a table and insert an initial column
  ## with all the line numbers, which requires you to pass the `code` to detect
  ## how many lines have to be generated (and starting at which point!).
  inc d.listingCounter
  let id = $d.listingCounter
  if not params.numberLines:
    result = (d.config.getOrDefault"doc.listing_start" %
                [id, sourceLanguageToStr[params.lang], idStr],
              d.config.getOrDefault"doc.listing_end" % id)
    return

  var codeLines = code.strip.countLines
  assert codeLines > 0
  result.beginTable = """<table$1 class="line-nums-table">""" % [idStr] &
      """<tbody><tr><td class="blob-line-nums"><pre class="line-nums">"""
  var line = params.startLine
  while codeLines > 0:
    result.beginTable.add($line & "\n")
    line.inc
    codeLines.dec
  result.beginTable.add("</pre></td><td>" & (
      d.config.getOrDefault"doc.listing_start" %
        [id, sourceLanguageToStr[params.lang], idStr]))
  result.endTable = (d.config.getOrDefault"doc.listing_end" % id) &
      "</td></tr></tbody></table>" & (
      d.config.getOrDefault"doc.listing_button" % id)

proc renderCodeLang*(result: var string, lang: SourceLanguage, code: string,
                     target: OutputTarget) =
  var g: GeneralTokenizer
  initGeneralTokenizer(g, code)
  while true:
    getNextToken(g, lang)
    case g.kind
    of gtEof: break
    of gtNone, gtWhitespace:
      add(result, substr(code, g.start, g.length + g.start - 1))
    else:
      dispA(target, result, "<span class=\"$2\">$1</span>", "\\span$2{$1}", [
        esc(target, substr(code, g.start, g.length+g.start-1)),
        tokenClassToStr[g.kind]])
  deinitGeneralTokenizer(g)

proc renderNimCode*(result: var string, code: string, target: OutputTarget) =
  renderCodeLang(result, langNim, code, target)

proc renderCode(d: PDoc, n: PRstNode, result: var string) {.gcsafe.} =
  ## Renders a code (code block or inline code), appending it to `result`.
  ##
  ## If the code block uses the ``number-lines`` option, a table will be
  ## generated with two columns, the first being a list of numbers and the
  ## second the code block itself. The code block can use syntax highlighting,
  ## which depends on the directive argument specified by the rst input, and
  ## may also come from the parser through the internal ``default-language``
  ## option to differentiate between a plain code block and Nim's code block
  ## extension.
  assert n.kind in {rnCodeBlock, rnInlineCode}
  var params = d.parseCodeBlockParams(n)
  if n.sons[2] == nil: return
  var m = n.sons[2].sons[0]
  assert m.kind == rnLeaf

  if params.testCmd.len > 0 and d.onTestSnippet != nil:
    d.onTestSnippet(d, params.filename, params.testCmd, params.status, m.text)

  var blockStart, blockEnd: string
  case d.target
  of outHtml:
    if n.kind == rnCodeBlock:
      (blockStart, blockEnd) = buildLinesHtmlTable(d, params, m.text,
                                                   n.anchor.idS)
    else:  # rnInlineCode
      blockStart = "<tt class=\"docutils literal\"><span class=\"pre\">"
      blockEnd = "</span></tt>"
  of outLatex:
    if n.kind == rnCodeBlock:
      blockStart = "\n\n" & n.anchor.idS & "\\begin{rstpre}\n"
      blockEnd = "\n\\end{rstpre}\n\n"
    else:  # rnInlineCode
      blockStart = "\\rstcode{"
      blockEnd = "}"
  dispA(d.target, result, blockStart, blockStart, [])
  if params.lang == langNone:
    if len(params.langStr) > 0 and params.langStr.toLowerAscii != "none":
      rstMessage(d.filenames, d.msgHandler, n.info, mwUnsupportedLanguage,
                 params.langStr)
    for letter in m.text: escChar(d.target, result, letter, emText)
  else:
    renderCodeLang(result, params.lang, m.text, d.target)
  dispA(d.target, result, blockEnd, blockEnd)

proc renderContainer(d: PDoc, n: PRstNode, result: var string) =
  var tmp = ""
  renderRstToOut(d, n.sons[2], tmp)
  var arg = esc(d.target, strip(getArgument(n)))
  if arg == "":
    dispA(d.target, result, "<div>$1</div>", "$1", [tmp])
  else:
    dispA(d.target, result, "<div class=\"$1\">$2</div>", "$2", [arg, tmp])

proc renderField(d: PDoc, n: PRstNode, result: var string) =
  var b = false
  if d.target == outLatex:
    var fieldname = addNodes(n.sons[0])
    var fieldval = esc(d.target, strip(addNodes(n.sons[1])))
    if cmpIgnoreStyle(fieldname, "author") == 0 or
       cmpIgnoreStyle(fieldname, "authors") == 0:
      if d.meta[metaAuthor].len == 0:
        d.meta[metaAuthor] = fieldval
        b = true
    elif cmpIgnoreStyle(fieldname, "version") == 0:
      if d.meta[metaVersion].len == 0:
        d.meta[metaVersion] = fieldval
        b = true
  if not b:
    renderAux(d, n, "<tr>$1</tr>\n", "$1", result)

proc renderEnumList(d: PDoc, n: PRstNode, result: var string) =
  var
    specifier = ""
    specStart = ""
    i1 = 0
    pre = ""
    i2 = n.labelFmt.len - 1
    post = ""
  if n.labelFmt[0] == '(':
    i1 = 1
    pre = "("
  if n.labelFmt[^1] == ')' or n.labelFmt[^1] == '.':
    i2 = n.labelFmt.len - 2
    post = $n.labelFmt[^1]
  let enumR = i1 .. i2  # enumerator range without surrounding (, ), .
  if d.target == outLatex:
    result.add ("\n%" & n.labelFmt & "\n")
    # use enumerate parameters from package enumitem
    if n.labelFmt[i1].isDigit:
      var labelDef = ""
      if pre != "" or post != "":
        labelDef = "label=" & pre & "\\arabic*" & post & ","
      if n.labelFmt[enumR] != "1":
        specStart = "start=$1" % [n.labelFmt[enumR]]
      if labelDef != "" or specStart != "":
        specifier = "[$1$2]" % [labelDef, specStart]
    else:
      let (first, labelDef) =
        if n.labelFmt[i1].isUpperAscii: ('A', "label=" & pre & "\\Alph*" & post)
        else: ('a', "label=" & pre & "\\alph*" & post)
      if n.labelFmt[i1] != first:
        specStart = ",start=" & $(ord(n.labelFmt[i1]) - ord(first) + 1)
      specifier = "[$1$2]" % [labelDef, specStart]
  else:  # HTML
    # TODO: implement enumerator formatting using pre and post ( and ) for HTML
    if n.labelFmt[i1].isDigit:
      if n.labelFmt[enumR] != "1":
        specStart = " start=\"$1\"" % [n.labelFmt[enumR]]
      specifier = "class=\"simple\"" & specStart
    else:
      let (first, labelDef) =
        if n.labelFmt[i1].isUpperAscii: ('A', "class=\"upperalpha simple\"")
        else: ('a', "class=\"loweralpha simple\"")
      if n.labelFmt[i1] != first:
        specStart = " start=\"$1\"" % [ $(ord(n.labelFmt[i1]) - ord(first) + 1) ]
      specifier = labelDef & specStart
  renderAux(d, n, "<ol$2 " & specifier & ">$1</ol>\n",
            "\\begin{enumerate}" & specifier & "$2$1\\end{enumerate}\n",
            result)

proc renderAdmonition(d: PDoc, n: PRstNode, result: var string) =
  var
    htmlCls = "admonition_warning"
    texSz = "\\large"
    texColor = "orange"
  case n.adType
  of "hint", "note", "tip":
    htmlCls = "admonition-info"; texSz = "\\normalsize"; texColor = "green"
  of "attention", "admonition", "important", "warning", "caution":
    htmlCls = "admonition-warning"; texSz = "\\large"; texColor = "orange"
  of "danger", "error":
    htmlCls = "admonition-error"; texSz = "\\Large"; texColor = "red"
  else: discard
  let txt = n.adType.capitalizeAscii()
  let htmlHead = "<div class=\"admonition " & htmlCls & "\">"
  renderAux(d, n,
      htmlHead & "<span$2 class=\"" & htmlCls & "-text\"><b>" & txt &
        ":</b></span>\n" & "$1</div>\n",
      "\n\n\\begin{rstadmonition}[borderline west={0.2em}{0pt}{" &
        texColor & "}]$2\n" &
        "{" & texSz & "\\color{" & texColor & "}{\\textbf{" & txt & ":}}} " &
        "$1\n\\end{rstadmonition}\n",
      result)

proc renderHyperlink(d: PDoc, text, link: PRstNode, result: var string,
                     external: bool, nimdoc = false, tooltip="") =
  var linkStr = ""
  block:
    let mode = d.escMode
    d.escMode = emUrl
    renderRstToOut(d, link, linkStr)
    d.escMode = mode
  discard safeProtocol(linkStr)
  var textStr = ""
  renderRstToOut(d, text, textStr)
  let nimDocStr = if nimdoc: " nimdoc" else: ""
  var tooltipStr = ""
  if tooltip != "":
    tooltipStr = """ title="$1"""" % [ esc(d.target, tooltip) ]
  if external:
    dispA(d.target, result,
      "<a class=\"reference external$3\"$4 href=\"$2\">$1</a>",
      "\\href{$2}{$1}", [textStr, linkStr, nimDocStr, tooltipStr])
  else:
    dispA(d.target, result,
      "<a class=\"reference internal$3\"$4 href=\"#$2\">$1</a>",
      "\\hyperlink{$2}{$1} (p.~\\pageref{$2})",
      [textStr, linkStr, nimDocStr, tooltipStr])

proc traverseForIndex*(d: PDoc, n: PRstNode) =
  ## A version of [renderRstToOut] that only fills entries for ``.idx`` files.
  var discarded: string
  if n == nil: return
  case n.kind
  of rnIdx: renderIndexTerm(d, n, discarded)
  of rnHeadline, rnMarkdownHeadline: renderHeadline(d, n, discarded)
  of rnOverline: renderOverline(d, n, discarded)
  else:
    for i in 0 ..< len(n):
      traverseForIndex(d, n.sons[i])

proc renderRstToOut(d: PDoc, n: PRstNode, result: var string) =
  if n == nil: return
  case n.kind
  of rnInner: renderAux(d, n, result)
  of rnHeadline, rnMarkdownHeadline: renderHeadline(d, n, result)
  of rnOverline: renderOverline(d, n, result)
  of rnTransition: renderAux(d, n, "<hr$2 />\n", "\n\n\\vspace{0.6em}\\hrule$2\n", result)
  of rnParagraph: renderAux(d, n, "<p$2>$1</p>\n", "\n\n$2\n$1\n\n", result)
  of rnBulletList:
    renderAux(d, n, "<ul$2 class=\"simple\">$1</ul>\n",
                    "\\begin{itemize}\n$2\n$1\\end{itemize}\n", result)
  of rnBulletItem, rnEnumItem:
    renderAux(d, n, "<li$2>$1</li>\n", "\\item $2$1\n", result)
  of rnEnumList: renderEnumList(d, n, result)
  of rnDefList, rnMdDefList:
    renderAux(d, n, "<dl$2 class=\"docutils\">$1</dl>\n",
                    "\\begin{description}\n$2\n$1\\end{description}\n", result)
  of rnDefItem: renderAux(d, n, result)
  of rnDefName: renderAux(d, n, "<dt$2>$1</dt>\n", "$2\\item[$1]\\  ", result)
  of rnDefBody: renderAux(d, n, "<dd$2>$1</dd>\n", "$2\n$1\n", result)
  of rnFieldList:
    var tmp = ""
    for i in countup(0, len(n) - 1):
      renderRstToOut(d, n.sons[i], tmp)
    if tmp.len != 0:
      dispA(d.target, result,
          "<table$2 class=\"docinfo\" frame=\"void\" rules=\"none\">" &
          "<col class=\"docinfo-name\" />" &
          "<col class=\"docinfo-content\" />" &
          "<tbody valign=\"top\">$1" &
          "</tbody></table>",
          "\\begin{description}\n$2\n$1\\end{description}\n",
          [tmp, n.anchor.idS])
  of rnField: renderField(d, n, result)
  of rnFieldName:
    renderAux(d, n, "<th class=\"docinfo-name\">$1:</th>",
                    "\\item[$1:]", result)
  of rnFieldBody:
    renderAux(d, n, "<td>$1</td>", " $1\n", result)
  of rnIndex:
    renderRstToOut(d, n.sons[2], result)
  of rnOptionList:
    renderAux(d, n, "<div$2 class=\"option-list\">$1</div>",
        "\\begin{rstoptlist}$2\n$1\\end{rstoptlist}", result)
  of rnOptionListItem:
    var addclass = if n.order mod 2 == 1: " odd" else: ""
    renderAux(d, n,
        "<div class=\"option-list-item" & addclass & "\">$1</div>\n",
        "$1", result)
  of rnOptionGroup:
    renderAux(d, n,
        "<div class=\"option-list-label\"><tt><span class=\"option\">" &
        "$1</span></tt></div>",
        "\\item[\\rstcodeitem{\\spanoption{$1}}]", result)
  of rnDescription:
    renderAux(d, n, "<div class=\"option-list-description\">$1</div>",
        " $1\n", result)
  of rnOption, rnOptionString, rnOptionArgument:
    raiseAssert "renderRstToOut"
  of rnLiteralBlock:
    renderAux(d, n, "<pre$2>$1</pre>\n",
                    "\n\n$2\\begin{rstpre}\n$1\n\\end{rstpre}\n\n", result)
  of rnMarkdownBlockQuote:
    d.curQuotationDepth = 1
    var tmp = ""
    renderAux(d, n, "$1", "$1", tmp)
    let itemEnding =
      if d.target == outHtml: "</blockquote>" else: "\\end{rstquote}"
    tmp.add itemEnding.repeat(d.curQuotationDepth - 1)
    dispA(d.target, result,
        "<blockquote$2 class=\"markdown-quote\">$1</blockquote>\n",
        "\n\\begin{rstquote}\n$2\n$1\\end{rstquote}\n", [tmp, n.anchor.idS])
  of rnMarkdownBlockQuoteItem:
    let addQuotationDepth = n.quotationDepth - d.curQuotationDepth
    var itemPrefix: string  # start or ending (quotation grey bar on the left)
    if addQuotationDepth >= 0:
      let s =
        if d.target == outHtml: "<blockquote class=\"markdown-quote\">"
        else: "\\begin{rstquote}"
      itemPrefix = s.repeat(addQuotationDepth)
    else:
      let s =
        if d.target == outHtml: "</blockquote>"
        else: "\\end{rstquote}"
      itemPrefix = s.repeat(-addQuotationDepth)
    renderAux(d, n, itemPrefix & "<p>$1</p>", itemPrefix & "\n$1", result)
    d.curQuotationDepth = n.quotationDepth
  of rnLineBlock:
    if n.sons.len == 1 and n.sons[0].lineIndent == "\n":
      # whole line block is one empty line, no need to add extra spacing
      renderAux(d, n, "<p$2>$1</p> ", "\n\n$2\n$1", result)
    else:  # add extra spacing around the line block for Latex
      renderAux(d, n, "<p$2>$1</p>",
        "\n\\vspace{0.5em}$2\n$1\\vspace{0.5em}\n", result)
  of rnLineBlockItem:
    if n.lineIndent.len == 0:  # normal case - no additional indentation
      renderAux(d, n, "$1<br/>", "\\noindent $1\n\n", result)
    elif n.lineIndent == "\n":  # add one empty line
      renderAux(d, n, "<br/>", "\\vspace{1em}\n", result)
    else:  # additional indentation w.r.t. '| '
      let indent = $(0.5 * (n.lineIndent.len - 1).toFloat) & "em"
      renderAux(d, n,
        "<span style=\"margin-left: " & indent & "\">$1</span><br/>",
        "\\noindent\\hspace{" & indent & "}$1\n\n", result)
  of rnBlockQuote:
    renderAux(d, n, "<blockquote$2><p>$1</p></blockquote>\n",
                    "\\begin{quote}\n$2\n$1\\end{quote}\n", result)
  of rnAdmonition: renderAdmonition(d, n, result)
  of rnTable, rnGridTable, rnMarkdownTable:
    renderAux(d, n,
      "<table$2 border=\"1\" class=\"docutils\">$1</table>",
      "\n$2\n\\begin{rsttab}{" &
        "L".repeat(n.colCount) & "}\n\\toprule\n$1" &
        "\\addlinespace[0.1em]\\bottomrule\n\\end{rsttab}", result)
  of rnTableRow:
    if len(n) >= 1:
      case d.target
      of outHtml:
        result.add("<tr>")
        renderAux(d, n, result)
        result.add("</tr>\n")
      of outLatex:
        if n.sons[0].kind == rnTableHeaderCell:
          result.add "\\rowcolor{gray!15} "
        var spanLines: seq[(int, int)]
        var nCell = 0
        for uCell in 0 .. n.len - 1:
          renderRstToOut(d, n.sons[uCell], result)
          if n.sons[uCell].span > 0:
            spanLines.add (nCell + 1, nCell + n.sons[uCell].span)
            nCell += n.sons[uCell].span
          else:
            nCell += 1
          if uCell != n.len - 1:
            result.add(" & ")
        result.add("\\\\")
        if n.endsHeader: result.add("\\midrule\n")
        for (start, stop) in spanLines:
          result.add("\\cmidrule(lr){$1-$2}" % [$start, $stop])
        result.add("\n")
  of rnTableHeaderCell, rnTableDataCell:
    case d.target
    of outHtml:
      let tag = if n.kind == rnTableHeaderCell: "th" else: "td"
      var spanSpec: string
      if n.span <= 1: spanSpec = ""
      else:
        spanSpec = " colspan=\"" & $n.span & "\" style=\"text-align: center\""
      renderAux(d, n, "<$1$2>$$1</$1>" % [tag, spanSpec], "", result)
    of outLatex:
      let text = if n.kind == rnTableHeaderCell: "\\textbf{$1}" else: "$1"
      var latexStr: string
      if n.span <= 1: latexStr = text
      else: latexStr = "\\multicolumn{" & $n.span & "}{c}{" & text & "}"
      renderAux(d, n, "", latexStr, result)
  of rnFootnoteGroup:
    renderAux(d, n,
      "<hr class=\"footnote\">" &
          "<div class=\"footnote-group\">\n$1</div>\n",
      "\n\n\\noindent\\rule{0.25\\linewidth}{.4pt}\n" &
          "\\begin{rstfootnote}\n$1\\end{rstfootnote}\n\n",
      result)
  of rnFootnote, rnCitation:
    var mark = ""
    renderAux(d, n.sons[0], mark)
    var body = ""
    renderRstToOut(d, n.sons[1], body)
    dispA(d.target, result,
      "<div$2><div class=\"footnote-label\">" &
          "<sup><strong><a href=\"#$4\">[$3]</a></strong></sup>" &
          "</div> &ensp; $1\n</div>\n",
      "\\item[\\textsuperscript{[$3]}]$2 $1\n",
      [body, n.anchor.idS, mark, n.anchor])
  of rnPandocRef:
    renderHyperlink(d, text=n.sons[0], link=n.sons[1], result, external=false)
  of rnRstRef:
    renderHyperlink(d, text=n.sons[0], link=n.sons[0], result, external=false)
  of rnStandaloneHyperlink:
    renderHyperlink(d, text=n.sons[0], link=n.sons[0], result, external=true)
  of rnInternalRef:
    renderHyperlink(d, text=n.sons[0], link=n.sons[1], result, external=false)
  of rnNimdocRef:
    renderHyperlink(d, text=n.sons[0], link=n.sons[1], result, external=false,
                    nimdoc=true, tooltip=n.tooltip)
  of rnHyperlink:
    renderHyperlink(d, text=n.sons[0], link=n.sons[1], result, external=true)
  of rnFootnoteRef:
    var tmp = "["
    renderAux(d, n.sons[0], tmp)
    tmp.add "]"
    dispA(d.target, result,
      "<sup><strong><a class=\"reference internal\" href=\"#$2\">" &
          "$1</a></strong></sup>",
      "\\textsuperscript{\\hyperlink{$2}{\\textbf{$1}}}",
      [tmp, n.sons[1].text])
  of rnDirArg, rnRaw: renderAux(d, n, result)
  of rnRawHtml:
    if d.target != outLatex and not lastSon(n).isNil:
      result.add addNodes(lastSon(n))
  of rnRawLatex:
    if d.target == outLatex and not lastSon(n).isNil:
      result.add addNodes(lastSon(n))

  of rnImage, rnFigure: renderImage(d, n, result)
  of rnCodeBlock, rnInlineCode: renderCode(d, n, result)
  of rnContainer: renderContainer(d, n, result)
  of rnSubstitutionReferences, rnSubstitutionDef:
    renderAux(d, n, "|$1|", "|$1|", result)
  of rnDirective:
    renderAux(d, n, "", "", result)
  of rnUnknownRole, rnCodeFragment:
    var tmp0 = ""
    var tmp1 = ""
    renderRstToOut(d, n.sons[0], tmp0)
    renderRstToOut(d, n.sons[1], tmp1)
    var class = tmp1
    # don't allow missing role break latex compilation:
    if d.target == outLatex and n.kind == rnUnknownRole: class = "Other"
    if n.kind == rnCodeFragment:
      dispA(d.target, result,
            "<tt class=\"docutils literal\"><span class=\"pre $2\">" &
              "$1</span></tt>",
            "\\rstcode{\\span$2{$1}}", [tmp0, class])
    else:  # rnUnknownRole, not necessarily code/monospace font
      dispA(d.target, result, "<span class=\"$2\">$1</span>", "\\span$2{$1}",
            [tmp0, class])
  of rnSub: renderAux(d, n, "<sub>$1</sub>", "\\rstsub{$1}", result)
  of rnSup: renderAux(d, n, "<sup>$1</sup>", "\\rstsup{$1}", result)
  of rnEmphasis: renderAux(d, n, "<em>$1</em>", "\\emph{$1}", result)
  of rnStrongEmphasis:
    renderAux(d, n, "<strong>$1</strong>", "\\textbf{$1}", result)
  of rnTripleEmphasis:
    renderAux(d, n, "<strong><em>$1</em></strong>",
                    "\\textbf{emph{$1}}", result)
  of rnIdx:
    renderIndexTerm(d, n, result)
  of rnInlineLiteral, rnInterpretedText:
    renderAux(d, n,
      "<tt class=\"docutils literal\"><span class=\"pre\">$1</span></tt>",
      "\\rstcode{$1}", result)
  of rnInlineTarget:
    var tmp = ""
    renderAux(d, n, tmp)
    dispA(d.target, result,
      "<span class=\"target\" id=\"$2\">$1</span>",
      "\\label{$2}\\hypertarget{$2}{$1}",
      [tmp, rstnodeToRefname(n)])
  of rnSmiley: renderSmiley(d, n, result)
  of rnLeaf: result.add(esc(d.target, n.text, escMode=d.escMode))
  of rnContents: d.hasToc = true
  of rnDefaultRole: discard
  of rnTitle:
    d.meta[metaTitle] = ""
    renderRstToOut(d, n.sons[0], d.meta[metaTitle])
    d.meta[metaTitleRaw] = n.sons[0].addNodes

# -----------------------------------------------------------------------------

proc getVarIdx(varnames: openArray[string], id: string): int =
  for i in countup(0, high(varnames)):
    if cmpIgnoreStyle(varnames[i], id) == 0:
      return i
  result = -1

proc formatNamedVars*(frmt: string, varnames: openArray[string],
                      varvalues: openArray[string]): string =
  var i = 0
  var L = len(frmt)
  result = ""
  var num = 0
  while i < L:
    if frmt[i] == '$':
      inc(i)                  # skip '$'
      case frmt[i]
      of '#':
        add(result, varvalues[num])
        inc(num)
        inc(i)
      of '$':
        add(result, "$")
        inc(i)
      of '0'..'9':
        var j = 0
        while true:
          j = (j * 10) + ord(frmt[i]) - ord('0')
          inc(i)
          if i > L-1 or frmt[i] notin {'0'..'9'}: break
        if j > high(varvalues) + 1:
          raise newException(ValueError, "invalid index: " & $j)
        num = j
        add(result, varvalues[j - 1])
      of 'A'..'Z', 'a'..'z', '\x80'..'\xFF':
        var id = ""
        while true:
          add(id, frmt[i])
          inc(i)
          if frmt[i] notin {'A'..'Z', '_', 'a'..'z', '\x80'..'\xFF'}: break
        var idx = getVarIdx(varnames, id)
        if idx >= 0:
          add(result, varvalues[idx])
        else:
          raise newException(ValueError, "unknown substitution var: " & id)
      of '{':
        var id = ""
        inc(i)
        while frmt[i] != '}':
          if frmt[i] == '\0':
            raise newException(ValueError, "'}' expected")
          add(id, frmt[i])
          inc(i)
        inc(i)                # skip }
                              # search for the variable:
        var idx = getVarIdx(varnames, id)
        if idx >= 0: add(result, varvalues[idx])
        else:
          raise newException(ValueError, "unknown substitution var: " & id)
      else:
        raise newException(ValueError, "unknown substitution: $" & $frmt[i])
    var start = i
    while i < L:
      if frmt[i] != '$': inc(i)
      else: break
    if i-1 >= start: add(result, substr(frmt, start, i - 1))


proc defaultConfig*(): StringTableRef =
  ## Returns a default configuration for embedded HTML generation.
  ##
  ## The returned ``StringTableRef`` contains the parameters used by the HTML
  ## engine to build the final output. For information on what these parameters
  ## are and their purpose, please look up the file ``config/nimdoc.cfg``
  ## bundled with the compiler.
  ##
  ## The only difference between the contents of that file and the values
  ## provided by this proc is the ``doc.file`` variable. The ``doc.file``
  ## variable of the configuration file contains HTML to build standalone
  ## pages, while this proc returns just the content for procs like
  ## ``rstToHtml`` to generate the bare minimum HTML.
  result = newStringTable(modeStyleInsensitive)

  template setConfigVar(key, val) =
    result[key] = val

  # If you need to modify these values, it might be worth updating the template
  # file in config/nimdoc.cfg.
  setConfigVar("split.item.toc", "20")
  setConfigVar("doc.section", """
<div class="section" id="$sectionID">
<h1><a class="toc-backref" href="#$sectionTitleID">$sectionTitle</a></h1>
<dl class="item">
$content
</dl></div>
""")
  setConfigVar("doc.section.toc", """
<li>
  <a class="reference" href="#$sectionID" id="$sectionTitleID">$sectionTitle</a>
  <ul class="simple">
    $content
  </ul>
</li>
""")
  setConfigVar("doc.item", """
<dt id="$itemID"><a name="$itemSymOrIDEnc"></a><pre>$header</pre></dt>
<dd>
$desc
</dd>
""")
  setConfigVar("doc.item.toc", """
  <li><a class="reference" href="#$itemSymOrIDEnc"
    title="$header_plain">$name</a></li>
""")
  setConfigVar("doc.toc", """
<div class="navigation" id="navigation">
<ul class="simple">
$content
</ul>
</div>""")
  setConfigVar("doc.body_toc", """
$tableofcontents
<div class="content" id="content">
$moduledesc
$content
</div>
""")
  setConfigVar("doc.listing_start", "<pre$3 class = \"listing\">")
  setConfigVar("doc.listing_end", "</pre>")
  setConfigVar("doc.listing_button", "</pre>")
  setConfigVar("doc.body_no_toc", "$moduledesc $content")
  setConfigVar("doc.file", "$content")
  setConfigVar("doc.smiley_format", "/images/smilies/$1.gif")

# ---------- forum ---------------------------------------------------------

proc rstToHtml*(s: string, options: RstParseOptions,
                config: StringTableRef,
                msgHandler: MsgHandler = rst.defaultMsgHandler): string {.gcsafe.} =
  ## Converts an input rst string into embeddable HTML.
  ##
  ## This convenience proc parses any input string using rst markup (it doesn't
  ## have to be a full document!) and returns an embeddable piece of HTML. The
  ## proc is meant to be used in *online* environments without access to a
  ## meaningful filesystem, and therefore rst ``include`` like directives won't
  ## work. For an explanation of the ``config`` parameter see the
  ## ``initRstGenerator`` proc. Example:
  ##
  ##   ```nim
  ##   import packages/docutils/rstgen, strtabs
  ##
  ##   echo rstToHtml("*Hello* **world**!", {},
  ##     newStringTable(modeStyleInsensitive))
  ##   # --> <em>Hello</em> <strong>world</strong>!
  ##   ```
  ##
  ## If you need to allow the rst ``include`` directive or tweak the generated
  ## output you have to create your own ``RstGenerator`` with
  ## ``initRstGenerator`` and related procs.

  proc myFindFile(filename: string): string =
    # we don't find any files in online mode:
    result = ""
  proc myFindRefFile(filename: string): (string, string) =
    result = ("", "")

  const filen = "input"
  let (rst, filenames, t) = rstParse(s, filen,
                                     line=LineRstInit, column=ColRstInit,
                                     options, myFindFile, myFindRefFile, msgHandler)
  var d: RstGenerator
  initRstGenerator(d, outHtml, config, filen, myFindFile, msgHandler,
                   filenames, hasToc = t)
  result = ""
  renderRstToOut(d, rst, result)
  strbasics.strip(result)


proc rstToLatex*(rstSource: string; options: RstParseOptions): string {.inline, since: (1, 3).} =
  ## Convenience proc for `renderRstToOut` and `initRstGenerator`.
  runnableExamples: doAssert rstToLatex("*Hello* **world**", {}) == """\emph{Hello} \textbf{world}"""
  if rstSource.len == 0: return
  let (rst, filenames, t) = rstParse(rstSource, "",
                                     line=LineRstInit, column=ColRstInit,
                                     options)
  var rstGenera: RstGenerator
  rstGenera.initRstGenerator(outLatex, defaultConfig(), "input",
                             filenames=filenames, hasToc = t)
  rstGenera.renderRstToOut(rst, result)
  strbasics.strip(result)
