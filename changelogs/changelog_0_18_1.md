## v0.18.0 - 01/03/2018

### Changes affecting backwards compatibility

#### Breaking changes in the standard library

- The ``[]`` proc for strings now raises an ``IndexError`` exception when
  the specified slice is out of bounds. See issue
  [#6223](https://github.com/nim-lang/Nim/issues/6223) for more details.
  You can use ``substr(str, start, finish)`` to get the old behaviour back,
  see [this commit](https://github.com/nim-lang/nimbot/commit/98cc031a27ea89947daa7f0bb536bcf86462941f) for an example.

- ``strutils.split`` and ``strutils.rsplit`` with an empty string and a
  separator now returns that empty string.
  See issue [#4377](https://github.com/nim-lang/Nim/issues/4377).

- Arrays of char cannot be converted to ``cstring`` anymore, pointers to
  arrays of char can! This means ``$`` for arrays can finally exist
  in ``system.nim`` and do the right thing. This means ``$myArrayOfChar`` changed
  its behaviour! Compile with ``-d:nimNoArrayToString`` to see where to fix your
  code.

- `reExtended` is no longer default for the `re` constructor in the `re`
  module.

- The behavior of ``$`` has been changed for all standard library collections. The
  collection-to-string implementations now perform proper quoting and escaping of
  strings and chars.

- `newAsyncSocket` taking an `AsyncFD` now runs `setBlocking(false)` on the
  fd.

- ``mod`` and bitwise ``and`` do not produce ``range`` subtypes anymore. This
  turned out to be more harmful than helpful and the language is simpler
  without this special typing rule.

- ``formatFloat``/``formatBiggestFloat`` now support formatting floats with zero
  precision digits. The previous ``precision = 0`` behavior (default formatting)
  is now available via ``precision = -1``.

- Moved from stdlib into Nimble packages:
  - [``basic2d``](https://github.com/nim-lang/basic2d)
    _deprecated: use ``glm``, ``arraymancer``, ``neo``, or another package instead_
  - [``basic3d``](https://github.com/nim-lang/basic3d)
    _deprecated: use ``glm``, ``arraymancer``, ``neo``, or another package instead_
  - [``gentabs``](https://github.com/lcrees/gentabs)
  - [``libuv``](https://github.com/lcrees/libuv)
  - [``numeric``](https://github.com/lcrees/polynumeric)
  - [``poly``](https://github.com/lcrees/polynumeric)
  - [``pdcurses``](https://github.com/lcrees/pdcurses)
  - [``romans``](https://github.com/lcrees/romans)
  - [``libsvm``](https://github.com/nim-lang/libsvm_legacy)
  - [``joyent_http_parser``](https://github.com/nim-lang/joyent_http_parser)

- Proc [toCountTable](https://nim-lang.org/docs/tables.html#toCountTable,openArray[A])
  now produces a `CountTable` with values corresponding to the number of occurrences
  of the key in the input. It used to produce a table with all values set to `1`.

  Counting occurrences in a sequence used to be:

  ```nim
  let mySeq = @[1, 2, 1, 3, 1, 4]
  var myCounter = initCountTable[int]()

  for item in mySeq:
    myCounter.inc item
  ```

  Now, you can simply do:

  ```nim
  let
    mySeq = @[1, 2, 1, 3, 1, 4]
    myCounter = mySeq.toCountTable()
  ```

- If you use ``--dynlibOverride:ssl`` with OpenSSL 1.0.x, you now have to
  define ``openssl10`` symbol (``-d:openssl10``). By default OpenSSL 1.1.x is
  assumed.

- ``newNativeSocket`` is now named ``createNativeSocket``.

- ``newAsyncNativeSocket`` is now named ``createAsyncNativeSocket``
  and it no longer raises an OS error but returns an ``osInvalidSocket`` when
  creation fails.

- The ``securehash`` module is now deprecated. Instead import ``std / sha1``.

- The ``readPasswordFromStdin`` proc has been moved from the ``rdstdin``
  to the ``terminal`` module, thus it does not depend on linenoise anymore.

#### Breaking changes in the compiler

- ``\n`` is now only the single line feed character like in most
  other programming languages. The new platform specific newline escape sequence is
  written as ``\p``. This change only affects the Windows platform.

- The overloading rules changed slightly so that constrained generics are
  preferred over unconstrained generics. (Bug #6526)

- We changed how array accesses "from backwards" like ``a[^1]`` or ``a[0..^1]`` are
  implemented. These are now implemented purely in ``system.nim`` without compiler
  support. There is a new "heterogeneous" slice type ``system.HSlice`` that takes 2
  generic parameters which can be ``BackwardsIndex`` indices. ``BackwardsIndex`` is
  produced by ``system.^``.
  This means if you overload ``[]`` or ``[]=`` you need to ensure they also work
  with ``system.BackwardsIndex`` (if applicable for the accessors).

- The parsing rules of ``if`` expressions were changed so that multiple
  statements are allowed in the branches. We found few code examples that
  now fail because of this change, but here is one:

```nim
t[ti] = if exp_negative: '-' else: '+'; inc(ti)
```

This now needs to be written as:

```nim
t[ti] = (if exp_negative: '-' else: '+'); inc(ti)
```

- The experimental overloading of the dot ``.`` operators now take
  an ``untyped``` parameter as the field name, it used to be
  a ``static[string]``. You can use ``when defined(nimNewDot)`` to make
  your code work with both old and new Nim versions.
  See [special-operators](https://nim-lang.org/docs/manual.html#special-operators)
  for more information.

- ``yield`` (or ``await`` which is mapped to ``yield``) never worked reliably
  in an array, seq or object constructor and is now prevented at compile-time.

### Library additions

- **Added ``sequtils.mapLiterals`` for easier construction of array and tuple literals.**

- Added ``system.runnableExamples`` to make examples in Nim's documentation easier
  to write and test. The examples are tested as the last step of
  ``nim doc``.

- Implemented ``getIoHandler`` proc in the ``asyncdispatch`` module that allows
  you to retrieve the underlying IO Completion Port or ``Selector[AsyncData]``
  object in the specified dispatcher.

- For string formatting / interpolation a new module
  called [strformat](https://nim-lang.org/docs/strformat.html) has been added
  to the stdlib.

- The `ReadyKey` type in the selectors module now contains an ``errorCode``
  field to help distinguish between ``Event.Error`` events.

- Implemented an `accept` proc that works on a `SocketHandle` in
  ``nativesockets``.

- Added ``algorithm.rotateLeft``.

- Added ``typetraits.$`` as an alias for ``typetraits.name``.

- Added ``system.getStackTraceEntries`` that allows you to access the stack
  trace in a structured manner without string parsing.

- Added ``parseutils.parseSaturatedNatural``.

- Added ``macros.unpackVarargs``.

- Added support for asynchronous programming for the JavaScript backend using
  the `asyncjs` module.

- Added true color support for some terminals. Example:
```nim
import colors, terminal

const Nim = "Efficient and expressive programming."

var
  fg = colYellow
  bg = colBlue
  int = 1.0

enableTrueColors()

for i in 1..15:
  styledEcho bgColor, bg, fgColor, fg, Nim, resetStyle
  int -= 0.01
  fg = intensity(fg, int)

setForegroundColor colRed
setBackgroundColor colGreen
styledEcho "Red on Green.", resetStyle
```

### Library changes

- ``echo`` now works with strings that contain ``\0`` (the binary zero is not
  shown) and ``nil`` strings are equal to empty strings.

- JSON: Deprecated `getBVal`, `getFNum`, and `getNum` in favour of
  `getBool`, `getFloat`, `getBiggestInt`. A new `getInt` procedure was also
  added.

- ``rationals.toRational`` now uses an algorithm based on continued fractions.
  This means its results are more precise and it can't run into an infinite loop
  anymore.

- ``os.getEnv`` now takes an optional ``default`` parameter that tells ``getEnv``
  what to return if the environment variable does not exist.

- The ``random`` procs in ``random.nim`` have all been deprecated. Instead use
  the new ``rand`` procs. The module now exports the state of the random
  number generator as type ``Rand`` so multiple threads can easily use their
  own random number generators that do not require locking. For more information
  about this rename see issue [#6934](https://github.com/nim-lang/Nim/issues/6934)

- ``writeStackTrace`` is now proclaimed to have no IO effect (even though it does)
  so that it is more useful for debugging purposes.

- ``db_mysql`` module: ``DbConn`` is now a ``distinct`` type that doesn't expose the
  details of the underlying ``PMySQL`` type.

- ``parseopt2`` is now deprecated, use ``parseopt`` instead.

### Language additions

- It is now possible to forward declare object types so that mutually
  recursive types can be created across module boundaries. See
  [package level objects](https://nim-lang.org/docs/manual.html#package-level-objects)
  for more information.

- Added support for casting between integers of same bitsize in VM (compile time and nimscript).
  This allows to, among other things, reinterpret signed integers as unsigned.

- Custom pragmas are now supported using pragma ``pragma``, please see language
  manual for details.

- Standard library modules can now also be imported via the ``std`` pseudo-directory.
  This is useful in order to distinguish between standard library and nimble package
  imports:

  ```nim
  import std / [strutils, os, osproc]
  import someNimblePackage / [strutils, os]
  ```

### Language changes

- The **unary** ``<`` is now deprecated, for ``.. <`` use ``..<`` for other usages
  use the ``pred`` proc.

- Bodies of ``for`` loops now get their own scope:

```nim
# now compiles:
for i in 0..4:
  let i = i + 1
  echo i
```

- To make Nim even more robust the system iterators ``..`` and ``countup``
  now only accept a single generic type ``T``. This means the following code
  doesn't die with an "out of range" error anymore:

```nim
var b = 5.Natural
var a = -5
for i in a..b:
  echo i
```

- ``atomic`` and ``generic`` are no longer keywords in Nim. ``generic`` used to be
  an alias for ``concept``, ``atomic`` was not used for anything.

- The memory manager now uses a variant of the TLSF algorithm that has much
  better memory fragmentation behaviour. According
  to [http://www.gii.upv.es/tlsf/](http://www.gii.upv.es/tlsf/) the maximum
  fragmentation measured is lower than 25%. As a nice bonus ``alloc`` and
  ``dealloc`` became O(1) operations.

- The compiler is now more consistent in its treatment of ambiguous symbols:
  Types that shadow procs and vice versa are marked as ambiguous (bug #6693).

- codegenDecl pragma now works for the JavaScript backend. It returns an empty
  string for function return type placeholders.

- Extra semantic checks for procs with noreturn pragma: return type is not allowed,
  statements after call to noreturn procs are no longer allowed.

- Noreturn proc calls and raising exceptions branches are now skipped during common type
  deduction in ``if`` and ``case`` expressions. The following code snippets now compile:
  ```nim
  import strutils
  let str = "Y"
  let a = case str:
    of "Y": true
    of "N": false
    else: raise newException(ValueError, "Invalid boolean")
  let b = case str:
    of nil, "": raise newException(ValueError, "Invalid boolean")
    elif str.startsWith("Y"): true
    elif str.startsWith("N"): false
    else: false
  let c = if str == "Y": true
    elif str == "N": false
    else:
      echo "invalid bool"
      quit("this is the end")
  ```

- Pragmas now support call syntax, for example: ``{.exportc"myname".}`` and
  ``{.exportc("myname").}``

- The ``deprecated`` pragma now supports a user-definable warning message for procs.

  ```nim
  proc bar {.deprecated: "use foo instead".} =
    return

  bar()
  ```

### Tool changes

- The ``nim doc`` command is now an alias for ``nim doc2``, the second version of
  the documentation generator. The old version 1 can still be accessed
  via the new ``nim doc0`` command.

- Nim's ``rst2html`` command now supports the testing of code snippets via an RST
  extension that we called ``:test:``::

  ```rst
  .. code-block:: nim
      :test:
    # shows how the 'if' statement works
    if true: echo "yes"
  ```

### Compiler changes

### Bugfixes

- Fixed "ReraiseError when using try/except within finally block"
  ([#5871](https://github.com/nim-lang/Nim/issues/5871))
- Fixed "Range type inference leads to counter-intuitive behaviour"
  ([#5854](https://github.com/nim-lang/Nim/issues/5854))
- Fixed "JSON % operator can fail in extern procs with dynamic types"
  ([#6385](https://github.com/nim-lang/Nim/issues/6385))
- Fixed ""intVal is not accessible" in VM"
  ([#6083](https://github.com/nim-lang/Nim/issues/6083))
- Fixed "Add excl for OrderedSet"
  ([#2467](https://github.com/nim-lang/Nim/issues/2467))
- Fixed "newSeqOfCap actually doesn't reserve memory"
  ([#6403](https://github.com/nim-lang/Nim/issues/6403))
- Fixed "[Regression] Nim segfaults"
  ([#6435](https://github.com/nim-lang/Nim/issues/6435))
- Fixed "Seq assignment is slower than expected"
  ([#6433](https://github.com/nim-lang/Nim/issues/6433))
- Fixed "json module issues with empty dicts and lists"
  ([#6438](https://github.com/nim-lang/Nim/issues/6438))
- Fixed "mingw installed via finish.exe fails to link if Nim located in path with whitespace"
  ([#6452](https://github.com/nim-lang/Nim/issues/6452))
- Fixed "unittest.check does not perform short-circuit evaluation"
  ([#5784](https://github.com/nim-lang/Nim/issues/5784))
- Fixed "Error while concatenating an array of chars."
  ([#5861](https://github.com/nim-lang/Nim/issues/5861))
- Fixed "range initialization: [ProveInit] hint: Cannot prove that"
  ([#6474](https://github.com/nim-lang/Nim/issues/6474))
- Fixed "scanf can call procs with side-effects multiple times"
  ([#6487](https://github.com/nim-lang/Nim/issues/6487))
- Fixed "gcsafe detection problem"
  ([#5620](https://github.com/nim-lang/Nim/issues/5620))
- Fixed "C++ codegen: `mitems` generates invalid code."
  ([#4910](https://github.com/nim-lang/Nim/issues/4910))
- Fixed "strange runtime behavior on macOS"
  ([#6496](https://github.com/nim-lang/Nim/issues/6496))
- Fixed "stdtmpl: invalid indentation after a line ending in question mark"
  ([#5070](https://github.com/nim-lang/Nim/issues/5070))
- Fixed "Windows: NAN troubles on c backend"
  ([#6511](https://github.com/nim-lang/Nim/issues/6511))
- Fixed "lib/nim/system/cellsets.nim(33, 31) Error: type mismatch while attempting to compile for 16bit CPUs"
  ([#3558](https://github.com/nim-lang/Nim/issues/3558))
- Fixed "Can't compile dynlib with ``-d:useNimRtl`` and ``--threads:on``"
  ([#5143](https://github.com/nim-lang/Nim/issues/5143))
- Fixed "var s = @[0,1,2,...] can generate thousand of single assignments in C code"
  ([#5007](https://github.com/nim-lang/Nim/issues/5007))
- Fixed "`echo` discards everything after a null character"
  ([#1137](https://github.com/nim-lang/Nim/issues/1137))
- Fixed "Turn off reExtended by default"
  ([#5627](https://github.com/nim-lang/Nim/issues/5627))
- Fixed "Bad Links in docs/backends.html"
  ([#5914](https://github.com/nim-lang/Nim/issues/5914))
- Fixed "Index out of bounds error in db_postgres when executing non parameter-substituted queries containing "?""
  ([#6571](https://github.com/nim-lang/Nim/issues/6571))
- Fixed "Please add pipe2 support to posix stdlib"
  ([#6553](https://github.com/nim-lang/Nim/issues/6553))
- Fixed "Return semantics vary depending on return style"
  ([#6422](https://github.com/nim-lang/Nim/issues/6422))
- Fixed "parsecsv.open reports SIGSEGV when calling 'open' on missing file"
  ([#6148](https://github.com/nim-lang/Nim/issues/6148))
- Fixed "VCC: Nim generates non-compilable code for system.nim"
  ([#6606](https://github.com/nim-lang/Nim/issues/6606))
- Fixed "Generic subtype matches worse than a generic"
  ([#6526](https://github.com/nim-lang/Nim/issues/6526))
- Fixed "formatFloat inconsistent scientific notation"
  ([#6589](https://github.com/nim-lang/Nim/issues/6589))
- Fixed "Generated c code calls function twice"
  ([#6292](https://github.com/nim-lang/Nim/issues/6292))
- Fixed "Range type inference leads to counter-intuitive behaviour"
  ([#5854](https://github.com/nim-lang/Nim/issues/5854))
- Fixed "New backward indexing is too limited"
  ([#6631](https://github.com/nim-lang/Nim/issues/6631))
- Fixed "Table usage in a macro (SIGSEGV: Illegal storage access.)"
  ([#1860](https://github.com/nim-lang/Nim/issues/1860))
- Fixed "Incorrect deprecation error"
  ([#6634](https://github.com/nim-lang/Nim/issues/6634))
- Fixed "Wrong indices in arrays not starting with 0"
  ([#6675](https://github.com/nim-lang/Nim/issues/6675))
- Fixed "if expressions"
  ([#6609](https://github.com/nim-lang/Nim/issues/6609))
- Fixed "BackwardsIndex: converter + `[]` + unrelated type[^1]: lib/system.nim(3536, 3) Error"
  ([#6692](https://github.com/nim-lang/Nim/issues/6692))
- Fixed "BackwardsIndex: converter + `[]` + unrelated type[^1]: lib/system.nim(3536, 3) Error"
  ([#6692](https://github.com/nim-lang/Nim/issues/6692))
- Fixed "js backend 0.17.3: array bounds check for non zero based arrays is buggy"
  ([#6532](https://github.com/nim-lang/Nim/issues/6532))
- Fixed "HttpClient's new API doesn't work through a proxy for https URLs"
  ([#6685](https://github.com/nim-lang/Nim/issues/6685))
- Fixed "isServing isn't declared and isn't compiling"
  ([#6707](https://github.com/nim-lang/Nim/issues/6707))
- Fixed "[Regression] value out of range"
  ([#6710](https://github.com/nim-lang/Nim/issues/6710))

- Fixed "Error when using `multisync` macro"
  ([#6708](https://github.com/nim-lang/Nim/issues/6708))

- Fixed "formatFloat inconsistent scientific notation"
  ([#6589](https://github.com/nim-lang/Nim/issues/6589))
- Fixed "Using : (constructor arguments) for passing values to functions with default arguments causes a compiler crash."
  ([#6765](https://github.com/nim-lang/Nim/issues/6765))
- Fixed "In-place object initialization leads to vcc incompatible code"
  ([#6757](https://github.com/nim-lang/Nim/issues/6757))
- Fixed "Improve parseCookies doc"
  ([#5721](https://github.com/nim-lang/Nim/issues/5721))
- Fixed "Parser regression with nested do notation inside conditional"
  ([#6166](https://github.com/nim-lang/Nim/issues/6166))
- Fixed "Request for better error message"
  ([#6776](https://github.com/nim-lang/Nim/issues/6776))
- Fixed "Testament tester does not execute test with `exitcode` only"
  ([#6775](https://github.com/nim-lang/Nim/issues/6775))
- Fixed "JS integer division off by one"
  ([#6753](https://github.com/nim-lang/Nim/issues/6753))
- Fixed "Regression: cannot prove not nil"
  ([#5781](https://github.com/nim-lang/Nim/issues/5781))
- Fixed "SIGSEGV: Illegal storage access. (Attempt to read from nil?) in generic proc"
  ([#6073](https://github.com/nim-lang/Nim/issues/6073))
- Fixed "Request for better error message"
  ([#6776](https://github.com/nim-lang/Nim/issues/6776))
- Fixed "Nim #head: sorting via reference hangs compiler"
  ([#6724](https://github.com/nim-lang/Nim/issues/6724))
- Fixed "Cannot cast pointer to char in cpp"
  ([#5979](https://github.com/nim-lang/Nim/issues/5979))
- Fixed "asynchttpserver replies with several errors on single request"
  ([#6386](https://github.com/nim-lang/Nim/issues/6386))
- Fixed "object variants superclass trigger bad codegen"
  ([#5521](https://github.com/nim-lang/Nim/issues/5521))
- Fixed "JS integer division off by one"
  ([#6753](https://github.com/nim-lang/Nim/issues/6753))
- Fixed "js backend compiler crash with tables indexed by certain types"
  ([#6568](https://github.com/nim-lang/Nim/issues/6568))
- Fixed "Jsgen bug with is"
  ([#6445](https://github.com/nim-lang/Nim/issues/6445))
- Fixed "Subrange definition with ..<"
  ([#6788](https://github.com/nim-lang/Nim/issues/6788))
- Fixed "fields not initialized: array with enum index type as object field."
  ([#6682](https://github.com/nim-lang/Nim/issues/6682))
- Fixed "Can not delete data in table when table's data type is kind of "not nil""
  ([#6555](https://github.com/nim-lang/Nim/issues/6555))
- Fixed "tables.nim: Cannot prove that 'n' is initialized"
  ([#6121](https://github.com/nim-lang/Nim/issues/6121))
- Fixed "issues with 'not nil' applied to a closure proc"
  ([#6489](https://github.com/nim-lang/Nim/issues/6489))
- Fixed "`not nil` not working in some cases"
  ([#4686](https://github.com/nim-lang/Nim/issues/4686))
- Fixed "Cannot prove '@[v]' is not nil"
  ([#3993](https://github.com/nim-lang/Nim/issues/3993))

- Fixed "Feature: support TCP_NODELAY in net.sockets"
  ([#6795](https://github.com/nim-lang/Nim/issues/6795))
- Fixed "Code that makes the compiler throw an error message and then hangs"
  ([#6820](https://github.com/nim-lang/Nim/issues/6820))
- Fixed "Code that makes the compiler throw an error message and then hangs"
  ([#6820](https://github.com/nim-lang/Nim/issues/6820))
- Fixed "Inconsistent behavior with sequence and string slicing"
  ([#6223](https://github.com/nim-lang/Nim/issues/6223))
- Fixed "Wrong behavior of "split" (proc and iterator)"
  ([#4377](https://github.com/nim-lang/Nim/issues/4377))
- Fixed "[Documentation] Invalid module name: [foo, bar]"
  ([#6831](https://github.com/nim-lang/Nim/issues/6831))
- Fixed "The destructor is not called for temporary objects"
  ([#4214](https://github.com/nim-lang/Nim/issues/4214))
- Fixed "Destructors does not work with implicit items iterator in for loop"
  ([#985](https://github.com/nim-lang/Nim/issues/985))
- Fixed "Error in template when using the type of the parameter inside it"
  ([#6756](https://github.com/nim-lang/Nim/issues/6756))
- Fixed "should json.to() respect parent attributes?"
  ([#5856](https://github.com/nim-lang/Nim/issues/5856))
- Fixed "json 'to' macro can not marshalize into tuples"
  ([#6095](https://github.com/nim-lang/Nim/issues/6095))
- Fixed "json.to fails with seq[T]"
  ([#6604](https://github.com/nim-lang/Nim/issues/6604))
- Fixed "json.to() is not worth using compared to marshal.to[T]"
  ([#5848](https://github.com/nim-lang/Nim/issues/5848))
- Fixed "Memory not being released in time, running out of memory"
  ([#6031](https://github.com/nim-lang/Nim/issues/6031))
- Fixed "[Regression] Bad C codegen for generic code"
  ([#6889](https://github.com/nim-lang/Nim/issues/6889))
- Fixed "rollingFileLogger deletes file on every start."
  ([#6264](https://github.com/nim-lang/Nim/issues/6264))
- Fixed "Remove/deprecate securehash module."
  ([#6033](https://github.com/nim-lang/Nim/issues/6033))
- Fixed "[bug or not] object construction for seq[T] failed without space after colon"
  ([#5999](https://github.com/nim-lang/Nim/issues/5999))
- Fixed "issues with the random module"
  ([#4726](https://github.com/nim-lang/Nim/issues/4726))
- Fixed "Reassigning local var to seq of objects results in nil element in Object's seq field"
  ([#668](https://github.com/nim-lang/Nim/issues/668))
- Fixed "Compilation error with "newseq[string]""
  ([#6726](https://github.com/nim-lang/Nim/issues/6726))
- Fixed "await inside array/dict literal produces invalid code - Part 2"
  ([#6626](https://github.com/nim-lang/Nim/issues/6626))
- Fixed "terminal.eraseline() gives OverflowError on Windows"
  ([#6931](https://github.com/nim-lang/Nim/issues/6931))
- Fixed "[Regression] `sequtils.any` conflicts with `system.any`"
  ([#6932](https://github.com/nim-lang/Nim/issues/6932))
- Fixed "C++ codegen: `mitems` generates invalid code."
  ([#4910](https://github.com/nim-lang/Nim/issues/4910))
- Fixed "seq.mitems produces invalid cpp codegen"
  ([#6892](https://github.com/nim-lang/Nim/issues/6892))
- Fixed "Concepts regression"
  ([#6108](https://github.com/nim-lang/Nim/issues/6108))
- Fixed "Generic iterable concept with array crashes compiler"
  ([#6277](https://github.com/nim-lang/Nim/issues/6277))
- Fixed "C code generation "‘a’ is a pointer; did you mean to use ‘->’?""
  ([#6462](https://github.com/nim-lang/Nim/issues/6462))
- Fixed "`--NimblePath` fails if a `-` in path which is not followed by a number"
  ([#6949](https://github.com/nim-lang/Nim/issues/6949))
- Fixed ""not registered in the selector" in asyncfile.close() for something that clearly was registered"
  ([#6906](https://github.com/nim-lang/Nim/issues/6906))
- Fixed "strange frexp behavior"
  ([#6353](https://github.com/nim-lang/Nim/issues/6353))

- Fixed "noreturn branches of case statements shouldn't contribute to type"
  ([#6885](https://github.com/nim-lang/Nim/issues/6885))
- Fixed "Type inference for 'if' statements changed"
  ([#6980](https://github.com/nim-lang/Nim/issues/6980))
- Fixed "newest asyncdispatch recursion"
  ([#6100](https://github.com/nim-lang/Nim/issues/6100))
- Fixed "Ambiguous identifier between set type and proc"
  ([#6965](https://github.com/nim-lang/Nim/issues/6965))

- Fixed "Inconsistent behavior with sequence and string slicing"
  ([#6223](https://github.com/nim-lang/Nim/issues/6223))

- Fixed "Unsupported OpenSSL library imported dynamically"
  ([#5000](https://github.com/nim-lang/Nim/issues/5000))
- Fixed "`nim check` segfaults"
  ([#6972](https://github.com/nim-lang/Nim/issues/6972))
- Fixed "GC deadlock"
  ([#6988](https://github.com/nim-lang/Nim/issues/6988))
- Fixed "Create a seq without memory initialization"
  ([#6401](https://github.com/nim-lang/Nim/issues/6401))
- Fixed "Fix bug for getch on Windows while using the arrow keys"
  ([#6966](https://github.com/nim-lang/Nim/issues/6966))
- Fixed "runnableExamples doesn't work in templates"
  ([#7018](https://github.com/nim-lang/Nim/issues/7018))
- Fixed "runnableExamples doesn't work with untyped statement blocks"
  ([#7019](https://github.com/nim-lang/Nim/issues/7019))

- Fixed "Critical bug in parseBiggestFloat"
  ([#7060](https://github.com/nim-lang/Nim/issues/7060))
- Fixed "[RFC] strformat.% should be gone"
  ([#7078](https://github.com/nim-lang/Nim/issues/7078))
- Fixed "compiler crash on simple macro"
  ([#7093](https://github.com/nim-lang/Nim/issues/7093))
- Fixed "Make newlines sane again"
  ([#7089](https://github.com/nim-lang/Nim/issues/7089))
- Fixed "JS - Unicode enum string representation issue"
  ([#6741](https://github.com/nim-lang/Nim/issues/6741))
- Fixed "Strange behaviour of 0.17.3 (working ok in 0.17.2)"
  ([#6989](https://github.com/nim-lang/Nim/issues/6989))
- Fixed "Strange behaviour of 0.17.3 (working ok in 0.17.2)"
  ([#6989](https://github.com/nim-lang/Nim/issues/6989))
- Fixed "Compiler crash: try expression with infix as"
  ([#7116](https://github.com/nim-lang/Nim/issues/7116))
- Fixed "nimsuggest crash"
  ([#7140](https://github.com/nim-lang/Nim/issues/7140))
- Fixed "[RFC] Reintroduce readChar"
  ([#7072](https://github.com/nim-lang/Nim/issues/7072))
- Fixed "Copyright line needs updating"
  ([#7129](https://github.com/nim-lang/Nim/issues/7129))
- Fixed "-0.0 doesn't result in negative zero in VM"
  ([#7079](https://github.com/nim-lang/Nim/issues/7079))
- Fixed "Windows large filesize"
  ([#7121](https://github.com/nim-lang/Nim/issues/7121))
- Fixed "Securehash is not parsimonious with MD5 and other hash modules"
  ([#6961](https://github.com/nim-lang/Nim/issues/6961))
- Fixed "os.findExe() shouldn't look in current directory on posix, unless exe has a /"
  ([#6939](https://github.com/nim-lang/Nim/issues/6939))
- Fixed "`compiles(...)` with `fatal` pragma causes compiler to exit early"
  ([#7080](https://github.com/nim-lang/Nim/issues/7080))
- Fixed "NPE when compile macro that returns concrete value"
  ([#5450](https://github.com/nim-lang/Nim/issues/5450))
- Fixed "Using a variable of type `int | float` causes internal compiler error"
  ([#6946](https://github.com/nim-lang/Nim/issues/6946))
- Fixed "Unsigned integers could not be used as array indexes."
  ([#7153](https://github.com/nim-lang/Nim/issues/7153))
- Fixed "countdown with uint causes underflow"
  ([#4220](https://github.com/nim-lang/Nim/issues/4220))
- Fixed "Inconsistent method call syntax"
  ([#7200](https://github.com/nim-lang/Nim/issues/7200))
- Fixed "Impossible to create an empty const array"
  ([#6853](https://github.com/nim-lang/Nim/issues/6853))
- Fixed "Strange UINT handling"
  ([#3985](https://github.com/nim-lang/Nim/issues/3985))
- Fixed "Bad codegen when passing arg that is part of return value destination"
  ([#6960](https://github.com/nim-lang/Nim/issues/6960))
- Fixed "No info about gcsafety in error message when global var is accessed in async proc"
  ([#6186](https://github.com/nim-lang/Nim/issues/6186))
- Fixed "Resolving package vs. local import ambiguities"
  ([#2819](https://github.com/nim-lang/Nim/issues/2819))
- Fixed "Internal error with type() operator"
  ([#3711](https://github.com/nim-lang/Nim/issues/3711))
- Fixed "newAsyncSocket should raise an OS error plus other inconsistencies"
  ([#4995](https://github.com/nim-lang/Nim/issues/4995))
- Fixed "mapLiterals fails with negative values"
  ([#7215](https://github.com/nim-lang/Nim/issues/7215))
- Fixed "fmWrite doesn't truncate file with openAsync, unlike open()"
  ([#5531](https://github.com/nim-lang/Nim/issues/5531))
- Fixed "Move libsvm to an external nimble module"
  ([#5786](https://github.com/nim-lang/Nim/issues/5786))
- Fixed "Prevent acceptAddr gotcha with newSocket"
  ([#7227](https://github.com/nim-lang/Nim/issues/7227))
- Fixed "strtabs.getOrDefault is inconsistent with tables.getOrDefault"
  ([#4265](https://github.com/nim-lang/Nim/issues/4265))

- Fixed "Code falling through into exception handler when no exception thrown."
  ([#7232](https://github.com/nim-lang/Nim/issues/7232))
- Fixed "the new generic inference rules are broken"
  ([#7247](https://github.com/nim-lang/Nim/issues/7247))
- Fixed "Odd `..<` regression"
  ([#6992](https://github.com/nim-lang/Nim/issues/6992))
- Fixed "Different proc type inferred from default parameter"
  ([#4659](https://github.com/nim-lang/Nim/issues/4659))
- Fixed "Different proc type inferred from default parameter"
  ([#4659](https://github.com/nim-lang/Nim/issues/4659))
- Fixed "Testament sometimes ignores test failures"
  ([#7236](https://github.com/nim-lang/Nim/issues/7236))
- Fixed "New Allocator Fails On >=4GB Requests"
  ([#7120](https://github.com/nim-lang/Nim/issues/7120))
- Fixed "User pragmas hide effect specifications from sempass2"
  ([#7216](https://github.com/nim-lang/Nim/issues/7216))
- Fixed "C++: SIGABRT instead of IndexError for out-of-bounds"
  ([#6512](https://github.com/nim-lang/Nim/issues/6512))
- Fixed "An uncaught exception in cpp mode doesn't show the exception name/msg"
  ([#6431](https://github.com/nim-lang/Nim/issues/6431))
