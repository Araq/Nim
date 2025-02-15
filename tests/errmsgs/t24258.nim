discard """
  cmd: "nim check $file"
  errormsg: "illformed AST: [22]43.len"
  joinable: false
"""

template encodeList*(args: varargs[untyped]): seq[byte] =
  @[byte args.len]

let x = encodeList([22], 43)