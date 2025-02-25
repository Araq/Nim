#
#
#            Nim Tester
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Include for the tester that contains test suites that test special features
## of the compiler.

# included from testament.nim

import important_packages
import std/[strformat, strutils]
from std/sequtils import filterIt

const
  specialCategories = [
    "assert",
    "async",
    "debugger",
    "dll",
    "examples",
    "gc",
    "io",
    "js",
    "ic",
    "lib",
    "manyloc",
    "nimble-packages",
    "niminaction",
    "threads",
    "untestable", # see trunner_special
    "testdata",
    "nimcache",
    "coroutines",
    "osproc",
    "shouldfail",
    "destructor"
  ]

proc isTestFile*(file: string): bool =
  let (_, name, ext) = splitFile(file)
  result = ext == ".nim" and name.startsWith("t")

# --------------------- DLL generation tests ----------------------------------

proc runBasicDLLTest(c, r: var TResults, cat: Category, options: string, isOrc = false) =
  const rpath = when defined(macosx):
      " --passL:-rpath --passL:@loader_path"
    else:
      ""

  var test1 = makeTest("lib/nimrtl.nim", options & " --outdir:tests/dll", cat)
  test1.spec.action = actionCompile
  testSpec c, test1
  var test2 = makeTest("tests/dll/server.nim", options & " --threads:on" & rpath, cat)
  test2.spec.action = actionCompile
  testSpec c, test2

  var test3 = makeTest("lib/nimhcr.nim", options & " --threads:off --outdir:tests/dll" & rpath, cat)
  test3.spec.action = actionCompile
  testSpec c, test3
  var test4 = makeTest("tests/dll/visibility.nim", options & " --threads:off --app:lib" & rpath, cat)
  test4.spec.action = actionCompile
  testSpec c, test4

  # windows looks in the dir of the exe (yay!):
  when not defined(windows):
    # posix relies on crappy LD_LIBRARY_PATH (ugh!):
    const libpathenv = when defined(haiku): "LIBRARY_PATH"
                       else: "LD_LIBRARY_PATH"
    var libpath = getEnv(libpathenv)
    # Temporarily add the lib directory to LD_LIBRARY_PATH:
    putEnv(libpathenv, "tests/dll" & (if libpath.len > 0: ":" & libpath else: ""))
    defer: putEnv(libpathenv, libpath)

  testSpec r, makeTest("tests/dll/client.nim", options & " --threads:on" & rpath, cat)
  testSpec r, makeTest("tests/dll/nimhcr_unit.nim", options & " --threads:off" & rpath, cat)
  testSpec r, makeTest("tests/dll/visibility.nim", options & " --threads:off" & rpath, cat)

  if "boehm" notin options:
    # hcr tests
    
    var basicHcrTest = makeTest("tests/dll/nimhcr_basic.nim", options & " --threads:off --forceBuild --hotCodeReloading:on " & rpath, cat)
    # test segfaults for now but compiles:
    if isOrc: basicHcrTest.spec.action = actionCompile
    testSpec r, basicHcrTest

    # force build required - see the comments in the .nim file for more details
    var hcri = makeTest("tests/dll/nimhcr_integration.nim",
                                   options & " --threads:off --forceBuild --hotCodeReloading:on" & rpath, cat)
    let nimcache = nimcacheDir(hcri.name, hcri.options, getTestSpecTarget())
    let cmd = prepareTestCmd(hcri.spec.getCmd, hcri.name,
                                hcri.options, nimcache, getTestSpecTarget())
    hcri.testArgs = cmd.parseCmdLine
    testSpec r, hcri

proc dllTests(r: var TResults, cat: Category, options: string) =
  # dummy compile result:
  var c = initResults()

  runBasicDLLTest c, r, cat, options & " --mm:refc"
  runBasicDLLTest c, r, cat, options & " -d:release --mm:refc"
  runBasicDLLTest c, r, cat, options, isOrc = true
  runBasicDLLTest c, r, cat, options & " -d:release", isOrc = true
  when not defined(windows) and not defined(osx):
    # boehm library linking broken on macos 13
    # still cannot find a recent Windows version of boehm.dll:
    runBasicDLLTest c, r, cat, options & " --gc:boehm"
    runBasicDLLTest c, r, cat, options & " -d:release --gc:boehm"

# ------------------------------ GC tests -------------------------------------

proc gcTests(r: var TResults, cat: Category, options: string) =
  template testWithoutMs(filename: untyped) =
    testSpec r, makeTest("tests/gc" / filename, options & "--mm:refc", cat)
    testSpec r, makeTest("tests/gc" / filename, options &
                  " -d:release -d:useRealtimeGC --mm:refc", cat)
    when filename != "gctest":
      testSpec r, makeTest("tests/gc" / filename, options &
                    " --gc:orc", cat)
      testSpec r, makeTest("tests/gc" / filename, options &
                    " --gc:orc -d:release", cat)

  template testWithoutBoehm(filename: untyped) =
    testWithoutMs filename
    testSpec r, makeTest("tests/gc" / filename, options &
                  " --gc:markAndSweep", cat)
    testSpec r, makeTest("tests/gc" / filename, options &
                  " -d:release --gc:markAndSweep", cat)

  template test(filename: untyped) =
    testWithoutBoehm filename
    when not defined(windows) and not defined(android) and not defined(osx):
      # boehm library linking broken on macos 13
      # AR: cannot find any boehm.dll on the net, right now, so disabled
      # for windows:
      testSpec r, makeTest("tests/gc" / filename, options &
                    " --gc:boehm", cat)
      testSpec r, makeTest("tests/gc" / filename, options &
                    " -d:release --gc:boehm", cat)

  testWithoutBoehm "foreign_thr"
  test "gcemscripten"
  test "growobjcrash"
  test "gcbench"
  test "gcleak"
  test "gcleak2"
  testWithoutBoehm "gctest"
  test "gcleak3"
  test "gcleak4"
  # Disabled because it works and takes too long to run:
  #test "gcleak5"
  testWithoutBoehm "weakrefs"
  test "cycleleak"
  testWithoutBoehm "closureleak"
  testWithoutMs "refarrayleak"

  testWithoutBoehm "tlists"
  testWithoutBoehm "thavlak"

  test "stackrefleak"
  test "cyclecollector"
  testWithoutBoehm "trace_globals"

# ------------------------- threading tests -----------------------------------

proc threadTests(r: var TResults, cat: Category, options: string) =
  template test(filename: untyped) =
    testSpec r, makeTest(filename, options, cat)
    testSpec r, makeTest(filename, options & " -d:release", cat)
    testSpec r, makeTest(filename, options & " --tlsEmulation:on", cat)
  for t in os.walkFiles("tests/threads/t*.nim"):
    test(t)

# ------------------------- IO tests ------------------------------------------

proc ioTests(r: var TResults, cat: Category, options: string) =
  # We need readall_echo to be compiled for this test to run.
  # dummy compile result:
  var c = initResults()
  testSpec c, makeTest("tests/system/helpers/readall_echo", options, cat)
  #        ^- why is this not appended to r? Should this be discarded?
  # EDIT: this should be replaced by something like in D20210524T180826,
  # likewise in similar instances where `testSpec c` is used, or more generally
  # when a test depends on another test, as it makes tests non-independent,
  # creating complications for batching and megatest logic.
  testSpec r, makeTest("tests/system/tio", options, cat)

# ------------------------- async tests ---------------------------------------
proc asyncTests(r: var TResults, cat: Category, options: string) =
  template test(filename: untyped) =
    testSpec r, makeTest(filename, options, cat)
  for t in os.walkFiles("tests/async/t*.nim"):
    test(t)

# ------------------------- debugger tests ------------------------------------

proc debuggerTests(r: var TResults, cat: Category, options: string) =
  if fileExists("tools/nimgrep.nim"):
    var t = makeTest("tools/nimgrep", options & " --debugger:on", cat)
    t.spec.action = actionCompile
    # force target to C because of MacOS 10.15 SDK headers bug
    # https://github.com/nim-lang/Nim/pull/15612#issuecomment-712471879
    t.spec.targets = {targetC}
    testSpec r, t

# ------------------------- JS tests ------------------------------------------

proc jsTests(r: var TResults, cat: Category, options: string) =
  template test(filename: untyped) =
    testSpec r, makeTest(filename, options, cat), {targetJS}
    testSpec r, makeTest(filename, options & " -d:release", cat), {targetJS}

  for t in os.walkFiles("tests/js/t*.nim"):
    test(t)
  for testfile in ["exception/texceptions", "exception/texcpt1",
                   "exception/texcsub", "exception/tfinally",
                   "exception/tfinally2", "exception/tfinally3",
                   "collections/tactiontable", "method/tmultimjs",
                   "varres/tvarres0", "varres/tvarres3", "varres/tvarres4",
                   "varres/tvartup", "int/tints", "int/tunsignedinc",
                   "async/tjsandnativeasync"]:
    test "tests/" & testfile & ".nim"

  for testfile in ["strutils", "json", "random", "times", "logging"]:
    test "lib/pure/" & testfile & ".nim"

# ------------------------- nim in action -----------

proc testNimInAction(r: var TResults, cat: Category, options: string) =
  template test(filename: untyped) =
    testSpec r, makeTest(filename, options, cat)

  template testJS(filename: untyped) =
    testSpec r, makeTest(filename, options, cat), {targetJS}

  template testCPP(filename: untyped) =
    testSpec r, makeTest(filename, options, cat), {targetCpp}

  let tests = [
    "niminaction/Chapter1/various1",
    "niminaction/Chapter2/various2",
    "niminaction/Chapter2/resultaccept",
    "niminaction/Chapter2/resultreject",
    "niminaction/Chapter2/explicit_discard",
    "niminaction/Chapter2/no_def_eq",
    "niminaction/Chapter2/no_iterator",
    "niminaction/Chapter2/no_seq_type",
    "niminaction/Chapter3/ChatApp/src/server",
    "niminaction/Chapter3/ChatApp/src/client",
    "niminaction/Chapter3/various3",
    "niminaction/Chapter6/WikipediaStats/concurrency_regex",
    "niminaction/Chapter6/WikipediaStats/concurrency",
    "niminaction/Chapter6/WikipediaStats/naive",
    "niminaction/Chapter6/WikipediaStats/parallel_counts",
    "niminaction/Chapter6/WikipediaStats/race_condition",
    "niminaction/Chapter6/WikipediaStats/sequential_counts",
    "niminaction/Chapter6/WikipediaStats/unguarded_access",
    "niminaction/Chapter7/Tweeter/src/tweeter",
    "niminaction/Chapter7/Tweeter/src/createDatabase",
    "niminaction/Chapter7/Tweeter/tests/database_test",
    "niminaction/Chapter8/sdl/sdl_test"
    ]

  when false:
    # Verify that the files have not been modified. Death shall fall upon
    # whoever edits these hashes without dom96's permission, j/k. But please only
    # edit when making a conscious breaking change, also please try to make your
    # commit message clear and notify me so I can easily compile an errata later.
    # ---------------------------------------------------------
    # Hash-checks are disabled for Nim 1.1 and beyond
    # since we needed to fix the deprecated unary '<' operator.
    const refHashes = @[
      "51afdfa84b3ca3d810809d6c4e5037ba",
      "30f07e4cd5eaec981f67868d4e91cfcf",
      "d14e7c032de36d219c9548066a97e846",
      "b335635562ff26ec0301bdd86356ac0c",
      "6c4add749fbf50860e2f523f548e6b0e",
      "76de5833a7cc46f96b006ce51179aeb1",
      "705eff79844e219b47366bd431658961",
      "a1e87b881c5eb161553d119be8b52f64",
      "2d706a6ec68d2973ec7e733e6d5dce50",
      "c11a013db35e798f44077bc0763cc86d",
      "3e32e2c5e9a24bd13375e1cd0467079c",
      "a5452722b2841f0c1db030cf17708955",
      "dc6c45eb59f8814aaaf7aabdb8962294",
      "69d208d281a2e7bffd3eaf4bab2309b1",
      "ec05666cfb60211bedc5e81d4c1caf3d",
      "da520038c153f4054cb8cc5faa617714",
      "59906c8cd819cae67476baa90a36b8c1",
      "9a8fe78c588d08018843b64b57409a02",
      "8b5d28e985c0542163927d253a3e4fc9",
      "783299b98179cc725f9c46b5e3b5381f",
      "1a2b3fba1187c68d6a9bfa66854f3318",
      "391ff57b38d9ea6f3eeb3fe69ab539d3"
    ]
    for i, test in tests:
      let filename = testsDir / test.addFileExt("nim")
      let testHash = getMD5(readFile(filename).string)
      doAssert testHash == refHashes[i], "Nim in Action test " & filename &
          " was changed: " & $(i: i, testHash: testHash, refHash: refHashes[i])

  # Run the tests.
  for testfile in tests:
    test "tests/" & testfile & ".nim"
  let jsFile = "tests/niminaction/Chapter8/canvas/canvas_test.nim"
  testJS jsFile
  let cppFile = "tests/niminaction/Chapter8/sfml/sfml_test.nim"
  testCPP cppFile

# ------------------------- manyloc -------------------------------------------

proc findMainFile(dir: string): string =
  # finds the file belonging to ".nim.cfg"; if there is no such file
  # it returns the some ".nim" file if there is only one:
  const cfgExt = ".nim.cfg"
  result = ""
  var nimFiles = 0
  for kind, file in os.walkDir(dir):
    if kind == pcFile:
      if file.endsWith(cfgExt): return file[0..^(cfgExt.len+1)] & ".nim"
      elif file.endsWith(".nim"):
        if result.len == 0: result = file
        inc nimFiles
  if nimFiles != 1: result.setLen(0)

proc manyLoc(r: var TResults, cat: Category, options: string) =
  for kind, dir in os.walkDir("tests/manyloc"):
    if kind == pcDir:
      when defined(windows):
        if dir.endsWith"nake": continue
      if dir.endsWith"named_argument_bug": continue
      let mainfile = findMainFile(dir)
      if mainfile != "":
        var test = makeTest(mainfile, options, cat)
        test.spec.action = actionCompile
        testSpec r, test

proc compileExample(r: var TResults, pattern, options: string, cat: Category) =
  for test in os.walkFiles(pattern):
    var test = makeTest(test, options, cat)
    test.spec.action = actionCompile
    testSpec r, test

proc testStdlib(r: var TResults, pattern, options: string, cat: Category) =
  var files: seq[string] = @[]

  proc isValid(file: string): bool =
    for dir in parentDirs(file, inclusive = false):
      if dir.lastPathPart in ["includes", "nimcache"]:
        # e.g.: lib/pure/includes/osenv.nim gives: Error: This is an include file for os.nim!
        return false
    let name = extractFilename(file)
    if name.splitFile.ext != ".nim": return false
    for namei in disabledFiles:
      # because of `LockFreeHash.nim` which has case
      if namei.cmpPaths(name) == 0: return false
    return true

  for testFile in os.walkDirRec(pattern):
    if isValid(testFile):
      files.add testFile

  files.sort # reproducible order
  for testFile in files:
    let contents = readFile(testFile)
    var testObj = makeTest(testFile, options, cat)
    #[
    todo:
    this logic is fragile:
    false positives (if appears in a comment), or false negatives, e.g.
    `when defined(osx) and isMainModule`.
    Instead of fixing this, see https://github.com/nim-lang/Nim/issues/10045
    for a much better way.
    ]#
    if "when isMainModule" notin contents:
      testObj.spec.action = actionCompile
    testSpec r, testObj

# ----------------------------- nimble ----------------------------------------
proc listPackagesAll(): seq[NimblePackage] =
  result = @[]
  var nimbleDir = getEnv("NIMBLE_DIR")
  if nimbleDir.len == 0: nimbleDir = getHomeDir() / ".nimble"
  let packageIndex = nimbleDir / "packages_official.json"
  let packageList = parseFile(packageIndex)
  proc findPackage(name: string): JsonNode =
    result = nil
    for a in packageList:
      if a["name"].str == name: return a
  for pkg in important_packages.packages.items:
    var pkg = pkg
    if pkg.url.len == 0:
      let pkg2 = findPackage(pkg.name)
      if pkg2 == nil:
        raise newException(ValueError, "Cannot find package '$#'." % pkg.name)
      pkg.url = pkg2["url"].str
    result.add pkg

proc listPackages(packageFilter: string): seq[NimblePackage] =
  let pkgs = listPackagesAll()
  if packageFilter.len != 0:
    # xxx document `packageFilter`, seems like a bad API,
    # at least should be a regex; a substring match makes no sense.
    result = pkgs.filterIt(packageFilter in it.name)
  else:
    if testamentData0.batchArg == "allowed_failures":
      result = pkgs.filterIt(it.allowFailure)
    elif testamentData0.testamentNumBatch == 0:
      result = pkgs
    else:
      result = @[]
      let pkgs2 = pkgs.filterIt(not it.allowFailure)
      for i in 0..<pkgs2.len:
        if i mod testamentData0.testamentNumBatch == testamentData0.testamentBatch:
          result.add pkgs2[i]

proc makeSupTest(test, options: string, cat: Category, debugInfo = ""): TTest =
  result = TTest(cat: cat, name: test, options: options, debugInfo: debugInfo,
                startTime: epochTime())

import std/private/gitutils

proc testNimblePackages(r: var TResults; cat: Category; packageFilter: string) =
  let nimbleExe = findExe("nimble")
  doAssert nimbleExe != "", "Cannot run nimble tests: Nimble binary not found."
  doAssert execCmd("$# update" % nimbleExe) == 0, "Cannot run nimble tests: Nimble update failed."
  let packageFileTest = makeSupTest("PackageFileParsed", "", cat)
  let packagesDir = "pkgstemp"
  createDir(packagesDir)
  var errors = 0
  try:
    let pkgs = listPackages(packageFilter)
    for i, pkg in pkgs:
      inc r.total
      var test = makeSupTest(pkg.name, "", cat, "[$#/$#] " % [$i, $pkgs.len])
      let buildPath = packagesDir / pkg.name
      template tryCommand(cmd: string, workingDir2 = buildPath, reFailed = reInstallFailed, maxRetries = 1): string =
        var outp: string = ""
        let ok = retryCall(maxRetry = maxRetries, backoffDuration = 10.0):
          var status: int
          (outp, status) = execCmdEx(cmd, workingDir = workingDir2)
          status == QuitSuccess
        if not ok:
          if pkg.allowFailure:
            inc r.passed
            inc r.failedButAllowed
          r.finishTest(test, targetC, "", "", cmd & "\n" & outp, reFailed, allowFailure = pkg.allowFailure)
          continue
        outp

      if not dirExists(buildPath):
        discard tryCommand("git clone $# $#" % [pkg.url.quoteShell, buildPath.quoteShell], workingDir2 = ".", maxRetries = 3)
        if not pkg.useHead:
          discard tryCommand("git fetch --tags", maxRetries = 3)
          let describeOutput = tryCommand("git describe --tags --abbrev=0")
          discard tryCommand("git checkout $#" % [describeOutput.strip.quoteShell])
        discard tryCommand("nimble install --depsOnly -y", maxRetries = 3)
      let cmds = pkg.cmd.split(';')
      for i in 0 ..< cmds.len - 1:
        discard tryCommand(cmds[i], maxRetries = 3)
      discard tryCommand(cmds[^1], reFailed = reBuildFailed)
      inc r.passed
      r.finishTest(test, targetC, "", "", "", reSuccess, allowFailure = pkg.allowFailure)

    errors = r.total - r.passed
    if errors == 0:
      r.finishTest(packageFileTest, targetC, "", "", "", reSuccess)
    else:
      r.finishTest(packageFileTest, targetC, "", "", "", reBuildFailed)

  except JsonParsingError:
    errors = 1
    r.finishTest(packageFileTest, targetC, "", "", "Invalid package file", reBuildFailed)
    raise
  except ValueError:
    errors = 1
    r.finishTest(packageFileTest, targetC, "", "", "Unknown package", reBuildFailed)
    raise # bug #18805
  finally:
    if errors == 0: removeDir(packagesDir)

# ---------------- IC tests ---------------------------------------------

proc icTests(r: var TResults; testsDir: string, cat: Category, options: string;
             isNavigatorTest: bool) =
  const
    tooltests = ["compiler/nim.nim"]
    writeOnly = " --incremental:writeonly "
    readOnly = " --incremental:readonly "
    incrementalOn = " --incremental:on -d:nimIcIntegrityChecks "
    navTestConfig = " --ic:on -d:nimIcNavigatorTests --hint:Conf:off --warnings:off "

  template test(x: untyped) =
    testSpecWithNimcache(r, makeRawTest(file, x & options, cat), nimcache)

  template editedTest(x: untyped) =
    var test = makeTest(file, x & options, cat)
    if isNavigatorTest:
      test.spec.action = actionCompile
    test.spec.targets = {getTestSpecTarget()}
    testSpecWithNimcache(r, test, nimcache)

  template checkTest() =
    var test = makeRawTest(file, options, cat)
    test.spec.cmd = compilerPrefix & " check --hint:Conf:off --warnings:off --ic:on $options " & file
    testSpecWithNimcache(r, test, nimcache)

  if not isNavigatorTest:
    for file in tooltests:
      let nimcache = nimcacheDir(file, options, getTestSpecTarget())
      removeDir(nimcache)

      let oldPassed = r.passed
      checkTest()

      if r.passed == oldPassed+1:
        checkTest()
        if r.passed == oldPassed+2:
          checkTest()

  const tempExt = "_temp.nim"
  for it in walkDirRec(testsDir):
  # for it in ["tests/ic/timports.nim"]: # debugging: to try a specific test
    if isTestFile(it) and not it.endsWith(tempExt):
      let nimcache = nimcacheDir(it, options, getTestSpecTarget())
      removeDir(nimcache)

      let content = readFile(it)
      for fragment in content.split("#!EDIT!#"):
        let file = it.replace(".nim", tempExt)
        writeFile(file, fragment)
        let oldPassed = r.passed
        editedTest(if isNavigatorTest: navTestConfig else: incrementalOn)
        if r.passed != oldPassed+1: break

# ----------------------------------------------------------------------------

const AdditionalCategories = ["debugger", "examples", "lib", "ic", "navigator"]
const MegaTestCat = "megatest"

proc `&.?`(a, b: string): string =
  # candidate for the stdlib?
  result = if b.startsWith(a): b else: a & b

proc processSingleTest(r: var TResults, cat: Category, options, test: string, targets: set[TTarget], targetsSet: bool) =
  var targets = targets
  if not targetsSet:
    let target = if cat.string.normalize == "js": targetJS else: targetC
    targets = {target}
  doAssert fileExists(test), test & " test does not exist"
  testSpec r, makeTest(test, options, cat), targets

proc isJoinableSpec(spec: TSpec): bool =
  # xxx simplify implementation using a whitelist of fields that are allowed to be
  # set to non-default values (use `fieldPairs`), to avoid issues like bug #16576.
  result = useMegatest and not spec.sortoutput and
    spec.action == actionRun and
    not fileExists(spec.file.changeFileExt("cfg")) and
    not fileExists(spec.file.changeFileExt("nims")) and
    not fileExists(parentDir(spec.file) / "nim.cfg") and
    not fileExists(parentDir(spec.file) / "config.nims") and
    spec.cmd.len == 0 and
    spec.err != reDisabled and
    not spec.unjoinable and
    spec.exitCode == 0 and
    spec.retries == 0 and
    spec.input.len == 0 and
    spec.nimout.len == 0 and
    spec.nimoutFull == false and
      # so that tests can have `nimoutFull: true` with `nimout.len == 0` with
      # the meaning that they expect empty output.
    spec.matrix.len == 0 and
    spec.outputCheck != ocSubstr and
    spec.ccodeCheck.len == 0 and
    (spec.targets == {} or spec.targets == {targetC})
  if result:
    if spec.file.readFile.contains "when isMainModule":
      result = false

proc quoted(a: string): string =
  # TODO: consider moving to system.nim
  result = ""
  result.addQuoted(a)

proc runJoinedTest(r: var TResults, cat: Category, testsDir: string, options: string) =
  ## returns a list of tests that have problems
  #[
  xxx create a reusable megatest API after abstracting out testament specific code,
  refs https://github.com/timotheecour/Nim/issues/655
  and https://github.com/nim-lang/gtk2/pull/28; it's useful in other contexts.
  ]#
  var specs: seq[TSpec] = @[]
  for kind, dir in walkDir(testsDir):
    assert dir.startsWith(testsDir)
    let cat = dir[testsDir.len .. ^1]
    if kind == pcDir and cat notin specialCategories:
      for file in walkDirRec(testsDir / cat):
        if isTestFile(file):
          var spec: TSpec = default(TSpec)
          try:
            spec = parseSpec(file)
          except ValueError:
            # e.g. for `tests/navigator/tincludefile.nim` which have multiple
            # specs; this will be handled elsewhere
            echo "parseSpec raised ValueError for: '$1', assuming this will be handled outside of megatest" % file
            continue
          if isJoinableSpec(spec):
            specs.add spec

  proc cmp(a: TSpec, b: TSpec): auto = cmp(a.file, b.file)
  sort(specs, cmp = cmp) # reproducible order
  echo "joinable specs: ", specs.len

  if simulate:
    var s = "runJoinedTest: "
    for a in specs: s.add a.file & " "
    echo s
    return

  var megatest: string = ""
  # xxx (minor) put outputExceptedFile, outputGottenFile, megatestFile under here or `buildDir`
  var outDir = nimcacheDir(testsDir / "megatest", "", targetC)
  template toMarker(file, i): string =
    "megatest:processing: [$1] $2" % [$i, file]
  for i, runSpec in specs:
    let file = runSpec.file
    let file2 = outDir / ("megatest_a_$1.nim" % $i)
    # `include` didn't work with `trecmod2.nim`, so using `import`
    let code = "echo $1\nstatic: echo \"CT:\", $1\n" % [toMarker(file, i).quoted]
    createDir(file2.parentDir)
    writeFile(file2, code)
    megatest.add "import $1\nimport $2 as megatest_b_$3\n" % [file2.quoted, file.quoted, $i]

  let megatestFile = testsDir / "megatest.nim" # so it uses testsDir / "config.nims"
  writeFile(megatestFile, megatest)

  let root = getCurrentDir()

  var args = @["c", "--nimCache:" & outDir, "-d:testing", "-d:nimMegatest", "--listCmd",
              "--path:" & root]
  args.add options.parseCmdLine
  args.add megatestFile
  var (cmdLine, buf, exitCode) = execCmdEx2(command = compilerPrefix, args = args, input = "")
  if exitCode != 0:
    echo "$ " & cmdLine & "\n" & buf
    quit(failString & "megatest compilation failed")

  (buf, exitCode) = execCmdEx(megatestFile.changeFileExt(ExeExt).dup normalizeExe)
  if exitCode != 0:
    echo buf
    quit(failString & "megatest execution failed")

  const outputExceptedFile = "outputExpected.txt"
  const outputGottenFile = "outputGotten.txt"
  writeFile(outputGottenFile, buf)
  var outputExpected = ""
  for i, runSpec in specs:
    outputExpected.add toMarker(runSpec.file, i) & "\n"
    if runSpec.output.len > 0:
      outputExpected.add runSpec.output
      if not runSpec.output.endsWith "\n":
        outputExpected.add '\n'

  if buf != outputExpected:
    writeFile(outputExceptedFile, outputExpected)
    echo diffFiles(outputGottenFile, outputExceptedFile).output
    echo failString & "megatest output different, see $1 vs $2" % [outputGottenFile, outputExceptedFile]
    # outputGottenFile, outputExceptedFile not removed on purpose for debugging.
    quit 1
  else:
    echo "megatest output OK"


# ---------------------------------------------------------------------------

proc processCategory(r: var TResults, cat: Category,
                     options, testsDir: string,
                     runJoinableTests: bool) =
  let cat2 = cat.string.normalize
  var handled = false
  if isNimRepoTests():
    handled = true
    case cat2
    of "js":
      # only run the JS tests on Windows or Linux because Travis is bad
      # and other OSes like Haiku might lack nodejs:
      if not defined(linux) and isTravis:
        discard
      else:
        jsTests(r, cat, options)
    of "dll":
      dllTests(r, cat, options & " -d:nimDebugDlOpen")
    of "gc":
      gcTests(r, cat, options)
    of "debugger":
      debuggerTests(r, cat, options)
    of "manyloc":
      manyLoc r, cat, options
    of "threads":
      threadTests r, cat, options & " --threads:on"
    of "io":
      ioTests r, cat, options
    of "async":
      asyncTests r, cat, options
    of "lib":
      testStdlib(r, "lib/pure/", options, cat)
      testStdlib(r, "lib/packages/docutils/", options, cat)
    of "examples":
      compileExample(r, "examples/*.nim", options, cat)
      compileExample(r, "examples/gtk/*.nim", options, cat)
      compileExample(r, "examples/talk/*.nim", options, cat)
    of "nimble-packages":
      testNimblePackages(r, cat, options)
    of "niminaction":
      testNimInAction(r, cat, options)
    of "ic":
      icTests(r, testsDir / cat2, cat, options, isNavigatorTest=false)
    of "navigator":
      icTests(r, testsDir / cat2, cat, options, isNavigatorTest=true)
    of "untestable":
      # These require special treatment e.g. because they depend on a third party
      # dependency; see `trunner_special` which runs some of those.
      discard
    else:
      handled = false
  if not handled:
    case cat2
    of "megatest":
      runJoinedTest(r, cat, testsDir, options)
      if isNimRepoTests():
        runJoinedTest(r, cat, testsDir, options & " --mm:refc")
    else:
      var testsRun = 0
      var files: seq[string] = @[]
      for file in walkDirRec(testsDir &.? cat.string):
        if isTestFile(file): files.add file
      files.sort # give reproducible order
      for i, name in files:
        var test = makeTest(name, options, cat)
        if runJoinableTests or not isJoinableSpec(test.spec) or cat.string in specialCategories:
          discard "run the test"
        else:
          test.spec.err = reJoined
        testSpec r, test
        inc testsRun
      if testsRun == 0:
        const whiteListedDirs = ["deps", "htmldocs", "pkgs"]
          # `pkgs` because bug #16556 creates `pkgs` dirs and this can affect some users
          # that try an old version of choosenim.
        doAssert cat.string in whiteListedDirs,
          "Invalid category specified: '$#' not in whilelist: $#" % [cat.string, $whiteListedDirs]

proc processPattern(r: var TResults, pattern, options: string; simulate: bool) =
  var testsRun = 0
  if dirExists(pattern):
    for k, name in walkDir(pattern):
      if k in {pcFile, pcLinkToFile} and name.endsWith(".nim"):
        if simulate:
          echo "Detected test: ", name
        else:
          var test = makeTest(name, options, Category"pattern")
          testSpec r, test
        inc testsRun
  else:
    for name in walkPattern(pattern):
      if simulate:
        echo "Detected test: ", name
      else:
        var test = makeTest(name, options, Category"pattern")
        testSpec r, test
      inc testsRun
  if testsRun == 0:
    echo "no tests were found for pattern: ", pattern
