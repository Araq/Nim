====================
Nim Standard Library
====================

:Author: Andreas Rumpf
:Version: |nimversion|

.. default-role:: code
.. include:: rstcommon.rst
.. contents::

Nim's library is divided into *pure libraries*, *impure libraries*, and *wrappers*.

Pure libraries do not depend on any external ``*.dll`` or ``lib*.so`` binary
while impure libraries do. A wrapper is an impure library that is a very
low-level interface to a C library.

Read [this document](apis.html) for a quick overview of the API design.


Nimble
======

Nim's standard library only covers the basics, check
out https://nimble.directory/ for a list of 3rd party packages.


Pure libraries
==============

Automatic imports
-----------------

* [system](system.html)
  Basic procs and operators that every program needs. It also provides IO
  facilities for reading and writing text and binary files. It is imported
  implicitly by the compiler. Do not import it directly. It relies on compiler
  magic to work.

Core
----

* [atomics](atomics.html)
  Types and operations for atomic operations and lockless algorithms.

* [bitops](bitops.html)
  Provides a series of low-level methods for bit manipulation.

* [compilesettings](compilesettings.html)
  Querying the compiler about diverse configuration settings from code.

* [cpuinfo](cpuinfo.html)
  Procs to determine the number of CPUs / cores.

* [effecttraits](effecttraits.html)
  Access to the inferred .raises effects
  for Nim's macro system.

* [endians](endians.html)
  Helpers that deal with different byte orders.

* [locks](locks.html)
  Locks and condition variables for Nim.

* [macrocache](macrocache.html)
  Provides an API for macros to collect compile-time information across modules.

* [macros](macros.html)
  Contains the AST API and documentation of Nim for writing macros.

* [rlocks](rlocks.html)
  Reentrant locks for Nim.

* [typeinfo](typeinfo.html)
  Provides (unsafe) access to Nim's run-time type information.

* [typetraits](typetraits.html)
  Compile-time reflection procs for working with types.

* [volatile](volatile.html)
  Code for generating volatile loads and stores,
  which are useful in embedded and systems programming.


Algorithms
----------

* [algorithm](algorithm.html)
  Some common generic algorithms like sort or binary search.

* [enumutils](enumutils.html)
  Additional functionality for the built-in `enum` type.

* [sequtils](sequtils.html)
  Operations for the built-in `seq` type
  which were inspired by functional programming languages.

* [setutils](setutils.html)
  Additional functionality for the built-in `set` type.


Collections
-----------

* [critbits](critbits.html)
  A *crit bit tree* which is an efficient
  container for a sorted set of strings, or a sorted mapping of strings.

* [deques](deques.html)
  Implementation of a double-ended queue.
  The underlying implementation uses a `seq`.

* [heapqueue](heapqueue.html)
  Implementation of a binary heap data structure that can be used as a priority queue.

* [intsets](intsets.html)
  Efficient implementation of a set of ints as a sparse bit set.

* [lists](lists.html)
  Nim linked list support. Contains singly and doubly linked lists and
  circular lists ("rings").

* [options](options.html)
  The option type encapsulates an optional value.

* [packedsets](packedsets.html)
  Efficient implementation of a set of ordinals as a sparse bit set.

* [ropes](ropes.html)
  A *rope* data type.
  Ropes can represent very long strings efficiently;
  in particular, concatenation is done in O(1) instead of O(n).

* [sets](sets.html)
  Nim hash set support.

* [strtabs](strtabs.html)
  The `strtabs` module implements an efficient hash table that is a mapping
  from strings to strings. Supports a case-sensitive, case-insensitive and
  style-insensitive modes.

* [tables](tables.html)
  Nim hash table support. Contains tables, ordered tables, and count tables.


String handling
---------------

* [cstrutils](cstrutils.html)
  Utilities for `cstring` handling.

* [editdistance](editdistance.html)
  An algorithm to compute the edit distance between two
  Unicode strings.

* [encodings](encodings.html)
  Converts between different character encodings. On UNIX, this uses
  the `iconv` library, on Windows the Windows API.

* [formatfloat](formatfloat.html)
  Formatting floats as strings.

* [objectdollar](objectdollar.html)
  A generic `$` operator to convert objects to strings.

* [punycode](punycode.html)
  Implements a representation of Unicode with the limited ASCII character subset.

* [strbasics](strbasics.html)
  Some high performance string operations.

* [strformat](strformat.html)
  Macro based standard string interpolation/formatting. Inspired by
  Python's f-strings.\
  **Note:** if you need templating, consider using Nim
  [Source Code Filters (SCF)](filters.html).

* [strmisc](strmisc.html)
  Uncommon string handling operations that do not
  fit with the commonly used operations in [strutils](strutils.html).

* [strscans](strscans.html)
  A `scanf` macro for convenient parsing of mini languages.

* [strutils](strutils.html)
  Common string handling operations like changing
  case of a string, splitting a string into substrings, searching for
  substrings, replacing substrings.

* [unicode](unicode.html)
  Support for handling the Unicode UTF-8 encoding.

* [unidecode](unidecode.html)
  It provides a single proc that does Unicode to ASCII transliterations.
  Based on Python's Unidecode module.

* [widestrs](widestrs.html)
  Nim support for C/C++'s wide strings.

* [wordwrap](wordwrap.html)
  An algorithm for word-wrapping Unicode strings.


Time handling
-------------

* [monotimes](monotimes.html)
  The `monotimes` module implements monotonic timestamps.

* [times](times.html)
  The `times` module contains support for working with time.


Generic Operating System Services
---------------------------------

* [appdirs](appdirs.html)
  Helpers for determining special directories used by apps.

* [cmdline](cmdline.html)
  System facilities for reading command line parameters.

* [dirs](dirs.html)
  Directory handling.

* [distros](distros.html)
  Basics for OS distribution ("distro") detection
  and the OS's native package manager.
  Its primary purpose is to produce output for Nimble packages,
  but it also contains the widely used **Distribution** enum
  that is useful for writing platform-specific code.
  See [packaging](packaging.html) for hints on distributing Nim using OS packages.

* [dynlib](dynlib.html)
  Accessing symbols from shared libraries.

* [envvars](envvars.html)
  Environment variable handling.

* [exitprocs](exitprocs.html)
  Adding hooks to program exit.

* [files](files.html)
  File handling.

* [memfiles](memfiles.html)
  Support for memory-mapped files (Posix's `mmap`)
  on the different operating systems.

* [os](os.html)
  Basic operating system facilities like retrieving environment variables,
  reading command line arguments, working with directories, running shell
  commands, etc.

* [oserrors](oserrors.html)
  OS error reporting.

* [osproc](osproc.html)
  Module for process communication beyond `os.execShellCmd`.

* [paths](paths.html)
  Path handling.

* [reservedmem](reservedmem.html)
  Utilities for reserving portions of the
  address space of a program without consuming physical memory.

* [streams](streams.html)
  A stream interface and two implementations thereof:
  the `FileStream` and the `StringStream` which implement the stream
  interface for Nim file objects (`File`) and strings. Other modules
  may provide other implementations for this standard stream interface.

* [symlinks](symlinks.html)
  Symlink handling.

* [syncio](syncio.html)
  Various synchronized I/O operations.

* [terminal](terminal.html)
  A module to control the terminal output (also called *console*).
  
* [tempfiles](tempfiles.html)
  Some utilities for generating temporary path names and
  creating temporary files and directories.


Math libraries
--------------

* [complex](complex.html)
  Complex numbers and relevant mathematical operations.

* [fenv](fenv.html)
  Floating-point environment. Handling of floating-point rounding and
  exceptions (overflow, zero-divide, etc.).

* [lenientops](lenientops.html)
  Binary operators for mixed integer/float expressions for convenience.

* [math](math.html)
  Mathematical operations like cosine, square root.

* [random](random.html)
  Fast and tiny random number generator.

* [rationals](rationals.html)
  Rational numbers and relevant mathematical operations.

* [stats](stats.html)
  Statistical analysis.

* [sysrand](sysrand.html)
  Cryptographically secure pseudorandom number generator.


Internet Protocols and Support
------------------------------

* [async](async.html)
  Exports `asyncmacro` and `asyncfutures` for native backends, and `asyncjs` on the JS backend. 

* [asyncdispatch](asyncdispatch.html)
  An asynchronous dispatcher for IO operations.

* [asyncfile](asyncfile.html)
  An asynchronous file reading and writing using `asyncdispatch`.

* [asyncftpclient](asyncftpclient.html)
  An asynchronous FTP client using the `asyncnet` module.

* [asynchttpserver](asynchttpserver.html)
  An asynchronous HTTP server using the `asyncnet` module.

* [asyncmacro](asyncmacro.html)
  `async` and `multisync` macros for `asyncdispatch`.

* [asyncnet](asyncnet.html)
  Asynchronous sockets based on the `asyncdispatch` module.

* [asyncstreams](asyncstreams.html)
  `FutureStream` - a future that acts as a queue.

* [cgi](cgi.html)
  Helpers for CGI applications.

* [cookies](cookies.html)
  Helper procs for parsing and generating cookies.

* [httpclient](httpclient.html)
  A simple HTTP client with support for both synchronous
  and asynchronous retrieval of web pages.

* [mimetypes](mimetypes.html)
  A mimetypes database.

* [nativesockets](nativesockets.html)
  A low-level sockets API.

* [net](net.html)
  A high-level sockets API.

* [selectors](selectors.html)
  A selector API with backends specific to each OS.
  Supported OS primitives: `epoll`, `kqueue`, `poll`, and `select` on Windows.

* [smtp](smtp.html)
  A simple SMTP client with support for both synchronous and asynchronous operation.

* [socketstreams](socketstreams.html)
  An implementation of the streams interface for sockets.

* [uri](uri.html)
  Functions for working with URIs and URLs.


Threading
---------

* [isolation](isolation.html)
  The `Isolated[T]` type for
  safe construction of isolated subgraphs that can be
  passed efficiently to different channels and threads.

* [tasks](tasks.html)
  Basic primitives for creating parallel programs.

* [threadpool](threadpool.html)
  Implements Nim's [spawn](manual_experimental.html#parallel-amp-spawn).

* [typedthreads](typedthreads.html)
  Basic Nim thread support.


Parsers
-------

* [htmlparser](htmlparser.html)
  HTML document parser that creates a XML tree representation.

* [json](json.html)
  High-performance JSON parser.

* [lexbase](lexbase.html)
  A low-level module that implements an extremely efficient buffering
  scheme for lexers and parsers. This is used by the diverse parsing modules.

* [parsecfg](parsecfg.html)
  The `parsecfg` module implements a high-performance configuration file
  parser. The configuration file's syntax is similar to the Windows ``.ini``
  format, but much more powerful, as it is not a line based parser. String
  literals, raw string literals, and triple quote string literals are supported
  as in the Nim programming language.

* [parsecsv](parsecsv.html)
  The `parsecsv` module implements a simple high-performance CSV parser.

* [parsejson](parsejson.html)
  A JSON parser. It is used and exported by the [json](json.html) module, but can also be used in its own right.

* [parseopt](parseopt.html)
  The `parseopt` module implements a command line option parser.

* [parsesql](parsesql.html)
  The `parsesql` module implements a simple high-performance SQL parser.

* [parseutils](parseutils.html)
  Helpers for parsing tokens, numbers, identifiers, etc.

* [parsexml](parsexml.html)
  The `parsexml` module implements a simple high performance XML/HTML parser.
  The only encoding that is supported is UTF-8. The parser has been designed
  to be somewhat error-correcting, so that even some "wild HTML" found on the
  web can be parsed with it.

* [pegs](pegs.html)
  Procedures and operators for handling PEGs.


Docutils
--------

* [packages/docutils/highlite](highlite.html)
  Source highlighter for programming or markup languages. Currently,
  only a few languages are supported, other languages may be added.
  The interface supports one language nested in another.

* [packages/docutils/rst](rst.html)
  A reStructuredText parser. A large subset
  is implemented. Some features of the markdown wiki syntax are also supported.

* [packages/docutils/rstast](rstast.html)
  An AST for the reStructuredText parser.

* [packages/docutils/rstgen](rstgen.html)
  A generator of HTML/Latex from reStructuredText.


XML Processing
--------------

* [xmltree](xmltree.html)
  A simple XML tree. More efficient and simpler than the DOM. It also
  contains a macro for XML/HTML code generation.

* [xmlparser](xmlparser.html)
  XML document parser that creates a XML tree representation.


Generators
----------

* [genasts](genasts.html)
  AST generation using captured variables for macros.

* [htmlgen](htmlgen.html)
  A simple XML and HTML code
  generator. Each commonly used HTML tag has a corresponding macro
  that generates a string with its HTML representation.


Hashing
-------

* [base64](base64.html)
  A Base64 encoder and decoder.

* [hashes](hashes.html)
  Efficient computations of hash values for diverse Nim types.

* [md5](md5.html)
  The MD5 checksum algorithm.

* [oids](oids.html)
  An OID is a global ID that consists of a timestamp,
  a unique counter, and a random value. This combination should suffice to
  produce a globally distributed unique ID.

* [sha1](sha1.html)
  The SHA-1 checksum algorithm.


Serialization
-------------

* [jsonutils](jsonutils.html)
  Hookable (de)serialization for arbitrary types
  using JSON.

* [marshal](marshal.html)
  Contains procs for serialization and deserialization of arbitrary Nim
  data structures.


Miscellaneous
-------------

* [assertions](assertions.html)
  Assertion handling.

* [browsers](browsers.html)
  Procs for opening URLs with the user's default
  browser.

* [colors](colors.html)
  Color handling.

* [coro](coro.html)
  Experimental coroutines in Nim.

* [decls](decls.html)
  Syntax sugar for some declarations.

* [enumerate](enumerate.html)
  `enumerate` syntactic sugar based on Nim's macro system.

* [importutils](importutils.html)
  Utilities related to import and symbol resolution.

* [logging](logging.html)
  A simple logger.

* [segfaults](segfaults.html)
  Turns access violations or segfaults into a `NilAccessDefect` exception.

* [sugar](sugar.html)
  Nice syntactic sugar based on Nim's macro system.

* [unittest](unittest.html)
  Implements a Unit testing DSL.

* [varints](varints.html)
  Decode variable-length integers that are compatible with SQLite.

* [with](with.html)
  The `with` macro for easy function chaining.

* [wrapnils](wrapnils.html)
  Allows evaluating expressions safely against nil dereferences.


Modules for the JavaScript backend
----------------------------------

* [asyncjs](asyncjs.html)
  Types and macros for writing asynchronous procedures in JavaScript.

* [dom](dom.html)
  Declaration of the Document Object Model for the JS backend.

* [jsbigints](jsbigints.html)
  Arbitrary precision integers.

* [jsconsole](jsconsole.html)
  Wrapper for the `console` object.

* [jscore](jscore.html)
  The wrapper of core JavaScript functions. For most purposes, you should be using
  the `math`, `json`, and `times` stdlib modules instead of this module.

* [jsfetch](jsfetch.html)
  Wrapper for `fetch`.

* [jsffi](jsffi.html)
  Types and macros for easier interaction with JavaScript.

* [jsre](jsre.html)
  Regular Expressions for the JavaScript target.


Impure libraries
================

Regular expressions
-------------------

* [re](re.html)
  Procedures and operators for handling regular
  expressions. The current implementation uses PCRE.

* [nre](nre.html)

  Many help functions for handling regular expressions.
  The current implementation uses PCRE.

Database support
----------------

* [db_mysql](db_mysql.html)
  A higher level MySQL database wrapper. The same interface is implemented
  for other databases too.

* [db_odbc](db_odbc.html)
  A higher level ODBC database wrapper. The same interface is implemented
  for other databases too.

* [db_postgres](db_postgres.html)
  A higher level PostgreSQL database wrapper. The same interface is implemented
  for other databases too.

* [db_sqlite](db_sqlite.html)
  A higher level SQLite database wrapper. The same interface is implemented
  for other databases too.


Generic Operating System Services
---------------------------------

* [rdstdin](rdstdin.html)
  Code for reading user input from stdin.


Wrappers
========

The generated HTML for some of these wrappers is so huge that it is
not contained in the distribution. You can then find them on the website.


Windows-specific
----------------

* [winlean](winlean.html)
  Wrapper for a small subset of the Win32 API.
* [registry](registry.html)
  Windows registry support.


UNIX specific
-------------

* [posix](posix.html)
  Wrapper for the POSIX standard.
* [posix_utils](posix_utils.html)
  Contains helpers for the POSIX standard or specialized for Linux and BSDs.


Regular expressions
-------------------

* [pcre](pcre.html)
  Wrapper for the PCRE library.


Database support
----------------

* [mysql](mysql.html)
  Wrapper for the mySQL API.
* [odbcsql](odbcsql.html)
  interface to the ODBC driver.
* [postgres](postgres.html)
  Wrapper for the PostgreSQL API.
* [sqlite3](sqlite3.html)
  Wrapper for the SQLite 3 API.


Network Programming and Internet Protocols
------------------------------------------

* [openssl](openssl.html)
  Wrapper for OpenSSL.
