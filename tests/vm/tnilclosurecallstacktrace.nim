discard """
  action: reject
  nimout: '''
stack trace: (most recent call last)
tnilclosurecallstacktrace.nim(23, 6) tnilclosurecallstacktrace
tnilclosurecallstacktrace.nim(20, 6) baz
tnilclosurecallstacktrace.nim(17, 6) bar
tnilclosurecallstacktrace.nim(14, 4) foo
tnilclosurecallstacktrace.nim(14, 4) Error: attempt to call nil closure
'''
"""

proc foo(x: proc ()) =
  x()

proc bar(x: proc ()) =
  foo(x)

proc baz(x: proc ()) =
  bar(x)

static:
  baz(nil)
