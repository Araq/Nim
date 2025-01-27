discard """
  joinable: false
"""

block:
  proc magics(): array[3, int] =
    result = [1, 2, 3]


  const magic_arrays {.exportc.} = magics()

  let sss {.importc: "magic_arrays", nodecl.} : array[3, int]


  doAssert sss[2] == 3

block:
  proc magics(): int =
    result = 12


  const magic_numbers {.exportc.} = magics()

  let sss {.importc: "magic_numbers", nodecl.} : int

  doAssert sss == 12
