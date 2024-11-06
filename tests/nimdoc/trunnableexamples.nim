discard """
cmd: '''nim doc --doccmd:"-d:testFooExternal --hints:off" --hints:off $file'''
action: "compile"
nimoutFull: true
nimout: '''
foo1
foo2
foo3
foo5
foo7
in examplesInTemplate1
doc in outer
doc in inner1
doc in inner2
foo8
foo9
foo6
'''
joinable: false
"""


proc fun*() =
  runnableExamples:
    block: # `defer` only allowed inside a block
      defer: echo "foo1"

  runnableExamples:
    # `fun*` only allowed at top level
    proc fun*()=echo "foo2"
    fun()
    block:
      defer: echo "foo3"

  runnableExamples:
    # ditto
    proc fun*()=echo "foo5"
    fun()

  runnableExamples("--experimental:codeReordering --warnings:off"):
    # `codeReordering` only allowed at top level
    {.experimental: "codeReordering".}
    proc fun1() = fun2()
    proc fun2() = echo "foo6"
    fun1()

  runnableExamples:
    # only works at top level
    import std/macros
    macro myImport(a: static string): untyped =
      newTree(nnkImportStmt, [newLit a])
    myImport "str" & "utils"
    doAssert declared(isAlphaAscii)
    echo "foo7"

when true: # issue #12746
  # this proc on its own works fine with `nim doc`
  proc goodProc*() =
    runnableExamples:
      try:
        discard
      except CatchableError:
        # just the general except will work
        discard

  # FIXED: this proc fails with `nim doc`
  proc badProc*() =
    runnableExamples:
      try:
        discard
      except IOError:
        # specifying Error is culprit
        discard

when true: # runnableExamples with rdoccmd
  runnableExamples "-d:testFoo -d:testBar":
    doAssert defined(testFoo) and defined(testBar)
    doAssert defined(testFooExternal)
  runnableExamples "-d:testFoo2":
    doAssert defined(testFoo2)
    doAssert not defined(testFoo) # doesn't get confused by other examples

  ## all these syntaxes work too
  runnableExamples("-d:testFoo2"): discard
  runnableExamples(): discard
  runnableExamples: discard
  runnableExamples "-r:off": # issue #10731
    doAssert false ## we compile only (-r:off), so this won't be run
  runnableExamples "-b:js":
    import std/compilesettings
    proc startsWith*(s, prefix: cstring): bool {.noSideEffect, importjs: "#.startsWith(#)".}
    doAssert querySetting(backend) == "js"
  runnableExamples "-b:cpp":
    static: doAssert defined(cpp)
    type std_exception {.importcpp: "std::exception", header: "<exception>".} = object

  proc fun2*() =
    runnableExamples "-d:foo": discard # checks that it also works inside procs

  template fun3Impl(): untyped =
    runnableExamples(rdoccmd="-d:foo"):
      nonexistent
        # bugfix: this shouldn't be semchecked when `runnableExamples`
        # has more than 1 argument
    discard

  proc fun3*[T]() =
    fun3Impl()

  when false: # future work
    # passing non-string-litterals (for reuse)
    const a = "-b:cpp"
    runnableExamples(a): discard

    # passing seq (to run with multiple compilation options)
    runnableExamples(@["-b:cpp", "-b:js"]): discard

when true: # bug #16993
  template examplesInTemplate1*(cond: untyped) =
    ## in examplesInTemplate1
    runnableExamples:
      echo "in examplesInTemplate1"
    discard
  examplesInTemplate1 true
  examplesInTemplate1 true
  examplesInTemplate1 true

when true: # bug #18054
  template outer*(body: untyped) =
    ## outer template doc string.
    runnableExamples:
      echo "doc in outer"
    ##
    template inner1*() =
      ## inner1 template doc string.
      runnableExamples:
        echo "doc in inner1"
      ##

    template inner2*() =
      ## inner2 template doc string.
      runnableExamples:
        echo "doc in inner2"
    body
  outer:
    inner1()
    inner2()

when true: # bug #17835
  template anyItFake*(s, pred: untyped): bool =
    ## Foo
    runnableExamples: discard
    true

  proc anyItFakeMain*(n: seq[int]): bool =
    result = anyItFake(n, it == 0)
      # this was giving: Error: runnableExamples must appear before the first non-comment statement

runnableExamples:
  block: # bug #17279
    when int.sizeof == 8:
      let x = 0xffffffffffffffff
      doAssert x == -1

  # bug #13491
  block:
    proc fun(): int =
      result = 0
      doAssert false
    doAssertRaises(AssertionDefect, (discard fun()))

  block:
    template foo(body) = discard
    foo (discard)

  block:
    template fn(body: untyped): untyped = true
    doAssert(fn do: nonexistent)
  import std/macros
  macro foo*(x, y) =
    result = newLetStmt(x[0][0], x[0][1])
  foo:
    a = 1
  do: discard

# also check for runnableExamples at module scope
runnableExamples:
  block:
    defer: echo "foo8"

runnableExamples:
  proc fun*()=echo "foo9"
  fun()

# import std/assertions by default
runnableExamples("-d:nimPreviewSlimSystem"):
  doAssert true

# note: there are yet other examples where putting runnableExamples at module
# scope is needed, for example when using an `include` before an `import`, etc.

##[
snippet:

.. code-block:: Nim
    :test:

  doAssert defined(testFooExternal)

]##

when true: # runnableExamples with rdoccmd
  runnableExamples "-d:testFoo -d:testBar":
    doAssert defined(testFoo) and defined(testBar)
    doAssert defined(testFooExternal)
