# issue #16439

import std/[strutils, sequtils]
var data = "aaa aaa"
echo data.split(" ").map(toSeq) #[tt.Error
                    ^ type mismatch: got <seq[string], template (iter: untyped): untyped>]#
