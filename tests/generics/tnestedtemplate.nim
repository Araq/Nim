block: # issue #13979
  var s: seq[int]
  proc filterScanline[T](input: openArray[T]) =
    template currPix: untyped = input[i]
    for i in 0..<input.len:
      s.add currPix
  let pix = [1, 2, 3]
  filterScanline(pix)
  doAssert s == @[1, 2, 3]
