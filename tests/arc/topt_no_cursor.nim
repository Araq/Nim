discard """
  nimoutFull: true
  cmd: '''nim c -r --warnings:off --hints:off --mm:arc --expandArc:newTarget --expandArc:delete --expandArc:p1 --expandArc:tt --hint:Performance:off --assertions:off --expandArc:extractConfig --expandArc:mergeShadowScope --expandArc:check $file'''
  nimout: '''
--expandArc: newTarget

var
  splat
  :tmp
  :tmp_1
splat = splitDrive do:
  let blitTmp = path
  blitTmp
:tmp = splat.drive
`=wasMoved`(splat.drive)
:tmp_1 = splat.path_1
`=wasMoved`(splat.path_1)
result = (
  let blitTmp_1 = :tmp
  blitTmp_1,
  let blitTmp_2 = :tmp_1
  blitTmp_2)
`=destroy`(splat)
-- end of expandArc ------------------------
--expandArc: delete

var
  sibling
  saved
`=copy`(sibling, target.parent.left)
`=copy`(saved, sibling.right)
`=copy`(sibling.right, saved.left)
`=sink`(sibling.parent, saved)
`=destroy`(sibling)
-- end of expandArc ------------------------
--expandArc: p1

var
  lresult
  lvalue
  lnext
  tmpTupleAsgn
result = default(Maybe)
lresult = @[123]
tmpTupleAsgn = (
  let blitTmp = lresult
  blitTmp, ";")
lvalue = tmpTupleAsgn[0]
lnext = tmpTupleAsgn[1]
`=sink`(result.value, move lvalue)
`=destroy`(lnext)
`=destroy_1`(lvalue)
-- end of expandArc ------------------------
--expandArc: tt

var
  it_cursor
  a
  :tmpD
  :tmpD_1
  :tmpD_2
try:
  it_cursor = x
  a = (
    :tmpD = `=dup`(it_cursor.key)
    :tmpD,
    :tmpD_1 = `=dup`(it_cursor.val)
    :tmpD_1)
  echo [
    :tmpD_2 = `$$`(a)
    :tmpD_2]
finally:
  `=destroy`(:tmpD_2)
  `=destroy_1`(a)
-- end of expandArc ------------------------
--expandArc: extractConfig

var lan_ip
try:
  lan_ip = ""
  block :tmp:
    var line
    var i = 0
    let L = len(txt)
    block :tmp_1:
      while i < L:
        var splitted
        try:
          line = txt[i]
          splitted = split(line, " ", -1)
          if splitted[0] == "opt":
            `=copy`(lan_ip, splitted[1])
          echo [lan_ip]
          echo [splitted[1]]
          {.push, overflowChecks: false.}
          inc(i, 1)
          {.pop.}
        finally:
          `=destroy`(splitted)
finally:
  `=destroy_1`(lan_ip)
-- end of expandArc ------------------------
--expandArc: mergeShadowScope

var shadowScope
`=copy`(shadowScope, c.currentScope)
rawCloseScope(c)
block :tmp:
  var sym
  var i = 0
  let L = len(shadowScope.symbols)
  block :tmp_1:
    while i < L:
      var :tmpD
      sym = shadowScope.symbols[i]
      addInterfaceDecl(c):
        :tmpD = `=dup`(sym)
        :tmpD
      {.push, overflowChecks: false.}
      inc(i, 1)
      {.pop.}
`=destroy`(shadowScope)
-- end of expandArc ------------------------
--expandArc: check

var par
this.isValid = fileExists(this.value)
if dirExists(this.value):
  var :tmpD
  par = (dir:
    :tmpD = `=dup`(this.value)
    :tmpD, front: "") else:
  var
    :tmpD_1
    :tmpD_2
    :tmpD_3
  par = (dir_1: parentDir(this.value), front_1:
    :tmpD_1 = `=dup`(
      :tmpD_3 = splitDrive do:
        :tmpD_2 = `=dup`(this.value)
        :tmpD_2
      :tmpD_3.path)
    :tmpD_1)
  `=destroy`(:tmpD_3)
if dirExists(par.dir):
  `=sink`(this.matchDirs, getSubDirs(par.dir, par.front))
else:
  `=sink`(this.matchDirs, [])
`=destroy`(par)
-- end of expandArc ------------------------
--expandArc: check

check(this)
-- end of expandArc ------------------------
(package: "", ext: "meo")
doing shady stuff...
3
6
(@[1], @[2])
192.168.0.1
192.168.0.1
192.168.0.1
192.168.0.1
'''
"""

import os, std/private/ntpath

type Target = tuple[package, ext: string]

proc newTarget*(path: string): Target =
  let splat = path.splitDrive
  result = (package: splat.drive, ext: splat.path)

echo newTarget("meo")

type
  Node = ref object
    left, right, parent: Node
    value: int

proc delete(target: var Node) =
  var sibling = target.parent.left # b3
  var saved = sibling.right # b3.right -> r4

  sibling.right = saved.left # b3.right -> r4.left = nil
  sibling.parent = saved # b3.parent -> r5 = r4

  #[after this proc:
        b 5
      /   \
    b 3     b 6
  ]#


#[before:
      r 5
    /   \
  b 3    b 6 - to delete
  /    \
empty  r 4
]#
proc main =
  var five = Node(value: 5)

  var six = Node(value: 6)
  six.parent = five
  five.right = six

  var three = Node(value: 3)
  three.parent = five
  five.left = three

  var four = Node(value: 4)
  four.parent = three
  three.right = four

  echo "doing shady stuff..."
  delete(six)
  # need both of these echos
  echo five.left.value
  echo five.right.value

main()

type
  Maybe = object
    value: seq[int]

proc p1(): Maybe =
  result = default(Maybe)
  let lresult = @[123]
  var lvalue: seq[int]
  var lnext: string
  (lvalue, lnext) = (lresult, ";")

  result.value = move lvalue

proc tissue15130 =
  doAssert p1().value == @[123]

tissue15130()

type
  KeyValue = tuple[key, val: seq[int]]

proc tt(x: KeyValue) =
  var it = x
  let a = (it.key, it.val)
  echo a

proc encodedQuery =
  var query: seq[KeyValue] = @[]
  query.add (key: @[1], val: @[2])

  for elem in query:
    elem.tt()

encodedQuery()

# bug #15147

proc s(input: string): (string, string) =
  result = (";", "")

proc charmatch(input: string): (string, string) =
  result = ("123", input[0 .. input.high])

proc plus(input: string) =
  var
    lvalue, rvalue: string # cursors
    lnext: string # must be cursor!!!
    rnext: string # cursor
  let lresult = charmatch(input)
  (lvalue, lnext) = lresult

  let rresult = s(lnext)
  (rvalue, rnext) = rresult

plus("123;")

func substrEq(s: string, pos: int, substr: string): bool =
  var i = 0
  var length = substr.len
  while i < length and pos+i < s.len and s[pos+i] == substr[i]:
    inc i
  return i == length

template stringHasSep(s: string, index: int, sep: string): bool =
  s.substrEq(index, sep)

template splitCommon(s, sep, maxsplit, sepLen) =
  var last = 0
  var splits = maxsplit

  while last <= len(s):
    var first = last
    while last < len(s) and not stringHasSep(s, last, sep):
      inc(last)
    if splits == 0: last = len(s)
    yield substr(s, first, last-1)
    if splits == 0: break
    dec(splits)
    inc(last, sepLen)

iterator split(s: string, sep: string, maxsplit = -1): string =
  splitCommon(s, sep, maxsplit, sep.len)

template accResult(iter: untyped) =
  result = @[]
  for x in iter: add(result, x)

func split*(s: string, sep: string, maxsplit = -1): seq[string] =
  accResult(split(s, sep, maxsplit))


let txt = @["opt 192.168.0.1", "static_lease 192.168.0.1"]

# bug #17033

proc extractConfig() =
  var lan_ip = ""

  for line in txt:
    let splitted = line.split(" ")
    if splitted[0] == "opt":
      lan_ip = splitted[1] # "borrow" is conditional and inside a loop.
      # Not good enough...
      # we need a flag that live-ranges are disjoint
    echo lan_ip
    echo splitted[1] # Without this line everything works

extractConfig()


type
  Symbol = ref object
    name: string

  Scope = ref object
    parent: Scope
    symbols: seq[Symbol]

  PContext = ref object
    currentScope: Scope

proc rawCloseScope(c: PContext) =
  c.currentScope = c.currentScope.parent

proc addInterfaceDecl(c: PContext; s: Symbol) =
  c.currentScope.symbols.add s

proc mergeShadowScope*(c: PContext) =
  let shadowScope = c.currentScope
  c.rawCloseScope
  for sym in shadowScope.symbols:
    c.addInterfaceDecl(sym)

mergeShadowScope(PContext(currentScope: Scope(parent: Scope())))

type
  Foo = ref object
    isValid*: bool
    value*: string
    matchDirs*: seq[string]

proc getSubDirs(parent, front: string): seq[string] = @[]

method check(this: Foo) {.base.} =
  this.isValid = fileExists(this.value)
  let par = if dirExists(this.value): (dir: this.value, front: "")
            else: (dir: parentDir(this.value), front: splitDrive(this.value).path)
  if dirExists(par.dir):
    this.matchDirs = getSubDirs(par.dir, par.front)
  else:
    this.matchDirs = @[]

check(Foo())
