#
#
#            Nim Tester
#        (c) Copyright 2017 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## HTML generator for the tester.

import strutils, json, os, times

import "testamenthtml.nimf"

proc generateTestResultPanelPartial(outfile: File, testResultRow: JsonNode) =
  let
    trId = htmlQuote(testResultRow["category"].str & "_" & testResultRow["name"].str).
        multiReplace({".": "_", " ": "_", ":": "_", "/": "_"})
    name = testResultRow["name"].str.htmlQuote()
    category = testResultRow["category"].str.htmlQuote()
    target = testResultRow["target"].str.htmlQuote()
    action = testResultRow["action"].str.htmlQuote()
    result = htmlQuote testResultRow["result"].str
    expected = testResultRow["expected"].getStr
    gotten = testResultRow["given"].getStr
    timestamp = "unknown"
  var
    panelCtxClass, textCtxClass, bgCtxClass: string
    resultSign, resultDescription: string
  case result
  of "reSuccess":
    panelCtxClass = "success"
    textCtxClass = "success"
    bgCtxClass = "success"
    resultSign = "ok"
    resultDescription = "PASS"
  of "reDisabled", "reJoined":
    panelCtxClass = "info"
    textCtxClass = "info"
    bgCtxClass = "info"
    resultSign = "question"
    resultDescription = if result != "reJoined": "SKIP" else: "JOINED"
  else:
    panelCtxClass = "danger"
    textCtxClass = "danger"
    bgCtxClass = "danger"
    resultSign = "exclamation"
    resultDescription = "FAIL"

  outfile.generateHtmlTestresultPanelBegin(
    trId, name, target, category, action, resultDescription,
    timestamp, result, resultSign, panelCtxClass, textCtxClass, bgCtxClass
  )
  if expected.isEmptyOrWhitespace() and gotten.isEmptyOrWhitespace():
    outfile.generateHtmlTestresultOutputNone()
  else:
    outfile.generateHtmlTestresultOutputDetails(
      expected.strip().htmlQuote,
      gotten.strip().htmlQuote
    )
  outfile.generateHtmlTestresultPanelEnd()

type
  AllTests = object
    data: JsonNode
    totalCount, successCount, ignoredCount, failedCount: int
    successPercentage, ignoredPercentage, failedPercentage: BiggestFloat

proc allTestResults(onlyFailing = false): AllTests =
  result = AllTests(data: newJArray())
  for file in os.walkFiles("testresults/*.json"):
    let data = parseFile(file)
    if data.kind != JArray:
      echo "[ERROR] ignoring json file that is not an array: ", file
    else:
      for elem in data:
        let state = elem["result"].str
        inc result.totalCount
        if state.contains("reSuccess"): inc result.successCount
        elif state.contains("reDisabled") or state.contains("reJoined"):
          inc result.ignoredCount
        if not onlyFailing or not(state.contains("reSuccess")):
          result.data.add elem
  result.successPercentage = 100 *
    (result.successCount.toBiggestFloat / result.totalCount.toBiggestFloat)
  result.ignoredPercentage = 100 *
    (result.ignoredCount.toBiggestFloat / result.totalCount.toBiggestFloat)
  result.failedCount = result.totalCount -
    result.successCount - result.ignoredCount
  result.failedPercentage = 100 *
    (result.failedCount.toBiggestFloat / result.totalCount.toBiggestFloat)

proc generateTestResultsPanelGroupPartial(outfile: File, allResults: JsonNode) =
  for testresultRow in allResults:
    generateTestResultPanelPartial(outfile, testresultRow)

proc generateAllTestsContent(outfile: File, allResults: AllTests,
  onlyFailing = false) =
  if allResults.data.len < 1: return # Nothing to do if there is no data.
  # Only results from one test run means that test run environment info is the
  # same for all tests
  let
    firstRow = allResults.data[0]
    commit = htmlQuote firstRow["commit"].str
    branch = htmlQuote firstRow["branch"].str
    machine = htmlQuote firstRow["machine"].str

  outfile.generateHtmlAllTestsBegin(
    machine, commit, branch,
    allResults.totalCount,
    allResults.successCount,
    formatBiggestFloat(allResults.successPercentage, ffDecimal, 2) & "%",
    allResults.ignoredCount,
    formatBiggestFloat(allResults.ignoredPercentage, ffDecimal, 2) & "%",
    allResults.failedCount,
    formatBiggestFloat(allResults.failedPercentage, ffDecimal, 2) & "%",
    onlyFailing
  )
  generateTestResultsPanelGroupPartial(outfile, allResults.data)
  outfile.generateHtmlAllTestsEnd()

proc generateHtml*(filename: string, onlyFailing: bool) =
  let
    currentTime = getTime().local()
    timestring = htmlQuote format(currentTime, "yyyy-MM-dd HH:mm:ss 'UTC'zzz")
  var outfile = open(filename, fmWrite)

  outfile.generateHtmlBegin()

  generateAllTestsContent(outfile, allTestResults(onlyFailing), onlyFailing)

  outfile.generateHtmlEnd(timestring)

  outfile.flushFile()
  close(outfile)

proc dumpJsonTestResults*(prettyPrint, onlyFailing: bool) =
  var
    outfile = stdout
    jsonString: string

  let results = allTestResults(onlyFailing)
  if prettyPrint:
    jsonString = results.data.pretty()
  else:
    jsonString = $ results.data

  outfile.writeLine(jsonString)
