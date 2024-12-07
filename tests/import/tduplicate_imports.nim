discard """
  cmd: '''nim c --hint:Processing:off $file'''
  action: compile
  nimout: '''
tduplicate_imports.nim(9, 23) Hint: duplicate import of 'strutils'; previous import here: tduplicate_imports.nim(9, 13) [DuplicateModuleImport]
'''
"""

import std/[strutils, strutils]
