import dom
import fuzzysearch
import std/[jsfetch, asyncjs]


proc setTheme(theme: cstring) {.exportc.} =
  document.documentElement.setAttribute("data-theme", theme)
  window.localStorage.setItem("theme", theme)

# set `data-theme` attribute early to prevent white flash
setTheme:
  let t = window.localStorage.getItem("theme")
  if t.isNil: cstring"auto" else: t

proc onDOMLoaded(e: Event) {.exportc.} =
  # set theme select value
  document.getElementById("theme-select").value = window.localStorage.getItem("theme")

  for pragmaDots in document.getElementsByClassName("pragmadots"):
    pragmaDots.onclick = proc (event: Event) =
      # Hide tease
      event.target.parentNode.style.display = "none"
      # Show actual
      event.target.parentNode.nextSibling.style.display = "inline"


proc tree(tag: cstring; kids: varargs[Element]): Element =
  result = document.createElement tag
  for k in kids:
    result.appendChild k

proc add(parent, kid: Element) =
  if parent.nodeName == "TR" and (kid.nodeName == "TD" or kid.nodeName == "TH"):
    let k = document.createElement("TD")
    appendChild(k, kid)
    appendChild(parent, k)
  else:
    appendChild(parent, kid)

proc setClass(e: Element; value: cstring) =
  e.setAttribute("class", value)
proc text(s: cstring): Element = cast[Element](document.createTextNode(s))

proc replaceById(id: cstring; newTree: Node) =
  let x = document.getElementById(id)
  x.parentNode.replaceChild(newTree, x)
  newTree.id = id

proc clone(e: Element): Element {.importcpp: "#.cloneNode(true)", nodecl.}
proc markElement(x: Element) {.importcpp: "#.__karaxMarker__ = true", nodecl.}
proc isMarked(x: Element): bool {.
  importcpp: "#.hasOwnProperty('__karaxMarker__')", nodecl.}
proc title(x: Element): cstring {.importcpp: "#.title", nodecl.}

proc sort[T](x: var openArray[T]; cmp: proc(a, b: T): int) {.importcpp:
  "#.sort(#)", nodecl.}

proc extractItems(x: Element; items: var seq[Element]) =
  if x == nil: return
  if x.nodeName == "A":
    items.add x
  else:
    for i in 0..<x.len:
      extractItems(x[i], items)

# HTML trees are so shitty we transform the TOC into a decent
# data-structure instead and work on that.
type
  TocEntry = ref object
    heading: Element
    kids: seq[TocEntry]
    sortId: int
    doSort: bool

proc extractItems(x: TocEntry; heading: cstring; items: var seq[Element]) =
  if x == nil: return
  if x.heading != nil and x.heading.textContent == heading:
    for i in 0..<x.kids.len:
      items.add x.kids[i].heading
  else:
    for k in x.kids:
      extractItems(k, heading, items)

proc toHtml(x: TocEntry; isRoot=false): Element =
  if x == nil: return nil
  if x.kids.len == 0:
    if x.heading == nil: return nil
    return x.heading.clone
  result = tree("DIV")
  if x.heading != nil and not isMarked(x.heading):
    result.add x.heading.clone
  let ul = tree("UL")
  if isRoot:
    ul.setClass("simple simple-toc")
  else:
    ul.setClass("simple")
  if x.dosort:
    x.kids.sort(proc(a, b: TocEntry): int =
      if a.heading != nil and b.heading != nil:
        let x = a.heading.textContent
        let y = b.heading.textContent
        if x < y: return -1
        if x > y: return 1
        return 0
      else:
        # ensure sorting is stable:
        return a.sortId - b.sortId
    )
  for k in x.kids:
    let y = toHtml(k)
    if y != nil:
      ul.add tree("LI", y)
  if ul.len != 0: result.add ul
  if result.len == 0: result = nil

proc isWhitespace(text: cstring): bool {.importcpp: r"!/\S/.test(#)".}

proc isWhitespace(x: Element): bool =
  x.nodeName == "#text" and x.textContent.isWhitespace or x.nodeName == "#comment"

proc toToc(x: Element; father: TocEntry) =
  if x.nodeName == "UL":
    let f = TocEntry(heading: nil, kids: @[], sortId: father.kids.len)
    var i = 0
    while i < x.len:
      var nxt = i+1
      while nxt < x.len and x[nxt].isWhitespace:
        inc nxt
      if nxt < x.len and x[i].nodeName == "LI" and x[i].len == 1 and
          x[nxt].nodeName == "UL":
        let e = TocEntry(heading: x[i][0], kids: @[], sortId: f.kids.len)
        let it = x[nxt]
        for j in 0..<it.len:
          toToc(it[j], e)
        f.kids.add e
        i = nxt+1
      else:
        toToc(x[i], f)
        inc i
    father.kids.add f
  elif isWhitespace(x):
    discard
  elif x.nodeName == "LI":
    var idx: seq[int] = @[]
    for i in 0 ..< x.len:
      if not x[i].isWhitespace: idx.add i
    if idx.len == 2 and x[idx[1]].nodeName == "UL":
      let e = TocEntry(heading: x[idx[0]], kids: @[], sortId: father.kids.len)
      let it = x[idx[1]]
      for j in 0..<it.len:
        toToc(it[j], e)
      father.kids.add e
    else:
      for i in 0..<x.len:
        toToc(x[i], father)
  else:
    father.kids.add TocEntry(heading: x, kids: @[], sortId: father.kids.len)

proc tocul(x: Element): Element =
  # x is a 'ul' element
  result = tree("UL")
  for i in 0..<x.len:
    let it = x[i]
    if it.nodeName == "LI":
      result.add it.clone
    elif it.nodeName == "UL":
      result.add tocul(it)

proc uncovered(x: TocEntry): TocEntry =
  if x.kids.len == 0 and x.heading != nil:
    return if not isMarked(x.heading): x else: nil
  result = TocEntry(heading: x.heading, kids: @[], sortId: x.sortId,
                    doSort: x.doSort)
  for k in x.kids:
    let y = uncovered(k)
    if y != nil: result.kids.add y
  if result.kids.len == 0: result = nil

proc mergeTocs(orig, news: TocEntry): TocEntry =
  result = uncovered(orig)
  if result == nil:
    result = news
  else:
    for i in 0..<news.kids.len:
      result.kids.add news.kids[i]

proc buildToc(orig: TocEntry; types, procs: seq[Element]): TocEntry =
  var newStuff = TocEntry(heading: nil, kids: @[], doSort: true)
  for t in types:
    let c = TocEntry(heading: t.clone, kids: @[], doSort: true)
    t.markElement()
    for p in procs:
      if not isMarked(p):
        let xx = getElementsByClass(p.parentNode, "attachedType")
        if xx.len == 1 and xx[0].textContent == t.textContent:
          let q = tree("A", text(p.title))
          q.setAttr("href", p.getAttribute("href"))
          c.kids.add TocEntry(heading: q, kids: @[])
          p.markElement()
    newStuff.kids.add c
  result = mergeTocs(orig, newStuff)

var alternative: Element

proc togglevis(d: Element) =
  if d.style.display == "none":
    d.style.display = "inline"
  else:
    d.style.display = "none"

proc groupBy*(value: cstring) {.exportc.} =
  let toc = document.getElementById("toc-list")
  if alternative.isNil:
    var tt = TocEntry(heading: nil, kids: @[])
    toToc(toc, tt)
    tt = tt.kids[0]

    var types: seq[Element] = @[]
    var procs: seq[Element] = @[]

    extractItems(tt, "Types", types)
    extractItems(tt, "Procs", procs)
    extractItems(tt, "Converters", procs)
    extractItems(tt, "Methods", procs)
    extractItems(tt, "Templates", procs)
    extractItems(tt, "Macros", procs)
    extractItems(tt, "Iterators", procs)

    let ntoc = buildToc(tt, types, procs)
    let x = toHtml(ntoc, isRoot=true)
    alternative = tree("DIV", x)
  if value == "type":
    replaceById("tocRoot", alternative)
  else:
    replaceById("tocRoot", tree("DIV"))
  togglevis(document.getElementById"toc-list")

var
  db: seq[Node]
  contents: seq[cstring]


proc escapeCString(x: var cstring) =
  # Original strings are already escaped except HTML tags, so
  # we only escape `<` and `>`.
  var s = ""
  for c in x:
    case c
    of '<': s.add("&lt;")
    of '>': s.add("&gt;")
    else: s.add(c)
  x = s.cstring

proc dosearch(value: cstring): Element =
  if db.len == 0:
    return
  let ul = tree("UL")
  result = tree("DIV")
  result.setClass"search_results"
  var matches: seq[(Node, int)] = @[]
  for i in 0..<db.len:
    let c = contents[i]
    if c == "Examples" or c == "PEG construction":
    # Some manual exclusions.
    # Ideally these should be fixed in the index to be more
    # descriptive of what they are.
      continue
    let (score, matched) = fuzzymatch(value, c)
    if matched:
      matches.add((db[i], score))

  matches.sort(proc(a, b: auto): int = b[1] - a[1])
  for i in 0 ..< min(matches.len, 29):
    matches[i][0].innerHTML = matches[i][0].getAttribute("data-doc-search-tag")
    escapeCString(matches[i][0].innerHTML)
    ul.add(tree("LI", cast[Element](matches[i][0])))
  if ul.len == 0:
    result.add tree("B", text"no search results")
  else:
    result.add tree("B", text"search results")
    result.add ul

proc loadIndex() {.async.} =
  ## Loads theindex.html to enable searching
  let
    indexURL = document.getElementById("indexLink").getAttribute("href")
    # Get root of project documentation by cutting off theindex.html from index href
    rootURL = ($indexURL)[0 ..< ^"theindex.html".len]
  var resp = fetch(indexURL).await().text().await()
  # Convert into element so we can use DOM functions to parse the html
  var indexElem = document.createElement("div")
  indexElem.innerHtml = resp
  # Add items into the DB/contents
  for href in indexElem.getElementsByClass("reference"):
    # Make links be relative to project root instead of current page
    href.setAttr("href", cstring(rootURL & $href.getAttribute("href")))
    db &= href
    contents &= href.getAttribute("data-doc-search-tag")


var
  oldtoc: Element
  timer: Timeout
  loadIndexFut: Future[void] = nil

proc hideSearch() =
  ## hides the search results element
  # If its nil, then results haven't been shown anyways
  if not oldToc.isNil:
    replaceById("tocRoot", oldToc)

proc runSearch() =
  ## Runs a search and shows the results in the page
  let elem = document.getElementById("searchInput")
  let value = elem.value
  if value != "":
    if oldtoc.isNil:
      oldtoc = document.getElementById("tocRoot")
    let results = dosearch(value)
    replaceById("tocRoot", results)
  else:
    hideSearch()

proc search*() {.exportc.} =
  # Start loading index as soon as user starts typing.
  # Will only be loaded the once anyways
  if loadIndexFut == nil:
    loadIndexFut = loadIndex()
    # Run wrapper once loaded so we don't miss the users query
    discard loadIndexFut.then(runSearch)
  if timer != nil: clearTimeout(timer)
  timer = setTimeout(runSearch, 400)

# Register `/` hotkey to jump to search
window.addEventListener("keypress") do (e: Event):
  if KeyboardEvent(e).key == "/":
    e.preventDefault()
    let searchElem = document.getElementById("searchInput")
    searchElem.focus()
    searchElem.parentElement.scrollIntoView()

    # Run search, so results are shown again if user is jumping back to
    # a partial search
    runSearch()

# Hide the search results when we jump around the page so we can read the page
window.addEventListener("hashchange") do (e: Event):
  hideSearch()

proc copyToClipboard*() {.exportc.} =
    {.emit: """

    function updatePreTags() {

      const allPreTags = document.querySelectorAll("pre:not(.line-nums)")

      allPreTags.forEach((e) => {

          const div = document.createElement("div")
          div.classList.add("copyToClipBoard")

          const preTag = document.createElement("pre")
          preTag.innerHTML = e.innerHTML

          const button = document.createElement("button")
          button.value = e.textContent.replace('...', '')
          button.classList.add("copyToClipBoardBtn")
          button.style.cursor = "pointer"

          div.appendChild(preTag)
          div.appendChild(button)

          e.outerHTML = div.outerHTML

      })
    }


    function copyTextToClipboard(e) {
        const clipBoardContent = e.target.value
        navigator.clipboard.writeText(clipBoardContent).then(function() {
            e.target.style.setProperty("--clipboard-image", "var(--clipboard-image-selected)")
        }, function(err) {
            console.error("Could not copy text: ", err);
        });
    }

    window.addEventListener("click", (e) => {
        if (e.target.classList.contains("copyToClipBoardBtn")) {
            copyTextToClipboard(e)
          }
    })

    window.addEventListener("mouseover", (e) => {
        if (e.target.nodeName === "PRE") {
            e.target.nextElementSibling.style.setProperty("--clipboard-image", "var(--clipboard-image-normal)")
        }
    })

    window.addEventListener("DOMContentLoaded", updatePreTags)

    """
    .}

copyToClipboard()
window.addEventListener("DOMContentLoaded", onDOMLoaded)
