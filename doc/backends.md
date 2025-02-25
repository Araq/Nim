================================
   Nim Backend Integration
================================

:Author: Puppet Master
:Version: |nimversion|

.. default-role:: code
.. include:: rstcommon.rst
.. no syntax highlighting here by default:

.. contents::

> "Heresy grows from idleness." -- Unknown.


Introduction
============

The [Nim Compiler User Guide](nimc.html) documents the typical
compiler invocation, using the `compile`:option:
or `c`:option: command to transform a
``.nim`` file into one or more ``.c`` files which are then compiled with the
platform's C compiler into a static binary. However, there are other commands
to compile to C++, Objective-C, or JavaScript. This document tries to
concentrate in a single place all the backend and interfacing options.

The Nim compiler supports mainly two backend families: the C, C++ and
Objective-C targets and the JavaScript target. [The C like targets](
#backends-the-c-like-targets) creates source files that can be compiled
into a library or a final executable. [The JavaScript target](
#backends-the-javascript-target) can generate a ``.js`` file which you
reference from an HTML file or create a [standalone Node.js program](
https://nodejs.org).

On top of generating libraries or standalone applications, Nim offers
bidirectional interfacing with the backend targets through generic and
specific pragmas.


Backends
========

The C like targets
------------------

The commands to compile to either C, C++ or Objective-C are:

//compileToC, cc          compile project with C code generator
//compileToCpp, cpp       compile project to C++ code
//compileToOC, objc       compile project to Objective C code

The most significant difference between these commands is that if you look
into the ``nimcache`` directory you will find ``.c``, ``.cpp`` or ``.m``
files, other than that all of them will produce a native binary for your
project. This allows you to take the generated code and place it directly
into a project using any of these languages. Here are some typical command-
line invocations:

  ```cmd
  nim c hallo.nim
  nim cpp hallo.nim
  nim objc hallo.nim
  ```

The compiler commands select the target backend, but if needed you can
[specify additional switches for cross-compilation](
nimc.html#crossminuscompilation) to select the target CPU, operative system
or compiler/linker commands.


The JavaScript target
---------------------

Nim can also generate `JavaScript`:idx: code through the `js`:option: command.

Nim targets JavaScript 1.5 which is supported by any widely used browser.
Since JavaScript does not have a portable means to include another module,
Nim just generates a long ``.js`` file.

Features or modules that the JavaScript platform does not support are not
available. This includes:

* manual memory management (`alloc`, etc.)
* casting and other unsafe operations (`cast` operator, `zeroMem`, etc.)
* file management
* OS-specific operations
* threading, coroutines
* some modules of the standard library

To compensate, the standard library has modules [catered to the JS backend](
lib.html#pure-libraries-modules-for-the-javascript-backend)
and more support will come in the future (for instance, Node.js bindings
to get OS info).

To compile a Nim module into a ``.js`` file use the `js`:option: command; the
default is a ``.js`` file that is supposed to be referenced in an ``.html``
file. However, you can also run the code with `nodejs`:idx:
(https://nodejs.org):

  ```cmd
  nim js -r examples/hallo.nim
  ```

If you experience errors saying that `globalThis` is not defined, be
sure to run a recent version of Node.js (at least 12.0).


Interfacing
===========

Nim offers bidirectional interfacing with the target backend. This means
that you can call backend code from Nim and Nim code can be called by
the backend code. Usually the direction of which calls which depends on your
software architecture (is Nim your main program or is Nim providing a
component?).


Nim code calling the backend
----------------------------

Nim code can interface with the backend through the [Foreign function
interface](manual.html#foreign-function-interface) mainly through the
[importc pragma](manual.html#foreign-function-interface-importc-pragma).
The `importc` pragma is the *generic* way of making backend symbols available
in Nim and is available in all the target backends (JavaScript too). The C++
or Objective-C backends have their respective [ImportCpp](
manual.html#implementation-specific-pragmas-importcpp-pragma) and
[ImportObjC](manual.html#implementation-specific-pragmas-importobjc-pragma)
pragmas to call methods from classes.

Whenever you use any of these pragmas you need to integrate native code into
your final binary. In the case of JavaScript this is no problem at all, the
same HTML file which hosts the generated JavaScript will likely provide other
JavaScript functions which you are importing with `importc`.

However, for the C like targets you need to link external code either
statically or dynamically. The preferred way of integrating native code is to
use dynamic linking because it allows you to compile Nim programs without
the need for having the related development libraries installed. This is done
through the [dynlib pragma for import](
manual.html#foreign-function-interface-dynlib-pragma-for-import), though
more specific control can be gained using the [dynlib module](dynlib.html).

The [dynlibOverride](nimc.html#dynliboverride) command line switch allows
to avoid dynamic linking if you need to statically link something instead.
Nim wrappers designed to statically link source files can use the [compile
pragma](manual.html#implementation-specific-pragmas-compile-pragma) if
there are few sources or providing them along the Nim code is easier than using
a system library. Libraries installed on the host system can be linked in with
the [PassL pragma](manual.html#implementation-specific-pragmas-passl-pragma).

To wrap native code, take a look at the [c2nim tool](
https://github.com/nim-lang/c2nim/blob/master/doc/c2nim.rst) which helps
with the process of scanning and transforming header files into a Nim
interface.

### C invocation example

Create a ``logic.c`` file with the following content:

  ```c
  int addTwoIntegers(int a, int b)
  {
    return a + b;
  }
  ```

Create a ``calculator.nim`` file with the following content:

  ```nim
  {.compile: "logic.c".}
  proc addTwoIntegers(a, b: cint): cint {.importc.}

  when isMainModule:
    echo addTwoIntegers(3, 7)
  ```

With these two files in place, you can run `nim c -r calculator.nim`:cmd: and
the Nim compiler will compile the ``logic.c`` file in addition to
``calculator.nim`` and link both into an executable, which outputs `10` when
run. Another way to link the C file statically and get the same effect would
be to remove the line with the `compile` pragma and run the following
typical Unix commands:

  ```cmd
  gcc -c logic.c
  ar rvs mylib.a logic.o
  nim c --passL:mylib.a -r calculator.nim
  ```

Just like in this example we pass the path to the ``mylib.a`` library (and we
could as well pass ``logic.o``) we could be passing switches to link any other
static C library.


### JavaScript invocation example

Create a ``host.html`` file with the following content:

  ```
  <html><body>
  <script type="text/javascript">
  function addTwoIntegers(a, b)
  {
    return a + b;
  }
  </script>
  <script type="text/javascript" src="calculator.js"></script>
  </body></html>
  ```

Create a ``calculator.nim`` file with the following content (or reuse the one
from the previous section):

  ```nim
  proc addTwoIntegers(a, b: int): int {.importc.}

  when isMainModule:
    echo addTwoIntegers(3, 7)
  ```

Compile the Nim code to JavaScript with `nim js -o:calculator.js
calculator.nim`:cmd: and open ``host.html`` in a browser. If the browser supports
javascript, you should see the value `10` in the browser's console. Use the
[dom module](dom.html) for specific DOM querying and modification procs
or take a look at [karax](https://github.com/pragmagic/karax) for how to
develop browser-based applications.


Backend code calling Nim
------------------------

Backend code can interface with Nim code exposed through the [exportc
pragma](manual.html#foreign-function-interface-exportc-pragma). The
`exportc` pragma is the *generic* way of making Nim symbols available to
the backends. By default, the Nim compiler will mangle all the Nim symbols to
avoid any name collision, so the most significant thing the `exportc` pragma
does is maintain the Nim symbol name, or if specified, use an alternative
symbol for the backend in case the symbol rules don't match.

The JavaScript target doesn't have any further interfacing considerations
since it also has garbage collection, but the C targets require you to
initialize Nim's internals, which is done calling a `NimMain` function.
Also, C code requires you to specify a forward declaration for functions or
the compiler will assume certain types for the return value and parameters
which will likely make your program crash at runtime.

The name `NimMain` can be influenced via the `--nimMainPrefix:prefix` switch.
Use `--nimMainPrefix:MyLib` and the function to call is named `MyLibNimMain`.

When compiling to static or dynamic libraries, they don't call destructors of global variables as normal Nim programs would do. A C API `NimDestroyGlobals` is provided to call these global destructors. It is influenced by the `--nimMainPrefix:prefix` switch, too.


### Nim invocation example from C

Create a ``fib.nim`` file with the following content:

  ```nim
  proc fib(a: cint): cint {.exportc.} =
    if a <= 2:
      result = 1
    else:
      result = fib(a - 1) + fib(a - 2)
  ```

Create a ``maths.c`` file with the following content:

  ```c
  #include <stdio.h>

  int fib(int a);
  void NimMain();

  int main(void)
  {
    NimMain();
    for (int f = 0; f < 10; f++)
      printf("Fib of %d is %d\n", f, fib(f));
    return 0;
  }
  ```

Now you can run the following Unix like commands to first generate C sources
from the Nim code, then link them into a static binary along your main C
program:

  ```cmd
  nim c --noMain --noLinking fib.nim
  gcc -o m -I$HOME/.cache/nim/fib_d -Ipath/to/nim/lib $HOME/.cache/nim/fib_d/*.c maths.c
  ```

The first command runs the Nim compiler with three special options to avoid
generating a `main()`:c: function in the generated files and to avoid linking the
object files into a final binary. All the generated files are placed into the ``nimcache``
directory. That's why the next command compiles the ``maths.c`` source plus
all the ``.c`` files from ``nimcache``. In addition to this path, you also
have to tell the C compiler where to find Nim's ``nimbase.h`` header file.

Instead of depending on the generation of the individual ``.c`` files you can
also ask the Nim compiler to generate a statically linked library:

  ```cmd
  nim c --app:staticLib fib.nim
  gcc -o m -Inimcache -Ipath/to/nim/lib maths.c libfib.nim.a
  ```

The Nim compiler will handle linking the source files generated in the
``nimcache`` directory into the ``libfib.nim.a`` static library, which you can
then link into your C program. Note that these commands are generic and will
vary for each system. For instance, on Linux systems you will likely need to
use `-ldl`:option: too to link in required dlopen functionality.


### Nim invocation example from JavaScript

Create a ``mhost.html`` file with the following content:

  ```
  <html><body>
  <script type="text/javascript" src="fib.js"></script>
  <script type="text/javascript">
  alert("Fib for 9 is " + fib(9));
  </script>
  </body></html>
  ```

Create a ``fib.nim`` file with the following content (or reuse the one
from the previous section):

  ```nim
  proc fib(a: cint): cint {.exportc.} =
    if a <= 2:
      result = 1
    else:
      result = fib(a - 1) + fib(a - 2)
  ```

Compile the Nim code to JavaScript with `nim js -o:fib.js fib.nim`:cmd: and
open ``mhost.html`` in a browser. If the browser supports javascript, you
should see an alert box displaying the text ``Fib for 9 is 34``. As mentioned
earlier, JavaScript doesn't require an initialization call to `NimMain` or
a similar function and you can call the exported Nim proc directly.


Nimcache naming logic
---------------------

The `nimcache`:idx: directory is generated during compilation and will hold
either temporary or final files depending on your backend target. The default
name for the directory depends on the used backend and on your OS but you can
use the `--nimcache`:option: [compiler switch](
nimc.html#compiler-usage-commandminusline-switches) to change it.


Memory management
=================

In the previous sections, the `NimMain()` function reared its head. Since
JavaScript already provides automatic memory management, you can freely pass
objects between the two languages without problems. In C and derivative languages
you need to be careful about what you do and how you share memory. The
previous examples only dealt with simple scalar values, but passing a Nim
string to C, or reading back a C string in Nim already requires you to be
aware of who controls what to avoid crashing.


Strings and C strings
---------------------

The manual mentions that [Nim strings are implicitly convertible to
cstrings](manual.html#types-cstring-type) which makes interaction usually
painless. Most C functions accepting a Nim string converted to a
`cstring` will likely not need to keep this string around and by the time
they return the string won't be needed anymore.

A similar thing happens with C code invoking Nim code which returns a
`cstring`. Consider the following proc:

  ```nim
  proc gimme(): cstring {.exportc.} =
    result = "Hey there C code! " & $rand(100)
  ```

Since Nim's reference counting mechanism is not aware of the C code, once the
`gimme` proc has finished it can reclaim the memory of the `cstring`.


Custom data types
-----------------

Just like strings, custom data types that are to be shared between Nim and
the backend will need careful consideration of who controls who. If you want
to hand a Nim reference to C code, you will need to use [GC_ref](
system.html#GC_ref,ref.T) to mark the reference as used, so it does not get
freed. And for the C backend you will need to expose the [GC_unref](
system.html#GC_unref,ref.T) proc to clean up this memory when it is not
required anymore.

Again, if you are wrapping a library which *mallocs* and *frees* data
structures, you need to expose the appropriate *free* function to Nim so
you can clean it up. And of course, once cleaned you should avoid accessing it
from Nim (or C for that matter). Typically C data structures have their own
`malloc_structure`:c: and `free_structure`:c: specific functions, so wrapping
these for the Nim side should be enough.
