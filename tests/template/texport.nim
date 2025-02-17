# issue #13828

import mexport

var a = Quat()
a.data = [1f,2,3,4]
a.x = 42.0
doAssert a.x == 42
doAssert a.z == 4
