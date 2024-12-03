discard """
  matrix: "-u:nimPreviewNonVarDestructor;"
"""
type DistinctSeq* = distinct seq[int]

# `=destroy`(cast[ptr DistinctSeq](0)[])
var x = @[].DistinctSeq
`=destroy`(x)
