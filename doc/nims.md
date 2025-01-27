================================
          NimScript
================================

.. default-role:: code
.. include:: rstcommon.rst

Strictly speaking, `NimScript` is the subset of Nim that can be evaluated
by Nim's builtin virtual machine (VM). This VM is used for Nim's compiletime
function evaluation features.

The `nim`:cmd: executable processes the ``.nims`` configuration files in
the following directories (in this order; later files overwrite
previous settings):

1) If environment variable `XDG_CONFIG_HOME` is defined,
   ``$XDG_CONFIG_HOME/nim/config.nims`` or
   ``~/.config/nim/config.nims`` (POSIX) or
   ``%APPDATA%/nim/config.nims`` (Windows). This file can be skipped
   with the `--skipUserCfg`:option: command line option.
2) ``$parentDir/config.nims`` where ``$parentDir`` stands for any
   parent directory of the project file's path. These files can be
   skipped with the `--skipParentCfg`:option: command line option.
3) ``$projectDir/config.nims`` where ``$projectDir`` stands for the
   project's path. This file can be skipped with the `--skipProjCfg`:option:
   command line option.
4) A project can also have a project specific configuration file named
   ``$project.nims`` that resides in the same directory as
   ``$project.nim``. This file can be skipped with the same
   `--skipProjCfg`:option: command line option.

For available procs and implementation details see [nimscript](nimscript.html).


Limitations
===========

NimScript is subject to some limitations caused by the implementation of the VM
(virtual machine):

* Nim's FFI (foreign function interface) is not available in NimScript. This
  means that any stdlib module which relies on `importc` can not be used in
  the VM.

* `ptr` operations are are hard to emulate with the symbolic representation
  the VM uses. They are available and tested extensively but there are bugs left.

* `var T` function arguments rely on `ptr` operations internally and might
  also be problematic in some cases.

* More than one level of `ref` is generally not supported (for example, the type
  `ref ref int`).

* Multimethods are not available.

* `random.randomize()` requires an `int64` explicitly passed as argument, you *must* pass a Seed integer.


Standard library modules
========================

At least the following standard library modules are available:

* [algorithm](algorithm.html)
* [base64](base64.html)
* [bitops](bitops.html)
* [chains](chains.html)
* [colors](colors.html)
* [complex](complex.html)
* [distros](distros.html)
* [std/editdistance](editdistance.html)
* [htmlgen](htmlgen.html)
* [htmlparser](htmlparser.html)
* [httpcore](httpcore.html)
* [json](json.html)
* [lenientops](lenientops.html)
* [macros](macros.html)
* [math](math.html)
* [options](options.html)
* [os](os.html)
* [parsecfg](parsecfg.html)
* [parsecsv](parsecsv.html)
* [parsejson](parsejson.html)
* [parsesql](parsesql.html)
* [parseutils](parseutils.html)
* [punycode](punycode.html)
* [random](random.html)
* [ropes](ropes.html)
* [std/setutils](setutils.html)
* [stats](stats.html)
* [strformat](strformat.html)
* [strmisc](strmisc.html)
* [strscans](strscans.html)
* [strtabs](strtabs.html)
* [strutils](strutils.html)
* [sugar](sugar.html)
* [unicode](unicode.html)
* [unidecode](unidecode.html)
* [uri](uri.html)
* [std/wordwrap](wordwrap.html)
* [xmlparser](xmlparser.html)

In addition to the standard Nim syntax ([system](system.html) module),
NimScripts support the procs and templates defined in the
[nimscript](nimscript.html) module too.

See also:
* [Check the tests for more information about modules compatible with NimScript](
  https://github.com/nim-lang/Nim/blob/devel/tests/test_nimscript.nims)


NimScript as a configuration file
=================================

A command-line switch `--FOO`:option: is written as `switch("FOO")` in
NimScript. Similarly, command-line `--FOO:VAL`:option: translates to
`switch("FOO", "VAL")`.

Here are few examples of using the `switch` proc:

  ```nim
  # command-line: --opt:size
  switch("opt", "size")
  # command-line: --define:release or -d:release
  switch("define", "release")
  # command-line: --forceBuild
  switch("forceBuild")
  # command-line: --hint[Conf]:off or --hint:Conf:off
  switch("hint", "[Conf]:off")
  ```

NimScripts also support `--`:option: templates for convenience, which look
like command-line switches written as-is in the NimScript file. So the
above example can be rewritten as:

  ```nim
  --opt:size
  --define:release
  --forceBuild
  ```

**Note**: In general, the *define* switches can also be set in
NimScripts using `switch` or `--`, as shown in above examples. Few
`define` switches such as `-d:strip`:option:, `-d:lto`:option: and
`-d:lto_incremental`:option: cannot be set in NimScripts.


NimScript as a build tool
=========================

The `task` template that the `system` module defines allows a NimScript
file to be used as a build tool. The following example defines a
task `build` that is an alias for the `c`:option: command:

  ```nim
  task build, "builds an example":
    setCommand "c"
  ```


In fact, as a convention the following tasks should be available:

=========     ===================================================
Task          Description
=========     ===================================================
`help`        List all the available NimScript tasks along with their docstrings.
`build`       Build the project with the required
              backend (`c`:option:, `cpp`:option: or `js`:option:).
`tests`       Runs the tests belonging to the project.
`bench`       Runs benchmarks belonging to the project.
=========     ===================================================


Look at the module [distros](distros.html) for some support of the
OS's native package managers.


Nimble integration
==================

See the [Nimble readme](https://github.com/nim-lang/nimble#readme)
for more information.


Standalone NimScript
====================

NimScript can also be used directly as a portable replacement for Bash and
Batch files. Use `nim myscript.nims`:cmd: to run ``myscript.nims``. For example,
installation of Nimble could be accomplished with this simple script:

  ```nim
  mode = ScriptMode.Verbose

  var id = 0
  while dirExists("nimble" & $id):
    inc id

  exec "git clone https://github.com/nim-lang/nimble.git nimble" & $id

  withDir "nimble" & $id & "/src":
    exec "nim c nimble"

  mvFile "nimble" & $id & "/src/nimble".toExe, "bin/nimble".toExe
  ```

On Unix, you can also use the shebang `#!/usr/bin/env nim`, as long as your filename
ends with ``.nims``:

  ```nim
  #!/usr/bin/env nim
  mode = ScriptMode.Silent

  echo "hello world"
  ```

Use `#!/usr/bin/env -S nim e --hints:off` to disable hints and relax the file extension constraint.


Benefits
========

Cross-Platform
--------------

It is a cross-platform scripting language that can run where Nim can run,
e.g. you can not run Batch or PowerShell on Linux or Mac,
the Bash for Linux might not run on Mac,
there are no unit tests tools for Batch, etc.

NimScript can detect on which platform, operating system,
architecture, and even which Linux distribution is running on,
allowing the same script to support a lot of systems.

See the following (incomplete) example:

  ```nim
  import std/distros

  # Architectures.
  if defined(amd64):
    echo "Architecture is x86 64Bits"
  elif defined(i386):
    echo "Architecture is x86 32Bits"
  elif defined(arm):
    echo "Architecture is ARM"

  # Operating Systems.
  if defined(linux):
    echo "Operating System is GNU Linux"
  elif defined(windows):
    echo "Operating System is Microsoft Windows"
  elif defined(macosx):
    echo "Operating System is Apple OS X"

  # Distros.
  if detectOs(Ubuntu):
    echo "Distro is Ubuntu"
  elif detectOs(ArchLinux):
    echo "Distro is ArchLinux"
  elif detectOs(Debian):
    echo "Distro is Debian"
  ```


Uniform Syntax
--------------

The syntax, style, and rest of the ecosystem is the same as for compiled Nim,
that means there is nothing new to learn, no context switch for developers.


Powerful Metaprogramming
------------------------

NimScript can use Nim's templates, macros, types, concepts, effect tracking system, and more,
you can create modules that work on compiled Nim and also on interpreted NimScript.

`func` will still check for side effects, `debugEcho` also works as expected,
making it ideal for functional scripting metaprogramming.

This is an example of a third party module that uses macros and templates to
translate text strings on unmodified NimScript:

  ```nim
  import nimterlingua
  nimterlingua("translations.cfg")
  echo "cat"  # Run with -d:RU becomes "kot", -d:ES becomes "gato", ...
  ```

translations.cfg

  ```none
  [cat]
  ES = gato
  IT = gatto
  RU = kot
  FR = chat
  ```


* [Nimterlingua](https://nimble.directory/pkg/nimterlingua)


Graceful Fallback
-----------------

Some features of compiled Nim may not work on NimScript,
but often a graceful and seamless fallback degradation is used.

See the following NimScript:

  ```nim
  if likely(true):
    discard
  elif unlikely(false):
    discard

  proc foo() {.compiletime.} = echo NimVersion

  static:
    echo CompileDate
  ```


`likely()`, `unlikely()`, `static:` and `{.compiletime.}`
will produce no code at all when run on NimScript,
but still no error nor warning is produced and the code just works.

Evolving Scripting language
---------------------------

NimScript evolves together with Nim,
[occasionally new features might become available on NimScript](
https://github.com/nim-lang/Nim/pulls?q=nimscript+is%3Amerged),
adapted from compiled Nim or added as new features on both.

Scripting Language with a Package Manager
-----------------------------------------

You can create your own modules to be compatible with NimScript,
and check [Nimble](https://nimble.directory)
to search for third party modules that may work on NimScript.

DevOps Scripting
----------------

You can use NimScript to deploy to production, run tests, build projects, do benchmarks,
generate documentation, and all kinds of DevOps/SysAdmin specific tasks.

* [An example of a third party NimScript that can be used as a project-agnostic
  tool.](https://github.com/kaushalmodi/nim_config#list-available-tasks)
