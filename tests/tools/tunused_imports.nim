discard """
  cmd: '''nim c --hint:Processing:off $file'''
  nimout: '''
tunused_imports.nim(15, 10) Warning: BEGIN [User]
tunused_imports.nim(43, 10) Warning: END [User]
tunused_imports.nim(38, 8) Warning: imported and not used: 'strutils' [UnusedImport]
tunused_imports.nim(39, 13) Warning: imported and not used: 'strtabs' [UnusedImport]
tunused_imports.nim(39, 22) Warning: imported and not used: 'cstrutils' [UnusedImport]
tunused_imports.nim(40, 12) Warning: imported and not used: 'macrocache' [UnusedImport]
tunused_imports.nim(41, 25) Warning: imported and not used: 'basics' [UnusedImport]
'''
  action: "compile"
"""

{.warning: "BEGIN".}

# bug #12885

import tables, second

template test(key: int): untyped =
  `[]`(dataEx, key)

echo test(1)

import net, dontmentionme

echo AF_UNIX

import macros
# bug #11809
macro bar(): untyped =
  template baz() = discard
  result = getAst(baz())

bar()

import strutils
import std/[strtabs, cstrutils]
import std/macrocache
import std/strbasics as basics

{.warning: "END".}
