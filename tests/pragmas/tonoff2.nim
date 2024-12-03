discard """
    action: compile
"""

# issue #22841

import unittest

proc on() =
    discard

suite "some suite":
    test "some test":
        discard
