type
  Task*[N: int] = object # XXX this shouldn't work, should be `static int`
    env*: array[N, byte]

var task14193: Task[20]
doAssert task14193.env.len == 20
