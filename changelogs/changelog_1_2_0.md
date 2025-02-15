# v1.2.0 - 2020-04-02


## Standard library additions and changes
- Added overloaded `strformat.fmt` macro that use specified characters as
  delimiter instead of '{' and '}'.
- Added new procs in `tables.nim`: `OrderedTable.pop`, `CountTable.del`,
  `CountTable.pop`, `Table.pop`.
- Added `strtabs.clear` overload that reuses the existing mode.
- Added `browsers.osOpen` const alias for the operating system specific *"open"* command.
- Added `sugar.dup` for turning in-place algorithms like `sort` and `shuffle`
  into operations that work on a copy of the data and return the mutated copy,
  like the existing `sorted` does.
- Added `sugar.collect` that does comprehension for seq/set/table collections.
- Added `sugar.capture` for capturing some local loop variables when creating a
  closure. This is an enhanced version of `closureScope`.
- Added `typetraits.tupleLen` to get number of elements of a tuple/type tuple,
  and `typetraits.get` to get the ith element of a type tuple.
- Added `typetraits.genericParams` to return a tuple of generic params from a
  generic instantiation.
- `options` now treats `proc` like other pointer types, meaning `nil` proc variables
  are converted to `None`.
- Added `os.normalizePathEnd` for additional path sanitization.
- Added `times.fromUnixFloat,toUnixFloat`, sub-second resolution versions of
  `fromUnix`,`toUnixFloat`.
- Added `wrapnils` module for chains of field-access and indexing where the LHS
  can be nil. This simplifies code by reducing need for if-else branches around
  intermediate maybe nil values. E.g. `echo ?.n.typ.kind`.
- Added `minIndex`, `maxIndex` and `unzip` to the `sequtils` module.
- Added `os.isRelativeTo` to tell whether a path is relative to another.
- Added `resetOutputFormatters` to `unittest`.
- Added `expectIdent` to the `macros` module.
- Added `os.isValidFilename` that returns `true` if `filename` argument is valid
  for cross-platform use.
- Added `times.isLeapDay`.
- `base64` adds URL-Safe Base64, implements RFC-4648 Section-7.
- Added a new module, `std / compilesettings` for querying the compiler about
  diverse configuration settings.
- Added `net.getPeerCertificates` and `asyncnet.getPeerCertificates` for
  retrieving the verified certificate chain of the peer we are connected to
  through an SSL-wrapped `Socket`/`AsyncSocket`.
- Added `browsers.openDefaultBrowser` without URL, implements IETF RFC-6694 Section-3.
- Added `jsconsole.trace`, `jsconsole.table`, `jsconsole.exception` for JavaScript target.
- Added `distinctBase` overload for values: `assert 12.MyInt.distinctBase == 12`
- Added new module `std/stackframes`, in particular `setFrameMsg`, which enables
  custom runtime annotation of stackframes, see #13351 for examples.
  Turn on/off via `--stackTraceMsgs:on/off`.
- Added `sequtils.countIt`, allowing for counting items using a predicate.
- Added a `with` macro for easy function chaining that's available everywhere,
  there is no need to concern your APIs with returning the first argument
  to enable "chaining", instead use the dedicated macro `with` that
  was designed for it. For example:

```nim
import std/with

type
  Foo = object
    col, pos: string

proc setColor(f: var Foo; r, g, b: int) = f.col = $(r, g, b)
proc setPosition(f: var Foo; x, y: float) = f.pos = $(x, y)

var f: Foo
with(f, setColor(2, 3, 4), setPosition(0.0, 1.0))
echo f
```

- `macros.newLit` now works for ref object types.
- `macro pragmas` can now be used in type sections.
- 5 new pragmas were added to Nim in order to make the upcoming tooling more
  convenient to use. Nim compiler checks these pragmas for syntax but otherwise
  ignores them. The pragmas are `requires`, `ensures`, `assume`, `assert`, `invariant`.
- `system.writeFile` has been overloaded to also support `openarray[byte]`.
- `asyncdispatch.drain` now properly takes into account `selector.hasPendingOperations`
  and only returns once all pending async operations are guaranteed to have completed.
- `sequtils.zip` now returns a sequence of anonymous tuples i.e. those tuples
  now do not have fields named "a" and "b".
- `distinctBase` has been moved from `sugar` to `typetraits` and now it is
  implemented as compiler type trait instead of macro. `distinctBase` in sugar
  module is now deprecated.
- `CountTable.mget` has been removed from `tables.nim`. It didn't work, and it
  was an oversight to be included in v1.0.
- `tables.merge(CountTable, CountTable): CountTable` has been removed.
  It didn't work well together with the existing inplace version of the same proc
  (`tables.merge(var CountTable, CountTable)`).
  It was an oversight to be included in v1.0.
- `asyncdispatch.drain` now consistently uses the passed timeout value for all
  iterations of the event loop, and not just the first iteration.
  This is more consistent with the other asyncdispatch APIs, and allows
  `asyncdispatch.drain` to be more efficient.
- `base64.encode` and `base64.decode` were made faster by about 50%.
- `htmlgen` adds [MathML](https://wikipedia.org/wiki/MathML) support
  (ISO 40314).
- `macros.eqIdent` is now invariant to export markers and backtick quotes.
- `htmlgen.html` allows `lang` in the `<html>` tag and common valid attributes.
- `macros.basename` and `basename=` got support for `PragmaExpr`,
  so that an expression like `MyEnum {.pure.}` is handled correctly.
- `httpclient.maxredirects` changed from `int` to `Natural`, because negative values
  serve no purpose whatsoever.
- `httpclient.newHttpClient` and `httpclient.newAsyncHttpClient` added `headers`
  argument to set initial HTTP Headers, instead of a hardcoded empty `newHttpHeader()`.
- `parseutils.parseUntil` has now a different behaviour if the `until` parameter is
  empty. This was required for intuitive behaviour of the strscans module
  (see bug #13605).
- `strutils.formatFloat` with `precision = 0` has the same behavior in all
  backends, and it is compatible with Python's behavior,
  e.g. `formatFloat(3.14159, precision = 0)` is now `3`, not `3.`.
- `times.parse` now only uses input to compute its result, and not `now`:
  `parse("2020", "YYYY", utc())` is now `2020-01-01T00:00:00Z` instead of
  `2020-03-02T00:00:00Z` if run on 03-02; it also doesn't crash anymore when
  used on 29th, 30th, 31st of each month.
- `httpcore.==(string, HttpCode)` is now deprecated due to lack of practical
  usage. The `$` operator can be used to obtain the string form of `HttpCode`
  for comparison if desired.
- `std/oswalkdir` was buggy, it's now deprecated and reuses `std/os` procs.
- `os.walkDir` and `os.walkDirRec` now have new flag, `checkDir` (default: false).
  If it is set to true, it will throw if input dir is invalid instead of a noop
  (which is the default behaviour, as it was before this change),
  `os.walkDirRec` only throws if top-level dir is invalid, but ignores errors for
  subdirs, otherwise it would be impossible to resume iteration.
- The `FD` variant of `selector.unregister` for `ioselector_epoll` and
  `ioselector_select` now properly handle the `Event.User` select event type.
- `joinPath` path normalization when `/` is the first argument works correctly:
  `assert "/" / "/a" == "/a"`. Fixed the edge case: `assert "" / "" == ""`.
- `xmltree` now adds indentation consistently to child nodes for any number
  of children nodes.
- `os.splitPath()` behavior synchronized with `os.splitFile()` to return "/"
  as the dir component of `/root_sub_dir` instead of the empty string.
- The deprecated `lc` macro has been removed from `sugar`. It is now replaced
  with the more powerful `collect` macro.
- `os.relativePath("foo", "foo")` is now `"."`, not `""`, as `""` means invalid
  path and shouldn't be conflated with `"."`; use `-d:nimOldRelativePathBehavior`
  to restore the old behavior.
- `os.joinPath(a, b)` now honors trailing slashes in `b` (or `a` if `b` = "").
- `base64.encode` no longer supports `lineLen` and `newLine`.
  Use `base64.encodeMime` instead.


### Breaking changes

- `net.newContext` now performs SSL Certificate checking on Linux and OSX.
  Define `nimDisableCertificateValidation` to disable it globally.



## Language changes

- An `align` pragma can now be used for variables and object fields, similar
  to the `alignas` declaration modifier in C/C++.
- The `=sink` type bound operator is now optional. The compiler can now use a
  combination of `=destroy` and `copyMem` to move objects efficiently.
- Unsigned integer operators have been fixed to allow promotion of the first operand.
- Conversions to unsigned integers are unchecked at runtime, imitating earlier Nim
  versions. The documentation was improved to acknowledge this special case.
  See https://github.com/nim-lang/RFCs/issues/175 for more details.
- There is a new syntax for lvalue references: `var b {.byaddr.} = expr` enabled by
  `import std/decls`.
- `var a {.foo.}: MyType = expr` now lowers to `foo(a, MyType, expr)` for
  non-builtin pragmas, enabling things like lvalue references (see `decls.byaddr`).



## Compiler changes

- The generated JS code uses spaces, instead of mixing spaces and tabs.
- The Nim compiler now supports the ``--asm`` command option for easier
  inspection of the produced assembler code.
- The Nim compiler now supports a new pragma called ``.localPassc`` to
  pass specific compiler options to the C(++) backend for the C(++) file
  that was produced from the current Nim module.
- The compiler now infers "sink parameters". To disable this for a specific routine,
  annotate it with `.nosinks`. To disable it for a section of code, use
  `{.push sinkInference: off.}`...`{.pop.}`.
- The compiler now supports a new switch `--panics:on` that turns runtime
  errors like `IndexError` or `OverflowError` into fatal errors that **cannot**
  be caught via Nim's `try` statement. `--panics:on` can improve the
  runtime efficiency and code size of your program significantly.
- The compiler now warns about inheriting directly from `system.Exception` as
  this is **very bad** style. You should inherit from `ValueError`, `IOError`,
  `OSError` or from a different specific exception type that inherits from
  `CatchableError` and cannot be confused with a `Defect`.
- The error reporting for Nim's effect system has been improved.
- Implicit conversions for `const` behave correctly now, meaning that code like
  `const SOMECONST = 0.int; procThatTakesInt32(SOMECONST)` will be illegal now.
  Simply write `const SOMECONST = 0` instead.
- The `{.dynlib.}` pragma is now required for exporting symbols when making
  shared objects on POSIX and macOS, which make it consistent with the behavior
  on Windows.
- The compiler is now more strict about type conversions concerning proc
  types: Type conversions cannot be used to hide `.raise` effects or side
  effects, instead a `cast` must be used. With the flag `--useVersion:1.0` the
  old behaviour is emulated.
- The Nim compiler now implements a faster way to detect overflows based
  on GCC's `__builtin_sadd_overflow` family of functions. (Clang also
  supports these). Some versions of GCC lack this feature and unfortunately
  we cannot detect this case reliably. So if you get compilation errors like
  "undefined reference to `__builtin_saddll_overflow`" compile your programs
  with `-d:nimEmulateOverflowChecks`.




## Bugfixes

- Fixed "`nimgrep --nocolor` is ignored on posix; should be instead: `--nimgrep --color=[auto]|true|false`"
  ([#7591](https://github.com/nim-lang/Nim/issues/7591))
- Fixed "Runtime index on const array (of converted obj) causes C-compiler error"
  ([#10514](https://github.com/nim-lang/Nim/issues/10514))
- Fixed "windows x86 with vcc compile error with "asmNoStackFrame""
  ([#12298](https://github.com/nim-lang/Nim/issues/12298))
- Fixed "[TODO] regression: Error: Locks requires --threads:on option"
  ([#12330](https://github.com/nim-lang/Nim/issues/12330))
- Fixed "Add --cc option to --help or --fullhelp output"
  ([#12010](https://github.com/nim-lang/Nim/issues/12010))
- Fixed "questionable `csize` definition in `system.nim`"
  ([#12187](https://github.com/nim-lang/Nim/issues/12187))
- Fixed "os.getAppFilename() returns incorrect results on OpenBSD"
  ([#12389](https://github.com/nim-lang/Nim/issues/12389))
- Fixed "HashSet[uint64] slow insertion depending on values"
  ([#11764](https://github.com/nim-lang/Nim/issues/11764))
- Fixed "Differences between compiling 'classic call syntax' vs 'method call syntax' ."
  ([#12453](https://github.com/nim-lang/Nim/issues/12453))
- Fixed "c -d:nodejs --> SIGSEGV: Illegal storage access"
  ([#12502](https://github.com/nim-lang/Nim/issues/12502))
- Fixed "Closure iterator crashes on --newruntime due to "dangling references""
  ([#12443](https://github.com/nim-lang/Nim/issues/12443))
- Fixed "No `=destroy` for elements of closure environments other than for latest devel --gc:destructors"
  ([#12577](https://github.com/nim-lang/Nim/issues/12577))
- Fixed "strutils:formatBiggestFloat() gives different results in JS mode"
  ([#8242](https://github.com/nim-lang/Nim/issues/8242))
- Fixed "Regression (devel): the new `csize_t` definition isn't consistently used, nor tested thoroughly..."
  ([#12597](https://github.com/nim-lang/Nim/issues/12597))
- Fixed "tables.take() is defined only for `Table` and missed for other table containers"
  ([#12519](https://github.com/nim-lang/Nim/issues/12519))
- Fixed "`pthread_key_t` errors on OpenBSD"
  ([#12135](https://github.com/nim-lang/Nim/issues/12135))
- Fixed "newruntime: simple seq pop at ct results in compile error"
  ([#12644](https://github.com/nim-lang/Nim/issues/12644))
- Fixed "[Windows] finish.exe C:\Users\<USERNAME>\.nimble\bin is not in your PATH environment variable."
  ([#12319](https://github.com/nim-lang/Nim/issues/12319))
- Fixed "Error with strformat + asyncdispatch + const"
  ([#12612](https://github.com/nim-lang/Nim/issues/12612))
- Fixed "MultipartData needs $"
  ([#11863](https://github.com/nim-lang/Nim/issues/11863))
- Fixed "Nim stdlib style issues with --styleCheck:error"
  ([#12687](https://github.com/nim-lang/Nim/issues/12687))
- Fixed "new $nimbleDir path substitution yields unexpected search paths"
  ([#12767](https://github.com/nim-lang/Nim/issues/12767))
- Fixed "Regression: inlined procs now get multiple rounds of destructor injection"
  ([#12766](https://github.com/nim-lang/Nim/issues/12766))
- Fixed "newruntime: compiler generates defective code"
  ([#12669](https://github.com/nim-lang/Nim/issues/12669))
- Fixed "broken windows modules path handling because of 'os.relativePath' breaking changes"
  ([#12734](https://github.com/nim-lang/Nim/issues/12734))
- Fixed "for loop tuple syntax not rendered correctly"
  ([#12740](https://github.com/nim-lang/Nim/issues/12740))
- Fixed "Crash when trying to use `type.name[0]`"
  ([#12804](https://github.com/nim-lang/Nim/issues/12804))
- Fixed "Enums should be considered Trivial types in Atomics"
  ([#12812](https://github.com/nim-lang/Nim/issues/12812))
- Fixed "Produce static/const initializations for variables when possible"
  ([#12216](https://github.com/nim-lang/Nim/issues/12216))
- Fixed "Assigning discriminator field leads to internal assert with --gc:destructors"
  ([#12821](https://github.com/nim-lang/Nim/issues/12821))
- Fixed "nimsuggest `use` command does not return all instances of symbol"
  ([#12832](https://github.com/nim-lang/Nim/issues/12832))
- Fixed "@[] is a problem for --gc:destructors"
  ([#12820](https://github.com/nim-lang/Nim/issues/12820))
- Fixed "Codegen ICE in allPathsAsgnResult"
  ([#12827](https://github.com/nim-lang/Nim/issues/12827))
- Fixed "seq[Object with ref and destructor type] doesn't work in old runtime"
  ([#12882](https://github.com/nim-lang/Nim/issues/12882))
- Fixed "Destructor not invoked because it is instantiated too late, old runtime"
  ([#12883](https://github.com/nim-lang/Nim/issues/12883))
- Fixed "The collect macro does not handle if/case correctly"
  ([#12874](https://github.com/nim-lang/Nim/issues/12874))
- Fixed "allow typed/untyped params in magic procs (even if not in stdlib)"
  ([#12911](https://github.com/nim-lang/Nim/issues/12911))
- Fixed "ARC/newruntime memory corruption"
  ([#12899](https://github.com/nim-lang/Nim/issues/12899))
- Fixed "tasyncclosestall.nim still flaky test: Address already in use"
  ([#12919](https://github.com/nim-lang/Nim/issues/12919))
- Fixed "newruntime and computed goto: variables inside the loop are in generated code uninitialised"
  ([#12785](https://github.com/nim-lang/Nim/issues/12785))
- Fixed "osx: dsymutil needs to be called for debug builds to keep debug info"
  ([#12735](https://github.com/nim-lang/Nim/issues/12735))
- Fixed "codegen ICE with ref objects, gc:destructors"
  ([#12826](https://github.com/nim-lang/Nim/issues/12826))
- Fixed "mutable iterator cannot yield named tuples"
  ([#12945](https://github.com/nim-lang/Nim/issues/12945))
- Fixed "parsecfg stores "\r\n" line breaks just as "\n""
  ([#12970](https://github.com/nim-lang/Nim/issues/12970))
- Fixed "db_postgres.getValue issues warning when no rows found"
  ([#12973](https://github.com/nim-lang/Nim/issues/12973))
- Fixed "ARC: Unpacking tuple with seq causes segfault"
  ([#12989](https://github.com/nim-lang/Nim/issues/12989))
- Fixed "ARC/newruntime: strutils.join on seq with only empty strings causes segfault"
  ([#12965](https://github.com/nim-lang/Nim/issues/12965))
- Fixed "regression (1.0.4): `{.push exportc.}` wrongly affects generic instantiations, causing codegen errors"
  ([#12985](https://github.com/nim-lang/Nim/issues/12985))
- Fixed "cdt, crash with --gc:arc, works fine with default gc"
  ([#12978](https://github.com/nim-lang/Nim/issues/12978))
- Fixed "ARC: No indexError thrown on out-of-bound seq access, SIGSEGV instead"
  ([#12961](https://github.com/nim-lang/Nim/issues/12961))
- Fixed "ARC/async: Returning in a try-block results in wrong codegen"
  ([#12956](https://github.com/nim-lang/Nim/issues/12956))
- Fixed "asm keyword is generating wrong output C code when --cc:tcc"
  ([#12988](https://github.com/nim-lang/Nim/issues/12988))
- Fixed "Destructor not invoked"
  ([#13026](https://github.com/nim-lang/Nim/issues/13026))
- Fixed "ARC/newruntime: Adding inherited var ref object to seq with base type causes segfault"
  ([#12964](https://github.com/nim-lang/Nim/issues/12964))
- Fixed "Style check error with JS compiler target"
  ([#13032](https://github.com/nim-lang/Nim/issues/13032))
- Fixed "regression(1.0.4): undeclared identifier: 'readLines'; plus another regression and bug"
  ([#13013](https://github.com/nim-lang/Nim/issues/13013))
- Fixed "regression(1.04) `invalid pragma: since` with nim js"
  ([#12996](https://github.com/nim-lang/Nim/issues/12996))
- Fixed "Sink to MemMove optimization in injectdestructors"
  ([#13002](https://github.com/nim-lang/Nim/issues/13002))
- Fixed "--gc:arc: `catch` doesn't work with exception subclassing"
  ([#13072](https://github.com/nim-lang/Nim/issues/13072))
- Fixed "nim c --gc:arc --exceptions:{setjmp,goto} incorrectly handles raise; `nim cpp --gc:arc` is ok"
  ([#13070](https://github.com/nim-lang/Nim/issues/13070))
- Fixed "typetraits feature request - get subtype of a generic type"
  ([#6454](https://github.com/nim-lang/Nim/issues/6454))
- Fixed "CountTable inconsistencies between keys() and len() after setting value to 0"
  ([#12813](https://github.com/nim-lang/Nim/issues/12813))
- Fixed "{.align.} pragma is not applied if there is a generic field"
  ([#13122](https://github.com/nim-lang/Nim/issues/13122))
- Fixed "ARC, finalizer, allow rebinding the same function multiple times"
  ([#13112](https://github.com/nim-lang/Nim/issues/13112))
- Fixed "`nim doc` treats `export localSymbol` incorrectly"
  ([#13100](https://github.com/nim-lang/Nim/issues/13100))
- Fixed "--gc:arc SIGSEGV (double free?)"
  ([#13119](https://github.com/nim-lang/Nim/issues/13119))
- Fixed "codegen bug with arc"
  ([#13105](https://github.com/nim-lang/Nim/issues/13105))
- Fixed "symbols not defined in the grammar"
  ([#10665](https://github.com/nim-lang/Nim/issues/10665))
- Fixed "[JS] Move is not defined"
  ([#9674](https://github.com/nim-lang/Nim/issues/9674))
- Fixed "[TODO] pathutils.`/` can return invalid AbsoluteFile"
  ([#13121](https://github.com/nim-lang/Nim/issues/13121))
- Fixed "regression(1.04) `nim doc main.nim` generates broken html (no css)"
  ([#12998](https://github.com/nim-lang/Nim/issues/12998))
- Fixed "Wrong supportsCopyMem on string in type section"
  ([#13095](https://github.com/nim-lang/Nim/issues/13095))
- Fixed "Arc, finalizer, out of memory"
  ([#13157](https://github.com/nim-lang/Nim/issues/13157))
- Fixed "`--genscript` messes up nimcache and future nim invocations"
  ([#13144](https://github.com/nim-lang/Nim/issues/13144))
- Fixed "--gc:arc with --exceptions:goto for "nim c" generate invalid c code"
  ([#13186](https://github.com/nim-lang/Nim/issues/13186))
- Fixed "[regression] duplicate member `_i1` codegen bug"
  ([#13195](https://github.com/nim-lang/Nim/issues/13195))
- Fixed "RTree investigations with valgrind for --gc:arc"
  ([#13110](https://github.com/nim-lang/Nim/issues/13110))
- Fixed "relativePath("foo", ".") returns wrong path"
  ([#13211](https://github.com/nim-lang/Nim/issues/13211))
- Fixed "asyncftpclient - problem with welcome.msg"
  ([#4684](https://github.com/nim-lang/Nim/issues/4684))
- Fixed "Unclear error message, lowest priority"
  ([#13256](https://github.com/nim-lang/Nim/issues/13256))
- Fixed "Channel messages are corrupted"
  ([#13219](https://github.com/nim-lang/Nim/issues/13219))
- Fixed "Codegen bug with exportc and case objects"
  ([#13281](https://github.com/nim-lang/Nim/issues/13281))
- Fixed "[bugfix] fix #11590: c compiler warnings silently ignored, giving undefined behavior"
  ([#11591](https://github.com/nim-lang/Nim/issues/11591))
- Fixed "[CI] tnetdial flaky test"
  ([#13132](https://github.com/nim-lang/Nim/issues/13132))
- Fixed "Cross-Compiling with -d:mingw fails to locate compiler under OSX"
  ([#10717](https://github.com/nim-lang/Nim/issues/10717))
- Fixed "`nim doc --project` broken with imports below main project file or duplicate names"
  ([#13150](https://github.com/nim-lang/Nim/issues/13150))
- Fixed "regression: isNamedTuple(MyGenericTuple[int]) is false, should be true"
  ([#13349](https://github.com/nim-lang/Nim/issues/13349))
- Fixed "--gc:arc codegen bug copying objects bound to C structs with missing C struct fields"
  ([#13269](https://github.com/nim-lang/Nim/issues/13269))
- Fixed "write requires conversion to string"
  ([#13182](https://github.com/nim-lang/Nim/issues/13182))
- Fixed "Some remarks to stdlib documentation"
  ([#13352](https://github.com/nim-lang/Nim/issues/13352))
- Fixed "a `check` in unittest generated by template doesn't show actual value"
  ([#6736](https://github.com/nim-lang/Nim/issues/6736))
- Fixed "Implicit return with case expression fails with 'var' return."
  ([#3339](https://github.com/nim-lang/Nim/issues/3339))
- Fixed "Segfault with closure on arc"
  ([#13314](https://github.com/nim-lang/Nim/issues/13314))
- Fixed "[Macro] Crash on malformed case statement with multiple else"
  ([#13255](https://github.com/nim-lang/Nim/issues/13255))
- Fixed "regression: `echo 'discard' | nim c -r -` generates a file '-' ; `-` should be treated specially"
  ([#13374](https://github.com/nim-lang/Nim/issues/13374))
- Fixed "on OSX, debugging (w gdb or lldb) a nim program crashes at the 1st call to `execCmdEx`"
  ([#9634](https://github.com/nim-lang/Nim/issues/9634))
- Fixed "Internal error in getTypeDescAux"
  ([#13378](https://github.com/nim-lang/Nim/issues/13378))
- Fixed "gc:arc mode breaks tuple let"
  ([#13368](https://github.com/nim-lang/Nim/issues/13368))
- Fixed "Nim compiler hangs for certain C/C++ compiler errors"
  ([#8648](https://github.com/nim-lang/Nim/issues/8648))
- Fixed "htmlgen does not support `data-*` attributes"
  ([#13444](https://github.com/nim-lang/Nim/issues/13444))
- Fixed "[gc:arc] setLen will cause string not to be null-terminated."
  ([#13457](https://github.com/nim-lang/Nim/issues/13457))
- Fixed "joinPath("", "") is "/" ; should be """
  ([#13455](https://github.com/nim-lang/Nim/issues/13455))
- Fixed "[CI] flaky test on windows: tests/osproc/texitcode.nim"
  ([#13449](https://github.com/nim-lang/Nim/issues/13449))
- Fixed "Casting to float32 on NimVM is broken"
  ([#13479](https://github.com/nim-lang/Nim/issues/13479))
- Fixed "`--hints:off` doesn't work (doesn't override ~/.config/nim.cfg)"
  ([#8312](https://github.com/nim-lang/Nim/issues/8312))
- Fixed "joinPath("", "") is "/" ; should be """
  ([#13455](https://github.com/nim-lang/Nim/issues/13455))
- Fixed "tables.values is broken"
  ([#13496](https://github.com/nim-lang/Nim/issues/13496))
- Fixed "global user config can override project specific config"
  ([#9405](https://github.com/nim-lang/Nim/issues/9405))
- Fixed "Non deterministic macros and id consistency problem"
  ([#12627](https://github.com/nim-lang/Nim/issues/12627))
- Fixed "try expression doesn't work with return on expect branch"
  ([#13490](https://github.com/nim-lang/Nim/issues/13490))
- Fixed "CI will break every 4 years on feb 28: times doesn't handle leap years properly"
  ([#13543](https://github.com/nim-lang/Nim/issues/13543))
- Fixed "[minor] `nimgrep --word` doesn't work with operators (eg misses  `1 +% 2`)"
  ([#13528](https://github.com/nim-lang/Nim/issues/13528))
- Fixed "`as` is usable as infix operator but its existence and precedence are not documented"
  ([#13409](https://github.com/nim-lang/Nim/issues/13409))
- Fixed "JSON unmarshalling drops seq's items"
  ([#13531](https://github.com/nim-lang/Nim/issues/13531))
- Fixed "os.joinPath returns wrong path when head ends '\' or '/' and tail starts '..'."
  ([#13579](https://github.com/nim-lang/Nim/issues/13579))
- Fixed "Block-local types with the same name lead to bad codegen (sighashes regression)"
  ([#5170](https://github.com/nim-lang/Nim/issues/5170))
- Fixed "tuple codegen error"
  ([#12704](https://github.com/nim-lang/Nim/issues/12704))
- Fixed "newHttpHeaders does not accept repeated headers"
  ([#13573](https://github.com/nim-lang/Nim/issues/13573))
- Fixed "regression: --incremental:on fails on simplest example"
  ([#13319](https://github.com/nim-lang/Nim/issues/13319))
- Fixed "strscan can't get value of last element in format"
  ([#13605](https://github.com/nim-lang/Nim/issues/13605))
- Fixed "hashes_examples crashes with "Bus Error" (unaligned access) on sparc64"
  ([#12508](https://github.com/nim-lang/Nim/issues/12508))
- Fixed "gc:arc bug with re-used `seq[T]`"
  ([#13596](https://github.com/nim-lang/Nim/issues/13596))
- Fixed "`raise CatchableError` is broken with --gc:arc  when throwing inside a proc"
  ([#13599](https://github.com/nim-lang/Nim/issues/13599))
- Fixed "cpp --gc:arc --exceptions:goto fails to raise with discard"
  ([#13436](https://github.com/nim-lang/Nim/issues/13436))
- Fixed "terminal doesn't compile with -d:useWinAnsi"
  ([#13607](https://github.com/nim-lang/Nim/issues/13607))
- Fixed "Parsing "sink ptr T" - region needs to be an object type"
  ([#12757](https://github.com/nim-lang/Nim/issues/12757))
- Fixed "gc:arc + threads:on + closures compilation error"
  ([#13519](https://github.com/nim-lang/Nim/issues/13519))
- Fixed "[ARC] segmentation fault"
  ([#13240](https://github.com/nim-lang/Nim/issues/13240))
- Fixed "times.toDateTime buggy on 29th, 30th and 31th of each month"
  ([#13558](https://github.com/nim-lang/Nim/issues/13558))
- Fixed "Deque misbehaves on VM"
  ([#13310](https://github.com/nim-lang/Nim/issues/13310))
- Fixed "Nimscript listFiles should throw exception when path is not found"
  ([#12676](https://github.com/nim-lang/Nim/issues/12676))
- Fixed "koch boot fails if even an empty config.nims is present in ~/.config/nims/ [devel regression]"
  ([#13633](https://github.com/nim-lang/Nim/issues/13633))
- Fixed "nim doc generates lots of false positive LockLevel warnings"
  ([#13218](https://github.com/nim-lang/Nim/issues/13218))
- Fixed "Arrays are passed by copy to iterators, causing crashes, unnecessary allocations and slowdowns"
  ([#12747](https://github.com/nim-lang/Nim/issues/12747))
- Fixed "Range types always uses signed integer as a base type"
  ([#13646](https://github.com/nim-lang/Nim/issues/13646))
- Fixed "Generate c code cannot compile with recent devel version"
  ([#13645](https://github.com/nim-lang/Nim/issues/13645))
- Fixed "[regression] VM: Error: cannot convert -1 to uint64"
  ([#13661](https://github.com/nim-lang/Nim/issues/13661))
- Fixed "Spurious raiseException(Exception) detected"
  ([#13654](https://github.com/nim-lang/Nim/issues/13654))
- Fixed "gc:arc memory leak"
  ([#13659](https://github.com/nim-lang/Nim/issues/13659))
- Fixed "Error: cannot convert -1 to uint (inside tuples)"
  ([#13671](https://github.com/nim-lang/Nim/issues/13671))
- Fixed "strformat issue with --gc:arc"
  ([#13622](https://github.com/nim-lang/Nim/issues/13622))
- Fixed "astToStr doesn't work inside generics"
  ([#13524](https://github.com/nim-lang/Nim/issues/13524))
- Fixed "oswalkdir.walkDirRec wont return folders"
  ([#11458](https://github.com/nim-lang/Nim/issues/11458))
- Fixed "`echo 'echo 1' | nim c -r -`  silently gives wrong results (nimBetterRun not updated for stdin)"
  ([#13412](https://github.com/nim-lang/Nim/issues/13412))
- Fixed "gc:arc destroys the global variable accidentally."
  ([#13691](https://github.com/nim-lang/Nim/issues/13691))
- Fixed "[minor] sigmatch errors should be sorted, for reproducible errors"
  ([#13538](https://github.com/nim-lang/Nim/issues/13538))
- Fixed "Exception when converting csize to clong"
  ([#13698](https://github.com/nim-lang/Nim/issues/13698))
- Fixed "ARC: variables are no copied on the thread spawn causing crashes"
  ([#13708](https://github.com/nim-lang/Nim/issues/13708))
- Fixed "Illegal distinct seq causes compiler crash"
  ([#13720](https://github.com/nim-lang/Nim/issues/13720))
- Fixed "cyclic seq definition crashes the compiler"
  ([#13715](https://github.com/nim-lang/Nim/issues/13715))
- Fixed "Iterator with openArray parameter make the argument evaluated many times"
  ([#13417](https://github.com/nim-lang/Nim/issues/13417))
- Fixed "net/asyncnet: Unable to access peer's certificate chain"
  ([#13299](https://github.com/nim-lang/Nim/issues/13299))
- Fixed "Accidentally "SIGSEGV: Illegal storage access" error after arc optimizations (#13325)"
  ([#13709](https://github.com/nim-lang/Nim/issues/13709))
- Fixed "Base64 Regression"
  ([#13722](https://github.com/nim-lang/Nim/issues/13722))
- Fixed "A regression (?) with --gc:arc and repr"
  ([#13731](https://github.com/nim-lang/Nim/issues/13731))
- Fixed "Internal compiler error when using the new variable pragmas"
  ([#13737](https://github.com/nim-lang/Nim/issues/13737))
- Fixed "bool conversion produces vcc 2019 warning at cpp compilation stage"
  ([#13744](https://github.com/nim-lang/Nim/issues/13744))
- Fixed "Compiler "does not detect" a type recursion error in the wrong code, remaining frozen"
  ([#13763](https://github.com/nim-lang/Nim/issues/13763))
- Fixed "[minor] regression: `Foo[0.0] is Foo[-0.0]` is now false"
  ([#13730](https://github.com/nim-lang/Nim/issues/13730))
- Fixed "`nim doc` - only whitespace on first line causes segfault"
  ([#13631](https://github.com/nim-lang/Nim/issues/13631))
- Fixed "hashset regression"
  ([#13794](https://github.com/nim-lang/Nim/issues/13794))
- Fixed "`os.getApplFreebsd` could return incorrect paths in the case of a long path"
  ([#13806](https://github.com/nim-lang/Nim/issues/13806))
- Fixed "Destructors are not inherited"
  ([#13810](https://github.com/nim-lang/Nim/issues/13810))
- Fixed "io.readLines AssertionError on devel"
  ([#13829](https://github.com/nim-lang/Nim/issues/13829))
- Fixed "exceptions:goto accidentally reset the variable during exception handling"
  ([#13782](https://github.com/nim-lang/Nim/issues/13782))
