# comment on issue #11167

import msetiter2

let x = dedupe([1, 2, 3])
doAssert x.len == 3
doAssert 1 in x
doAssert 2 in x
doAssert 3 in x
