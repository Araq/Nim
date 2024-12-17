===================================
   Nim Compiler User Guide
===================================

:Author: Andreas Rumpf
:Version: |nimversion|

.. default-role:: code
.. include:: rstcommon.rst
.. contents::

..

> "Look at you, hacker. A pathetic creature of meat and bone, panting and
> sweating as you run through my corridors. How can you challenge a perfect,
> immortal machine?"


Introduction
============

This document describes the usage of the *Nim compiler*
on the different supported platforms. It is not a definition of the Nim
programming language (which is covered in the [manual](manual.html)).

Nim is free software; it is licensed under the
[MIT License](https://www.opensource.org/licenses/mit-license.php).


Compiler Usage
==============

Command-line switches
---------------------
All options that take a `PATH` or `DIR` argument are subject to path substitution:

- `$nim`: The global nim prefix path
- `$lib`: The stdlib path
- `$home` and `~`: The user's home path
- `$config`: The directory of the module currently being compiled
- `$projectname`: The project file's name without file extension
- `$projectpath` and `$projectdir`: The project file's path
- `$nimcache`: The nimcache path


Basic command-line switches are:

.. no syntax highlighting in the below included files at the moment
.. default-role:: code

Usage:

.. include:: basicopt.txt

----

Advanced command-line switches are:

.. include:: advopt.txt


.. include:: rstcommon.rst

List of warnings
----------------

Each warning can be activated individually with `--warning:NAME:on|off`:option: or
in a `push` pragma with `{.warning[NAME]:on|off.}`.

==========================       ============================================
Name                             Description
==========================       ============================================
CannotOpenFile                   Some file not essential for the compiler's
                                 working could not be opened.
OctalEscape                      The code contains an unsupported octal
                                 sequence.
Deprecated                       The code uses a deprecated symbol.
ConfigDeprecated                 The project makes use of a deprecated config
                                 file.
SmallLshouldNotBeUsed            The letter 'l' should not be used as an
                                 identifier.
EachIdentIsTuple                 The code contains a confusing `var`
                                 declaration.
CStringConv                      Warn about dangerous implicit conversions
                                 to `cstring`.
EnumConv                         Warn about conversions from enum to enum.
AnyEnumConv                      Warn about any conversions to an enum type.
HoleEnumConv                     Warn about conversion to an enum with
                                 holes. These conversions are unsafe.
ResultUsed                       Warn about the usage of the
                                 built-in `result` variable.
User                             Some user-defined warning.
==========================       ============================================


List of hints
-------------

Each hint can be activated individually with `--hint:NAME:on|off`:option: or in a
`push` pragma with `{.hint[NAME]:on|off.}`.

==========================       ============================================
Name                             Description
==========================       ============================================
CC                               Shows when the C compiler is called.
CodeBegin
CodeEnd
CondTrue
Conf                             A config file was loaded.
ConvToBaseNotNeeded
ConvFromXtoItselfNotNeeded
Dependency
Exec                             Program is executed.
ExprAlwaysX
ExtendedContext
GCStats                          Dumps statistics about the Garbage Collector.
GlobalVar                        Shows global variables declarations.
Link                             Linking phase.
Name
Path                             Search paths modifications.
Pattern
Performance
Processing                       Artifact being compiled.
QuitCalled
Source                           The source line that triggered a diagnostic
                                 message.
StackTrace
Success, SuccessX                Successful compilation of a library or a binary.
User
UserRaw
XDeclaredButNotUsed              Unused symbols in the code.
==========================       ============================================


Verbosity levels
----------------

=====  ============================================
Level  Description
=====  ============================================
0      Minimal output level for the compiler.
1      Displays compilation of all the compiled files, including those imported
       by other modules or through the [compile pragma](
       manual.html#implementation-specific-pragmas-compile-pragma).
       This is the default level.
2      Displays compilation statistics, enumerates the dynamic
       libraries that will be loaded by the final binary, and dumps to
       standard output the result of applying [a filter to the source code](
       filters.html) if any filter was used during compilation.
3      In addition to the previous levels dumps a debug stack trace
       for compiler developers.
=====  ============================================


Compile-time symbols
--------------------

Through the `-d:x`:option: or `--define:x`:option: switch you can define compile-time
symbols for conditional compilation. The defined switches can be checked in
source code with the [when statement](
manual.html#statements-and-expressions-when-statement) and
[defined proc](system.html#defined,untyped). The typical use of this switch is
to enable builds in release mode (`-d:release`:option:) where optimizations are
enabled for better performance. Another common use is the `-d:ssl`:option: switch to
activate SSL sockets.

Additionally, you may pass a value along with the symbol: `-d:x=y`:option:
which may be used in conjunction with the [compile-time define
pragmas](manual.html#implementation-specific-pragmas-compileminustime-define-pragmas)
to override symbols during build time.

Compile-time symbols are completely **case insensitive** and underscores are
ignored too. `--define:FOO`:option: and `--define:foo`:option: are identical.

Compile-time symbols starting with the `nim` prefix are reserved for the
implementation and should not be used elsewhere.

==========================       ============================================
Name                             Description
==========================       ============================================
nimStdSetjmp                     Use the standard `setjmp()/longjmp()` library
                                 functions for setjmp-based exceptions. This is
                                 the default on most platforms.
nimSigSetjmp                     Use `sigsetjmp()/siglongjmp()` for setjmp-based exceptions.
nimRawSetjmp                     Use `_setjmp()/_longjmp()` on POSIX and `_setjmp()/longjmp()`
                                 on Windows, for setjmp-based exceptions. It's the default on
                                 BSDs and BSD-like platforms, where it's significantly faster
                                 than the standard functions.
nimBuiltinSetjmp                 Use `__builtin_setjmp()/__builtin_longjmp()` for setjmp-based
                                 exceptions. This will not work if an exception is being thrown
                                 and caught inside the same procedure. Useful for benchmarking.
==========================       ============================================


Configuration files
-------------------

**Note:** The *project file name* is the name of the ``.nim`` file that is
passed as a command-line argument to the compiler.


The `nim`:cmd: executable processes configuration files in the following
directories (in this order; later files overwrite previous settings):

1) ``$nim/config/nim.cfg``, ``/etc/nim/nim.cfg`` (UNIX) or
   ``<Nim's installation directory>\config\nim.cfg`` (Windows).
   This file can be skipped with the `--skipCfg`:option: command line option.
2) If environment variable `XDG_CONFIG_HOME` is defined,
   ``$XDG_CONFIG_HOME/nim/nim.cfg`` or ``~/.config/nim/nim.cfg`` (POSIX) or
   ``%APPDATA%/nim/nim.cfg`` (Windows).
   This file can be skipped with the `--skipUserCfg`:option: command line
   option.
3) ``$parentDir/nim.cfg`` where ``$parentDir`` stands for any parent
   directory of the project file's path.
   These files can be skipped with the `--skipParentCfg`:option:
   command-line option.
4) ``$projectDir/nim.cfg`` where ``$projectDir`` stands for the project
   file's path.
   This file can be skipped with the `--skipProjCfg`:option:
   command-line option.
5) A project can also have a project-specific configuration file named
   ``$project.nim.cfg`` that resides in the same directory as ``$project.nim``.
   This file can be skipped with the `--skipProjCfg`:option:
   command-line option.


Command-line settings have priority over configuration file settings.

The default build of a project is a `debug build`:idx:. To compile a
`release build`:idx: define the `release` symbol:

  ```cmd
  nim c -d:release myproject.nim
  ```

To compile a `dangerous release build`:idx: define the `danger` symbol:

  ```cmd
  nim c -d:danger myproject.nim
  ```


Search path handling
--------------------

Nim has the concept of a global search path (PATH) that is queried to
determine where to find imported modules or include files. If multiple files are
found an ambiguity error is produced.

`nim dump`:cmd: shows the contents of the PATH.

However before the PATH is used the current directory is checked for the
file's existence. So if PATH contains ``$lib`` and ``$lib/bar`` and the
directory structure looks like this:

    $lib/x.nim
    $lib/bar/x.nim
    foo/x.nim
    foo/main.nim
    other.nim

And `main` imports `x`, `foo/x` is imported. If `other` imports `x`
then both ``$lib/x.nim`` and ``$lib/bar/x.nim`` match but ``$lib/x.nim`` is used
as it is the first match.


Generated C code directory
--------------------------
The generated files that Nim produces all go into a subdirectory called
``nimcache``. Its full path is

- ``$XDG_CACHE_HOME/nim/$projectname(_r|_d)`` or ``~/.cache/nim/$projectname(_r|_d)``
  on Posix
- ``$HOME\nimcache\$projectname(_r|_d)`` on Windows.

The `_r` suffix is used for release builds, `_d` is for debug builds.

This makes it easy to delete all generated files.

The `--nimcache`:option:
[compiler switch][command-line switches] can be used to
to change the ``nimcache`` directory.

However, the generated C code is not platform-independent. C code generated for
Linux does not compile on Windows, for instance. The comment on top of the
C file lists the OS, CPU, and CC the file has been compiled for.


Compiler Selection
==================

To change the compiler from the default compiler (at the command line):

  ```cmd
  nim c --cc:llvm_gcc --compile_only myfile.nim
  ```

This uses the configuration defined in ``config\nim.cfg`` for `llvm_gcc`:cmd:.

If nimcache already contains compiled code from a different compiler for the same project,
add the `-f`:option: flag to force all files to be recompiled.

The default compiler is defined at the top of ``config\nim.cfg``.
Changing this setting affects the compiler used by `koch`:cmd: to (re)build Nim.

To use the `CC` environment variable, use `nim c --cc:env myfile.nim`:cmd:.
To use the `CXX` environment variable, use `nim cpp --cc:env myfile.nim`:cmd:.
`--cc:env`:option: is available since Nim version 1.4.


Cross-compilation
=================

To cross compile, use for example:

  ```cmd
  nim c --cpu:i386 --os:linux --compileOnly --genScript myproject.nim
  ```

Then move the C code and the compile script `compile_myproject.sh`:cmd: to your
Linux i386 machine and run the script.

Another way is to make Nim invoke a cross compiler toolchain:

  ```cmd
  nim c --cpu:arm --os:linux myproject.nim
  ```

For cross compilation, the compiler invokes a C compiler named like
`$cpu.$os.$cc` (for example `arm.linux.gcc`) with options defined in
`$cpu.$os.$cc.options.always`. The configuration system is used to provide
meaningful defaults. For example, for Linux on a 32-bit ARM CPU, your
configuration file should contain something like:

    arm.linux.gcc.path = "/usr/bin"
    arm.linux.gcc.exe = "arm-linux-gcc"
    arm.linux.gcc.linkerexe = "arm-linux-gcc"
    arm.linux.gcc.options.always = "-w -fmax-errors=3"

Cross-compilation for Windows
=============================

To cross-compile for Windows from Linux or macOS using the MinGW-w64 toolchain:

  ```cmd
  nim c -d:mingw myproject.nim
  # `nim r` also works, running the binary via `wine` or `wine64`:
  nim r -d:mingw --eval:'import os; echo "a" / "b"'
  ```

Use `--cpu:i386`:option: or `--cpu:amd64`:option: to switch the CPU architecture.

The MinGW-w64 toolchain can be installed as follows:

  ```cmd
  apt install mingw-w64   # Ubuntu
  yum install mingw32-gcc
  yum install mingw64-gcc # CentOS - requires EPEL
  brew install mingw-w64  # OSX
  ```


Cross-compilation for Android
=============================

There are two ways to compile for Android: terminal programs (Termux) and with
the NDK (Android Native Development Kit).

The first one is to treat Android as a simple Linux and use
[Termux](https://wiki.termux.com) to connect and run the Nim compiler
directly on android as if it was Linux. These programs are console-only
programs that can't be distributed in the Play Store.

Use regular `nim c`:cmd: inside termux to make Android terminal programs.

Normal Android apps are written in Java, to use Nim inside an Android app
you need a small Java stub that calls out to a native library written in
Nim using the [NDK](https://developer.android.com/ndk). You can also use
[native-activity](https://developer.android.com/ndk/samples/sample_na)
to have the Java stub be auto-generated for you.

Use `nim c -c --cpu:arm --os:android -d:androidNDK --noMain:on`:cmd: to
generate the C source files you need to include in your Android Studio
project. Add the generated C files to CMake build script in your Android
project. Then do the final compile with Android Studio which uses Gradle
to call CMake to compile the project.

Because Nim is part of a library it can't have its own C-style `main()`:c:
so you would need to define your own `android_main`:c: and init the Java
environment, or use a library like SDL2 or GLFM to do it. After the Android
stuff is done, it's very important to call `NimMain()`:c: in order to
initialize Nim's garbage collector and to run the top level statements
of your program.

  ```Nim
  proc NimMain() {.importc.}
  proc glfmMain*(display: ptr GLFMDisplay) {.exportc.} =
    NimMain() # initialize garbage collector memory, types and stack
  ```


The name `NimMain` can be influenced via the `--nimMainPrefix:prefix` switch.
Use `--nimMainPrefix:MyLib` and the function to call is named `MyLibNimMain`.


Cross-compilation for iOS
=========================

To cross-compile for iOS you need to be on a macOS computer and use XCode.
Normal languages for iOS development are Swift and Objective C. Both of these
use LLVM and can be compiled into object files linked together with C, C++
or Objective C code produced by Nim.

Use `nim c -c --os:ios --noMain:on`:cmd: to generate C files and include them in
your XCode project. Then you can use XCode to compile, link, package and
sign everything.

Because Nim is part of a library it can't have its own C-style `main()`:c: so you
would need to define `main` that calls `autoreleasepool` and
`UIApplicationMain` to do it, or use a library like SDL2 or GLFM. After
the iOS setup is done, it's very important to call `NimMain()`:c: to
initialize Nim's garbage collector and to run the top-level statements
of your program.

  ```Nim
  proc NimMain() {.importc.}
  proc glfmMain*(display: ptr GLFMDisplay) {.exportc.} =
    NimMain() # initialize garbage collector memory, types and stack
  ```

Note: XCode's "make clean" gets confused about the generated nim.c files,
so you need to clean those files manually to do a clean build.

The name `NimMain` can be influenced via the `--nimMainPrefix:prefix` switch.
Use `--nimMainPrefix:MyLib` and the function to call is named `MyLibNimMain`.


Cross-compilation for Nintendo Switch
=====================================

Simply add `--os:nintendoswitch`:option:
to your usual `nim c`:cmd: or `nim cpp`:cmd: command and set the `passC`:option:
and `passL`:option: command line switches to something like:

  ```cmd
  nim c ... --d:nimAllocPagesViaMalloc --mm:orc --passC="-I$DEVKITPRO/libnx/include" ...
  --passL="-specs=$DEVKITPRO/libnx/switch.specs -L$DEVKITPRO/libnx/lib -lnx"
  ```

or setup a ``nim.cfg`` file like so:

    #nim.cfg
    --mm:orc
    --d:nimAllocPagesViaMalloc
    --define:nimInheritHandles
    --passC="-I$DEVKITPRO/libnx/include"
    --passL="-specs=$DEVKITPRO/libnx/switch.specs -L$DEVKITPRO/libnx/lib -lnx"

The devkitPro setup must be the same as the default with their new installer
[here for Mac/Linux](https://github.com/devkitPro/pacman/releases) or
[here for Windows](https://github.com/devkitPro/installer/releases).

For example, with the above-mentioned config:

  ```cmd
  nim c --os:nintendoswitch switchhomebrew.nim
  ```

This will generate a file called ``switchhomebrew.elf`` which can then be turned into
an nro file with the `elf2nro`:cmd: tool in the devkitPro release. Examples can be found at
[the nim-libnx github repo](https://github.com/jyapayne/nim-libnx.git).

There are a few things that don't work because the devkitPro libraries don't support them.
They are:

1. Waiting for a subprocess to finish. A subprocess can be started, but right
   now it can't be waited on, which sort of makes subprocesses a bit hard to use
2. Dynamic calls. Switch OS (Horizon) doesn't support dynamic libraries, so dlopen/dlclose are not available.
3. mqueue. Sadly there are no mqueue headers.
4. ucontext. No headers for these either. No coroutines for now :(
5. nl_types. No headers for this.
6. As mmap is not supported, the nimAllocPagesViaMalloc option has to be used.

GPU Compilation
===============

Compiling for GPU computation can be achieved with `--cc:nvcc` for CUDA with nvcc, or with `--cc:hipcc` for AMD GPUs with HIP. Both compilers require building for C++ with `nim cpp`.

Here's a very simple CUDA kernel example using emit, which can be compiled with `nim cpp --cc:nvcc --define:"useMalloc" hello_kernel.nim` assuming you have the CUDA toolkit installed.

```nim
{.emit: """
__global__ void add(int a, int b) {
  int c;
  c = a + b;
}
""".}

proc main() =
  {.emit: """
  add<<<1,1>>>(2,7);
  """.}

main()
```

DLL generation
==============

**Note**: The same rules apply to `lib*.so` shared object files on UNIX. For better
readability only the DLL version is described here.

Nim supports the generation of DLLs. However, there must be only one
instance of the GC per process/address space. This instance is contained in
``nimrtl.dll``. This means that every generated Nim DLL depends
on ``nimrtl.dll``. To generate the "nimrtl.dll" file, use the command:

  ```cmd
  nim c -d:release lib/nimrtl.nim
  ```

To link against ``nimrtl.dll`` use the command:

  ```cmd
  nim c -d:useNimRtl myprog.nim
  ```


Additional compilation switches
===============================

The standard library supports a growing number of `useX` conditional defines
affecting how some features are implemented. This section tries to give a
complete list.

======================   =========================================================
Define                   Effect
======================   =========================================================
`release`                Turns on the optimizer.
                         More aggressive optimizations are possible, e.g.:
                         `--passC:-ffast-math`:option: (but see issue #10305)
`danger`                 Turns off all runtime checks and turns on the optimizer.
`useFork`                Makes `osproc` use `fork`:c: instead of `posix_spawn`:c:.
`useNimRtl`              Compile and link against ``nimrtl.dll``.
`useMalloc`              Makes Nim use C's `malloc`:idx: instead of Nim's
                         own memory manager, albeit prefixing each allocation with
                         its size to support clearing memory on reallocation.
                         This only works with `--mm:none`:option:,
                         `--mm:arc`:option: and `--mm:orc`:option:.
`useRealtimeGC`          Enables support of Nim's GC for *soft* realtime
                         systems. See the documentation of the [refc](refc.html)
                         for further information.
`logGC`                  Enable GC logging to stdout.
`nodejs`                 The JS target is actually ``node.js``.
`ssl`                    Enables OpenSSL support for the sockets module.
`memProfiler`            Enables memory profiling for the native GC.
`uClibc`                 Use uClibc instead of libc. (Relevant for Unix-like OSes)
`checkAbi`               When using types from C headers, add checks that compare
                         what's in the Nim file with what's in the C header.
                         This may become enabled by default in the future.
`tempDir`                This symbol takes a string as its value, like
                         `--define:tempDir:/some/temp/path`:option: to override
                         the temporary directory returned by `os.getTempDir()`.
                         The value **should** end with a directory separator
                         character. (Relevant for the Android platform)
`useShPath`              This symbol takes a string as its value, like
                         `--define:useShPath:/opt/sh/bin/sh`:option: to override
                         the path for the `sh`:cmd: binary, in cases where it is
                         not located in the default location ``/bin/sh``.
`noSignalHandler`        Disable the crash handler from ``system.nim``.
`globalSymbols`          Load all `{.dynlib.}` libraries with the `RTLD_GLOBAL`:c:
                         flag on Posix systems to resolve symbols in subsequently
                         loaded libraries.
`lto`                    Enable link-time optimization in the backend compiler and
                         linker.
`lto_incremental`        Enable link-time optimization and additionally enable
                         incremental linking for compilers that support it.
                         Currently only clang and vcc.
`strip`                  Strip debug symbols added by the backend compiler from
                         the executable.
======================   =========================================================



Additional Features
===================

This section describes Nim's additional features that are not listed in the
Nim manual. Some of the features here only make sense for the C code
generator and are subject to change.


LineDir option
--------------
The `--lineDir`:option: option can be turned on or off. If turned on the
generated C code contains `#line`:c: directives. This may be helpful for
debugging with GDB.


StackTrace option
-----------------
If the `--stackTrace`:option: option is turned on, the generated C contains code to
ensure that proper stack traces are given if the program crashes or some uncaught exception is raised.


LineTrace option
----------------
The `--lineTrace`:option: option implies the `stackTrace`:option: option.
If turned on,
the generated C contains code to ensure that proper stack traces with line
number information are given if the program crashes or an uncaught exception
is raised.


DynlibOverride
==============

By default Nim's `dynlib` pragma causes the compiler to generate
`GetProcAddress`:cpp: (or their Unix counterparts)
calls to bind to a DLL. With the `dynlibOverride`:option: command line switch this
can be prevented and then via `--passL`:option: the static library can be linked
against. For instance, to link statically against Lua this command might work
on Linux:

  ```cmd
  nim c --dynlibOverride:lua --passL:liblua.lib program.nim
  ```


Backend language options
========================

The typical compiler usage involves using the `compile`:option: or `c`:option:
command to transform a ``.nim`` file into one or more ``.c`` files which are then
compiled with the platform's C compiler into a static binary. However, there
are other commands to compile to C++, Objective-C, or JavaScript. More details
can be read in the [Nim Backend Integration document](backends.html).


Nim documentation tools
=======================

Nim provides the `doc`:idx: command to generate HTML
documentation from ``.nim`` source files. Only exported symbols will appear in
the output. For more details see [the docgen documentation](docgen.html).

Nim idetools integration
========================

Nim provides language integration with external IDEs through the
idetools command. See the documentation of [idetools](idetools.html)
for further information.

..
  Nim interactive mode
  ====================

  The Nim compiler supports an interactive mode. This is also known as
  a `REPL`:idx: (*read eval print loop*). If Nim has been built with the
  `-d:nimUseLinenoise` switch, it uses the GNU readline library for terminal
  input management. To start Nim in interactive mode use the command
  `nim secret`. To quit use the `quit()` command. To determine whether an input
  line is an incomplete statement to be continued these rules are used:

  1. The line ends with ``[-+*/\\<>!\?\|%&$@~,;:=#^]\s*$`` (operator symbol followed by optional whitespace).
  2. The line starts with a space (indentation).
  3. The line is within a triple quoted string literal. However, the detection
     does not work if the line contains more than one `"""`.


Nim for embedded systems
========================

While the default Nim configuration is targeted for optimal performance on
modern PC hardware and operating systems with ample memory, it is very well
possible to run Nim code and a good part of the Nim standard libraries on small
embedded microprocessors with only a few kilobytes of memory.

A good start is to use the `any` operating target together with the
`malloc` memory allocator and the `arc` garbage collector. For example:

  ```cmd
  nim c --os:any --mm:arc -d:useMalloc [...] x.nim
  ```

- `--mm:arc`:option: will enable the reference counting memory management instead
  of the default garbage collector. This enables Nim to use heap memory which
  is required for strings and seqs, for example.

- The `--os:any`:option: target makes sure Nim does not depend on any specific
  operating system primitives. Your platform should support only some basic
  ANSI C library `stdlib` and `stdio` functions which should be available
  on almost any platform.

- The `-d:useMalloc`:option: option configures Nim to use only the standard C memory
  manage primitives `malloc()`:c:, `free()`:c:, `realloc()`:c:.

If your platform does not provide these functions it should be trivial to
provide an implementation for them and link these to your program.

For targets with very restricted memory, it might be beneficial to pass some
additional flags to both the Nim compiler and the C compiler and/or linker
to optimize the build for size. For example, the following flags can be used
when targeting a gcc compiler:

`--opt:size -d:lto -d:strip`:option:

The `--opt:size`:option: flag instructs Nim to optimize code generation for small
size (with the help of the C compiler), the `-d:lto`:option: flags enable link-time
optimization in the compiler and linker, the `-d:strip`:option: strips debug symbols.

Check the [Cross-compilation] section for instructions on how to compile the
program for your target.


nimAllocPagesViaMalloc
----------------------

Nim's default allocator is based on TLSF, this algorithm was designed for embedded
devices. This allocator gets blocks/pages of memory via a currently undocumented
`osalloc` API which usually uses POSIX's `mmap` call. On many environments `mmap`
is not available but C's `malloc` is. You can use the `nimAllocPagesViaMalloc`
define to use `malloc` instead of `mmap`. `nimAllocPagesViaMalloc` is currently
only supported with `--mm:arc` or `--mm:orc`. (Since version 1.6)

nimPage256 / nimPage512 / nimPage1k
===================================

Adjust the page size for Nim's GC allocator. This enables using
`nimAllocPagesViaMalloc` on devices with less RAM. The default
page size requires too much RAM to work.

Recommended settings:

- < 32 kB of RAM use `nimPage256`

- < 512 kB of RAM use `nimPage512`

- < 2 MB of RAM use `nimPage1k`

Initial testing hasn't shown much difference between 512B or 1kB page sizes
in terms of performance or latency. Using `nimPages256` will limit the
total amount of allocatable RAM.

nimMemAlignTiny
===============

Sets `MemAlign` to `4` bytes which reduces the memory alignment
to better match some embedded devices.

Thread stack size
=================

Nim's thread API provides a simple wrapper around more advanced
RTOS task features. Customizing the stack size and stack guard size can
be done by setting `-d:nimThreadStackSize=16384` or `-d:nimThreadStackGuard=32`.

Currently only Zephyr, NuttX and FreeRTOS support these configurations.

Nim for realtime systems
========================

See the `--mm:arc` or `--mm:orc` memory management settings in
[MM](mm.html) for further information.


Signal handling in Nim
======================

The Nim programming language has no concept of Posix's signal handling
mechanisms. However, the standard library offers some rudimentary support
for signal handling, in particular, segmentation faults are turned into
fatal errors that produce a stack trace. This can be disabled with the
`-d:noSignalHandler`:option: switch.


Optimizing for Nim
==================

Nim has no separate optimizer, but the C code that is produced is very
efficient. Most C compilers have excellent optimizers, so usually it is
not needed to optimize one's code. Nim has been designed to encourage
efficient code: The most readable code in Nim is often the most efficient
too.

However, sometimes one has to optimize. Do it in the following order:

1. switch off the embedded debugger (it is **slow**!)
2. turn on the optimizer and turn off runtime checks
3. profile your code to find where the bottlenecks are
4. try to find a better algorithm
5. do low-level optimizations

This section can only help you with the last item.


Optimizing string handling
--------------------------

String assignments are sometimes expensive in Nim: They are required to
copy the whole string. However, the compiler is often smart enough to not copy
strings. Due to the argument passing semantics, strings are never copied when
passed to subroutines. The compiler does not copy strings that are a result of
a procedure call, because the callee returns a new string anyway.
Thus it is efficient to do:

  ```Nim
  var s = procA() # assignment will not copy the string; procA allocates a new
                  # string already
  ```

However, it is not efficient to do:

  ```Nim
  var s = varA    # assignment has to copy the whole string into a new buffer!
  ```

For `let` symbols a copy is not always necessary:

  ```Nim
  let s = varA    # may only copy a pointer if it safe to do so
  ```

The compiler optimizes string case statements: A hashing scheme is used for them
if several different string constants are used. So code like this is reasonably
efficient:

  ```Nim
  case normalize(k.key)
  of "name": c.name = v
  of "displayname": c.displayName = v
  of "version": c.version = v
  of "os": c.oses = split(v, {';'})
  of "cpu": c.cpus = split(v, {';'})
  of "authors": c.authors = split(v, {';'})
  of "description": c.description = v
  of "app":
    case normalize(v)
    of "console": c.app = appConsole
    of "gui": c.app = appGUI
    else: quit(errorStr(p, "expected: console or gui"))
  of "license": c.license = UnixToNativePath(k.value)
  else: quit(errorStr(p, "unknown variable: " & k.key))
  ```
