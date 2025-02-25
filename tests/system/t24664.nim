discard """
  output: '''
TestString123TestString123
TestString123TestString123
'''
"""

proc foostring() = # bug #24664
  for i in 0..1:
    var s = "TestString123"
    s.add s
    echo s

foostring()