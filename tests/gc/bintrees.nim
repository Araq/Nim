discard """
  retries: 2
"""

# -*- nim -*-

import os, strutils

type
  PNode = ref TNode
  TNode {.final, acyclic.} = object
    left, right: PNode
    item: int

proc checkTree(node: PNode): int =
  result = node.item
  if node.left != nil:
    inc result, checkTree(node.left) - checkTree(node.right)

proc makeTreeAux(item, depth: int): PNode =
  new(result)
  result.item = item
  if depth > 0:
    result.left = makeTreeAux(2 * item - 1, depth - 1)
    result.right = makeTreeAux(2 * item,    depth - 1)

proc makeTree(item, depth: int): PNode =
  #GC_disable()
  result = makeTreeAux(item, depth)
  #GC_enable()

proc main =
  var n = parseInt(paramStr(1))
  const minDepth = 4
  var maxDepth = if minDepth+2 > n: minDepth+2 else: n

  var stretchDepth = maxDepth + 1

  echo("stretch tree of depth ", stretchDepth, "\t check: ", checkTree(
      makeTree(0, stretchDepth)))

  var longLivedTree = makeTree(0, maxDepth)

  var iterations = 1 shl maxDepth
  for depth in countup (minDepth, stretchDepth-1, 2):
    var check = 0
    for i in 1..iterations:
      check += checkTree(makeTree(i, depth)) + checkTree(makeTree(-i, depth))

    echo(iterations*2, "\t trees of depth ", depth, "\t check: ", check)
    iterations = iterations div 4

  echo("long lived tree of depth ", maxDepth, "\t check: ",
      longLivedTree.checkTree)
  echo GC_getstatistics()

main()

