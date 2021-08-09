type State = enum
  sInStart
  sInRegular
  sInSpace
  sInSingleQuote
  sInDoubleQuote
  sFinished

type ShlexError = enum
  seOk
  seMissingDoubleQuote
  seMissingSingleQuote

iterator shlex*(a: openArray[char], error: var ShlexError): string =
  var i = 0
  var buf: string
  var state = sInStart
  var ready = false
  error = seOk
  const
    ShellWhiteSpace = {' ', '\t'} # not \n
    Quote = '\''
    DoubleQuote = '"'
  while true:
    if i >= a.len:
      case state
      of sInSingleQuote: error = seMissingSingleQuote
      of sInDoubleQuote: error = seMissingDoubleQuote
      of sInStart: discard
      else: ready = true
      state = sFinished
    var c: char
    if i < a.len:
      c = a[i]
    i.inc
    case state
    of sFinished: discard
    of sInStart:
      case c
      of ShellWhiteSpace: discard
      of Quote: state = sInSingleQuote
      of DoubleQuote: state = sInDoubleQuote
      else:
        state = sInRegular
        buf.add c
    of sInRegular:
      case c
      of ShellWhiteSpace: ready = true
      of Quote: state = sInSingleQuote
      of DoubleQuote: state = sInDoubleQuote
      else: buf.add c
    of sInSingleQuote:
      case c
      of Quote: state = sInRegular
      else: buf.add c
    of sInDoubleQuote:
      case c
      of DoubleQuote: state = sInRegular
      else: buf.add c
    of sInSpace:
      case c
      of ShellWhiteSpace: discard
      of Quote: state = sInSingleQuote
      of DoubleQuote: state = sInDoubleQuote
      else:
        state = sInRegular
        buf.add c
    if ready:
      ready = false
      yield buf
      buf.setLen 0
      if state != sFinished:
        state = sInStart
    if state == sFinished:
      break

iterator shlex*(a: openArray[char]): string =
  var err: ShlexError
  for val in shlex(a, err):
    assert err == seOk
    yield val
  if err != seOk:
    var msg = "error: " & $err & " a: "
    for ai in a: msg.add ai
    raise newException(ValueError, msg)
