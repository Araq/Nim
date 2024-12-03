# v2.x.x - yyyy-mm-dd


## Changes affecting backward compatibility

- `-d:nimPreviewFloatRoundtrip` becomes the default. `system.addFloat` and `system.$` now can produce string representations of
floating point numbers that are minimal in size and possess round-trip and correct
rounding guarantees (via the
[Dragonbox](https://raw.githubusercontent.com/jk-jeon/dragonbox/master/other_files/Dragonbox.pdf) algorithm). Use `-d:nimLegacySprintf` to emulate old behaviors.

- The `default` parameter of `tables.getOrDefault` has been renamed to `def` to
  avoid conflicts with `system.default`, so named argument usage for this
  parameter like `getOrDefault(..., default = ...)` will have to be changed.

- With `-d:nimPreviewCheckedClose`, the `close` function in the `std/syncio` module now raises an IO exception in case of an error.

## Standard library additions and changes

[//]: # "Additions:"
- `setutils.symmetricDifference` along with its operator version
  `` setutils.`-+-` `` and in-place version `setutils.toggle` have been added
  to more efficiently calculate the symmetric difference of bitsets.

[//]: # "Changes:"
- `std/math` The `^` symbol now supports floating-point as exponent in addition to the Natural type.

## Language changes

- An experimental option `--experimental:typeBoundOps` has been added that
  implements the RFC https://github.com/nim-lang/RFCs/issues/380.
  This makes the behavior of interfaces like `hash`, `$`, `==` etc. more
  reliable for nominal types across indirect/restricted imports.

  ```nim
  # objs.nim
  import std/hashes

  type
    Obj* = object
      x*, y*: int
      z*: string # to be ignored for equality

  proc `==`*(a, b: Obj): bool =
    a.x == b.x and a.y == b.y

  proc hash*(a: Obj): Hash =
    $!(hash(a.x) &! hash(a.y))
  ```

  ```nim
  # main.nim
  {.experimental: "typeBoundOps".}
  from objs import Obj # objs.hash, objs.`==` not imported
  import std/tables

  var t: Table[Obj, int]
  t[Obj(x: 3, y: 4, z: "debug")] = 34
  echo t[Obj(x: 3, y: 4, z: "ignored")] # 34
  ```

  See the [experimental manual](https://nim-lang.github.io/Nim/manual_experimental.html#typeminusbound-overloads)
  for more information.

## Compiler changes


## Tool changes


