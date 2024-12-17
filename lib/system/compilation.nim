const
  NimMajor* {.intdefine.}: int = 2
    ## is the major number of Nim's version. Example:
    ##   ```nim
    ##   when (NimMajor, NimMinor, NimPatch) >= (1, 3, 1): discard
    ##   ```
    # see also std/private/since

  NimMinor* {.intdefine.}: int = 3
    ## is the minor number of Nim's version.
    ## Odd for devel, even for releases.

  NimPatch* {.intdefine.}: int = 1
    ## is the patch number of Nim's version.
    ## Odd for devel, even for releases.

{.push profiler: off.}
let nimvm* {.magic: "Nimvm", compileTime.}: bool = false
  ## May be used only in `when` expression.
  ## It is true in Nim VM context and false otherwise.
{.pop.}

const
  isMainModule* {.magic: "IsMainModule".}: bool = false
    ## True only when accessed in the main module. This works thanks to
    ## compiler magic. It is useful to embed testing code in a module.

  CompileDate* {.magic: "CompileDate".}: string = "0000-00-00"
    ## The date (in UTC) of compilation as a string of the form
    ## `YYYY-MM-DD`. This works thanks to compiler magic.

  CompileTime* {.magic: "CompileTime".}: string = "00:00:00"
    ## The time (in UTC) of compilation as a string of the form
    ## `HH:MM:SS`. This works thanks to compiler magic.

proc defined*(x: untyped): bool {.magic: "Defined", noSideEffect, compileTime.}
  ## Special compile-time procedure that checks whether `x` is
  ## defined.
  ##
  ## `x` is an external symbol introduced through the compiler's
  ## `-d:x switch <nimc.html#compiler-usage-compileminustime-symbols>`_ to enable
  ## build time conditionals:
  ##   ```nim
  ##   when not defined(release):
  ##     # Do here programmer friendly expensive sanity checks.
  ##   # Put here the normal code
  ##   ```
  ##
  ## See also:
  ## * `compileOption <#compileOption,string>`_ for `on|off` options
  ## * `compileOption <#compileOption,string,string>`_ for enum options
  ## * `define pragmas <manual.html#implementation-specific-pragmas-compileminustime-define-pragmas>`_

proc declared*(x: untyped): bool {.magic: "Declared", noSideEffect, compileTime.}
  ## Special compile-time procedure that checks whether `x` is
  ## declared. `x` has to be an identifier or a qualified identifier.
  ##
  ## This can be used to check whether a library provides a certain
  ## feature or not:
  ##   ```nim
  ##   when not declared(strutils.toUpper):
  ##     # provide our own toUpper proc here, because strutils is
  ##     # missing it.
  ##   ```
  ##
  ## See also:
  ## * `declaredInScope <#declaredInScope,untyped>`_

proc declaredInScope*(x: untyped): bool {.magic: "DeclaredInScope", noSideEffect, compileTime.}
  ## Special compile-time procedure that checks whether `x` is
  ## declared in the current scope. `x` has to be an identifier.

proc compiles*(x: untyped): bool {.magic: "Compiles", noSideEffect, compileTime.} =
  ## Special compile-time procedure that checks whether `x` can be compiled
  ## without any semantic error.
  ## This can be used to check whether a type supports some operation:
  ##   ```nim
  ##   when compiles(3 + 4):
  ##     echo "'+' for integers is available"
  ##   ```
  discard

proc astToStr*[T](x: T): string {.magic: "AstToStr", noSideEffect.}
  ## Converts the AST of `x` into a string representation. This is very useful
  ## for debugging.

proc runnableExamples*(rdoccmd = "", body: untyped) {.magic: "RunnableExamples".} =
  ## A section you should use to mark `runnable example`:idx: code with.
  ##
  ## - In normal debug and release builds code within
  ##   a `runnableExamples` section is ignored.
  ## - The documentation generator is aware of these examples and considers them
  ##   part of the `##` doc comment. As the last step of documentation
  ##   generation each runnableExample is put in its own file `$file_examples$i.nim`,
  ##   compiled and tested. The collected examples are
  ##   put into their own module to ensure the examples do not refer to
  ##   non-exported symbols.
  runnableExamples:
    proc timesTwo*(x: int): int =
      ## This proc doubles a number.
      runnableExamples:
        # at module scope
        const exported* = 123
        assert timesTwo(5) == 10
        block: # at block scope
          defer: echo "done"
      runnableExamples "-d:foo -b:cpp":
        import std/compilesettings
        assert querySetting(backend) == "cpp"
        assert defined(foo)
      runnableExamples "-r:off": ## this one is only compiled
         import std/browsers
         openDefaultBrowser "https://forum.nim-lang.org/"
      2 * x

proc compileOption*(option: string): bool {.
  magic: "CompileOption", noSideEffect.} =
  ## Can be used to determine an `on|off` compile-time option.
  ##
  ## See also:
  ## * `compileOption <#compileOption,string,string>`_ for enum options
  ## * `defined <#defined,untyped>`_
  ## * `std/compilesettings module <compilesettings.html>`_
  runnableExamples("--floatChecks:off"):
    static: doAssert not compileOption("floatchecks")
    {.push floatChecks: on.}
    static: doAssert compileOption("floatchecks")
    # floating point NaN and Inf checks enabled in this scope
    {.pop.}

proc compileOption*(option, arg: string): bool {.
  magic: "CompileOptionArg", noSideEffect.} =
  ## Can be used to determine an enum compile-time option.
  ##
  ## See also:
  ## * `compileOption <#compileOption,string>`_ for `on|off` options
  ## * `defined <#defined,untyped>`_
  ## * `std/compilesettings module <compilesettings.html>`_
  runnableExamples:
    when compileOption("opt", "size") and compileOption("gc", "boehm"):
      discard "compiled with optimization for size and uses Boehm's GC"

template currentSourcePath*: string = instantiationInfo(-1, true).filename
  ## Returns the full file-system path of the current source.
  ##
  ## To get the directory containing the current source, use it with
  ## `ospaths2.parentDir() <ospaths2.html#parentDir%2Cstring>`_ as
  ## `currentSourcePath.parentDir()`.
  ##
  ## The path returned by this template is set at compile time.
  ##
  ## See the docstring of `macros.getProjectPath() <macros.html#getProjectPath>`_
  ## for an example to see the distinction between the `currentSourcePath()`
  ## and `getProjectPath()`.
  ##
  ## See also:
  ## * `ospaths2.getCurrentDir() proc <ospaths2.html#getCurrentDir>`_

proc slurp*(filename: string): string {.magic: "Slurp".}
  ## This is an alias for `staticRead <#staticRead,string>`_.

proc staticRead*(filename: string): string {.magic: "Slurp".}
  ## Compile-time `readFile <syncio.html#readFile,string>`_ proc for easy
  ## `resource`:idx: embedding:
  ##
  ## The maximum file size limit that `staticRead` and `slurp` can read is
  ## near or equal to the *free* memory of the device you are using to compile.
  ##   ```nim
  ##   const myResource = staticRead"mydatafile.bin"
  ##   ```
  ##
  ## `slurp <#slurp,string>`_ is an alias for `staticRead`.

proc gorge*(command: string, input = "", cache = ""): string {.
  magic: "StaticExec".} = discard
  ## This is an alias for `staticExec <#staticExec,string,string,string>`_.

proc staticExec*(command: string, input = "", cache = ""): string {.
  magic: "StaticExec".} = discard
  ## Executes an external process at compile-time and returns its text output
  ## (stdout + stderr).
  ##
  ## If `input` is not an empty string, it will be passed as a standard input
  ## to the executed program.
  ##   ```nim
  ##   const buildInfo = "Revision " & staticExec("git rev-parse HEAD") &
  ##                     "\nCompiled on " & staticExec("uname -v")
  ##   ```
  ##
  ## `gorge <#gorge,string,string,string>`_ is an alias for `staticExec`.
  ##
  ## Note that you can use this proc inside a pragma like
  ## `passc <manual.html#implementation-specific-pragmas-passc-pragma>`_ or
  ## `passl <manual.html#implementation-specific-pragmas-passl-pragma>`_.
  ##
  ## If `cache` is not empty, the results of `staticExec` are cached within
  ## the `nimcache` directory. Use `--forceBuild` to get rid of this caching
  ## behaviour then. `command & input & cache` (the concatenated string) is
  ## used to determine whether the entry in the cache is still valid. You can
  ## use versioning information for `cache`:
  ##   ```nim
  ##   const stateMachine = staticExec("dfaoptimizer", "input", "0.8.0")
  ##   ```

proc gorgeEx*(command: string, input = "", cache = ""): tuple[output: string,
                                                              exitCode: int] {.noinit.} =
  ## Similar to `gorge <#gorge,string,string,string>`_ but also returns the
  ## precious exit code.
  discard
