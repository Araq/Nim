# v2.0.0 - 2023-08-01

Version 2.0 is a big milestone with too many changes to list them all here.

For a full list see [details](changelog_2_0_0_details.html).


## New features

### Better tuple unpacking

Tuple unpacking for variables is now treated as syntax sugar that directly
expands into multiple assignments. Along with this, tuple unpacking for
variables can now be nested.

```nim
proc returnsNestedTuple(): (int, (int, int), int, int) = (4, (5, 7), 2, 3)

# Now nesting is supported!
let (x, (_, y), _, z) = returnsNestedTuple()

```

### Improved type inference

A new form of type inference called [top-down inference](https://nim-lang.github.io/Nim/manual_experimental.html#topminusdown-type-inference) has been implemented for a variety of basic cases.

For example, code like the following now compiles:

```nim
let foo: seq[(float, byte, cstring)] = @[(1, 2, "abc")]
```

### Forbidden Tags

[Tag tracking](https://nim-lang.github.io/Nim/manual.html#effect-system-tag-tracking) now supports the definition
of forbidden tags by the `.forbids` pragma which can be used to disable certain effects in proc types.

For example:

```nim

type IO = object ## input/output effect
proc readLine(): string {.tags: [IO].} = discard
proc echoLine(): void = discard

proc no_IO_please() {.forbids: [IO].} =
  # this is OK because it didn't define any tag:
  echoLine()
  # the compiler prevents this:
  let y = readLine()

```

### New standard library modules

The famous `os` module got an overhaul. Several of its features are available
under a new interface that introduces a `Path` abstraction. A `Path` is
a `distinct string`, which improves the type safety when dealing with paths, files
and directories.

Use:

- `std/oserrors` for OS error reporting.
- `std/envvars` for environment variables handling.
- `std/paths` for path handling.
- `std/dirs` for directory creation/deletion/traversal.
- `std/files` for file existence checking, file deletions and moves.
- `std/symlinks` for symlink handling.
- `std/appdirs` for accessing configuration/home/temp directories.
- `std/cmdline` for reading command line parameters.

### Consistent underscore handling

The underscore identifier (`_`) is now generally not added to scope when
used as the name of a definition. While this was already the case for
variables, it is now also the case for routine parameters, generic
parameters, routine declarations, type declarations, etc. This means that the following code now does not compile:

```nim
proc foo(_: int): int = _ + 1
echo foo(1)

proc foo[_](t: typedesc[_]): seq[_] = @[default(_)]
echo foo[int]()

proc _() = echo "_"
_()

type _ = int
let x: _ = 3
```

Whereas the following code now compiles:

```nim
proc foo(_, _: int): int = 123
echo foo(1, 2)

proc foo[_, _](): int = 123
echo foo[int, bool]()

proc foo[T, U](_: typedesc[T], _: typedesc[U]): (T, U) = (default(T), default(U))
echo foo(int, bool)

proc _() = echo "one"
proc _() = echo "two"

type _ = int
type _ = float
```

### JavaScript codegen improvement

The JavaScript backend now uses [BigInt](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/BigInt)
for 64-bit integer types (`int64` and `uint64`) by default. As this affects
JS code generation, code using these types to interface with the JS backend
may need to be updated. Note that `int` and `uint` are not affected.

For compatibility with [platforms that do not support BigInt](https://caniuse.com/bigint)
and in the case of potential bugs with the new implementation, the
old behavior is currently still supported with the command line option
`--jsbigint64:off`.


## Docgen improvements

`Markdown` is now the default markup language of doc comments (instead
of the legacy `RstMarkdown` mode). In this release we begin to separate
RST and Markdown features to better follow specification of each
language, with the focus on Markdown development.
See also [the docs](https://nim-lang.github.io/Nim/markdown_rst.html).

* Added a `{.doctype: Markdown | RST | RstMarkdown.}` pragma allowing to
  select the markup language mode in the doc comments of the current `.nim`
  file for processing by `nim doc`:

    1. `Markdown` (default) is basically CommonMark (standard Markdown) +
        some Pandoc Markdown features + some RST features that are missing
        in our current implementation of CommonMark and Pandoc Markdown.
    2. `RST` closely follows the RST spec with few additional Nim features.
    3. `RstMarkdown` is a maximum mix of RST and Markdown features, which
        is kept for the sake of compatibility and ease of migration.

* Added separate `md2html` and `rst2html` commands for processing
  standalone `.md` and `.rst` files respectively (and also `md2tex`/`rst2tex`).

* Added Pandoc Markdown bracket syntax `[...]` for making anchor-less links.
* Docgen now supports concise syntax for referencing Nim symbols:
  instead of specifying HTML anchors directly one can use original
  Nim symbol declarations (adding the aforementioned link brackets
  `[...]` around them).
  * To use this feature across modules, a new `importdoc` directive was added.
    Using this feature for referencing also helps to ensure that links
    (inside one module or the whole project) are not broken.
* Added support for RST & Markdown quote blocks (blocks starting with `>`).
* Added a popular Markdown definition lists extension.
* Added Markdown indented code blocks (blocks indented by >= 4 spaces).
* Added syntax for additional parameters to Markdown code blocks:

       ```nim test="nim c $1"
       ...
       ```


## C++ interop enhancements

Nim 2.0 takes C++ interop to the next level. With the new [virtual](https://nim-lang.github.io/Nim/manual_experimental.html#virtual-pragma) pragma and the extended [constructor](https://nim-lang.github.io/Nim/manual_experimental.html#constructor-pragma) pragma.
Now one can define constructors and virtual procs that maps to C++ constructors and virtual methods, allowing one to further customize
the interoperability. There is also extended support for the [codeGenDecl](https://nim-lang.org/docs/manual.html#implementation-specific-pragmas-codegendecl-pragma) pragma, so that it works on types.

It's a common pattern in C++ to use inheritance to extend a library. Some even use multiple inheritance as a mechanism to make interfaces.

Consider the following example:

```cpp

struct Base {
  int someValue;
  Base(int inValue)  {
    someValue = inValue;
  };
};

class IPrinter {
public:
  virtual void print() = 0;
};
```

```nim

type
  Base* {.importcpp, inheritable.} = object
    someValue*: int32
  IPrinter* {.importcpp.} = object

const objTemplate = """
  struct $1 : public $3, public IPrinter {
    $2
  };
""";

type NimChild {.codegenDecl: objTemplate .} = object of Base

proc makeNimChild(val: int32): NimChild {.constructor: "NimClass('1 #1) : Base(#1)".} =
  echo "It calls the base constructor passing " & $this.someValue
  this.someValue = val * 2 # Notice how we can access `this` inside the constructor. It's of the type `ptr NimChild`.

proc print*(self: NimChild) {.virtual.} =
  echo "Some value is " & $self.someValue

let child = makeNimChild(10)
child.print()
```

It outputs:

```
It calls the base constructor passing 10
Some value is 20
```


## ARC/ORC refinements

With the 2.0 release, the ARC/ORC model got refined once again and is now finally complete:

1. Programmers now have control over the "item was moved from" state as `=wasMoved` is overridable.
2. There is a new `=dup` hook which is more efficient than the old combination of `=wasMoved(tmp); =copy(tmp, x)` operations.
3. Destructors now take a parameter of the attached object type `T` directly and don't have to take a `var T` parameter.

With these important optimizations we improved the runtime of the compiler and important benchmarks by 0%! Wait ... what?
Yes, unfortunately it turns out that for a modern optimizer like in GCC or LLVM there is no difference.

But! This refined model is more efficient once separate compilation enters the picture. In other words, as we think of
providing a stable ABI it is important not to lose any efficiency in the calling conventions.


## Tool changes

- Nim now ships Nimble version 0.14 which added support for lock-files. Libraries are stored in `$nimbleDir/pkgs2` (it was `$nimbleDir/pkgs` before). Use `nimble develop --global` to create an old style link file in the special links directory documented at https://github.com/nim-lang/nimble#nimble-develop.
- nimgrep now offers the option `--inContext` (and `--notInContext`), which
  allows to filter only matches with the context block containing a given pattern.
- nimgrep: names of options containing "include/exclude" are deprecated,
  e.g. instead of `--includeFile` and `--excludeFile` we have
  `--filename` and `--notFilename` respectively.
  Also, the semantics are now consistent for such positive/negative filters.
- Nim now ships with an alternative package manager called Atlas. More on this in upcoming versions.


## Porting guide

### Block and Break

Using an unnamed break in a block is deprecated. This warning will become an error in future versions! Use a named block with a named break instead. In other words, turn:

```nim

block:
  a()
  if cond:
    break
  b()

```

Into:

```nim

block maybePerformB:
  a()
  if cond:
    break maybePerformB
  b()

```

### Strict funcs

The definition of `"strictFuncs"` was changed.
The old definition was roughly: "A store to a ref/ptr deref is forbidden unless it's coming from a `var T` parameter".
The new definition is: "A store to a ref/ptr deref is forbidden."

This new definition is much easier to understand, the price is some expressiveness. The following code used to be
accepted:

```nim

{.experimental: "strictFuncs".}

type Node = ref object
  s: string

func create(s: string): Node =
  result = Node()
  result.s = s # store to result[]

```

Now it has to be rewritten to:

```nim

{.experimental: "strictFuncs".}

type Node = ref object
  s: string

func create(s: string): Node =
  result = Node(s: s)

```

### Standard library

Several standard library modules have been moved to nimble packages, use `nimble` or `atlas` to install them:

- `std/punycode` => `punycode`
- `std/asyncftpclient` => `asyncftpclient`
- `std/smtp` => `smtp`
- `std/db_common` => `db_connector/db_common`
- `std/db_sqlite` => `db_connector/db_sqlite`
- `std/db_mysql` => `db_connector/db_mysql`
- `std/db_postgres` => `db_connector/db_postgres`
- `std/db_odbc` => `db_connector/db_odbc`
- `std/md5` => `checksums/md5`
- `std/sha1` => `checksums/sha1`
- `std/sums` => `sums`
