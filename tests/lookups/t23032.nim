discard """
action: "run"
outputsub: "proc (a: A[system.float]): bool{.noSideEffect, gcsafe.}"
"""

import issue_23032/deep_scope

proc foo(a: A[float]):bool = true

let p: proc = foo
echo p.typeof
doAssert p(A[float]()) == true
doAssert compiles(doAssert p(A[int]()) == true) == false
