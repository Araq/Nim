discard """
action: compile
"""

{.compile: "cffi.c".}

proc xx(): int {.importc.}

proc yy() {.memSafe.} =
  echo "yy"
  {.cast(memSafe).}:
    echo xx()

yy()
