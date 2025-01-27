discard """
  matrix: "--hint:all:off --hint:XDeclaredButNotUsed --path:."
  joinable: false
  nimoutFull: true
  nimout: '''
mused2a.nim(12, 6) Hint: 'fn1' is declared but not used [XDeclaredButNotUsed]
mused2a.nim(16, 5) Hint: 'fn4' is declared but not used [XDeclaredButNotUsed]
mused2a.nim(20, 7) Hint: 'fn7' is declared but not used [XDeclaredButNotUsed]
mused2a.nim(23, 6) Hint: 'T1' is declared but not used [XDeclaredButNotUsed]
mused2a.nim(1, 12) Warning: imported and not used: 'strutils' [UnusedImport]
mused2a.nim(3, 10) Warning: imported and not used: 'os' [UnusedImport]
mused2a.nim(5, 26) Warning: imported and not used: 'typetraits2' [UnusedImport]
mused2a.nim(6, 10) Warning: imported and not used: 'setutils' [UnusedImport]
tused2.nim(42, 8) Warning: imported and not used: 'mused2a' [UnusedImport]
tused2.nim(45, 12) Warning: imported and not used: 'strutils' [UnusedImport]
'''
"""






















# line 40

import mused2a
import mused2b

import std/strutils
baz()
