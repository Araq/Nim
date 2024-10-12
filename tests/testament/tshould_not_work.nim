discard """
  joinable: false
"""

const expected = """
FAIL: tests/shouldfail/tccodecheck.nim
Failure: reCodegenFailure
Expected:
baz
FAIL: tests/shouldfail/tcolumn.nim
Failure: reLinesDiffer
FAIL: tests/shouldfail/terrormsg.nim
Failure: reMsgsDiffer
FAIL: tests/shouldfail/texitcode1.nim
Failure: reExitcodesDiffer
FAIL: tests/shouldfail/tfile.nim
Failure: reFilesDiffer
FAIL: tests/shouldfail/tline.nim
Failure: reLinesDiffer
FAIL: tests/shouldfail/tmaxcodesize.nim
Failure: reCodegenFailure
max allowed size: 1
FAIL: tests/shouldfail/tnimout.nim
Failure: reMsgsDiffer
FAIL: tests/shouldfail/tnimoutfull.nim
Failure: reMsgsDiffer
FAIL: tests/shouldfail/tnotenoughretries.nim
Failure: reExitcodesDiffer
FAIL: tests/shouldfail/toutput.nim
Failure: reOutputsDiffer
FAIL: tests/shouldfail/toutputsub.nim
Failure: reOutputsDiffer
FAIL: tests/shouldfail/treject.nim
Failure: reFilesDiffer
FAIL: tests/shouldfail/tsortoutput.nim
Failure: reOutputsDiffer
FAIL: tests/shouldfail/ttimeout.nim
Failure: reTimeout
FAIL: tests/shouldfail/tvalgrind.nim
Failure: reExitcodesDiffer
"""

import std/[os,strformat,osproc]
import stdtest/testutils

proc main =
  const nim = getCurrentCompilerExe()
  let testamentExe = "testament/testament"
  let cmd = fmt"{testamentExe} --directory:testament --colors:off --backendLogging:off --nim:{nim} category shouldfail"
  let (outp, status) = execCmdEx(cmd)
  doAssert status == 1, $status

  let ok = greedyOrderedSubsetLines(expected, outp, allowPrefixMatch = true)
  doAssert ok, &"\nexpected:\n{expected}\noutp:\n{outp}"
main()
