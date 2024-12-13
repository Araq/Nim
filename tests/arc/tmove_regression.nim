discard """
  output: '''/1/2
/1
/
'''
""""

# bug #22001

import std / [os, strutils]

proc finOp2(path, name: string): (string, File) = # Find & open FIRST `name`
  result = default((string, File))
  var current = path
  while true:
    if current.isRootDir: break # <- current=="" => current.isRootDir
    current = current.parentDir
    let dir = current
    echo dir.replace('\\', '/')  # Commenting out try/except below hides bug
    try: result[0] = dir/name; result[1] = open(result[0]); return
    except CatchableError: discard

discard finOp2("/1/2/3", "4")  # All same if this->inside a proc
