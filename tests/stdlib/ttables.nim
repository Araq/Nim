discard """
  matrix: "--mm:refc; --mm:orc"
"""

import tables, hashes
import std/assertions

type
  Person = object
    firstName, lastName: string

proc hash(x: Person): Hash =
  ## Piggyback on the already available string hash proc.
  ##
  ## Without this proc nothing works!
  result = x.firstName.hash !& x.lastName.hash
  result = !$result

var
  salaries = initTable[Person, int]()
  p1, p2: Person
p1.firstName = "Jon"
p1.lastName = "Ross"
salaries[p1] = 30_000
p2.firstName = "소진"
p2.lastName = "박"
salaries[p2] = 45_000
var
  s2 = initOrderedTable[Person, int]()
  s3 = initCountTable[Person]()
s2[p1] = 30_000
s2[p2] = 45_000
s3[p1] = 30_000
s3[p2] = 45_000

block: # Ordered table should preserve order after deletion
  var
    s4 = initOrderedTable[int, int]()
  s4[1] = 1
  s4[2] = 2
  s4[3] = 3

  var prev = 0
  for i in s4.values:
    doAssert(prev < i)
    prev = i

  s4.del(2)
  doAssert(2 notin s4)
  doAssert(s4.len == 2)
  prev = 0
  for i in s4.values:
    doAssert(prev < i)
    prev = i

block: # Deletion from OrderedTable should account for collision groups. See issue #5057.
  # The bug is reproducible only with exact keys
  const key1 = "boy_jackpot.inGamma"
  const key2 = "boy_jackpot.outBlack"

  var t = {
      key1: 0,
      key2: 0
  }.toOrderedTable()

  t.del(key1)
  doAssert(t.len == 1)
  doAssert(key2 in t)

var
  t1 = initCountTable[string]()
  t2 = initCountTable[string]()
t1.inc("foo")
t1.inc("bar", 2)
t1.inc("baz", 3)
t2.inc("foo", 4)
t2.inc("bar")
t2.inc("baz", 11)
merge(t1, t2)
doAssert(t1["foo"] == 5)
doAssert(t1["bar"] == 3)
doAssert(t1["baz"] == 14)

let
  t1r = newCountTable[string]()
  t2r = newCountTable[string]()
t1r.inc("foo")
t1r.inc("bar", 2)
t1r.inc("baz", 3)
t2r.inc("foo", 4)
t2r.inc("bar")
t2r.inc("baz", 11)
merge(t1r, t2r)
doAssert(t1r["foo"] == 5)
doAssert(t1r["bar"] == 3)
doAssert(t1r["baz"] == 14)

var
  t1l = initCountTable[string]()
  t2l = initCountTable[string]()
t1l.inc("foo")
t1l.inc("bar", 2)
t1l.inc("baz", 3)
t2l.inc("foo", 4)
t2l.inc("bar")
t2l.inc("baz", 11)

block:
  const testKey = "TESTKEY"
  let t: CountTableRef[string] = newCountTable[string]()

  # Before, does not compile with error message:
  #test_counttable.nim(7, 43) template/generic instantiation from here
  #lib/pure/collections/tables.nim(117, 21) template/generic instantiation from here
  #lib/pure/collections/tableimpl.nim(32, 27) Error: undeclared field: 'hcode
  doAssert 0 == t[testKey]
  t.inc(testKey, 3)
  doAssert 3 == t[testKey]

block:
  # Clear tests
  var clearTable = newTable[int, string]()
  clearTable[42] = "asd"
  clearTable[123123] = "piuyqwb "
  doAssert clearTable[42] == "asd"
  clearTable.clear()
  doAssert(not clearTable.hasKey(123123))
  doAssert clearTable.getOrDefault(42) == ""

block: #5482
  var a = [("wrong?", "foo"), ("wrong?", "foo2")].newOrderedTable()
  var b = newOrderedTable[string, string](initialSize = 2)
  b["wrong?"] = "foo"
  b["wrong?"] = "foo2"
  doAssert a == b

block: #5482
  var a = {"wrong?": "foo", "wrong?": "foo2"}.newOrderedTable()
  var b = newOrderedTable[string, string](initialSize = 2)
  b["wrong?"] = "foo"
  b["wrong?"] = "foo2"
  doAssert a == b

block: #5487
  var a = {"wrong?": "foo", "wrong?": "foo2"}.newOrderedTable()
  var b = newOrderedTable[string, string]()         # notice, default size!
  b["wrong?"] = "foo"
  b["wrong?"] = "foo2"
  doAssert a == b

block: #5487
  var a = [("wrong?", "foo"), ("wrong?", "foo2")].newOrderedTable()
  var b = newOrderedTable[string, string]()         # notice, default size!
  b["wrong?"] = "foo"
  b["wrong?"] = "foo2"
  doAssert a == b

block:
  var a = {"wrong?": "foo", "wrong?": "foo2"}.newOrderedTable()
  var b = [("wrong?", "foo"), ("wrong?", "foo2")].newOrderedTable()
  var c = newOrderedTable[string, string]()         # notice, default size!
  c["wrong?"] = "foo"
  c["wrong?"] = "foo2"
  doAssert a == b
  doAssert a == c

block: #6250
  let
    a = {3: 1}.toOrderedTable
    b = {3: 2}.toOrderedTable
  doAssert((a == b) == false)
  doAssert((b == a) == false)

block: #6250
  let
    a = {3: 2}.toOrderedTable
    b = {3: 2}.toOrderedTable
  doAssert((a == b) == true)
  doAssert((b == a) == true)

block: # CountTable.smallest
  let t = toCountTable([0, 0, 5, 5, 5])
  doAssert t.smallest == (0, 2)

block: #10065
  let t = toCountTable("abracadabra")
  doAssert t['z'] == 0

  var t_mut = toCountTable("abracadabra")
  doAssert t_mut['z'] == 0
  # the previous read may not have modified the table.
  doAssert t_mut.hasKey('z') == false
  t_mut['z'] = 1
  doAssert t_mut['z'] == 1
  doAssert t_mut.hasKey('z') == true

block: #12813 #13079
  var t = toCountTable("abracadabra")
  doAssert len(t) == 5

  t['a'] = 0 # remove a key
  doAssert len(t) == 4

block:
  var tp: Table[string, string] = initTable[string, string]()
  doAssert "test1" == tp.getOrDefault("test1", "test1")
  tp["test2"] = "test2"
  doAssert "test2" == tp.getOrDefault("test2", "test1")
  var tr: TableRef[string, string] = newTable[string, string]()
  doAssert "test1" == tr.getOrDefault("test1", "test1")
  tr["test2"] = "test2"
  doAssert "test2" == tr.getOrDefault("test2", "test1")
  var op: OrderedTable[string, string] = initOrderedTable[string, string]()
  doAssert "test1" == op.getOrDefault("test1", "test1")
  op["test2"] = "test2"
  doAssert "test2" == op.getOrDefault("test2", "test1")
  var orf: OrderedTableRef[string, string] = newOrderedTable[string, string]()
  doAssert "test1" == orf.getOrDefault("test1", "test1")
  orf["test2"] = "test2"
  doAssert "test2" == orf.getOrDefault("test2", "test1")

block tableWithoutInit:
  var
    a: Table[string, int]
    b: Table[string, int]
    c: Table[string, int]
    d: Table[string, int]
    e: Table[string, int]

  a["a"] = 7
  doAssert a.hasKey("a")
  doAssert a.len == 1
  doAssert a["a"] == 7
  a["a"] = 9
  doAssert a.len == 1
  doAssert a["a"] == 9

  doAssert b.hasKeyOrPut("b", 5) == false
  doAssert b.hasKey("b")
  doAssert b.hasKeyOrPut("b", 8)
  doAssert b["b"] == 5

  doAssert c.getOrDefault("a") == 0
  doAssert c.getOrDefault("a", 3) == 3
  c["a"] = 6
  doAssert c.getOrDefault("a", 3) == 6

  doAssert d.mgetOrPut("a", 3) == 3
  doAssert d.mgetOrPut("a", 6) == 3

  var x = 99
  doAssert e.pop("a", x) == false
  doAssert x == 99
  e["a"] = 77
  doAssert e.pop("a", x)
  doAssert x == 77

block orderedTableWithoutInit:
  var
    a: OrderedTable[string, int]
    b: OrderedTable[string, int]
    c: OrderedTable[string, int]
    d: OrderedTable[string, int]

  a["a"] = 7
  doAssert a.hasKey("a")
  doAssert a.len == 1
  doAssert a["a"] == 7
  a["a"] = 9
  doAssert a.len == 1
  doAssert a["a"] == 9

  doAssert b.hasKeyOrPut("b", 5) == false
  doAssert b.hasKey("b")
  doAssert b.hasKeyOrPut("b", 8)
  doAssert b["b"] == 5

  doAssert c.getOrDefault("a") == 0
  doAssert c.getOrDefault("a", 3) == 3
  c["a"] = 6
  doAssert c.getOrDefault("a", 3) == 6

  doAssert d.mgetOrPut("a", 3) == 3
  doAssert d.mgetOrPut("a", 6) == 3

block countTableWithoutInit:
  var
    a: CountTable[string]
    b: CountTable[string]
    c: CountTable[string]
    d: CountTable[string]
    e: CountTable[string]

  a["a"] = 7
  doAssert a.hasKey("a")
  doAssert a.len == 1
  doAssert a["a"] == 7
  a["a"] = 9
  doAssert a.len == 1
  doAssert a["a"] == 9

  doAssert b["b"] == 0
  b.inc("b")
  doAssert b["b"] == 1

  doAssert c.getOrDefault("a") == 0
  doAssert c.getOrDefault("a", 3) == 3
  c["a"] = 6
  doAssert c.getOrDefault("a", 3) == 6

  e["f"] = 3
  merge(d, e)
  doAssert d.hasKey("f")
  d.inc("f")
  merge(d, e)
  doAssert d["f"] == 7

block: # issue #23587
  type
    A = proc ()

  proc main =
    let repo = initTable[uint32, A]()

    let c1 = repo.getOrDefault(uint32(1), nil)
    doAssert c1.isNil

    let c2 = repo.getOrDefault(uint32(1), A(nil))
    doAssert c2.isNil

  main()
