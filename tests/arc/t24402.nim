discard """
  joinable: false
"""

# bug #24402

iterator myPairsInline*[T](twoDarray: seq[seq[T]]): (int, seq[T]) {.inline.} =
  for indexValuePair in twoDarray.pairs:
    yield indexValuePair

iterator myPairsClosure*[T](twoDarray: seq[seq[T]]): (int, seq[T]) {.closure.} =
  for indexValuePair in twoDarray.pairs:
    yield indexValuePair

template testTotalMem(iter: untyped): int =
  proc innerTestTotalMem(): int {.gensym.} =
    result = 0

    # do the same operation 100 times, which should have similar mem footprint
    # as doing it once.
    for iterNum in 0..100:
      result = max(result, getTotalMem()) # record current mem footprint

      # initialize nested sequence
      var my2dArray: seq[seq[int32]] = @[]

      # fill with some data...
      for i in 0'i32..10_000:
        var z = @[i, i+1]
        my2dArray.add z

      # use that data somehow...
      var otherContainer: seq[int32] = @[]
      var count = 0'i32
      for oneDindex, innerArray in my2dArray.iter:
        for value in innerArray:
          inc count
          if oneDindex > 50 and value < 200:
            otherContainer.add count

  innerTestTotalMem()

proc main =
  let closureMem = testTotalMem(myPairsClosure) #1052672
  let inlineMem = testTotalMem(myPairsInline) #20328448

  when defined(echoFootprint):
    echo "Closure memory footprint: " & $closureMem
    echo "Inline memory footprint: " & $inlineMem

  # check that mem footprint is relatively similar b/t each method
  doAssert (closureMem - inlineMem).abs < (closureMem div 10)

main()