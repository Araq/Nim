# issue #23002

import monoff1

proc test() =
  {.warning[ProveInit]: on.}

test()
