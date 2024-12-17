discard """
  targets: "c cpp"
  joinable: false
"""

## tests that don't quite fit the mold and are easier to handle via `execCmdEx`
## A few others could be added to here to simplify code.
## Note: this test is a bit slow but tests a lot of things; please don't disable.
## Note: if needed, we could use `matrix: "-d:case1; -d:case2"` to split this
## into several independent tests while retaining the common test helpers.

import std/[strformat,os,osproc,unittest,compilesettings]
from std/sequtils import toSeq,mapIt
from std/algorithm import sorted
import stdtest/[specialpaths, unittest_light]
from std/private/globs import nativeToUnixPath
from strutils import startsWith, strip, removePrefix
from std/sugar import dup
import "$lib/../compiler/nimpaths"

proc isDots(a: string): bool =
  ## test for `hintProcessing` dots
  a.startsWith(".") and a.strip(chars = {'.'}) == ""

const
  nim = getCurrentCompilerExe()
  mode = querySetting(backend)
  nimcache = buildDir / "nimcacheTrunner"
    # instead of `querySetting(nimcacheDir)`, avoids stomping on other parallel tests

proc runNimCmd(file, options = "", rtarg = ""): auto =
  let fileabs = testsDir / file.unixToNativePath
  # doAssert fileabs.fileExists, fileabs # disabled because this allows passing `nim r --eval:code fakefile`
  let cmd = fmt"{nim} {mode} --hint:all:off {options} {fileabs} {rtarg}"
  result = execCmdEx(cmd)
  when false: # for debugging
    echo cmd
    echo result[0] & "\n" & $result[1]

proc runNimCmdChk(file, options = "", rtarg = "", status = 0): string =
  let (ret, status2) = runNimCmd(file, options, rtarg = rtarg)
  doAssert status2 == status, $(file, options, status, status2) & "\n" & ret
  ret

proc genShellCmd(filename: string): string =
  let filename = filename.quoteShell
  when defined(windows): "cmd /c " & filename # or "cmd /c " ?
  else: "sh " & filename

when defined(nimTrunnerFfi):
  block: # mevalffi
    when defined(openbsd):
      #[
      openbsd defines `#define stderr (&__sF[2])` which makes it cumbersome
      for dlopen'ing inside `importcSymbol`. Instead of adding special rules
      inside `importcSymbol` to handle this, we disable just the part that's
      not working and will provide a more general, clean fix in future PR.
      ]#
      var opt = "-d:nimEvalffiStderrWorkaround"
      let prefix = ""
    else:
      var opt = ""
      let prefix = """
hello world stderr
hi stderr
"""
    let output = runNimCmdChk("vm/mevalffi.nim", fmt"{opt} --warnings:off --experimental:compiletimeFFI")
    doAssert output == fmt"""
{prefix}foo
foo:100
foo:101
foo:102:103
foo:102:103:104
foo:0.03:asdf:103:105
ret=[s1:foobar s2:foobar age:25 pi:3.14]
""", output

elif not defined(nimTestsTrunnerDebugging):
  # don't run twice the same test with `nimTrunnerFfi`
  # use `-d:nimTestsTrunnerDebugging` for debugging convenience when you want to just run 1 test
  import std/strutils
  import std/json
  template check2(msg) = doAssert msg in output, output

  block: # tests with various options `nim doc --project --index --docroot`
    # regression tests for issues and PRS: #14376 #13223 #6583 ##13647
    let file = testsDir / "nimdoc/sub/mmain.nim"
    let mainFname = "mmain.html"
    let htmldocsDirCustom = nimcache / "htmldocsCustom"
    let docroot = testsDir / "nimdoc"
    let options = [
      0: "--project",
      1: "--project --docroot",
      2: "",
      3: fmt"--outDir:{htmldocsDirCustom}",
      4: fmt"--docroot:{docroot}",
      5: "--project --useNimcache",
      6: "--index:off",
    ]

    for i in 0..<options.len:
      let htmldocsDir = case i
      of 3: htmldocsDirCustom
      of 5: nimcache / htmldocsDirname
      else: file.parentDir / htmldocsDirname

      var cmd = fmt"{nim} doc --index:on --filenames:abs --hint:successX:on --nimcache:{nimcache} {options[i]} {file}"
      removeDir(htmldocsDir)
      let (outp, exitCode) = execCmdEx(cmd)
      check exitCode == 0
      let ret = toSeq(walkDirRec(htmldocsDir, relative=true)).mapIt(it.nativeToUnixPath).sorted.join("\n")
      let context = $(i, ret, cmd)
      case i
      of 0,5:
        let htmlFile = htmldocsDir/mainFname
        check htmlFile in outp # sanity check for `hintSuccessX`
        assertEquals ret, fmt"""
{dotdotMangle}/imp.html
{dotdotMangle}/imp.idx
{docHackJsFname}
imp.html
imp.idx
imp2.html
imp2.idx
{mainFname}
mmain.idx
{nimdocOutCss}
{theindexFname}""", context
      of 1: assertEquals ret, fmt"""
{docHackJsFname}
{nimdocOutCss}
tests/nimdoc/imp.html
tests/nimdoc/imp.idx
tests/nimdoc/sub/imp.html
tests/nimdoc/sub/imp.idx
tests/nimdoc/sub/imp2.html
tests/nimdoc/sub/imp2.idx
tests/nimdoc/sub/{mainFname}
tests/nimdoc/sub/mmain.idx
{theindexFname}"""
      of 2, 3: assertEquals ret, fmt"""
{docHackJsFname}
{mainFname}
mmain.idx
{nimdocOutCss}""", context
      of 4: assertEquals ret, fmt"""
{docHackJsFname}
{nimdocOutCss}
sub/{mainFname}
sub/mmain.idx""", context
      of 6: assertEquals ret, fmt"""
{mainFname}
{nimdocOutCss}""", context
      else: doAssert false

  block: # mstatic_assert
    let (output, exitCode) = runNimCmd("ccgbugs/mstatic_assert.nim", "-d:caseBad")
    check2 "sizeof(bool) == 2"
    check exitCode != 0

  block: # ABI checks
    let file = "misc/msizeof5.nim"
    block:
      discard runNimCmdChk(file, "-d:checkAbi")
    block:
      let (output, exitCode) = runNimCmd(file, "-d:checkAbi -d:caseBad")
      # on platforms that support _StaticAssert natively, errors will show full context, e.g.:
      # error: static_assert failed due to requirement 'sizeof(unsigned char) == 8'
      # "backend & Nim disagree on size for: BadImportcType{int64} [declared in mabi_check.nim(1, 6)]"
      check2 "sizeof(unsigned char) == 8"
      check2 "sizeof(struct Foo2) == 1"
      check2 "sizeof(Foo5) == 16"
      check2 "sizeof(Foo5) == 3"
      check2 "sizeof(struct Foo6) == "
      check exitCode != 0

  import streams
  block: # stdin input
    let nimcmd = fmt"""{nim} r --hints:off - -firstparam "-second param" """
    let expected = """@["-firstparam", "-second param"]"""
    block:
      let p = startProcess(nimcmd, options = {poEvalCommand})
      p.inputStream.write("import os; echo commandLineParams()")
      p.inputStream.close
      var output = p.outputStream.readAll
      let error = p.errorStream.readAll
      doAssert p.waitForExit == 0
      doAssert error.len == 0, $error
      output.stripLineEnd
      check output == expected
      p.errorStream.close
      p.outputStream.close

    block:
      when defined posix:
        # xxx on windows, `poEvalCommand` should imply `/cmd`, (which should
        # make this work), but currently doesn't
        let cmd = fmt"""echo "import os; echo commandLineParams()" | {nimcmd}"""
        var (output, exitCode) = execCmdEx(cmd)
        output.stripLineEnd
        check output == expected
        doAssert exitCode == 0

  block: # nim doc --backend:$backend --doccmd:$cmd
    # test for https://github.com/nim-lang/Nim/issues/13129
    # test for https://github.com/nim-lang/Nim/issues/13891
    let file = testsDir / "nimdoc/m13129.nim"
    for backend in fmt"{mode} js".split:
      # pending #14343 this fails on windows: --doccmd:"-d:m13129Foo2 --hints:off"
      let cmd = fmt"""{nim} doc -b:{backend} --nimcache:{nimcache} -d:m13129Foo1 "--doccmd:-d:m13129Foo2 --hints:off" --usenimcache --hints:off {file}"""
      check execCmdEx(cmd) == (&"ok1:{backend}\nok2: backend: {backend}\n", 0)
    # checks that --usenimcache works with `nim doc`
    check fileExists(nimcache / "htmldocs/m13129.html")

    block: # mak sure --backend works with `nim r`
      let cmd = fmt"{nim} r --backend:{mode} --hints:off --nimcache:{nimcache} {file}"
      check execCmdEx(cmd) == ("ok3\n", 0)

  block: # nim jsondoc # bug #20132
    let file = testsDir / "misc/mjsondoc.nim"
    let output = "nimcache_tjsondoc.json"
    defer: removeFile(output)
    let (msg, exitCode) = execCmdEx(fmt"{nim} jsondoc -o:{output} {file}")
    doAssert exitCode == 0, msg

    let data = parseJson(readFile(output))["entries"]
    doAssert data.len == 5
    let doSomething = data[0]
    doAssert doSomething["name"].getStr == "doSomething"
    doAssert doSomething["type"].getStr == "skProc"
    doAssert doSomething["line"].getInt == 1
    doAssert doSomething["col"].getInt == 0
    doAssert doSomething["code"].getStr == "proc doSomething(x, y: int): int {.raises: [], tags: [], forbids: [].}"
    let foo2 = data[4]
    doAssert $foo2["signature"] == """{"arguments":[{"name":"x","type":"T"},{"name":"y","type":"U"},{"name":"z","type":"M"}],"genericParams":[{"name":"T","types":"int"},{"name":"M","types":"string"},{"name":"U"}]}"""

  block: # nim jsondoc # bug #11953
    let file = testsDir / "misc/mjsondoc.nim"
    let destDir = testsDir / "misc/htmldocs"
    removeDir(destDir)
    defer: removeDir(destDir)
    let (msg, exitCode) = execCmdEx(fmt"{nim} jsondoc {file}")
    doAssert exitCode == 0, msg

    let data = parseJson(readFile(destDir / "mjsondoc.json"))["entries"]
    doAssert data.len == 5
    let doSomething = data[0]
    doAssert doSomething["name"].getStr == "doSomething"
    doAssert doSomething["type"].getStr == "skProc"
    doAssert doSomething["line"].getInt == 1
    doAssert doSomething["col"].getInt == 0
    doAssert doSomething["code"].getStr == "proc doSomething(x, y: int): int {.raises: [], tags: [], forbids: [].}"

  block: # further issues with `--backend`
    let file = testsDir / "misc/mbackend.nim"
    var cmd = fmt"{nim} doc -b:cpp --hints:off --nimcache:{nimcache} {file}"
    check execCmdEx(cmd) == ("", 0)
    cmd = fmt"{nim} check -b:c -b:cpp --hints:off --nimcache:{nimcache} {file}"
    check execCmdEx(cmd) == ("", 0)
    # issue https://github.com/timotheecour/Nim/issues/175
    cmd = fmt"{nim} c -b:js -b:cpp --hints:off --nimcache:{nimcache} {file}"
    check execCmdEx(cmd) == ("", 0)

  block: # some importc tests
    # issue #14314
    let file = testsDir / "misc/mimportc.nim"
    let cmd = fmt"{nim} r -b:cpp --hints:off --nimcache:{nimcache} --warningAsError:ProveInit {file}"
    check execCmdEx(cmd) == ("witness\n", 0)

  block: # bug #20149
    let file = testsDir / "misc/m20149.nim"
    let cmd = fmt"{nim} r --hints:off --nimcache:{nimcache} --hintAsError:XDeclaredButNotUsed {file}"
    check execCmdEx(cmd) == ("12\n", 0)

  block: # bug #15316
    when not defined(windows):
      # This never worked reliably on Windows. Needs further investigation but it is hard to reproduce.
      # Looks like a mild stack corruption when bailing out of nested exception handling.
      let file = testsDir / "misc/m15316.nim"
      let cmd = fmt"{nim} check --hints:off --nimcache:{nimcache} {file}"
      check execCmdEx(cmd) == ("m15316.nim(1, 15) Error: expression expected, but found \')\'\nm15316.nim(2, 1) Error: expected: \':\', but got: \'[EOF]\'\nm15316.nim(2, 1) Error: expression expected, but found \'[EOF]\'\nm15316.nim(2, 1) " &
            "Error: expected: \')\', but got: \'[EOF]\'\nError: illformed AST: \n", 1)


  block: # config.nims, nim.cfg, hintConf, bug #16557
    let cmd = fmt"{nim} r --hint:all:off --hint:conf tests/newconfig/bar/mfoo.nim"
    let (outp, exitCode) = execCmdEx(cmd, options = {poStdErrToStdOut})
    doAssert exitCode == 0
    let dir = getCurrentDir()
    let files = """
tests/config.nims
tests/newconfig/bar/nim.cfg
tests/newconfig/bar/config.nims
tests/newconfig/bar/mfoo.nim.cfg
tests/newconfig/bar/mfoo.nims""".splitLines
    var expected = ""
    for a in files:
      let b = dir / a
      expected.add &"Hint: used config file '{b}' [Conf]\n"
    doAssert outp.endsWith expected, outp & "\n" & expected

  block: # bug #8219
    let file = "tests/newconfig/mconfigcheck.nims"
    let cmd = fmt"{nim} check --hints:off {file}"
    check execCmdEx(cmd) == ("", 0)

  block: # mfoo2.customext
    let filename = testsDir / "newconfig/foo2/mfoo2.customext"
    let cmd = fmt"{nim} e --hint:conf {filename}"
    let (outp, exitCode) = execCmdEx(cmd, options = {poStdErrToStdOut})
    doAssert exitCode == 0
    var expected = &"Hint: used config file '{filename}' [Conf]\n"
    doAssert outp.endsWith "123" & "\n" & expected


  block: # nim --eval
    let opt = "--hints:off"
    check fmt"""{nim} {opt} --eval:"echo defined(nimscript)"""".execCmdEx == ("true\n", 0)
    check fmt"""{nim} r {opt} --eval:"echo defined(c)"""".execCmdEx == ("true\n", 0)
    check fmt"""{nim} r -b:js {opt} --eval:"echo defined(js)"""".execCmdEx == ("true\n", 0)

  block: # `hintProcessing` dots should not interfere with `static: echo` + friends
    let cmd = fmt"""{nim} r --hint:all:off --hint:processing -f --eval:"static: echo 1+1""""
    let (outp, exitCode) = execCmdEx(cmd, options = {poStdErrToStdOut})
    template check3(cond) = doAssert cond, $(outp,)
    doAssert exitCode == 0
    let lines = outp.splitLines
    check3 lines.len == 3
    when not defined(windows): # xxx: on windows, dots not properly handled, gives: `....2\n\n`
      check3 lines[0].isDots
      check3 lines[1] == "2"
      check3 lines[2] == ""
    else:
      check3 "2" in outp

  block: # nim secret
    let opt = "--hint:all:off --hint:processing"
    template check3(cond) = doAssert cond, $(outp,)
    for extra in ["", "--stdout"]:
      let cmd = fmt"""{nim} secret {opt} {extra}"""
      # xxx minor bug: `nim --hint:QuitCalled:off secret` ignores the hint cmdline flag
      template run(input2): untyped =
        execCmdEx(cmd, options = {poStdErrToStdOut}, input = input2)
      block:
        let (outp, exitCode) = run """echo 1+2; import strutils; echo strip(" ab "); quit()"""
        let lines = outp.splitLines
        when not defined(windows):
          check3 lines.len == 5
          check3 lines[0].isDots
          # check3 lines[1].isDots # todo nim secret might use parsing pipeline
          check3 lines[2].dup(removePrefix(">>> ")) == "3" # prompt depends on `nimUseLinenoise`
          check3 lines[3] == "ab"
          check3 lines[4] == ""
        else:
          check3 "3" in outp
          check3 "ab" in outp
        doAssert exitCode == 0
      block:
        let (outp, exitCode) = run "echo 1+2; quit(2)"
        check3 "3" in outp
        doAssert exitCode == 2

  block: # nimBetterRun
    let file = "misc/mbetterrun.nim"
    const nimcache2 = buildDir / "D20210423T185116"
    removeDir nimcache2
    # related to `-d:nimBetterRun`
    let opt = fmt"-r --usenimcache --nimcache:{nimcache2}"
    var ret = ""
    for a in @["v1", "v2", "v1", "v3"]:
      ret.add runNimCmdChk(file, fmt"{opt} -d:mbetterrunVal:{a}")
    ret.add runNimCmdChk(file, fmt"{opt} -d:mbetterrunVal:v2", rtarg = "arg1 arg2")
      # rt arguments should not cause a recompilation
    doAssert ret == """
compiling: v1
running: v1
compiling: v2
running: v2
running: v1
compiling: v3
running: v3
running: v2
""", ret

  block: # nim dump
    let cmd = fmt"{nim} dump --dump.format:json -d:D20210428T161003 --hints:off ."
    let (ret, status) = execCmdEx(cmd)
    doAssert status == 0
    let j = ret.parseJson
    # sanity checks
    doAssert "D20210428T161003" in j["defined_symbols"].to(seq[string])
    doAssert j["version"].to(string) == NimVersion
    doAssert j["nimExe"].to(string) == getCurrentCompilerExe()

  block: # genscript
    const nimcache2 = buildDir / "D20210524T212851"
    removeDir(nimcache2)
    let input = "tgenscript_fakefile" # no need for a real file, --eval is good enough
    let output = runNimCmdChk(input, fmt"""--genscript --nimcache:{nimcache2.quoteShell} --eval:"echo(12345)" """)
    doAssert output.len == 0, output
    let ext = when defined(windows): ".bat" else: ".sh"
    let filename = fmt"compile_{input}{ext}" # synchronize with `generateScript`
    doAssert fileExists(nimcache2/filename), nimcache2/filename
    let (outp, status) = execCmdEx(genShellCmd(filename), options = {poStdErrToStdOut}, workingDir = nimcache2)
    doAssert status == 0, outp
    let (outp2, status2) = execCmdEx(nimcache2 / input, options = {poStdErrToStdOut})
    doAssert outp2 == "12345\n", outp2
    doAssert status2 == 0

  block: # UnusedImport
    proc fn(opt: string, expected: string) =
      let output = runNimCmdChk("msgs/mused3.nim", fmt"--warning:all:off --warning:UnusedImport --hint:DuplicateModuleImport {opt}")
      doAssert output == expected, opt & "\noutput:\n" & output & "expected:\n" & expected
    fn("-d:case1"): """
mused3.nim(13, 8) Warning: imported and not used: 'mused3b' [UnusedImport]
"""
    fn("-d:case2"): ""
    fn("-d:case3"): ""
    fn("-d:case4"): ""
    fn("-d:case5"): ""
    fn("-d:case6"): ""
    fn("-d:case7"): ""
    fn("-d:case8"): ""
    fn("-d:case9"): ""
    fn("-d:case10"): ""
    when false:
      fn("-d:case11"): """
  Warning: imported and not used: 'm2' [UnusedImport]
  """
    fn("-d:case12"): """
mused3.nim(75, 10) Hint: duplicate import of 'mused3a'; previous import here: mused3.nim(74, 10) [DuplicateModuleImport]
"""

  block: # FieldDefect
    proc fn(opt: string, expected: string) =
      let output = runNimCmdChk("misc/mfield_defect.nim", fmt"-r --warning:all:off --declaredlocs {opt}", status = 1)
      doAssert expected in output, opt & "\noutput:\n" & output & "expected:\n" & expected
    fn("-d:case1"): """mfield_defect.nim(25, 15) Error: field 'f2' is not accessible for type 'Foo' [discriminant declared in mfield_defect.nim(14, 8)] using 'kind = k3'"""
    fn("-d:case2 --gc:refc"): """mfield_defect.nim(25, 15) field 'f2' is not accessible for type 'Foo' [discriminant declared in mfield_defect.nim(14, 8)] using 'kind = k3'"""
    fn("-d:case1 -b:js"): """mfield_defect.nim(25, 15) Error: field 'f2' is not accessible for type 'Foo' [discriminant declared in mfield_defect.nim(14, 8)] using 'kind = k3'"""
    fn("-d:case2 -b:js"): """field 'f2' is not accessible for type 'Foo' [discriminant declared in mfield_defect.nim(14, 8)] using 'kind = k3'"""
    fn("-d:case2 --gc:arc"): """mfield_defect.nim(25, 15) field 'f2' is not accessible for type 'Foo' [discriminant declared in mfield_defect.nim(14, 8)] using 'kind = k3'"""
else:
  discard # only during debugging, tests added here will run with `-d:nimTestsTrunnerDebugging` enabled
