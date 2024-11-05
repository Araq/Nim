discard """
  errormsg: "cannot instantiate: 'ShouldNotResolve'"
"""

# issue #24091

type Generic[U] = object
proc foo[ShouldNotResolve](x: typedesc[ShouldNotResolve]): ShouldNotResolve =
  echo ShouldNotResolve # Generic
  echo declared(result) # true
  echo typeof(result) # Generic
echo typeof(foo(Generic)) # void
foo(Generic)
