discard """
  errormsg: "invalid type: 'typedesc[string]' for const"
"""

# bug #22996
type MyObject = ref object
  _ = string
