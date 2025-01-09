# bug #1744

import macros

type
  SuiteTest = object
    suiteName: string
    suiteDesc: string
    testName: string
    testDesc: string
    testBlock: NimNode

proc buildSuiteContents(suiteName, suiteDesc, suiteBloc: NimNode): tuple[tests: seq[SuiteTest]]  {.compileTime.} =
  var
    tests:seq[SuiteTest] = @[]

  for child in suiteBloc.children():
    case $child[0].strVal:
    of "test":

      var testObj = SuiteTest()
      if suiteName.kind == nnkNilLit:
        testObj.suiteName = ""
      else:
        testObj.suiteName = $suiteName
      if suiteDesc.kind == nnkNilLit:
        testObj.suiteDesc = ""
      else:
        testObj.suiteDesc = suiteDesc.strVal
      testObj.testName = $child[1] # should not ever be nil
      if child[2].kind == nnkNilLit:
        testObj.testDesc = ""
      else:
        testObj.testDesc = child[2].strVal
      testObj.testBlock = child[1]

      tests.add(testObj)

    else:
      discard

  return (tests: tests)

macro suite(suiteName, suiteDesc, suiteBloc: untyped): typed =
  let contents = buildSuiteContents(suiteName, suiteDesc, suiteBloc)

# Test above
suite basics, "Description of such":
  test(t5, ""):
    doAssert false
