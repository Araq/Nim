discard """
disabled: "arm64"
"""

proc testAsm() =
  let src = 41
  var dst = 0

  asm """
    mov %1, %0\n\t
    add $1, %0
    : "=r" (`dst`)
    : "r" (`src`)"""

  doAssert dst == 42

when defined(gcc) or defined(clang) and not defined(cpp):
  {.passc: "-std=c99".}
  testAsm()
