discard """
  output: '''
Success
'''
"""

# modified issue #12620, see placeholder procs in mlistdeques

# runtime.nim
import ./mcontext_thread_local

var localCtx* : TLContext
