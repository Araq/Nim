discard """
  errormsg: "'result' is of type <int> which cannot be captured as it would violate memory safety, declared here: tresultcapture.nim(13, 1); using '-d:nimNoLentIterators' helps in some cases. Consider using a <ref int> which can be captured"
  line: 16
"""

proc foo(): ref int =
  new result
  proc inner =
    echo result[]
  inner()
discard foo()

proc bar(): int =
  result = 0
  proc inner =
    echo result # illegal capture
  inner()
discard bar()