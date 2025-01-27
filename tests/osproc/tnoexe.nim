discard """
  output: '''true
true'''
"""

import std/osproc

const command = "lsaaa -lah"

try:
  let process = startProcess(command, options = {poUsePath})
  discard process.waitForExit()
except OSError as e:
  echo e.errorCode != 0

# `poEvalCommand`, invokes the system shell to run the specified command
try:
  let process = startProcess(command, options = {poUsePath, poEvalCommand})
  # linux
  let exitCode = process.waitForExit()
  echo exitCode != 0
except OSError as e:
  # Because the implementation of `poEvalCommand` on different platforms is inconsistent, 
  # Linux will not throw an exception, but Windows will throw an exception

  # windows
  echo e.errorCode != 0
