discard """
  targets: "c cpp"
  disabled: "arm64"
"""

import std/strutils

block: # bug #23114
  func ccopy_x86_asm(ctl: uint64, x: var uint64, y: uint64) =
    asm """
      testq %[ctl], %[ctl]
      cmovnzq %[y], %[x]
      : [x] "+r" (`x`)
      : [ctl] "r" (`ctl`), [y] "r" (`y`)
      : "cc"
    """

  func ccopy_x86_emit(ctl: uint64, x: var uint64, y: uint64) =
    {.emit:[
      """
      asm volatile(
        "testq %[ctl], %[ctl]\n"
        "cmovnzq %[y], %[x]\n"
        : [x] "+r" (""", x, """)
        : [ctl] "r" (""", ctl, """), [y] "r" (""", y, """)
        : "cc"
      );"""].}


  let x = 0x1111111'u64
  let y = 0xFFFFFFF'u64

  block:
    let ctl = 1'u64
    var a0 = x
    ctl.ccopy_x86_asm(a0, y)

    var a1 = x
    ctl.ccopy_x86_emit(a1, y)

    doAssert a0.toHex() == "000000000FFFFFFF"
    doAssert a0 == a1

  block:
    let ctl = 0'u64
    var a0 = x
    ctl.ccopy_x86_asm(a0, y)

    var a1 = x
    ctl.ccopy_x86_emit(a1, y)

    doAssert a0.toHex() == "0000000001111111"
    doAssert a0 == a1

