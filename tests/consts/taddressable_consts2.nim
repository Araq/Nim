discard """
  joinable: false
"""

block:

  const magic_numbers {.exportc.} = 12

  let sss {.importc: "magic_numbers", nodecl.} : int

  doAssert magic_numbers == 12
  doAssert sss == 12

block:
  proc magics(): array[3, int] =
    result = [1, 2, 3]


  const magic_arrays {.exportc.} = magics()

  let sss {.importc: "magic_arrays", nodecl.} : array[3, int]

  doAssert magic_arrays[1] == 2
  doAssert sss[2] == 3
