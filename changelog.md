# v2.x.x - yyyy-mm-dd


## Changes affecting backward compatibility

- `-d:nimPreviewFloatRoundtrip` becomes the default. `system.addFloat` and `system.$` now can produce string representations of
floating point numbers that are minimal in size and possess round-trip and correct
rounding guarantees (via the
[Dragonbox](https://raw.githubusercontent.com/jk-jeon/dragonbox/master/other_files/Dragonbox.pdf) algorithm). Use `-d:nimLegacySprintf` to emulate old behaviors.

- The `default` parameter of `tables.getOrDefault` has been renamed to `def` to
  avoid conflicts with `system.default`, so named argument usage for this
  parameter like `getOrDefault(..., default = ...)` will have to be changed.

## Standard library additions and changes

[//]: # "Additions:"
- `setutils.symmetricDifference` along with its operator version
  `` setutils.`-+-` `` and in-place version `setutils.toggle` have been added
  to more efficiently calculate the symmetric difference of bitsets.

[//]: # "Changes:"
- `std/math` The `^` symbol now supports floating-point as exponent in addition to the Natural type.

## Language changes


## Compiler changes


## Tool changes


