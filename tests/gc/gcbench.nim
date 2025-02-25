discard """
  outputsub: "Success!"
  retries: 2
"""

# This is adapted from a benchmark written by John Ellis and Pete Kovac
# of Post Communications.
# It was modified by Hans Boehm of Silicon Graphics.
#
# This is no substitute for real applications. No actual application
# is likely to behave in exactly this way. However, this benchmark was
# designed to be more representative of real applications than other
# Java GC benchmarks of which we are aware.
# It attempts to model those properties of allocation requests that
# are important to current GC techniques.
# It is designed to be used either to obtain a single overall performance
# number, or to give a more detailed estimate of how collector
# performance varies with object lifetimes. It prints the time
# required to allocate and collect balanced binary trees of various
# sizes. Smaller trees result in shorter object lifetimes. Each cycle
# allocates roughly the same amount of memory.
# Two data structures are kept around during the entire process, so
# that the measured performance is representative of applications
# that maintain some live in-memory data. One of these is a tree
# containing many pointers. The other is a large array containing
# double precision floating point numbers. Both should be of comparable
# size.
#
# The results are only really meaningful together with a specification
# of how much memory was used. It is possible to trade memory for
# better time performance. This benchmark should be run in a 32 MB
# heap, though we don't currently know how to enforce that uniformly.
#
# Unlike the original Ellis and Kovac benchmark, we do not attempt
# measure pause times. This facility should eventually be added back
# in. There are several reasons for omitting it for now.  The original
# implementation depended on assumptions about the thread scheduler
# that don't hold uniformly. The results really measure both the
# scheduler and GC. Pause time measurements tend to not fit well with
# current benchmark suites. As far as we know, none of the current
# commercial Java implementations seriously attempt to minimize GC pause
# times.
#
# Known deficiencies:
# - No way to check on memory use
# - No cyclic data structures
# - No attempt to measure variation with object size
# - Results are sensitive to locking cost, but we don't
#   check for proper locking
#

import
  strutils, times

type
  PNode = ref TNode
  TNode {.final, acyclic.} = object
    left, right: PNode
    i, j: int

proc newNode(L, r: sink PNode): PNode =
  new(result)
  result.left = L
  result.right = r

const
  kStretchTreeDepth = 18 # about 16Mb
  kLongLivedTreeDepth = 16  # about 4Mb
  kArraySize = 500000  # about 4Mb
  kMinTreeDepth = 4
  kMaxTreeDepth = 16

when not declared(withScratchRegion):
  template withScratchRegion(body: untyped) = body

# Nodes used by a tree of a given size
proc treeSize(i: int): int = return ((1 shl (i + 1)) - 1)

# Number of iterations to use for a given tree depth
proc numIters(i: int): int =
  return 2 * treeSize(kStretchTreeDepth) div treeSize(i)

# Build tree top down, assigning to older objects.
proc populate(iDepth: int, thisNode: PNode) =
  if iDepth <= 0:
    return
  else:
    new(thisNode.left)
    new(thisNode.right)
    populate(iDepth-1, thisNode.left)
    populate(iDepth-1, thisNode.right)

# Build tree bottom-up
proc makeTree(iDepth: int): PNode =
  if iDepth <= 0:
    new(result)
  else:
    return newNode(makeTree(iDepth-1), makeTree(iDepth-1))

proc printDiagnostics() =
  echo("Total memory available: " & formatSize(getTotalMem()) & " bytes")
  echo("Free memory: " & formatSize(getFreeMem()) & " bytes")

proc timeConstruction(depth: int) =
  var
    root, tempTree: PNode
    iNumIters: int

  iNumIters = numIters(depth)

  echo("Creating " & $iNumIters & " trees of depth " & $depth)
  var t = epochTime()
  for i in 0..iNumIters-1:
    new(tempTree)
    populate(depth, tempTree)
    tempTree = nil
  echo("\tTop down construction took " & $(epochTime() - t) & "msecs")
  t = epochTime()
  for i in 0..iNumIters-1:
    tempTree = makeTree(depth)
    tempTree = nil
  echo("\tBottom up construction took " & $(epochTime() - t) & "msecs")

type
  tMyArray = seq[float]

proc main() =
  var
    root, longLivedTree, tempTree: PNode
    myarray: tMyArray

  echo("Garbage Collector Test")
  echo(" Stretching memory with a binary tree of depth " & $kStretchTreeDepth)
  printDiagnostics()
  var t = epochTime()

  # Stretch the memory space quickly
  withScratchRegion:
    tempTree = makeTree(kStretchTreeDepth)
    tempTree = nil

  # Create a long lived object
  echo(" Creating a long-lived binary tree of depth " &
        $kLongLivedTreeDepth)
  new(longLivedTree)
  populate(kLongLivedTreeDepth, longLivedTree)

  # Create long-lived array, filling half of it
  echo(" Creating a long-lived array of " & $kArraySize & " doubles")
  withScratchRegion:
    newSeq(myarray, kArraySize)
    for i in 0..kArraySize div 2 - 1:
      myarray[i] = 1.0 / toFloat(i)

    printDiagnostics()

    var d = kMinTreeDepth
    while d <= kMaxTreeDepth:
      withScratchRegion:
        timeConstruction(d)
      inc(d, 2)

    if longLivedTree == nil or myarray[1000] != 1.0/1000.0:
      echo("Failed")
      # fake reference to LongLivedTree
      # and array to keep them from being optimized away

  var elapsed = epochTime() - t
  printDiagnostics()
  echo("Completed in " & $elapsed & "s. Success!")
  when declared(getMaxMem):
    echo "Max memory ", formatSize getMaxMem()

when defined(GC_setMaxPause):
  GC_setMaxPause 2_000

when defined(gcDestructors):
  let mem = getOccupiedMem()
main()
when defined(gcDestructors):
  doAssert getOccupiedMem() == mem
