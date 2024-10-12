discard """
  output: '''
10000000
10000000
10000000'''
  retries: 2
"""

# bug #17085

#[
refs https://github.com/nim-lang/Nim/issues/17085#issuecomment-786466595
with --gc:boehm, this warning sometimes gets generated:
Warning: Repeated allocation of very large block (appr. size 14880768):
May lead to memory leak and poor performance.
nim CI now runs this test with `testWithoutBoehm` to avoid running it with --gc:boehm.
]#

proc init(): string =
  for a in 0..<10000000:
    result.add 'c'

proc f() =
  var a {.global.} = init()
  var b {.global.} = init()
  var c {.global.} = init()

  echo a.len
    # `echo` intentional according to
    # https://github.com/nim-lang/Nim/pull/17469/files/0c9e94cb6b9ebca9da7cb19a063fba7aa409748e#r600016573
  echo b.len
  echo c.len

f()
