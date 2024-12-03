discard """
  targets: "cpp"
  output: "hello"
  cmd: "nim cpp --clearNimblePath --nimblePath:build/deps/pkgs2 $file"
"""

# bug #3299

import jester
import asyncdispatch, asyncnet

# bug #5081
#import nre

echo "hello"
