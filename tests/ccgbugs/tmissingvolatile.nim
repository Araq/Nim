discard """
  output: "1"
  cmd: r"nim c --hints:on $options --mm:refc -d:release $file"
  ccodecheck: "'NI volatile state_1;'"
  targets: "c"
"""

# bug #1539

proc err() =
  raise newException(Exception, "test")

proc main() =
  var state: int
  try:
    state = 1
    err()
  except:
    echo state

main()
