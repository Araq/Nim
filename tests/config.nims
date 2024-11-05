switch("path", "$lib/../testament/lib")
  # so we can `import stdtest/foo` inside tests
  # Using $lib/../ instead of $nim/ so you can use a different nim to run tests
  # during local testing, e.g. nim --lib:lib.

## prevent common user config settings to interfere with testament expectations
## Indifidual tests can override this if needed to test for these options.
switch("colors", "off")

switch("excessiveStackTrace", "off")

when (NimMajor, NimMinor, NimPatch) >= (1,5,1):
  # to make it easier to test against older nim versions, (best effort only)
  switch("filenames", "legacyRelProj")
  switch("spellSuggest", "0")

# for std/unittest
switch("define", "nimUnittestOutputLevel:PRINT_FAILURES")
switch("define", "nimUnittestColor:off")

switch("define", "nimLegacyTypeMismatch")

hint("Processing", off)
  # dots can cause annoyances; instead, a single test can test `hintProcessing`

# uncomment to enable all flaky tests disabled by this flag
# (works through process calls, e.g. tests that invoke nim).
# switch("define", "nimTestsEnableFlaky")

# switch("hint", "ConvFromXtoItselfNotNeeded")
# switch("warningAsError", "InheritFromException") # would require fixing a few tests


# preview APIs are expected to be the new default in upcoming versions
#switch("define", "nimPreviewDotLikeOps") # deprecated?
switch("define", "nimPreviewJsonutilsHoleyEnum")
switch("define", "nimPreviewHashRef")
switch("define", "nimPreviewRangeDefault")
switch("define", "nimPreviewNonVarDestructor")

switch("warningAserror", "UnnamedBreak")
when not defined(testsConciseTypeMismatch):
  switch("legacy", "verboseTypeMismatch")
switch("experimental", "vtables")
switch("experimental", "openSym")
switch("experimental", "typeBoundOps")
