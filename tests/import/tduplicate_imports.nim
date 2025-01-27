discard """
  cmd: '''nim c --hint:Processing:off $file'''
  action: compile
  nimout: '''
tduplicate_imports.nim(12, 23) Hint: duplicate import of 'strutils'; previous import here: tduplicate_imports.nim(12, 13) [DuplicateModuleImport]
tduplicate_imports.nim(15, 20) Hint: duplicate import of 'foobar'; previous import here: tduplicate_imports.nim(14, 20) [DuplicateModuleImport]
tduplicate_imports.nim(16, 10) Hint: duplicate import of 'strutils'; previous import here: tduplicate_imports.nim(12, 23) [DuplicateModuleImport]
tduplicate_imports.nim(17, 8) Hint: duplicate import of 'strutils'; previous import here: tduplicate_imports.nim(16, 10) [DuplicateModuleImport]
'''
"""

import std/[strutils, strutils]

import strutils as foobar
import strutils as foobar
from std/strutils import split
import strutils except split
