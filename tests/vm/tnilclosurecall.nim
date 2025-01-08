discard """
  errormsg: "attempt to call nil closure"
  line: 8
"""

static:
  let x: proc () = nil
  x()
