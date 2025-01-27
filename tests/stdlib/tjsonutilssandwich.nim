discard """
  action: compile
"""

# issue #24559

import mjsonutilssandwich
# import std/[json, jsonutils] # Add this line and everything works 🤡

unserialize[Foo]("{}")
