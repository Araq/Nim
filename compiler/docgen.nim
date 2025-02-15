#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This is the Nim documentation generator. Cross-references are generated
## by knowing how the anchors are going to be named.
##
## .. importdoc:: ../docgen.md
##
## For corresponding users' documentation see [Nim DocGen Tools Guide].

import
  ast, options, msgs, idents,
  wordrecg, syntaxes, renderer, lexer,
  packages/docutils/[rst, rstidx, rstgen, dochelpers],
  trees, types,
  typesrenderer, astalgo, lineinfos,
  pathutils, nimpaths, renderverbatim, packages
import packages/docutils/rstast except FileIndex, TLineInfo

import std/[os, strutils, strtabs, algorithm, json, osproc, tables, intsets, xmltree, sequtils]
from std/uri import encodeUrl
from nodejs import findNodeJs

when defined(nimPreviewSlimSystem):
  import std/[assertions, syncio]


const
  exportSection = skField
  docCmdSkip = "skip"
  DocColOffset = "## ".len  # assuming that a space was added after ##

type
  ItemFragment = object  ## A fragment from each item will be eventually
                         ## constructed by converting `rst` fields to strings.
    case isRst: bool
    of true:
      rst: PRstNode
    of false:            ## contains ready markup e.g. from runnableExamples
      str: string
  ItemPre = seq[ItemFragment]  ## A pre-processed item.
  Item = object        ## Any item in documentation, e.g. symbol
                       ## entry. Configuration variable ``doc.item``
                       ## is used for its HTML rendering.
    descRst: ItemPre     ## Description of the item (may contain
                         ## runnableExamples).
    substitutions: seq[string]    ## Variable names in `doc.item`...
    sortName: string    ## The string used for sorting in output
    info: rstast.TLineInfo  ## place where symbol was defined (for messages)
    anchor: string  ## e.g. HTML anchor
    name: string  ## short name of the symbol, not unique
                  ## (includes backticks ` if present)
    detailedName: string  ## longer name like `proc search(x: int): int`
  ModSection = object  ## Section like Procs, Types, etc.
    secItems: Table[string, seq[Item]]
                         ## Map basic name -> pre-processed items.
    finalMarkup: string  ## The items, after RST pass 2 and rendering.
  ModSections = array[TSymKind, ModSection]
  TocItem = object  ## HTML TOC item
    content: string
    sortName: string
  TocSectionsFinal = array[TSymKind, string]
  ExampleGroup = ref object
    ## a group of runnableExamples with same rdoccmd
    rdoccmd: string ## from 1st arg in `runnableExamples(rdoccmd): body`
    docCmd: string ## from user config, e.g. --doccmd:-d:foo
    code: string ## contains imports; each import contains `body`
    index: int ## group index
  JsonItem = object  # pre-processed item: `rst` should be finalized
    json: JsonNode
    rst: PRstNode
    rstField: string
  TDocumentor = object of rstgen.RstGenerator
    modDescPre: ItemPre   # module description, not finalized
    modDescFinal: string  # module description, after RST pass 2 and rendering
    module: PSym
    modDeprecationMsg: string
    section: ModSections     # entries of ``.nim`` file (for `proc`s, etc)
    tocSimple: array[TSymKind, seq[TocItem]]
      # TOC entries for non-overloadable symbols (e.g. types, constants)...
    tocTable:  array[TSymKind, Table[string, seq[TocItem]]]
      # ...otherwise (e.g. procs)
    toc2: TocSectionsFinal  # TOC `content`, which is probably wrapped
                            # in `doc.section.toc2`
    toc: TocSectionsFinal  # final TOC (wrapped in `doc.section.toc`)
    indexValFilename: string
    analytics: string  # Google Analytics javascript, "" if doesn't exist
    seenSymbols: StringTableRef # avoids duplicate symbol generation for HTML.
    jEntriesPre: seq[JsonItem] # pre-processed RST + JSON content
    jEntriesFinal: JsonNode    # final JSON after RST pass 2 and rendering
    types: TStrTable
    sharedState: PRstSharedState
    standaloneDoc: bool        # is markup (.rst/.md) document?
    conf*: ConfigRef
    cache*: IdentCache
    exampleCounter: int
    emitted: IntSet # we need to track which symbols have been emitted
                    # already. See bug #3655
    thisDir*: AbsoluteDir
    exampleGroups: OrderedTable[string, ExampleGroup]
    wroteSupportFiles*: bool
    nimToRstFid: Table[lineinfos.FileIndex, rstast.FileIndex]
      ## map Nim FileIndex -> RST one, it's needed because we keep them separate

  PDoc* = ref TDocumentor ## Alias to type less.

proc add(dest: var ItemPre, rst: PRstNode) = dest.add ItemFragment(isRst: true, rst: rst)
proc add(dest: var ItemPre, str: string) = dest.add ItemFragment(isRst: false, str: str)

proc addRstFileIndex(d: PDoc, fileIndex: lineinfos.FileIndex): rstast.FileIndex =
  let invalid = rstast.FileIndex(-1)
  result = d.nimToRstFid.getOrDefault(fileIndex, invalid)
  if result == invalid:
    let fname = toFullPath(d.conf, fileIndex)
    result = addFilename(d.sharedState, fname)
    d.nimToRstFid[fileIndex] = result

proc addRstFileIndex(d: PDoc, info: lineinfos.TLineInfo): rstast.FileIndex =
  addRstFileIndex(d, info.fileIndex)

proc cmpDecimalsIgnoreCase(a, b: string): int =
  ## For sorting with correct handling of cases like 'uint8' and 'uint16'.
  ## Also handles leading zeros well (however note that leading zeros are
  ## significant when lengths of numbers mismatch, e.g. 'bar08' > 'bar8' !).
  runnableExamples:
    doAssert cmpDecimalsIgnoreCase("uint8", "uint16") < 0
    doAssert cmpDecimalsIgnoreCase("val00032", "val16suffix") > 0
    doAssert cmpDecimalsIgnoreCase("val16suffix", "val16") > 0
    doAssert cmpDecimalsIgnoreCase("val_08_32", "val_08_8") > 0
    doAssert cmpDecimalsIgnoreCase("val_07_32", "val_08_8") < 0
    doAssert cmpDecimalsIgnoreCase("ab8", "ab08") < 0
    doAssert cmpDecimalsIgnoreCase("ab8de", "ab08c") < 0 # sanity check
  let aLen = a.len
  let bLen = b.len
  var
    iA = 0
    iB = 0
  while iA < aLen and iB < bLen:
    if isDigit(a[iA]) and isDigit(b[iB]):
      var
        limitA = iA  # index after the last (least significant) digit
        limitB = iB
      while limitA < aLen and isDigit(a[limitA]): inc limitA
      while limitB < bLen and isDigit(b[limitB]): inc limitB
      var pos = max(limitA-iA, limitB-iA)
      while pos > 0:
        if limitA-pos < iA:  # digit in `a` is 0 effectively
          result = ord('0') - ord(b[limitB-pos])
        elif limitB-pos < iB:  # digit in `b` is 0 effectively
          result = ord(a[limitA-pos]) - ord('0')
        else:
          result = ord(a[limitA-pos]) - ord(b[limitB-pos])
        if result != 0: return
        dec pos
      result = (limitA - iA) - (limitB - iB)  # consider 'bar08' > 'bar8'
      if result != 0: return
      iA = limitA
      iB = limitB
    else:
      result = ord(toLowerAscii(a[iA])) - ord(toLowerAscii(b[iB]))
      if result != 0: return
      inc iA
      inc iB
  result = (aLen - iA) - (bLen - iB)

proc prettyString(a: object): string =
  # xxx pending std/prettyprint refs https://github.com/nim-lang/RFCs/issues/203#issuecomment-602534906
  result = ""
  for k, v in fieldPairs(a):
    result.add k & ": " & $v & "\n"

proc presentationPath*(conf: ConfigRef, file: AbsoluteFile): RelativeFile =
  ## returns a relative file that will be appended to outDir
  let file2 = $file
  template bail() =
    result = relativeTo(file, conf.projectPath)
  proc nimbleDir(): AbsoluteDir =
    getNimbleFile(conf, file2).parentDir.AbsoluteDir
  case conf.docRoot:
  of docRootDefault:
    result = getRelativePathFromConfigPath(conf, file)
    let dir = nimbleDir()
    if not dir.isEmpty:
      let result2 = relativeTo(file, dir)
      if not result2.isEmpty and (result.isEmpty or result2.string.len < result.string.len):
        result = result2
    if result.isEmpty: bail()
  of "@pkg":
    let dir = nimbleDir()
    if dir.isEmpty: bail()
    else: result = relativeTo(file, dir)
  of "@path":
    result = getRelativePathFromConfigPath(conf, file)
    if result.isEmpty: bail()
  elif conf.docRoot.len > 0:
    # we're (currently) requiring `isAbsolute` to avoid confusion when passing
    # a relative path (would it be relative with regard to $PWD or to projectfile)
    conf.globalAssert conf.docRoot.isAbsolute, arg=conf.docRoot
    conf.globalAssert conf.docRoot.dirExists, arg=conf.docRoot
    # needed because `canonicalizePath` called on `file`
    result = file.relativeTo conf.docRoot.expandFilename.AbsoluteDir
  else:
    bail()
  if isAbsolute(result.string):
    result = file.string.splitPath()[1].RelativeFile
  result = result.string.replace("..", dotdotMangle).RelativeFile
  doAssert not result.isEmpty
  doAssert not isAbsolute(result.string)

proc whichType(d: PDoc; n: PNode): PSym =
  if n.kind == nkSym:
    if d.types.strTableContains(n.sym):
      result = n.sym
    else:
      result = nil
  else:
    result = nil
    for i in 0..<n.safeLen:
      let x = whichType(d, n[i])
      if x != nil: return x

proc attachToType(d: PDoc; p: PSym): PSym =
  result = nil
  let params = p.ast[paramsPos]
  template check(i) =
    result = whichType(d, params[i])
    if result != nil: return result

  # first check the first parameter, then the return type,
  # then the other parameter:
  if params.len > 1: check(1)
  if params.len > 0: check(0)
  for i in 2..<params.len: check(i)

template declareClosures(currentFilename: AbsoluteFile, destFile: string) =
  proc compilerMsgHandler(filename: string, line, col: int,
                          msgKind: rst.MsgKind, arg: string) {.gcsafe.} =
    # translate msg kind:
    var k: TMsgKind
    case msgKind
    of meCannotOpenFile: k = errCannotOpenFile
    of meExpected: k = errXExpected
    of meMissingClosing: k = errRstMissingClosing
    of meGridTableNotImplemented: k = errRstGridTableNotImplemented
    of meMarkdownIllformedTable: k = errRstMarkdownIllformedTable
    of meIllformedTable: k = errRstIllformedTable
    of meNewSectionExpected: k = errRstNewSectionExpected
    of meGeneralParseError: k = errRstGeneralParseError
    of meInvalidDirective: k = errRstInvalidDirectiveX
    of meInvalidField: k = errRstInvalidField
    of meFootnoteMismatch: k = errRstFootnoteMismatch
    of meSandboxedDirective: k = errRstSandboxedDirective
    of mwRedefinitionOfLabel: k = warnRstRedefinitionOfLabel
    of mwUnknownSubstitution: k = warnRstUnknownSubstitutionX
    of mwAmbiguousLink: k = warnRstAmbiguousLink
    of mwBrokenLink: k = warnRstBrokenLink
    of mwUnsupportedLanguage: k = warnRstLanguageXNotSupported
    of mwUnsupportedField: k = warnRstFieldXNotSupported
    of mwUnusedImportdoc: k = warnRstUnusedImportdoc
    of mwRstStyle: k = warnRstStyle
    {.gcsafe.}:
      let errorsAsWarnings = (roPreferMarkdown in d.sharedState.options) and
          not d.standaloneDoc  # not tolerate errors in .rst/.md files
      if whichMsgClass(msgKind) == mcError and errorsAsWarnings:
        liMessage(conf, newLineInfo(conf, AbsoluteFile filename, line, col),
                  k, arg, doNothing, instLoc(), ignoreError=true)
        # when our Markdown parser fails, we currently can only terminate the
        # parsing (and then we will return monospaced text instead of markup):
        raiseRecoverableError("")
      else:
        globalError(conf, newLineInfo(conf, AbsoluteFile filename, line, col), k, arg)

  proc docgenFindFile(s: string): string {.gcsafe.} =
    result = options.findFile(conf, s).string
    if result.len == 0:
      result = getCurrentDir() / s
      if not fileExists(result): result = ""

  proc docgenFindRefFile(targetRelPath: string):
         tuple[targetPath: string, linkRelPath: string] {.gcsafe.} =
    let fromDir = splitFile(destFile).dir  # dir where we reference from
    let basedir = os.splitFile(currentFilename.string).dir
    let outDirPath: RelativeFile =
        presentationPath(conf, AbsoluteFile(basedir / targetRelPath))
          # use presentationPath because `..` path can be be mangled to `_._`
    result = (string(conf.outDir / outDirPath), "")
    if not fileExists(result.targetPath):
      # this can happen if targetRelPath goes to parent directory `OUTDIR/..`.
      # Trying it, this may cause ambiguities, but allows us to insert
      # "packages" into each other, which is actually used in Nim repo itself.
      let destPath = fromDir / targetRelPath
      if destPath != result.targetPath and fileExists(destPath):
        result.targetPath = destPath

    result.linkRelPath = relativePath(result.targetPath.splitFile.dir,
                                      fromDir).replace('\\', '/')


proc parseRst(text: string,
              line, column: int,
              conf: ConfigRef, sharedState: PRstSharedState): PRstNode =
  result = rstParsePass1(text, line, column, sharedState)

proc getOutFile2(conf: ConfigRef; filename: RelativeFile,
                 ext: string, guessTarget: bool): AbsoluteFile =
  if optWholeProject in conf.globalOptions or guessTarget:
    let d = conf.outDir
    createDir(d)
    result = d / changeFileExt(filename, ext)
  elif not conf.outFile.isEmpty:
    result = absOutFile(conf)
  else:
    result = getOutFile(conf, filename, ext)

proc isLatexCmd(conf: ConfigRef): bool =
  conf.cmd in {cmdRst2tex, cmdMd2tex, cmdDoc2tex}

proc newDocumentor*(filename: AbsoluteFile; cache: IdentCache; conf: ConfigRef,
                    outExt: string = HtmlExt, module: PSym = nil,
                    standaloneDoc = false, preferMarkdown = true,
                    hasToc = true): PDoc =
  let destFile = getOutFile2(conf, presentationPath(conf, filename), outExt, false).string
  new(result)
  let d = result  # pass `d` to `declareClosures`:
  declareClosures(currentFilename = filename, destFile = destFile)
  result.module = module
  result.conf = conf
  result.cache = cache
  result.outDir = conf.outDir.string
  result.standaloneDoc = standaloneDoc
  var options= {roSupportRawDirective, roSupportMarkdown, roSandboxDisabled}
  if preferMarkdown:
    options.incl roPreferMarkdown
  if not standaloneDoc: options.incl roNimFile
  # (options can be changed dynamically in `setDoctype` by `{.doctype.}`)
  result.hasToc = hasToc
  result.sharedState = newRstSharedState(
      options, filename.string,
      docgenFindFile, docgenFindRefFile, compilerMsgHandler, hasToc)
  initRstGenerator(result[], (if conf.isLatexCmd: outLatex else: outHtml),
                   conf.configVars, filename.string,
                   docgenFindFile, compilerMsgHandler)

  if conf.configVars.hasKey("doc.googleAnalytics") and
      conf.configVars.hasKey("doc.plausibleAnalytics"):
    raiseAssert "Either use googleAnalytics or plausibleAnalytics"

  if conf.configVars.hasKey("doc.googleAnalytics"):
    result.analytics = """
<script>
  (function(i,s,o,g,r,a,m){i['GoogleAnalyticsObject']=r;i[r]=i[r]||function(){
  (i[r].q=i[r].q||[]).push(arguments)},i[r].l=1*new Date();a=s.createElement(o),
  m=s.getElementsByTagName(o)[0];a.async=1;a.src=g;m.parentNode.insertBefore(a,m)
  })(window,document,'script','//www.google-analytics.com/analytics.js','ga');

  ga('create', '$1', 'auto');
  ga('send', 'pageview');

</script>
    """ % [conf.configVars.getOrDefault"doc.googleAnalytics"]
  elif conf.configVars.hasKey("doc.plausibleAnalytics"):
    result.analytics = """
    <script defer data-domain="$1" src="https://plausible.io/js/plausible.js"></script>
    """ % [conf.configVars.getOrDefault"doc.plausibleAnalytics"]
  else:
    result.analytics = ""

  result.seenSymbols = newStringTable(modeCaseInsensitive)
  result.id = 100
  result.jEntriesFinal = newJArray()
  result.types = initStrTable()
  result.onTestSnippet =
    proc (gen: var RstGenerator; filename, cmd: string; status: int; content: string) {.gcsafe.} =
      if conf.docCmd == docCmdSkip: return
      inc(gen.id)
      var d = (ptr TDocumentor)(addr gen)
      var outp: AbsoluteFile
      if filename.len == 0:
        let nameOnly = splitFile(d.filename).name
        # "snippets" needed, refs bug #17183
        outp = getNimcacheDir(conf) / "snippets".RelativeDir / RelativeDir(nameOnly) /
               RelativeFile(nameOnly & "_snippet_" & $d.id & ".nim")
      elif isAbsolute(filename):
        outp = AbsoluteFile(filename)
      else:
        # Nim's convention: every path is relative to the file it was written in:
        let nameOnly = splitFile(d.filename).name
        outp = AbsoluteDir(nameOnly) / RelativeFile(filename)
      # Make sure the destination directory exists
      createDir(outp.splitFile.dir)
      # Include the current file if we're parsing a nim file
      let importStmt = if d.standaloneDoc: "" else: "import \"$1\"\n" % [d.filename.replace("\\", "/")]
      writeFile(outp, importStmt & content)

      proc interpSnippetCmd(cmd: string): string =
        # backward compatibility hacks; interpolation commands should explicitly use `$`
        if cmd.startsWith "nim ": result = "$nim " & cmd[4..^1]
        else: result = cmd
        # factor with D20210224T221756
        result = result.replace("$1", "$options") % [
          "nim", os.getAppFilename().quoteShell,
          "libpath", quoteShell(d.conf.libpath),
          "docCmd", d.conf.docCmd,
          "backend", $d.conf.backend,
          "options", outp.quoteShell,
            # xxx `quoteShell` seems buggy if user passes options = "-d:foo somefile.nim"
        ]
      let cmd = cmd.interpSnippetCmd
      rawMessage(conf, hintExecuting, cmd)
      let (output, gotten) = execCmdEx(cmd)
      if gotten != status:
        rawMessage(conf, errGenerated, "snippet failed: cmd: '$1' status: $2 expected: $3 output: $4" % [cmd, $gotten, $status, output])
  result.emitted = initIntSet()
  result.destFile = destFile
  result.thisDir = result.destFile.AbsoluteFile.splitFile.dir

template dispA(conf: ConfigRef; dest: var string, xml, tex: string,
               args: openArray[string]) =
  if not conf.isLatexCmd: dest.addf(xml, args)
  else: dest.addf(tex, args)

proc getVarIdx(varnames: openArray[string], id: string): int =
  for i in 0..high(varnames):
    if cmpIgnoreStyle(varnames[i], id) == 0:
      return i
  result = -1

proc genComment(d: PDoc, n: PNode): PRstNode =
  if n.comment.len > 0:
    d.sharedState.currFileIdx = addRstFileIndex(d, n.info)
    try:
      result = parseRst(n.comment,
                        toLinenumber(n.info),
                        toColumn(n.info) + DocColOffset,
                        d.conf, d.sharedState)
    except ERecoverableError:
      result = newRstNode(rnLiteralBlock, @[newRstLeaf(n.comment)])
  else:
    result = nil

proc genRecCommentAux(d: PDoc, n: PNode): PRstNode =
  if n == nil: return nil
  result = genComment(d, n)
  if result == nil:
    if n.kind in {nkStmtList, nkStmtListExpr, nkTypeDef, nkConstDef, nkTypeClassTy,
                  nkObjectTy, nkRefTy, nkPtrTy, nkAsgn, nkFastAsgn, nkSinkAsgn, nkHiddenStdConv}:
      # notin {nkEmpty..nkNilLit, nkEnumTy, nkTupleTy}:
      for i in 0..<n.len:
        result = genRecCommentAux(d, n[i])
        if result != nil: return
  else:
    n.comment = ""

proc genRecComment(d: PDoc, n: PNode): PRstNode =
  if n == nil: return nil
  result = genComment(d, n)
  if result == nil:
    if n.kind in {nkProcDef, nkFuncDef, nkMethodDef, nkIteratorDef,
                  nkMacroDef, nkTemplateDef, nkConverterDef}:
      result = genRecCommentAux(d, n[bodyPos])
    else:
      result = genRecCommentAux(d, n)

proc getPlainDocstring(n: PNode): string =
  ## Gets the plain text docstring of a node non destructively.
  ##
  ## You need to call this before genRecComment, whose side effects are removal
  ## of comments from the tree. The proc will recursively scan and return all
  ## the concatenated ``##`` comments of the node.
  if n == nil: result = ""
  elif startsWith(n.comment, "##"):
    result = n.comment
  else:
    result = ""
    for i in 0..<n.safeLen:
      result = getPlainDocstring(n[i])
      if result.len > 0: return

proc externalDep(d: PDoc; module: PSym): string =
  if optWholeProject in d.conf.globalOptions or d.conf.docRoot.len > 0:
    let full = AbsoluteFile toFullPath(d.conf, FileIndex module.position)
    let tmp = getOutFile2(d.conf, presentationPath(d.conf, full), HtmlExt, sfMainModule notin module.flags)
    result = relativeTo(tmp, d.thisDir, '/').string
  else:
    result = extractFilename toFullPath(d.conf, FileIndex module.position)

proc nodeToHighlightedHtml(d: PDoc; n: PNode; result: var string;
                           renderFlags: TRenderFlags = {};
                           procLink: string) =
  var r: TSrcGen = initTokRender(n, renderFlags)
  var literal = ""
  var kind = tkEof
  var tokenPos = 0
  var procTokenPos = 0
  template escLit(): untyped = esc(d.target, literal)
  while true:
    getNextTok(r, kind, literal)
    inc tokenPos
    case kind
    of tkEof:
      break
    of tkComment:
      dispA(d.conf, result, "<span class=\"Comment\">$1</span>", "\\spanComment{$1}",
            [escLit])
    of tokKeywordLow..tokKeywordHigh:
      if kind in {tkProc, tkMethod, tkIterator, tkMacro, tkTemplate, tkFunc, tkConverter}:
        procTokenPos = tokenPos
      dispA(d.conf, result, "<span class=\"Keyword\">$1</span>", "\\spanKeyword{$1}",
            [literal])
    of tkOpr:
      dispA(d.conf, result, "<span class=\"Operator\">$1</span>", "\\spanOperator{$1}",
            [escLit])
    of tkStrLit..tkTripleStrLit, tkCustomLit:
      dispA(d.conf, result, "<span class=\"StringLit\">$1</span>",
            "\\spanStringLit{$1}", [escLit])
    of tkCharLit:
      dispA(d.conf, result, "<span class=\"CharLit\">$1</span>", "\\spanCharLit{$1}",
            [escLit])
    of tkIntLit..tkUInt64Lit:
      dispA(d.conf, result, "<span class=\"DecNumber\">$1</span>",
            "\\spanDecNumber{$1}", [escLit])
    of tkFloatLit..tkFloat128Lit:
      dispA(d.conf, result, "<span class=\"FloatNumber\">$1</span>",
            "\\spanFloatNumber{$1}", [escLit])
    of tkSymbol:
      let s = getTokSym(r)
      # -2 because of the whitespace in between:
      if procTokenPos == tokenPos-2 and procLink != "":
        dispA(d.conf, result, "<a href=\"#$2\"><span class=\"Identifier\">$1</span></a>",
              "\\spanIdentifier{$1}", [escLit, procLink])
      elif s != nil and s.kind in {skType, skVar, skLet, skConst} and
           sfExported in s.flags and s.owner != nil and
           belongsToProjectPackage(d.conf, s.owner) and d.target == outHtml:
        let external = externalDep(d, s.owner)
        result.addf "<a href=\"$1#$2\"><span class=\"Identifier\">$3</span></a>",
          [changeFileExt(external, "html"), literal,
           escLit]
      else:
        dispA(d.conf, result, "<span class=\"Identifier\">$1</span>",
              "\\spanIdentifier{$1}", [escLit])
    of tkSpaces, tkInvalid:
      result.add(literal)
    of tkHideableStart:
      template fun(s) = dispA(d.conf, result, s, "\\spanOther{$1}", [escLit])
      if renderRunnableExamples in renderFlags: fun "$1"
      else:
        # 1st span is required for the JS to work properly
        fun """
<span>
<span class="Other pragmadots">...</span>
</span>
<span class="pragmawrap">""".replace("\n", "")  # Must remove newlines because wrapped in a <pre>
    of tkHideableEnd:
      template fun(s) = dispA(d.conf, result, s, "\\spanOther{$1}", [escLit])
      if renderRunnableExamples in renderFlags: fun "$1"
      else: fun "</span>"
    of tkCurlyDotLe: dispA(d.conf, result, "$1", "\\spanOther{$1}", [escLit])
    of tkCurlyDotRi: dispA(d.conf, result, "$1", "\\spanOther{$1}", [escLit])
    of tkParLe, tkParRi, tkBracketLe, tkBracketRi, tkCurlyLe, tkCurlyRi,
       tkBracketDotLe, tkBracketDotRi, tkParDotLe,
       tkParDotRi, tkComma, tkSemiColon, tkColon, tkEquals, tkDot, tkDotDot,
       tkAccent, tkColonColon,
       tkGStrLit, tkGTripleStrLit, tkInfixOpr, tkPrefixOpr, tkPostfixOpr,
       tkBracketLeColon:
      dispA(d.conf, result, "<span class=\"Other\">$1</span>", "\\spanOther{$1}",
            [escLit])

proc exampleOutputDir(d: PDoc): AbsoluteDir = d.conf.getNimcacheDir / RelativeDir"runnableExamples"

proc runAllExamples(d: PDoc) =
  # This used to be: `let backend = if isDefined(d.conf, "js"): "js"` (etc), however
  # using `-d:js` (etc) cannot work properly, e.g. would fail with `importjs`
  # since semantics are affected by `config.backend`, not by isDefined(d.conf, "js")
  let outputDir = d.exampleOutputDir
  for _, group in d.exampleGroups:
    if group.docCmd == docCmdSkip: continue
    let outp = outputDir / RelativeFile("$1_group$2_examples.nim" % [d.filename.splitFile.name, $group.index])
    group.code = "# autogenerated by docgen\n# source: $1\n# rdoccmd: $2\n$3" % [d.filename, group.rdoccmd, group.code]
    writeFile(outp, group.code)
    # most useful semantics is that `docCmd` comes after `rdoccmd`, so that we can (temporarily) override
    # via command line
    # D20210224T221756:here
    var pathArgs = "--path:$path" % [ "path", quoteShell(d.conf.projectPath) ]
    for p in d.conf.searchPaths:
      pathArgs = "$args --path:$path" % [ "args", pathArgs, "path", quoteShell(p) ]
    let cmd = "$nim $backend -r --lib:$libpath --warning:UnusedImport:off $pathArgs --nimcache:$nimcache $rdoccmd $docCmd $file" % [
      "nim", quoteShell(os.getAppFilename()),
      "backend", $d.conf.backend,
      "pathArgs", pathArgs,
      "libpath", quoteShell(d.conf.libpath),
      "nimcache", quoteShell(outputDir),
      "file", quoteShell(outp),
      "rdoccmd", group.rdoccmd,
      "docCmd", group.docCmd,
    ]
    if d.conf.backend == backendJs and findNodeJs() == "":
      discard "ignore JS runnableExample"
    elif os.execShellCmd(cmd) != 0:
      d.conf.quitOrRaise "[runnableExamples] failed: generated file: '$1' group: '$2' cmd: $3" % [outp.string, group[].prettyString, cmd]
    else:
      # keep generated source file `outp` to allow inspection.
      rawMessage(d.conf, hintSuccess, ["runnableExamples: " & outp.string])
      # removeFile(outp.changeFileExt(ExeExt)) # it's in nimcache, no need to remove

proc quoted(a: string): string =
  result = ""
  result.addQuoted(a)

proc toInstantiationInfo(conf: ConfigRef, info: TLineInfo): (string, int, int) =
  # xxx expose in compiler/lineinfos.nim
  (conf.toMsgFilename(info), info.line.int, info.col.int + ColOffset)

proc prepareExample(d: PDoc; n: PNode, topLevel: bool): tuple[rdoccmd: string, code: string] =
  ## returns `rdoccmd` and source code for this runnableExamples
  var rdoccmd = ""
  if n.len < 2 or n.len > 3: globalError(d.conf, n.info, "runnableExamples invalid")
  if n.len == 3:
    let n1 = n[1]
    # xxx this should be evaluated during sempass
    if n1.kind notin nkStrKinds: globalError(d.conf, n1.info, "string litteral expected")
    rdoccmd = n1.strVal

  let useRenderModule = false
  let loc = d.conf.toFileLineCol(n.info)
  let code = extractRunnableExamplesSource(d.conf, n)

  if d.conf.errorCounter > 0:
    return (rdoccmd, code)

  let comment = "autogenerated by docgen\nloc: $1\nrdoccmd: $2" % [loc, rdoccmd]
  let outputDir = d.exampleOutputDir
  createDir(outputDir)
  inc d.exampleCounter
  let outp = outputDir / RelativeFile("$#_examples_$#.nim" % [d.filename.extractFilename.changeFileExt"", $d.exampleCounter])

  if useRenderModule:
    var docComment = newTree(nkCommentStmt)
    docComment.comment = comment
    var runnableExamples = newTree(nkStmtList,
        docComment,
        newTree(nkImportStmt, newStrNode(nkStrLit, "std/assertions")),
        newTree(nkImportStmt, newStrNode(nkStrLit, d.filename)))
    runnableExamples.info = n.info
    for a in n.lastSon: runnableExamples.add a

    # buggy, refs bug #17292
    # still worth fixing as it can affect other code relying on `renderModule`,
    # so we keep this code path here for now, which could still be useful in some
    # other situations.
    renderModule(runnableExamples, outp.string, conf = d.conf)

  else:
    var code2 = code
    if code.len > 0 and "codeReordering" notin code:
      let codeIndent = extractRunnableExamplesSource(d.conf, n, indent = 2)
      # hacky but simplest solution, until we devise a way to make `{.line.}`
      # work without introducing a scope
      code2 = """
{.line: $#.}:
$#
""" % [$toInstantiationInfo(d.conf, n.info), codeIndent]
    code2 = """
#[
$#
]#
import std/assertions
import $#
$#
""" % [comment, d.filename.quoted, code2]
    writeFile(outp.string, code2)

  if rdoccmd notin d.exampleGroups:
    d.exampleGroups[rdoccmd] = ExampleGroup(rdoccmd: rdoccmd, docCmd: d.conf.docCmd, index: d.exampleGroups.len)
  d.exampleGroups[rdoccmd].code.add "import $1\n" % outp.string.quoted

  var codeShown: string
  if topLevel: # refs https://github.com/nim-lang/RFCs/issues/352
    let title = canonicalImport(d.conf, AbsoluteFile d.filename)
    codeShown = "import $#\n$#" % [title, code]
  else:
    codeShown = code
  result = (rdoccmd, codeShown)
  when false:
    proc extractImports(n: PNode; result: PNode) =
      if n.kind in {nkImportStmt, nkImportExceptStmt, nkFromStmt}:
        result.add copyTree(n)
        n.kind = nkEmpty
        return
      for i in 0..<n.safeLen: extractImports(n[i], result)
    let imports = newTree(nkStmtList)
    var savedLastSon = copyTree n.lastSon
    extractImports(savedLastSon, imports)
    for imp in imports: runnableExamples.add imp
    runnableExamples.add newTree(nkBlockStmt, newNode(nkEmpty), copyTree savedLastSon)

type RunnableState = enum
  rsStart
  rsComment
  rsRunnable
  rsDone

proc getAllRunnableExamplesImpl(d: PDoc; n: PNode, dest: var ItemPre,
                                state: RunnableState, topLevel: bool):
                               RunnableState =
  ##[
  Simple state machine to tell whether we render runnableExamples and doc comments.
  This is to ensure that we can interleave runnableExamples and doc comments freely;
  the logic is easy to change but currently a doc comment following another doc comment
  will not render, to avoid rendering in following case:

  proc fn* =
    runnableExamples: discard
    ## d1
    runnableExamples: discard
    ## d2

    ## internal explanation  # <- this one should be out; it's part of rest of function body and would likey not make sense in doc comment
    discard # some code
  ]##

  case n.kind
  of nkCommentStmt:
    if state in {rsStart, rsRunnable}:
      dest.add genRecComment(d, n)
      return rsComment
  of nkCallKinds:
    if isRunnableExamples(n[0]) and
        n.len >= 2 and n.lastSon.kind == nkStmtList:
      if state in {rsStart, rsComment, rsRunnable}:
        let (rdoccmd, code) = prepareExample(d, n, topLevel)
        var msg = "Example:"
        if rdoccmd.len > 0: msg.add " cmd: " & rdoccmd
        var s: string = ""
        dispA(d.conf, s, "\n<p><strong class=\"examples_text\">$1</strong></p>\n",
            "\n\n\\textbf{$1}\n", [msg])
        dest.add s
        inc d.listingCounter
        let id = $d.listingCounter
        dest.add(d.config.getOrDefault"doc.listing_start" % [id, "langNim", ""])
        var dest2 = ""
        renderNimCode(dest2, code, d.target)
        dest.add dest2
        dest.add(d.config.getOrDefault"doc.listing_end" % id)
        return rsRunnable
      else:
        localError(d.conf, n.info, errUser, "runnableExamples must appear before the first non-comment statement")
  else: discard
  return rsDone
    # change this to `rsStart` if you want to keep generating doc comments
    # and runnableExamples that occur after some code in routine

proc getRoutineBody(n: PNode): PNode =
  ##[
  nim transforms these quite differently:

  proc someType*(): int =
    ## foo
    result = 3
=>
  result =
    ## foo
    3;

  proc someType*(): int =
    ## foo
    3
=>
  ## foo
  result = 3;

  so we normalize the results to get to the statement list containing the
  (0 or more) doc comments and runnableExamples.
  ]##
  result = n[bodyPos]

  # This won't be transformed: result.id = 10. Namely result[0].kind != nkSym.
  if result.kind == nkAsgn and result[0].kind == nkSym and
                               n.len > bodyPos+1 and n[bodyPos+1].kind == nkSym:
    doAssert result.len == 2
    result = result[1]

proc getAllRunnableExamples(d: PDoc, n: PNode, dest: var ItemPre) =
  var n = n
  var state = rsStart
  template fn(n2, topLevel) =
    state = getAllRunnableExamplesImpl(d, n2, dest, state, topLevel)
  dest.add genComment(d, n)
  case n.kind
  of routineDefs:
    n = n.getRoutineBody
    case n.kind
    of nkCommentStmt, nkCallKinds: fn(n, topLevel = false)
    else:
      for i in 0..<n.safeLen:
        fn(n[i], topLevel = false)
        if state == rsDone: discard # check all sons
  else: fn(n, topLevel = true)

proc isVisible(d: PDoc; n: PNode): bool =
  result = false
  if n.kind == nkPostfix:
    if n.len == 2 and n[0].kind == nkIdent:
      var v = n[0].ident
      result = v.id == ord(wStar) or v.id == ord(wMinus)
  elif n.kind == nkSym:
    # we cannot generate code for forwarded symbols here as we have no
    # exception tracking information here. Instead we copy over the comment
    # from the proc header.
    if optDocInternal in d.conf.globalOptions:
      result = {sfFromGeneric, sfForward}*n.sym.flags == {}
    else:
      result = {sfExported, sfFromGeneric, sfForward}*n.sym.flags == {sfExported}
    if result and containsOrIncl(d.emitted, n.sym.id):
      result = false
  elif n.kind == nkPragmaExpr:
    result = isVisible(d, n[0])

proc getName(n: PNode): string =
  case n.kind
  of nkPostfix: result = getName(n[1])
  of nkPragmaExpr: result = getName(n[0])
  of nkSym: result = n.sym.renderDefinitionName
  of nkIdent: result = n.ident.s
  of nkAccQuoted:
    result = "`"
    for i in 0..<n.len: result.add(getName(n[i]))
    result.add('`')
  of nkOpenSymChoice, nkClosedSymChoice, nkOpenSym:
    result = getName(n[0])
  else:
    result = ""

proc getNameEsc(d: PDoc, n: PNode): string =
  esc(d.target, getName(n))

proc getNameIdent(cache: IdentCache; n: PNode): PIdent =
  case n.kind
  of nkPostfix: result = getNameIdent(cache, n[1])
  of nkPragmaExpr: result = getNameIdent(cache, n[0])
  of nkSym: result = n.sym.name
  of nkIdent: result = n.ident
  of nkAccQuoted:
    var r = ""
    for i in 0..<n.len: r.add(getNameIdent(cache, n[i]).s)
    result = getIdent(cache, r)
  of nkOpenSymChoice, nkClosedSymChoice, nkOpenSym:
    result = getNameIdent(cache, n[0])
  else:
    result = nil

proc getRstName(n: PNode): PRstNode =
  case n.kind
  of nkPostfix: result = getRstName(n[1])
  of nkPragmaExpr: result = getRstName(n[0])
  of nkSym: result = newRstLeaf(n.sym.renderDefinitionName)
  of nkIdent: result = newRstLeaf(n.ident.s)
  of nkAccQuoted:
    result = getRstName(n[0])
    for i in 1..<n.len: result.text.add(getRstName(n[i]).text)
  of nkOpenSymChoice, nkClosedSymChoice, nkOpenSym:
    result = getRstName(n[0])
  else:
    result = nil

proc newUniquePlainSymbol(d: PDoc, original: string): string =
  ## Returns a new unique plain symbol made up from the original.
  ##
  ## When a collision is found in the seenSymbols table, new numerical variants
  ## with underscore + number will be generated.
  if not d.seenSymbols.hasKey(original):
    result = original
    d.seenSymbols[original] = ""
    return
  # Iterate over possible numeric variants of the original name.
  var count = 2
  while true:
    result = original & "_" & $count
    if not d.seenSymbols.hasKey(result):
      d.seenSymbols[result] = ""
      break
    count += 1

proc complexName(k: TSymKind, n: PNode, baseName: string): string =
  ## Builds a complex unique href name for the node.
  ##
  ## Pass as ``baseName`` the plain symbol obtained from the nodeName. The
  ## format of the returned symbol will be ``baseName(.callable type)?,(param
  ## type)?(,param type)*``. The callable type part will be added only if the
  ## node is not a proc, as those are the common ones. The suffix will be a dot
  ## and a single letter representing the type of the callable. The parameter
  ## types will be added with a preceding dash. Return types won't be added.
  ##
  ## If you modify the output of this proc, please update the anchor generation
  ## section of ``doc/docgen.rst``.
  result = baseName
  case k
  of skProc, skFunc: discard
  of skMacro: result.add(".m")
  of skMethod: result.add(".e")
  of skIterator: result.add(".i")
  of skTemplate: result.add(".t")
  of skConverter: result.add(".c")
  else: discard
  if n.safeLen > paramsPos and n[paramsPos].kind == nkFormalParams:
    let params = renderParamTypes(n[paramsPos])
    if params.len > 0:
      result.add(defaultParamSeparator)
      result.add(params)

proc docstringSummary(rstText: string): string =
  ## Returns just the first line or a brief chunk of text from a rst string.
  ##
  ## Most docstrings will contain a one liner summary, so stripping at the
  ## first newline is usually fine. If after that the content is still too big,
  ## it is stripped at the first comma, colon or dot, usual English sentence
  ## separators.
  ##
  ## No guarantees are made on the size of the output, but it should be small.
  ## Also, we hope to not break the rst, but maybe we do. If there is any
  ## trimming done, an ellipsis unicode char is added.
  const maxDocstringChars = 100
  assert(rstText.len < 2 or (rstText[0] == '#' and rstText[1] == '#'))
  result = rstText.substr(2).strip
  var pos = result.find('\L')
  if pos > 0:
    result.setLen(pos - 1)
    result.add("…")
  if pos < maxDocstringChars:
    return
  # Try to keep trimming at other natural boundaries.
  pos = result.find({'.', ',', ':'})
  let last = result.len - 1
  if pos > 0 and pos < last:
    result.setLen(pos - 1)
    result.add("…")

proc genDeprecationMsg(d: PDoc, n: PNode): string =
  ## Given a nkPragma wDeprecated node output a well-formatted section
  if n == nil: return

  case n.safeLen:
  of 0: # Deprecated w/o any message
    result = getConfigVar(d.conf, "doc.deprecationmsg") % [
       "label" , "Deprecated", "message", ""]
  of 2: # Deprecated w/ a message
    if n[1].kind in {nkStrLit..nkTripleStrLit}:
      result = getConfigVar(d.conf, "doc.deprecationmsg") % [
          "label", "Deprecated:", "message", xmltree.escape(n[1].strVal)]
    else:
      result = ""
  else:
    raiseAssert "unreachable"

type DocFlags = enum
  kDefault
  kForceExport

proc genSeeSrc(d: PDoc, path: string, line: int): string =
  result = ""
  let docItemSeeSrc = getConfigVar(d.conf, "doc.item.seesrc")
  if docItemSeeSrc.len > 0:
    let path = relativeTo(AbsoluteFile path, AbsoluteDir getCurrentDir(), '/')
    when false:
      let cwd = canonicalizePath(d.conf, getCurrentDir())
      var path = path
      if path.startsWith(cwd):
        path = path[cwd.len+1..^1].replace('\\', '/')
    let gitUrl = getConfigVar(d.conf, "git.url")
    if gitUrl.len > 0:
      let defaultBranch =
        if NimPatch mod 2 == 1: "devel"
        else: "version-$1-$2" % [$NimMajor, $NimMinor]
      let commit = getConfigVar(d.conf, "git.commit", defaultBranch)
      let develBranch = getConfigVar(d.conf, "git.devel", "devel")
      dispA(d.conf, result, "$1", "", [docItemSeeSrc % [
          "path", path.string, "line", $line, "url", gitUrl,
          "commit", commit, "devel", develBranch]])

proc symbolPriority(k: TSymKind): int =
  result = case k
    of skMacro: -3
    of skTemplate: -2
    of skIterator: -1
    else: 0  # including skProc which have higher priority
    # documentation itself has even higher priority 1

proc getTypeKind(n: PNode): string =
  case n[2].kind
  of nkEnumTy: "enum"
  of nkObjectTy: "object"
  of nkTupleTy: "tuple"
  else: ""

proc toLangSymbol(k: TSymKind, n: PNode, baseName: string): LangSymbol =
  ## Converts symbol info (names/types/parameters) in `n` into format
  ## `LangSymbol` convenient for ``rst.nim``/``dochelpers.nim``.
  result = LangSymbol(name: baseName.nimIdentNormalize,
      symKind: k.toHumanStr
  )
  if k in routineKinds:
    var
      paramTypes: seq[string] = @[]
    renderParamTypes(paramTypes, n[paramsPos], toNormalize=true)
    let paramNames = renderParamNames(n[paramsPos], toNormalize=true)
    # In some rare cases (system.typeof) parameter type is not set for default:
    doAssert paramTypes.len <= paramNames.len
    for i in 0 ..< paramNames.len:
      if i < paramTypes.len:
        result.parameters.add (paramNames[i], paramTypes[i])
      else:
        result.parameters.add (paramNames[i], "")
    result.parametersProvided = true

    result.outType = renderOutType(n[paramsPos], toNormalize=true)

  if k in {skProc, skFunc, skType, skIterator}:
    # Obtain `result.generics`
    # Use `n[miscPos]` since n[genericParamsPos] does not contain constraints
    var genNode: PNode = nil
    if k == skType:
      genNode = n[1]  # FIXME: what is index 1?
    else:
      if n[miscPos].kind != nkEmpty:
        genNode = n[miscPos][1]   # FIXME: what is index 1?
    if genNode != nil:
      var literal = ""
      var r: TSrcGen = initTokRender(genNode, {renderNoBody, renderNoComments,
        renderNoPragmas, renderNoProcDefs, renderExpandUsing, renderNoPostfix})
      var kind = tkEof
      while true:
        getNextTok(r, kind, literal)
        if kind == tkEof:
          break
        if kind != tkSpaces:
          result.generics.add(literal.nimIdentNormalize)

  if k == skType: result.symTypeKind = getTypeKind(n)

proc genItem(d: PDoc, n, nameNode: PNode, k: TSymKind, docFlags: DocFlags, nonExports: bool = false) =
  if (docFlags != kForceExport) and not isVisible(d, nameNode): return
  let
    name = getName(nameNode)
    nameEsc = esc(d.target, name)
  var plainDocstring = getPlainDocstring(n) # call here before genRecComment!
  var result = ""
  var literal, plainName = ""
  var kind = tkEof
  var comm: ItemPre = default(ItemPre)
  if n.kind in routineDefs:
    getAllRunnableExamples(d, n, comm)
  else:
    comm.add genRecComment(d, n)

  # Obtain the plain rendered string for hyperlink titles.
  var r: TSrcGen = initTokRender(n, {renderNoBody, renderNoComments, renderDocComments,
    renderNoPragmas, renderNoProcDefs, renderExpandUsing, renderNoPostfix})
  while true:
    getNextTok(r, kind, literal)
    if kind == tkEof:
      break
    plainName.add(literal)

  var pragmaNode = getDeclPragma(n)
  if pragmaNode != nil: pragmaNode = findPragma(pragmaNode, wDeprecated)

  inc(d.id)
  let
    plainNameEsc = esc(d.target, plainName.strip)
    typeDescr =
      if k == skType and getTypeKind(n) != "": getTypeKind(n)
      else: k.toHumanStr
    detailedName = typeDescr & " " & (
        if k in routineKinds: plainName else: name)
    uniqueName = if k in routineKinds: plainNameEsc else: nameEsc
    sortName = if k in routineKinds: plainName.strip else: name
    cleanPlainSymbol = renderPlainSymbolName(nameNode)
    complexSymbol = complexName(k, n, cleanPlainSymbol)
    plainSymbolEnc = encodeUrl(cleanPlainSymbol, usePlus = false)
    symbolOrId = d.newUniquePlainSymbol(complexSymbol)
    symbolOrIdEnc = encodeUrl(symbolOrId, usePlus = false)
    deprecationMsg = genDeprecationMsg(d, pragmaNode)
    rstLangSymbol = toLangSymbol(k, n, cleanPlainSymbol)
    symNameNode =
      if nameNode.kind == nkPostfix: nameNode[1]
      else: nameNode

  # we generate anchors automatically for subsequent use in doc comments
  let lineinfo = rstast.TLineInfo(
      line: nameNode.info.line, col: nameNode.info.col,
      fileIndex: addRstFileIndex(d, nameNode.info))
  addAnchorNim(d.sharedState, external = false, refn = symbolOrId,
               tooltip = detailedName, langSym = rstLangSymbol,
               priority = symbolPriority(k), info = lineinfo,
               module = addRstFileIndex(d, FileIndex d.module.position))

  var renderFlags = {renderNoBody, renderNoComments, renderDocComments,
    renderSyms, renderExpandUsing, renderNoPostfix}
  if nonExports:
    renderFlags.incl renderNonExportedFields
  nodeToHighlightedHtml(d, n, result, renderFlags, symbolOrIdEnc)

  let seeSrc = genSeeSrc(d, toFullPath(d.conf, n.info), n.info.line.int)

  d.section[k].secItems.mgetOrPut(cleanPlainSymbol, newSeq[Item]()).add Item(
    descRst: comm,
    sortName: sortName,
    info: lineinfo,
    anchor: symbolOrId,
    detailedName: detailedName,
    name: name,
    substitutions: @[
     "uniqueName", uniqueName,
     "header", result, "itemID", $d.id,
     "header_plain", plainNameEsc, "itemSym", cleanPlainSymbol,
     "itemSymEnc", plainSymbolEnc,
     "itemSymOrIDEnc", symbolOrIdEnc, "seeSrc", seeSrc,
     "deprecationMsg", deprecationMsg])

  let external = d.destFile.AbsoluteFile.relativeTo(d.conf.outDir, '/').changeFileExt(HtmlExt).string

  var attype = ""
  if k in routineKinds and symNameNode.kind == nkSym:
    let att = attachToType(d, nameNode.sym)
    if att != nil:
      attype = esc(d.target, att.name.s)
  elif k == skType and symNameNode.kind == nkSym and
      symNameNode.sym.typ.kind in {tyEnum, tyBool}:
    let etyp = symNameNode.sym.typ
    for e in etyp.n:
      if e.sym.kind != skEnumField: continue
      let plain = renderPlainSymbolName(e)
      let symbolOrId = d.newUniquePlainSymbol(plain)
      setIndexTerm(d[], ieNim, htmlFile = external, id = symbolOrId,
                   term = plain, linkTitle = symNameNode.sym.name.s & '.' & plain,
                   linkDesc = xmltree.escape(getPlainDocstring(e).docstringSummary),
                   line = n.info.line.int)

  d.tocSimple[k].add TocItem(
    sortName: sortName,
    content: getConfigVar(d.conf, "doc.item.toc") % [
      "name", name, "header_plain", plainNameEsc,
      "itemSymOrIDEnc", symbolOrIdEnc])

  d.tocTable[k].mgetOrPut(cleanPlainSymbol, newSeq[TocItem]()).add TocItem(
    sortName: sortName,
    content: getConfigVar(d.conf, "doc.item.tocTable") % [
      "name", name, "header_plain", plainNameEsc,
      "itemSymOrID", symbolOrId.replace(",", ",<wbr>"),
      "itemSymOrIDEnc", symbolOrIdEnc])

  setIndexTerm(d[], ieNim, htmlFile = external, id = symbolOrId, term = name,
               linkTitle = detailedName,
               linkDesc = xmltree.escape(plainDocstring.docstringSummary),
               line = n.info.line.int)
  if k == skType and symNameNode.kind == nkSym:
    d.types.strTableAdd symNameNode.sym

proc genJsonItem(d: PDoc, n, nameNode: PNode, k: TSymKind, nonExports = false): JsonItem =
  if not isVisible(d, nameNode): return
  var
    name = getNameEsc(d, nameNode)
    comm = genRecComment(d, n)
    r: TSrcGen
    renderFlags = {renderNoBody, renderNoComments, renderDocComments,
      renderExpandUsing, renderNoPostfix}
  if nonExports:
    renderFlags.incl renderNonExportedFields
  r = initTokRender(n, renderFlags)
  result = JsonItem(json: %{ "name": %name, "type": %($k), "line": %n.info.line.int,
                   "col": %n.info.col}
  )
  if comm != nil:
    result.rst = comm
    result.rstField = "description"
  if r.buf.len > 0:
    result.json["code"] = %r.buf
  if k in routineKinds:
    result.json["signature"] = newJObject()
    if n[paramsPos][0].kind != nkEmpty:
      result.json["signature"]["return"] = %($n[paramsPos][0])
    if n[paramsPos].len > 1:
      result.json["signature"]["arguments"] = newJArray()
    for paramIdx in 1 ..< n[paramsPos].len:
      for identIdx in 0 ..< n[paramsPos][paramIdx].len - 2:
        let
          paramName = $n[paramsPos][paramIdx][identIdx]
          paramType = $n[paramsPos][paramIdx][^2]
        if n[paramsPos][paramIdx][^1].kind != nkEmpty:
          let paramDefault = $n[paramsPos][paramIdx][^1]
          result.json["signature"]["arguments"].add %{"name": %paramName, "type": %paramType, "default": %paramDefault}
        else:
          result.json["signature"]["arguments"].add %{"name": %paramName, "type": %paramType}
    if n[pragmasPos].kind != nkEmpty:
      result.json["signature"]["pragmas"] = newJArray()
      for pragma in n[pragmasPos]:
        result.json["signature"]["pragmas"].add %($pragma)
    if n[genericParamsPos].kind != nkEmpty:
      result.json["signature"]["genericParams"] = newJArray()
      for genericParam in n[genericParamsPos]:
        var param = %{"name": %($genericParam)}
        if genericParam.sym.typ.len > 0:
          param["types"] = newJArray()
          param["types"] = %($genericParam.sym.typ.elementType)
        result.json["signature"]["genericParams"].add param
  if optGenIndex in d.conf.globalOptions:
    genItem(d, n, nameNode, k, kForceExport)

proc setDoctype(d: PDoc, n: PNode) =
  ## Processes `{.doctype.}` pragma changing Markdown/RST parsing options.
  if n == nil:
    return
  if n.len != 2:
    localError(d.conf, n.info, errUser,
      "doctype pragma takes exactly 1 argument"
    )
    return
  var dt = ""
  case n[1].kind
  of nkStrLit:
    dt = toLowerAscii(n[1].strVal)
  of nkIdent:
    dt = toLowerAscii(n[1].ident.s)
  else:
    localError(d.conf, n.info, errUser,
      "unknown argument type $1 provided to doctype" % [$n[1].kind]
    )
    return
  case dt
  of "markdown":
    d.sharedState.options.incl roSupportMarkdown
    d.sharedState.options.incl roPreferMarkdown
  of "rstmarkdown":
    d.sharedState.options.incl roSupportMarkdown
    d.sharedState.options.excl roPreferMarkdown
  of "rst":
    d.sharedState.options.excl roSupportMarkdown
    d.sharedState.options.excl roPreferMarkdown
  else:
    localError(d.conf, n.info, errUser,
      (
        "unknown doctype value \"$1\", should be from " &
        "\"RST\", \"Markdown\", \"RstMarkdown\""
      ) % [dt]
    )

proc checkForFalse(n: PNode): bool =
  result = n.kind == nkIdent and cmpIgnoreStyle(n.ident.s, "false") == 0

proc traceDeps(d: PDoc, it: PNode) =
  const k = skModule
  if it.kind == nkInfix and it.len == 3 and it[2].kind == nkBracket:
    let sep = it[0]
    let dir = it[1]
    let a = newNodeI(nkInfix, it.info)
    a.add sep
    a.add dir
    a.add sep # dummy entry, replaced in the loop
    for x in it[2]:
      a[2] = x
      traceDeps(d, a)
  elif it.kind == nkSym and belongsToProjectPackage(d.conf, it.sym):
    let external = externalDep(d, it.sym)
    if d.section[k].finalMarkup != "": d.section[k].finalMarkup.add(", ")
    dispA(d.conf, d.section[k].finalMarkup,
          "<a class=\"reference external\" href=\"$2\">$1</a>",
          "$1", [esc(d.target, external.prettyLink),
                 changeFileExt(external, "html")])

proc exportSym(d: PDoc; s: PSym) =
  const k = exportSection
  if s.kind == skModule and belongsToProjectPackage(d.conf, s):
    let external = externalDep(d, s)
    if d.section[k].finalMarkup != "": d.section[k].finalMarkup.add(", ")
    dispA(d.conf, d.section[k].finalMarkup,
          "<a class=\"reference external\" href=\"$2\">$1</a>",
          "$1", [esc(d.target, external.prettyLink),
                 changeFileExt(external, "html")])
  elif s.kind != skModule and s.owner != nil:
    let module = originatingModule(s)
    if belongsToProjectPackage(d.conf, module):
      let
        complexSymbol = complexName(s.kind, s.ast, s.name.s)
        symbolOrId = d.newUniquePlainSymbol(complexSymbol)
        external = externalDep(d, module)
      if d.section[k].finalMarkup != "": d.section[k].finalMarkup.add(", ")
      # XXX proper anchor generation here
      dispA(d.conf, d.section[k].finalMarkup,
            "<a href=\"$2#$3\"><span class=\"Identifier\">$1</span></a>",
            "$1", [esc(d.target, s.name.s),
                   changeFileExt(external, "html"),
                   symbolOrId])

proc documentNewEffect(cache: IdentCache; n: PNode): PNode =
  let s = n[namePos].sym
  if tfReturnsNew in s.typ.flags:
    result = newIdentNode(getIdent(cache, "new"), n.info)
  else:
    result = nil

proc documentEffect(cache: IdentCache; n, x: PNode, effectType: TSpecialWord, idx: int): PNode =
  let spec = effectSpec(x, effectType)
  if isNil(spec):
    let s = n[namePos].sym

    let actual = s.typ.n[0]
    if actual.len != effectListLen: return
    let real = actual[idx]
    if real == nil: return
    let realLen = real.len
    # warning: hack ahead:
    var effects = newNodeI(nkBracket, n.info, realLen)
    for i in 0..<realLen:
      var t = typeToString(real[i].typ)
      if t.startsWith("ref "): t = substr(t, 4)
      effects[i] = newIdentNode(getIdent(cache, t), n.info)
      # set the type so that the following analysis doesn't screw up:
      effects[i].typ() = real[i].typ

    result = newTreeI(nkExprColonExpr, n.info,
      newIdentNode(getIdent(cache, $effectType), n.info), effects)
  else:
    result = nil

proc documentWriteEffect(cache: IdentCache; n: PNode; flag: TSymFlag; pragmaName: string): PNode =
  let s = n[namePos].sym
  let params = s.typ.n

  var effects = newNodeI(nkBracket, n.info)
  for i in 1..<params.len:
    if params[i].kind == nkSym and flag in params[i].sym.flags:
      effects.add params[i]

  if effects.len > 0:
    result = newTreeI(nkExprColonExpr, n.info,
      newIdentNode(getIdent(cache, pragmaName), n.info), effects)
  else:
    result = nil

proc documentRaises*(cache: IdentCache; n: PNode) =
  if n[namePos].kind != nkSym: return
  let pragmas = n[pragmasPos]
  let p1 = documentEffect(cache, n, pragmas, wRaises, exceptionEffects)
  let p2 = documentEffect(cache, n, pragmas, wTags, tagEffects)
  let p3 = documentWriteEffect(cache, n, sfWrittenTo, "writes")
  let p4 = documentNewEffect(cache, n)
  let p5 = documentWriteEffect(cache, n, sfEscapes, "escapes")
  let p6 = documentEffect(cache, n, pragmas, wForbids, forbiddenEffects)

  if p1 != nil or p2 != nil or p3 != nil or p4 != nil or p5 != nil or p6 != nil:
    if pragmas.kind == nkEmpty:
      n[pragmasPos] = newNodeI(nkPragma, n.info)
    if p1 != nil: n[pragmasPos].add p1
    if p2 != nil: n[pragmasPos].add p2
    if p3 != nil: n[pragmasPos].add p3
    if p4 != nil: n[pragmasPos].add p4
    if p5 != nil: n[pragmasPos].add p5
    if p6 != nil: n[pragmasPos].add p6

proc generateDoc*(d: PDoc, n, orig: PNode, config: ConfigRef, docFlags: DocFlags = kDefault) =
  ## Goes through nim nodes recursively and collects doc comments.
  ## Main function for `doc`:option: command,
  ## which is implemented in ``docgen2.nim``.
  template genItemAux(skind) =
    genItem(d, n, n[namePos], skind, docFlags)
  let showNonExports = optShowNonExportedFields in config.globalOptions
  case n.kind
  of nkPragma:
    let pragmaNode = findPragma(n, wDeprecated)
    d.modDeprecationMsg.add(genDeprecationMsg(d, pragmaNode))
    let doctypeNode = findPragma(n, wDoctype)
    setDoctype(d, doctypeNode)
  of nkCommentStmt: d.modDescPre.add(genComment(d, n))
  of nkProcDef, nkFuncDef:
    when useEffectSystem: documentRaises(d.cache, n)
    genItemAux(skProc)
  of nkMethodDef:
    when useEffectSystem: documentRaises(d.cache, n)
    genItemAux(skMethod)
  of nkIteratorDef:
    when useEffectSystem: documentRaises(d.cache, n)
    genItemAux(skIterator)
  of nkMacroDef: genItemAux(skMacro)
  of nkTemplateDef: genItemAux(skTemplate)
  of nkConverterDef:
    when useEffectSystem: documentRaises(d.cache, n)
    genItemAux(skConverter)
  of nkTypeSection, nkVarSection, nkLetSection, nkConstSection:
    for i in 0..<n.len:
      if n[i].kind != nkCommentStmt:
        # order is always 'type var let const':
        genItem(d, n[i], n[i][0],
                succ(skType, ord(n.kind)-ord(nkTypeSection)), docFlags, showNonExports)
  of nkStmtList:
    for i in 0..<n.len: generateDoc(d, n[i], orig, config)
  of nkWhenStmt:
    # generate documentation for the first branch only:
    if not checkForFalse(n[0][0]):
      generateDoc(d, lastSon(n[0]), orig, config)
  of nkImportStmt:
    for it in n: traceDeps(d, it)
  of nkExportStmt:
    for it in n:
      # bug #23051; don't generate documentation for exported symbols again
      if it.kind == nkSym and sfExported notin it.sym.flags:
        if d.module != nil and d.module == it.sym.owner:
          generateDoc(d, it.sym.ast, orig, config, kForceExport)
        elif it.sym.ast != nil:
          exportSym(d, it.sym)
  of nkExportExceptStmt: discard "transformed into nkExportStmt by semExportExcept"
  of nkFromStmt, nkImportExceptStmt: traceDeps(d, n[0])
  of nkCallKinds:
    var comm: ItemPre = default(ItemPre)
    getAllRunnableExamples(d, n, comm)
    if comm.len != 0: d.modDescPre.add(comm)
  else: discard

proc overloadGroupName(s: string, k: TSymKind): string =
  ## Turns a name like `f` into anchor `f-procs-all`
  s & "-" & k.toHumanStr & "s-all"

proc setIndexTitle(d: PDoc, useMetaTitle: bool) =
  let titleKind = if d.standaloneDoc: ieMarkupTitle else: ieNimTitle
  let external = AbsoluteFile(d.destFile)
    .relativeTo(d.conf.outDir, '/')
    .changeFileExt(HtmlExt)
    .string
  var term, linkTitle: string
  if useMetaTitle and d.meta[metaTitle].len != 0:
    term = d.meta[metaTitleRaw]
    linkTitle = d.meta[metaTitleRaw]
  else:
    let filename = extractFilename(d.filename)
    term =
      if d.standaloneDoc: filename  # keep .rst/.md extension
      else: changeFileExt(filename, "")  # rm .nim extension
    linkTitle =
      if d.standaloneDoc: term  # keep .rst/.md extension
      else: canonicalImport(d.conf, AbsoluteFile d.filename)
  if not d.standaloneDoc:
    linkTitle = "module " & linkTitle
  setIndexTerm(d[], titleKind, htmlFile = external, id = "",
               term = term, linkTitle = linkTitle)

proc finishGenerateDoc*(d: var PDoc) =
  ## Perform 2nd RST pass for resolution of links/footnotes/headings...
  # copy file map `filenames` to ``rstgen.nim`` for its warnings
  d.filenames = d.sharedState.filenames

  # Main title/subtitle are allowed only in the first RST fragment of document
  var firstRst = PRstNode(nil)
  for fragment in d.modDescPre:
    if fragment.isRst:
      firstRst = fragment.rst
      break
  d.hasToc = d.hasToc or d.sharedState.hasToc
  # in --index:only mode we do NOT want to load other .idx, only write ours:
  let importdoc = optGenIndexOnly notin d.conf.globalOptions and
                  optNoImportdoc notin d.conf.globalOptions
  preparePass2(d.sharedState, firstRst, importdoc)

  if optGenIndexOnly in d.conf.globalOptions:
    # Top-level doc.comments may contain titles and :idx: statements:
    for fragment in d.modDescPre:
      if fragment.isRst:
        traverseForIndex(d[], fragment.rst)
    setIndexTitle(d, useMetaTitle = d.standaloneDoc)
    # Symbol-associated doc.comments may contain :idx: statements:
    for k in TSymKind:
      for _, overloadChoices in d.section[k].secItems:
        for item in overloadChoices:
          for fragment in item.descRst:
            if fragment.isRst:
              traverseForIndex(d[], fragment.rst)

  # add anchors to overload groups before RST resolution
  for k in TSymKind:
    if k in routineKinds:
      for plainName, overloadChoices in d.section[k].secItems:
        if overloadChoices.len > 1:
          let refn = overloadGroupName(plainName, k)
          let tooltip = "$1 ($2 overloads)" % [
                      k.toHumanStr & " " & plainName, $overloadChoices.len]
          let name = nimIdentBackticksNormalize(plainName)
          # save overload group to ``.idx``
          let external = d.destFile.AbsoluteFile.relativeTo(d.conf.outDir, '/').
                         changeFileExt(HtmlExt).string
          setIndexTerm(d[], ieNimGroup, htmlFile = external, id = refn,
                       term = name, linkTitle = k.toHumanStr,
                       linkDesc = "", line = overloadChoices[0].info.line.int)
          if optGenIndexOnly in d.conf.globalOptions: continue
          addAnchorNim(d.sharedState, external=false, refn, tooltip,
                       LangSymbol(symKind: k.toHumanStr,
                                  name: name,
                                  isGroup: true),
                       priority = symbolPriority(k),
                       # select index `0` just to have any meaningful warning:
                       info = overloadChoices[0].info,
                       module = addRstFileIndex(d, FileIndex d.module.position))

  if optGenIndexOnly in d.conf.globalOptions:
    return

  # Finalize fragments of ``.nim`` or ``.rst`` file
  proc renderItemPre(d: PDoc, fragments: ItemPre, result: var string) =
    for f in fragments:
      case f.isRst:
      of true:
        var resolved = resolveSubs(d.sharedState, f.rst)
        renderRstToOut(d[], resolved, result)
      of false: result &= f.str
  proc cmp(x, y: Item): int = cmpDecimalsIgnoreCase(x.sortName, y.sortName)
  for k in TSymKind:
    # add symbols to section for each `k`, while optionally wrapping
    # overloadable items with the same basic name by ``doc.item2``
    let overloadableNames = toSeq(keys(d.section[k].secItems))
    for plainName in overloadableNames.sorted(cmpDecimalsIgnoreCase):
      var overloadChoices = d.section[k].secItems[plainName]
      overloadChoices.sort(cmp)
      var nameContent = ""
      for item in overloadChoices:
        var itemDesc: string = ""
        renderItemPre(d, item.descRst, itemDesc)
        nameContent.add(
          getConfigVar(d.conf, "doc.item") % (
              item.substitutions & @[
                "desc", itemDesc,
                "name", item.name,
                "itemSymOrID", item.anchor]))
      if k in routineKinds:
        let plainNameEsc1 = esc(d.target, plainName.strip)
        let plainNameEsc2 = esc(d.target, plainName.strip, escMode=emUrl)
        d.section[k].finalMarkup.add(
          getConfigVar(d.conf, "doc.item2") % (
            @["header_plain", plainNameEsc1,
              "overloadGroupName", overloadGroupName(plainNameEsc2, k),
              "content", nameContent]))
      else:
        d.section[k].finalMarkup.add(nameContent)
    d.section[k].secItems.clear
  renderItemPre(d, d.modDescPre, d.modDescFinal)
  d.modDescPre.setLen 0

  # Finalize fragments of ``.json`` file
  for i, entry in d.jEntriesPre:
    if entry.rst != nil:
      let resolved = resolveSubs(d.sharedState, entry.rst)
      var str: string = ""
      renderRstToOut(d[], resolved, str)
      entry.json[entry.rstField] = %str
      d.jEntriesPre[i].rst = nil

    d.jEntriesFinal.add entry.json # generates docs

  setIndexTitle(d, useMetaTitle = d.standaloneDoc)
  completePass2(d.sharedState)

proc add(d: PDoc; j: JsonItem) =
  if j.json != nil or j.rst != nil: d.jEntriesPre.add j

proc generateJson*(d: PDoc, n: PNode, config: ConfigRef, includeComments: bool = true) =
  case n.kind
  of nkPragma:
    let doctypeNode = findPragma(n, wDoctype)
    setDoctype(d, doctypeNode)
  of nkCommentStmt:
    if includeComments:
      d.add JsonItem(rst: genComment(d, n), rstField: "comment",
                     json: %Table[string, string]())
    else:
      d.modDescPre.add(genComment(d, n))
  of nkProcDef, nkFuncDef:
    when useEffectSystem: documentRaises(d.cache, n)
    d.add genJsonItem(d, n, n[namePos], skProc)
  of nkMethodDef:
    when useEffectSystem: documentRaises(d.cache, n)
    d.add genJsonItem(d, n, n[namePos], skMethod)
  of nkIteratorDef:
    when useEffectSystem: documentRaises(d.cache, n)
    d.add genJsonItem(d, n, n[namePos], skIterator)
  of nkMacroDef:
    d.add genJsonItem(d, n, n[namePos], skMacro)
  of nkTemplateDef:
    d.add genJsonItem(d, n, n[namePos], skTemplate)
  of nkConverterDef:
    when useEffectSystem: documentRaises(d.cache, n)
    d.add genJsonItem(d, n, n[namePos], skConverter)
  of nkTypeSection, nkVarSection, nkLetSection, nkConstSection:
    for i in 0..<n.len:
      if n[i].kind != nkCommentStmt:
        # order is always 'type var let const':
        d.add genJsonItem(d, n[i], n[i][0],
                succ(skType, ord(n.kind)-ord(nkTypeSection)), optShowNonExportedFields in config.globalOptions)
  of nkStmtList:
    for i in 0..<n.len:
      generateJson(d, n[i], config, includeComments)
  of nkWhenStmt:
    # generate documentation for the first branch only:
    if not checkForFalse(n[0][0]):
      generateJson(d, lastSon(n[0]), config, includeComments)
  else: discard

proc genTagsItem(d: PDoc, n, nameNode: PNode, k: TSymKind): string =
  result = getNameEsc(d, nameNode) & "\n"

proc generateTags*(d: PDoc, n: PNode, r: var string) =
  case n.kind
  of nkCommentStmt:
    if startsWith(n.comment, "##"):
      let stripped = n.comment.substr(2).strip
      r.add stripped
  of nkProcDef:
    when useEffectSystem: documentRaises(d.cache, n)
    r.add genTagsItem(d, n, n[namePos], skProc)
  of nkFuncDef:
    when useEffectSystem: documentRaises(d.cache, n)
    r.add genTagsItem(d, n, n[namePos], skFunc)
  of nkMethodDef:
    when useEffectSystem: documentRaises(d.cache, n)
    r.add genTagsItem(d, n, n[namePos], skMethod)
  of nkIteratorDef:
    when useEffectSystem: documentRaises(d.cache, n)
    r.add genTagsItem(d, n, n[namePos], skIterator)
  of nkMacroDef:
    r.add genTagsItem(d, n, n[namePos], skMacro)
  of nkTemplateDef:
    r.add genTagsItem(d, n, n[namePos], skTemplate)
  of nkConverterDef:
    when useEffectSystem: documentRaises(d.cache, n)
    r.add genTagsItem(d, n, n[namePos], skConverter)
  of nkTypeSection, nkVarSection, nkLetSection, nkConstSection:
    for i in 0..<n.len:
      if n[i].kind != nkCommentStmt:
        # order is always 'type var let const':
        r.add genTagsItem(d, n[i], n[i][0],
                succ(skType, ord(n.kind)-ord(nkTypeSection)))
  of nkStmtList:
    for i in 0..<n.len:
      generateTags(d, n[i], r)
  of nkWhenStmt:
    # generate documentation for the first branch only:
    if not checkForFalse(n[0][0]):
      generateTags(d, lastSon(n[0]), r)
  else: discard

proc genSection(d: PDoc, kind: TSymKind, groupedToc = false) =
  const sectionNames: array[skModule..skField, string] = [
    "Imports", "Types", "Vars", "Lets", "Consts", "Vars", "Procs", "Funcs",
    "Methods", "Iterators", "Converters", "Macros", "Templates", "Exports"
  ]
  if d.section[kind].finalMarkup == "": return
  var title = sectionNames[kind]
  d.section[kind].finalMarkup = getConfigVar(d.conf, "doc.section") % [
      "sectionid", $ord(kind), "sectionTitle", title,
      "sectionTitleID", $(ord(kind) + 50), "content", d.section[kind].finalMarkup]

  proc cmp(x, y: TocItem): int = cmpDecimalsIgnoreCase(x.sortName, y.sortName)
  if groupedToc:
    let overloadableNames = toSeq(keys(d.tocTable[kind]))
    for plainName in overloadableNames.sorted(cmpDecimalsIgnoreCase):
      var overloadChoices = d.tocTable[kind][plainName]
      overloadChoices.sort(cmp)
      var content: string = ""
      for item in overloadChoices:
        content.add item.content
      d.toc2[kind].add getConfigVar(d.conf, "doc.section.toc2") % [
          "sectionid", $ord(kind), "sectionTitle", title,
          "sectionTitleID", $(ord(kind) + 50),
          "content", content, "plainName", plainName]
  else:
    for item in d.tocSimple[kind].sorted(cmp):
      d.toc2[kind].add item.content

  let sectionValues = @[
     "sectionID", $ord(kind), "sectionTitleID", $(ord(kind) + 50),
     "sectionTitle", title
  ]

  # Check if the toc has any children
  if d.toc2[kind] != "":
    # Use the dropdown version instead and store the children in the dropdown
    d.toc[kind] = getConfigVar(d.conf, "doc.section.toc") % (sectionValues & @[
       "content", d.toc2[kind]
    ])
  else:
    # Just have the link
    d.toc[kind] =  getConfigVar(d.conf, "doc.section.toc_item") % sectionValues

proc relLink(outDir: AbsoluteDir, destFile: AbsoluteFile, linkto: RelativeFile): string =
  $relativeTo(outDir / linkto, destFile.splitFile().dir, '/')

proc genOutFile(d: PDoc, groupedToc = false): string =
  var
    code, content: string = ""
    title = ""
  var j = 0
  var toc = ""
  renderTocEntries(d[], j, 1, toc)
  for i in TSymKind:
    var shouldSort = i in routineKinds and groupedToc
    genSection(d, i, shouldSort)
    toc.add(d.toc[i])
  if toc != "" or d.target == outLatex:
    # for Latex $doc.toc will automatically generate TOC if `d.hasToc` is set
    toc = getConfigVar(d.conf, "doc.toc") % ["content", toc]
  for i in TSymKind: code.add(d.section[i].finalMarkup)

  # Extract the title. Non API modules generate an entry in the index table.
  if d.meta[metaTitle].len != 0:
    title = d.meta[metaTitle]
  else:
    title = canonicalImport(d.conf, AbsoluteFile d.filename)
  title = esc(d.target, title)
  var subtitle = ""
  if d.meta[metaSubtitle] != "":
    dispA(d.conf, subtitle, "<h2 class=\"subtitle\">$1</h2>",
        "\\\\\\vspace{0.5em}\\large $1", [esc(d.target, d.meta[metaSubtitle])])

  var groupsection = getConfigVar(d.conf, "doc.body_toc_groupsection")
  let bodyname = if d.hasToc and not d.standaloneDoc and not d.conf.isLatexCmd:
                   groupsection.setLen 0
                   "doc.body_toc_group"
                 elif d.hasToc: "doc.body_toc"
                 else: "doc.body_no_toc"
  let seeSrc = genSeeSrc(d, d.filename, 1)
  content = getConfigVar(d.conf, bodyname) % [
      "title", title, "subtitle", subtitle,
      "tableofcontents", toc, "moduledesc", d.modDescFinal, "date", getDateStr(),
      "time", getClockStr(), "content", code,
      "deprecationMsg", d.modDeprecationMsg,
      "theindexhref", relLink(d.conf.outDir, d.destFile.AbsoluteFile,
                              theindexFname.RelativeFile),
      "body_toc_groupsection", groupsection, "seeSrc", seeSrc]
  if optCompileOnly notin d.conf.globalOptions:
    # XXX what is this hack doing here? 'optCompileOnly' means raw output!?
    code = getConfigVar(d.conf, "doc.file") % [
        "nimdoccss", relLink(d.conf.outDir, d.destFile.AbsoluteFile,
                             nimdocOutCss.RelativeFile),
        "dochackjs", relLink(d.conf.outDir, d.destFile.AbsoluteFile,
                             docHackJsFname.RelativeFile),
        "title", title, "subtitle", subtitle, "tableofcontents", toc,
        "moduledesc", d.modDescFinal, "date", getDateStr(), "time", getClockStr(),
        "content", content, "author", d.meta[metaAuthor],
        "version", esc(d.target, d.meta[metaVersion]), "analytics", d.analytics,
        "deprecationMsg", d.modDeprecationMsg, "nimVersion", $NimMajor & "." & $NimMinor & "." & $NimPatch]
  else:
    code = content
  result = code

proc indexFile(d: PDoc): AbsoluteFile =
  let dir = d.conf.outDir
  result = dir / changeFileExt(presentationPath(d.conf,
                                                AbsoluteFile d.filename),
                               IndexExt)
  let (finalDir, _, _) = result.string.splitFile
  createDir(finalDir)

proc generateIndex*(d: PDoc) =
  if optGenIndex in d.conf.globalOptions:
    let dest = indexFile(d)
    writeIndexFile(d[], dest.string)

proc updateOutfile(d: PDoc, outfile: AbsoluteFile) =
  if d.module == nil or sfMainModule in d.module.flags: # nil for e.g. for commandRst2Html
    if d.conf.outFile.isEmpty:
      d.conf.outFile = outfile.relativeTo(d.conf.outDir)
      if isAbsolute(d.conf.outFile.string):
        d.conf.outFile = splitPath(d.conf.outFile.string)[1].RelativeFile

proc writeOutput*(d: PDoc, useWarning = false, groupedToc = false) =
  if optGenIndexOnly in d.conf.globalOptions:
    d.conf.outFile = indexFile(d).relativeTo(d.conf.outDir)  # just for display
    return
  runAllExamples(d)
  var content = genOutFile(d, groupedToc)
  if optStdout in d.conf.globalOptions:
    write(stdout, content)
  else:
    template outfile: untyped = d.destFile.AbsoluteFile
    #let outfile = getOutFile2(d.conf, shortenDir(d.conf, filename), outExt)
    let dir = outfile.splitFile.dir
    createDir(dir)
    updateOutfile(d, outfile)
    try:
      writeFile(outfile, content)
    except IOError:
      rawMessage(d.conf, if useWarning: warnCannotOpenFile else: errCannotOpenFile,
        outfile.string)
    if not d.wroteSupportFiles: # nimdoc.css + dochack.js
      let nimr = $d.conf.getPrefixDir()
      case d.target
      of outHtml:
        copyFile(docCss.interp(nimr = nimr), $d.conf.outDir / nimdocOutCss)
      of outLatex:
        copyFile(docCls.interp(nimr = nimr), $d.conf.outDir / nimdocOutCls)
      if optGenIndex in d.conf.globalOptions:
        let docHackJs2 = getDocHacksJs(nimr, nim = getAppFilename())
        copyFile(docHackJs2, $d.conf.outDir / docHackJs2.lastPathPart)
      d.wroteSupportFiles = true

proc writeOutputJson*(d: PDoc, useWarning = false) =
  runAllExamples(d)
  var modDesc: string = ""
  for desc in d.modDescFinal:
    modDesc &= desc
  let content = %*{"orig": d.filename,
    "nimble": getPackageName(d.conf, d.filename),
    "moduleDescription": modDesc,
    "entries": d.jEntriesFinal}
  if optStdout in d.conf.globalOptions:
    writeLine(stdout, $content)
  else:
    let dir = d.destFile.splitFile.dir
    createDir(dir)
    var f: File = default(File)
    if open(f, d.destFile, fmWrite):
      write(f, $content)
      close(f)
      updateOutfile(d, d.destFile.AbsoluteFile)
    else:
      localError(d.conf, newLineInfo(d.conf, AbsoluteFile d.filename, -1, -1),
                 warnUser, "unable to open file \"" & d.destFile &
                 "\" for writing")

proc handleDocOutputOptions*(conf: ConfigRef) =
  if optWholeProject in conf.globalOptions:
    # Backward compatibility with previous versions
    # xxx this is buggy when user provides `nim doc --project -o:sub/bar.html main`,
    # it'd write to `sub/bar.html/main.html`
    conf.outDir = AbsoluteDir(conf.outDir / conf.outFile)

proc commandDoc*(cache: IdentCache, conf: ConfigRef) =
  ## implementation of deprecated ``doc0`` command (without semantic checking)
  handleDocOutputOptions conf
  var ast = parseFile(conf.projectMainIdx, cache, conf)
  if ast == nil: return
  var d = newDocumentor(conf.projectFull, cache, conf, hasToc = true)
  generateDoc(d, ast, ast, conf)
  finishGenerateDoc(d)
  writeOutput(d)
  generateIndex(d)

proc commandRstAux(cache: IdentCache, conf: ConfigRef;
                   filename: AbsoluteFile, outExt: string,
                   preferMarkdown: bool) =
  var filen = addFileExt(filename, "txt")
  var d = newDocumentor(filen, cache, conf, outExt, standaloneDoc = true,
                        preferMarkdown = preferMarkdown, hasToc = false)
  try:
    let rst = parseRst(readFile(filen.string),
                      line=LineRstInit, column=ColRstInit,
                      conf, d.sharedState)
    d.modDescPre = @[ItemFragment(isRst: true, rst: rst)]
    finishGenerateDoc(d)
    writeOutput(d)
    generateIndex(d)
  except ERecoverableError:
    discard "already reported the error"

proc commandRst2Html*(cache: IdentCache, conf: ConfigRef,
                      preferMarkdown=false) =
  commandRstAux(cache, conf, conf.projectFull, HtmlExt, preferMarkdown)

proc commandRst2TeX*(cache: IdentCache, conf: ConfigRef,
                     preferMarkdown=false) =
  commandRstAux(cache, conf, conf.projectFull, TexExt, preferMarkdown)

proc commandJson*(cache: IdentCache, conf: ConfigRef) =
  ## implementation of a deprecated jsondoc0 command
  var ast = parseFile(conf.projectMainIdx, cache, conf)
  if ast == nil: return
  var d = newDocumentor(conf.projectFull, cache, conf, hasToc = true)
  d.onTestSnippet = proc (d: var RstGenerator; filename, cmd: string;
                          status: int; content: string) {.gcsafe.} =
    localError(conf, newLineInfo(conf, AbsoluteFile d.filename, -1, -1),
               warnUser, "the ':test:' attribute is not supported by this backend")
  generateJson(d, ast, conf)
  finishGenerateDoc(d)
  let json = d.jEntriesFinal
  let content = pretty(json)

  if optStdout in d.conf.globalOptions:
    write(stdout, content)
  else:
    #echo getOutFile(gProjectFull, JsonExt)
    let filename = getOutFile(conf, RelativeFile conf.projectName, JsonExt)
    try:
      writeFile(filename, content)
    except IOError:
      rawMessage(conf, errCannotOpenFile, filename.string)

proc commandTags*(cache: IdentCache, conf: ConfigRef) =
  var ast = parseFile(conf.projectMainIdx, cache, conf)
  if ast == nil: return
  var d = newDocumentor(conf.projectFull, cache, conf, hasToc = true)
  d.onTestSnippet = proc (d: var RstGenerator; filename, cmd: string;
                          status: int; content: string) {.gcsafe.} =
    localError(conf, newLineInfo(conf, AbsoluteFile d.filename, -1, -1),
               warnUser, "the ':test:' attribute is not supported by this backend")
  var
    content = ""
  generateTags(d, ast, content)

  if optStdout in d.conf.globalOptions:
    write(stdout, content)
  else:
    #echo getOutFile(gProjectFull, TagsExt)
    let filename = getOutFile(conf, RelativeFile conf.projectName, TagsExt)
    try:
      writeFile(filename, content)
    except IOError:
      rawMessage(conf, errCannotOpenFile, filename.string)

proc commandBuildIndex*(conf: ConfigRef, dir: string, outFile = RelativeFile"") =
  if optGenIndexOnly in conf.globalOptions:
    return
  var content = mergeIndexes(dir)

  var outFile = outFile
  if outFile.isEmpty: outFile = theindexFname.RelativeFile.changeFileExt("")
  let filename = getOutFile(conf, outFile, HtmlExt)

  let code = getConfigVar(conf, "doc.file") % [
      "nimdoccss", relLink(conf.outDir, filename, nimdocOutCss.RelativeFile),
      "dochackjs", relLink(conf.outDir, filename, docHackJsFname.RelativeFile),
      "title", "Index",
      "subtitle", "", "tableofcontents", "", "moduledesc", "",
      "date", getDateStr(), "time", getClockStr(),
      "content", content, "author", "", "version", "", "analytics", "", "nimVersion", $NimMajor & "." & $NimMinor & "." & $NimPatch]
  # no analytics because context is not available

  try:
    writeFile(filename, code)
  except IOError:
    rawMessage(conf, errCannotOpenFile, filename.string)

proc commandBuildIndexJson*(conf: ConfigRef, dir: string, outFile = RelativeFile"") =
  var (modules, symbols, docs) = readIndexDir(dir)
  let documents = toSeq(keys(Table[IndexEntry, seq[IndexEntry]](docs)))
  let body = %*({"documents": documents, "modules": modules, "symbols": symbols})

  var outFile = outFile
  if outFile.isEmpty: outFile = theindexFname.RelativeFile.changeFileExt("")
  let filename = getOutFile(conf, outFile, JsonExt)

  try:
    writeFile(filename, $body)
  except IOError:
    rawMessage(conf, errCannotOpenFile, filename.string)
