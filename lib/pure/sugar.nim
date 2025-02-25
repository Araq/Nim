#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements nice syntactic sugar based on Nim's
## macro system.

import std/private/since
import std/macros

proc checkPragma(ex, prag: var NimNode) =
  since (1, 3):
    if ex.kind == nnkPragmaExpr:
      prag = ex[1]
      ex = ex[0]

proc createProcType(p, b: NimNode): NimNode =
  result = newNimNode(nnkProcTy)
  var
    formalParams = newNimNode(nnkFormalParams).add(b)
    p = p
    prag = newEmptyNode()

  checkPragma(p, prag)

  case p.kind
  of nnkPar, nnkTupleConstr:
    for i in 0 ..< p.len:
      let ident = p[i]
      var identDefs = newNimNode(nnkIdentDefs)
      case ident.kind
      of nnkExprColonExpr:
        identDefs.add ident[0]
        identDefs.add ident[1]
      else:
        identDefs.add newIdentNode("i" & $i)
        identDefs.add(ident)
      identDefs.add newEmptyNode()
      formalParams.add identDefs
  else:
    var identDefs = newNimNode(nnkIdentDefs)
    identDefs.add newIdentNode("i0")
    identDefs.add(p)
    identDefs.add newEmptyNode()
    formalParams.add identDefs

  result.add formalParams
  result.add prag

macro `=>`*(p, b: untyped): untyped =
  ## Syntax sugar for anonymous procedures. It also supports pragmas.
  ##
  ## .. warning:: Semicolons can not be used to separate procedure arguments.
  runnableExamples:
    proc passTwoAndTwo(f: (int, int) -> int): int = f(2, 2)

    assert passTwoAndTwo((x, y) => x + y) == 4

    type
      Bot = object
        call: (string {.noSideEffect.} -> string)

    var myBot = Bot()

    myBot.call = (name: string) {.noSideEffect.} => "Hello " & name & ", I'm a bot."
    assert myBot.call("John") == "Hello John, I'm a bot."

    let f = () => (discard) # simplest proc that returns void
    f()

  var
    params = @[ident"auto"]
    name = newEmptyNode()
    kind = nnkLambda
    pragma = newEmptyNode()
    p = p

  checkPragma(p, pragma)

  if p.kind == nnkInfix and p[0].kind == nnkIdent and p[0].eqIdent"->":
    params[0] = p[2]
    p = p[1]

  checkPragma(p, pragma) # check again after -> transform

  case p.kind
  of nnkPar, nnkTupleConstr:
    var untypedBeforeColon = 0
    for i, c in p:
      var identDefs = newNimNode(nnkIdentDefs)
      case c.kind
      of nnkExprColonExpr:
        let t = c[1]
        since (1, 3):
          # + 1 here because of return type in params
          for j in (i - untypedBeforeColon + 1) .. i:
            params[j][1] = t
        untypedBeforeColon = 0
        identDefs.add(c[0])
        identDefs.add(t)
        identDefs.add(newEmptyNode())
      of nnkIdent:
        identDefs.add(c)
        identDefs.add(newIdentNode("auto"))
        identDefs.add(newEmptyNode())
        inc untypedBeforeColon
      of nnkInfix:
        if c[0].kind == nnkIdent and c[0].eqIdent"->":
          var procTy = createProcType(c[1], c[2])
          params[0] = procTy[0][0]
          for i in 1 ..< procTy[0].len:
            params.add(procTy[0][i])
        else:
          error("Expected proc type (->) got (" & c[0].strVal & ").", c)
        break
      else:
        error("Incorrect procedure parameter.", c)
      params.add(identDefs)
  of nnkIdent, nnkOpenSymChoice, nnkClosedSymChoice, nnkSym:
    var identDefs = newNimNode(nnkIdentDefs)
    identDefs.add(ident $p)
    identDefs.add(ident"auto")
    identDefs.add(newEmptyNode())
    params.add(identDefs)
  else:
    error("Incorrect procedure parameter list.", p)
  result = newProc(body = b, params = params,
                   pragmas = pragma, name = name,
                   procType = kind)

macro `->`*(p, b: untyped): untyped =
  ## Syntax sugar for procedure types. It also supports pragmas.
  ##
  ## .. warning:: Semicolons can not be used to separate procedure arguments.
  runnableExamples:
    proc passTwoAndTwo(f: (int, int) -> int): int = f(2, 2)
    # is the same as:
    # proc passTwoAndTwo(f: proc (x, y: int): int): int = f(2, 2)

    assert passTwoAndTwo((x, y) => x + y) == 4

    proc passOne(f: (int {.noSideEffect.} -> int)): int = f(1)
    # is the same as:
    # proc passOne(f: proc (x: int): int {.noSideEffect.}): int = f(1)

    assert passOne(x {.noSideEffect.} => x + 1) == 2

  result = createProcType(p, b)

macro dump*(x: untyped): untyped =
  ## Dumps the content of an expression, useful for debugging.
  ## It accepts any expression and prints a textual representation
  ## of the tree representing the expression - as it would appear in
  ## source code - together with the value of the expression.
  ##
  ## See also: `dumpToString` which is more convenient and useful since
  ## it expands intermediate templates/macros, returns a string instead of
  ## calling `echo`, and works with statements and expressions.
  runnableExamples("-r:off"):
    let
      x = 10
      y = 20
    dump(x + y) # prints: `x + y = 30`

  let s = x.toStrLit
  result = quote do:
    debugEcho `s`, " = ", `x`

macro dumpToStringImpl(s: static string, x: typed): string =
  let s2 = x.toStrLit
  if x.typeKind == ntyVoid:
    result = quote do:
      `s` & ": " & `s2`
  else:
    result = quote do:
      `s` & ": " & `s2` & " = " & $`x`

macro dumpToString*(x: untyped): string =
  ## Returns the content of a statement or expression `x` after semantic analysis,
  ## useful for debugging.
  runnableExamples:
    const a = 1
    let x = 10
    assert dumpToString(a + 2) == "a + 2: 3 = 3"
    assert dumpToString(a + x) == "a + x: 1 + x = 11"
    template square(x): untyped = x * x
    assert dumpToString(square(x)) == "square(x): x * x = 100"
    assert not compiles dumpToString(1 + nonexistent)
    import std/strutils
    assert "failedAssertImpl" in dumpToString(assert true) # example with a statement
  result = newCall(bindSym"dumpToStringImpl")
  result.add newLit repr(x)
  result.add x

# TODO: consider exporting this in macros.nim
proc freshIdentNodes(ast: NimNode): NimNode =
  # Replace NimIdent and NimSym by a fresh ident node
  # see also https://github.com/nim-lang/Nim/pull/8531#issuecomment-410436458
  proc inspect(node: NimNode): NimNode =
    case node.kind:
    of nnkIdent, nnkSym, nnkOpenSymChoice, nnkClosedSymChoice, nnkOpenSym:
      result = ident($node)
    of nnkEmpty, nnkLiterals:
      result = node
    else:
      result = node.kind.newTree()
      for child in node:
        result.add inspect(child)
  result = inspect(ast)

macro capture*(locals: varargs[typed], body: untyped): untyped {.since: (1, 1).} =
  ## Useful when creating a closure in a loop to capture some local loop variables
  ## by their current iteration values.
  runnableExamples:
    import std/strformat

    var myClosure: () -> string
    for i in 5..7:
      for j in 7..9:
        if i * j == 42:
          capture i, j:
            myClosure = () => fmt"{i} * {j} = 42"
    assert myClosure() == "6 * 7 = 42"

  var params = @[newIdentNode("auto")]
  let locals = if locals.len == 1 and locals[0].kind == nnkBracket: locals[0]
               else: locals
  for arg in locals:
    proc getIdent(n: NimNode): NimNode =
      case n.kind
      of nnkIdent, nnkSym:
        let nStr = n.strVal
        if nStr == "result":
          error("The variable name cannot be `result`!", n)
        result = ident(nStr)
      of nnkHiddenDeref: result = n[0].getIdent()
      else:
        error("The argument to be captured `" & n.repr & "` is not a pure identifier. " &
          "It is an unsupported `" & $n.kind & "` node.", n)
    let argName = getIdent(arg)
    params.add(newIdentDefs(argName, freshIdentNodes getTypeInst arg))
  result = newNimNode(nnkCall)
  result.add(newProc(newEmptyNode(), params, body, nnkLambda))
  for arg in locals: result.add(arg)

since (1, 1):
  import std/private/underscored_calls

  macro dup*[T](arg: T, calls: varargs[untyped]): T =
    ## Turns an `in-place`:idx: algorithm into one that works on
    ## a copy and returns this copy, without modifying its input.
    ##
    ## This macro also allows for (otherwise in-place) function chaining.
    ##
    ## **Since:** Version 1.2.
    runnableExamples:
      import std/algorithm

      let a = @[1, 2, 3, 4, 5, 6, 7, 8, 9]
      assert a.dup(sort) == sorted(a)

      # Chaining:
      var aCopy = a
      aCopy.insert(10)
      assert a.dup(insert(10), sort) == sorted(aCopy)

      let s1 = "abc"
      let s2 = "xyz"
      assert s1 & s2 == s1.dup(&= s2)

      # An underscore (_) can be used to denote the place of the argument you're passing:
      assert "".dup(addQuoted(_, "foo")) == "\"foo\""
      # but `_` is optional here since the substitution is in 1st position:
      assert "".dup(addQuoted("foo")) == "\"foo\""

      proc makePalindrome(s: var string) =
        for i in countdown(s.len-2, 0):
          s.add(s[i])

      let c = "xyz"

      # chaining:
      let d = dup c:
        makePalindrome # xyzyx
        sort(_, SortOrder.Descending) # zyyxx
        makePalindrome # zyyxxxyyz
      assert d == "zyyxxxyyz"

    result = newNimNode(nnkStmtListExpr, arg)
    let tmp = genSym(nskVar, "dupResult")
    result.add newVarStmt(tmp, arg)
    underscoredCalls(result, calls, tmp)
    result.add tmp

proc trans(n, res, bracketExpr: NimNode): (NimNode, NimNode, NimNode) {.since: (1, 1).} =
  # Looks for the last statement of the last statement, etc...
  case n.kind
  of nnkIfExpr, nnkIfStmt, nnkTryStmt, nnkCaseStmt, nnkWhenStmt:
    result[0] = copyNimTree(n)
    result[1] = copyNimTree(n)
    result[2] = copyNimTree(n)
    for i in ord(n.kind == nnkCaseStmt) ..< n.len:
      (result[0][i], result[1][^1], result[2][^1]) = trans(n[i], res, bracketExpr)
  of nnkStmtList, nnkStmtListExpr, nnkBlockStmt, nnkBlockExpr, nnkWhileStmt,
      nnkForStmt, nnkElifBranch, nnkElse, nnkElifExpr, nnkOfBranch, nnkExceptBranch:
    result[0] = copyNimTree(n)
    result[1] = copyNimTree(n)
    result[2] = copyNimTree(n)
    if n.len >= 1:
      (result[0][^1], result[1][^1], result[2][^1]) = trans(n[^1],
          res, bracketExpr)
  of nnkTableConstr:
    result[1] = n[0][0]
    result[2] = n[0][1]
    if bracketExpr.len == 0:
      bracketExpr.add(ident"initTable") # don't import tables
    if bracketExpr.len == 1:
      bracketExpr.add([newCall(bindSym"typeof",
          newEmptyNode()), newCall(bindSym"typeof", newEmptyNode())])
    template adder(res, k, v) = res[k] = v
    result[0] = getAst(adder(res, n[0][0], n[0][1]))
  of nnkCurly:
    result[2] = n[0]
    if bracketExpr.len == 0:
      bracketExpr.add(ident"initHashSet")
    if bracketExpr.len == 1:
      bracketExpr.add(newCall(bindSym"typeof", newEmptyNode()))
    template adder(res, v) = res.incl(v)
    result[0] = getAst(adder(res, n[0]))
  else:
    result[2] = n
    if bracketExpr.len == 0:
      bracketExpr.add(bindSym"newSeq")
    if bracketExpr.len == 1:
      bracketExpr.add(newCall(bindSym"typeof", newEmptyNode()))
    template adder(res, v) = res.add(v)
    result[0] = getAst(adder(res, n))

proc collectImpl(init, body: NimNode): NimNode {.since: (1, 1).} =
  let res = genSym(nskVar, "collectResult")
  var bracketExpr: NimNode
  if init != nil:
    expectKind init, {nnkCall, nnkIdent, nnkSym, nnkClosedSymChoice, nnkOpenSymChoice, nnkOpenSym}
    bracketExpr = newTree(nnkBracketExpr,
      if init.kind in {nnkCall, nnkClosedSymChoice, nnkOpenSymChoice, nnkOpenSym}:
        freshIdentNodes(init[0]) else: freshIdentNodes(init))
  else:
    bracketExpr = newTree(nnkBracketExpr)
  let (resBody, keyType, valueType) = trans(body, res, bracketExpr)
  if bracketExpr.len == 3:
    bracketExpr[1][1] = keyType
    bracketExpr[2][1] = valueType
  else:
    bracketExpr[1][1] = valueType
  let call = newTree(nnkCall, bracketExpr)
  if init != nil and init.kind == nnkCall:
    for i in 1 ..< init.len:
      call.add init[i]
  result = newTree(nnkStmtListExpr, newVarStmt(res, call), resBody, res)

macro collect*(init, body: untyped): untyped {.since: (1, 1).} =
  ## Comprehension for seqs/sets/tables.
  ##
  ## The last expression of `body` has special syntax that specifies
  ## the collection's add operation. Use `{e}` for set's `incl`,
  ## `{k: v}` for table's `[]=` and `e` for seq's `add`.
  # analyse the body, find the deepest expression 'it' and replace it via
  # 'result.add it'
  runnableExamples:
    import std/[sets, tables]

    let data = @["bird", "word"]

    ## seq:
    let k = collect(newSeq):
      for i, d in data.pairs:
        if i mod 2 == 0: d
    assert k == @["bird"]

    ## seq with initialSize:
    let x = collect(newSeqOfCap(4)):
      for i, d in data.pairs:
        if i mod 2 == 0: d
    assert x == @["bird"]

    ## HashSet:
    let y = collect(initHashSet()):
      for d in data.items: {d}
    assert y == data.toHashSet

    ## Table:
    let z = collect(initTable(2)):
      for i, d in data.pairs: {i: d}
    assert z == {0: "bird", 1: "word"}.toTable

  result = collectImpl(init, body)

macro collect*(body: untyped): untyped {.since: (1, 5).} =
  ## Same as `collect` but without an `init` parameter.
  ##
  ## **See also:**
  ## * `sequtils.toSeq proc<sequtils.html#toSeq.t%2Cuntyped>`_
  ## * `sequtils.mapIt template<sequtils.html#mapIt.t%2Ctyped%2Cuntyped>`_
  runnableExamples:
    import std/[sets, tables]
    let data = @["bird", "word"]

    # seq:
    let k = collect:
      for i, d in data.pairs:
        if i mod 2 == 0: d
    assert k == @["bird"]

    ## HashSet:
    let n = collect:
      for d in data.items: {d}
    assert n == data.toHashSet

    ## Table:
    let m = collect:
      for i, d in data.pairs: {i: d}
    assert m == {0: "bird", 1: "word"}.toTable

  result = collectImpl(nil, body)
