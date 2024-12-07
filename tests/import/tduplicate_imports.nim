discard """
  cmd: '''nim c --hint:Processing:off $file'''
  action: compile
  nimout: '''
tduplicate_imports.nim(11, 23) Hint: duplicate import of 'strutils'; previous import here: tduplicate_imports.nim(11, 13) [DuplicateModuleImport]
tduplicate_imports.nim(14, 20) Hint: duplicate import of 'foobar'; previous import here: tduplicate_imports.nim(13, 20) [DuplicateModuleImport]
tduplicate_imports.nim(15, 20) Hint: duplicate import of 'strutils'; previous import here: tduplicate_imports.nim(11, 23) [DuplicateModuleImport]
'''
"""

import std/[strutils, strutils]

import strutils as foobar
import strutils as foobar
from strutils import split
