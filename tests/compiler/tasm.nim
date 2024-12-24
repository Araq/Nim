proc testAsm() =
  let src = 41
  var dst = 0

  when defined(i386) or defined(amd64):
    asm """
      mov %1, %0\n\t
      add $1, %0
      : "=r" (`dst`)
      : "r" (`src`)"""
  elif defined(arm) or defined(arm64):
    asm """
      mov %0, %1\n\t
      add %0, %0, #1
      : "=r" (`dst`)
      : "r" (`src`)"""
  elif defined(riscv32) or defined(riscv64):
    asm """
      addi %0, %1, 0\n\t
      addi %0, %0, 1
      : "=r" (`dst`)
      : "r" (`src)"""

  doAssert dst == 42

when defined(gcc) or defined(clang) and not defined(cpp):
  {.passc: "-std=c99".}
  testAsm()
