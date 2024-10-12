discard """
  retries: 2
"""

import os

const tempFile = "tretries_temp"

if not fileExists(tempFile):
  writeFile(tempFile, "abc")
  quit(1)
else:
  let content = readFile(tempFile)
  if content == "abc":
    writeFile(tempFile, "def")
    quit(1)
  else:
    # success
    removeFile(tempFile)
    discard
