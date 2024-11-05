discard """
  ccodecheck: "time_t"
  joinable: false
"""

type
  Time* {.importc: "time_t", header: "<time.h>".} = distinct clong

proc foo =
  var s: Time = default(Time)
  discard s

foo()
