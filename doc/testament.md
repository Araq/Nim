===========
 Testament
===========

.. default-role:: code
.. include:: rstcommon.rst
.. contents::

Testament is an advanced automatic unittests runner for Nim tests, is used for the development of Nim itself,
offers process isolation for your tests, it can generate statistics about test cases,
supports multiple targets (C, C++, ObjectiveC, JavaScript, etc.),
simulated [Dry-Runs](https://en.wikipedia.org/wiki/Dry_run_(testing)),
has logging, can generate HTML reports, skip tests from a file, and more,
so can be useful to run your tests, even the most complex ones.


Test files location
===================

By default, Testament looks for test files on ``"./tests/category/*.nim"``.
You can overwrite this pattern glob using `pattern <glob>`:option:.
The default working directory path can be changed using
`--directory:"folder/subfolder/"`:option:.

Testament uses the `nim`:cmd: compiler on `PATH`.
You can change that using `--nim:"folder/subfolder/nim"`:option:.
Running JavaScript tests with `--targets:"js"`:option: requires
a working NodeJS on `PATH`.

Commands
========

==========================  ==========================
p|pat|pattern <glob>        run all the tests matching the given pattern
all                         run all tests inside of category folders
c|cat|category <category>   run all the tests of a certain category
r|run <test>                run single test file
html                        generate testresults.html from the database
==========================  ==========================


Options
=======

--print                    print results to the console
--verbose                  print commands (compiling and running tests)
--simulate                 see what tests would be run but don't run them (for debugging)
--failing                  only show failing/ignored tests
--targets:"c cpp js objc"  run tests for specified targets (default: c)
--nim:path                 use a particular nim executable (default: $PATH/nim)
--directory:dir            Change to directory dir before reading the tests or doing anything else.
--colors:on|off            Turn messages coloring on|off.
--backendLogging:on|off    Disable or enable backend logging. By default turned on.
--megatest:on|off          Enable or disable megatest. Default is on.
--valgrind:on|off          Enable or disable valgrind support. Default is on.
--skipFrom:file            Read tests to skip from `file` - one test per line, # comments ignored


Running a single test
=====================

This is a minimal example to understand the basics,
not very useful for production, but easy to understand:

  ```console
  $ mkdir -p tests/category
  $ echo "assert 42 == 42" > tests/category/test0.nim
  $ testament run tests/category/test0.nim
  PASS: tests/category/test0.nim c                           ( 0.2 sec)
  $ testament r tests/category/test0
  PASS: tests/category/test0.nim C                           ( 0.2 sec)
  ```


Running all tests from a directory
==================================

 This will run all tests in the top level tests/ directory. NOTE: these
 tests are skipped by `testament all`.
 
  ```console
  $ testament pattern "tests/*.nim"
  ```

To search for tests deeper in a directory, use

  ```console
  $ testament pattern "tests/**/*.nim"    # one level deeper
  $ testament pattern "tests/**/**/*.nim" # two levels deeper
  ```

HTML Reports
============

Generate HTML Reports ``testresults.html`` from unittests,
you have to run at least 1 test *before* generating a report:

  ```console
  $ testament html
  ```


Writing Unit tests
==================

Example "template" **to edit** and write a Testament unittest:

  ```nim
  discard """

    # What actions to expect completion on.
    # Options:
    #   "compile": expect successful compilation
    #   "run": expect successful compilation and execution
    #   "reject": expect failed compilation. The "reject" action can catch
    #             {.error.} pragmas but not {.fatal.} pragmas because
    #             {.error.} calls are expected to originate from the test-file, 
    #             and can explicitly be specified using the "file", "line" and
    #             "column" options.
    #             {.fatal.} pragmas guarantee that compilation will be aborted.
    action: "run"
    
    # For testing failed compilations you can specify the expected origin of the 
    # compilation error.
    # With the "file", "line" and "column" options you can define the file, 
    # line and column that a compilation-error should have originated from.
    # Use only with action: "reject" as it expects a failed compilation.
    # Requires errormsg or msg to be defined.
    # file: ""
    # line: ""
    # column: ""

    # The exit code that the test is expected to return. Typically, the default
    # value of 0 is fine. Note that if the test will be run by valgrind, then
    # the test will exit with either a code of 0 on success or 1 on failure.
    exitcode: 0

    # Provide an `output` string to assert that the test prints to standard out
    # exactly the expected string. Provide an `outputsub` string to assert that
    # the string given here is a substring of the standard out output of the
    # test (the output includes both the compiler and test execution output).
    output: ""
    outputsub: ""

    # Whether to sort the compiler output lines before comparing them to the 
    # expected output.
    sortoutput: true

    # Provide a `nimout` string to assert that the compiler during compilation
    # prints the defined lines to the standard out.
    # The lines must match in order, but there may be more lines that appear 
    # before, after, or in between them. 
    nimout: '''
  a very long,
  multi-line
  string'''

    # This is the Standard Input the test should take, if any.
    input: ""

    # Error message the test should print, if any.
    errormsg: ""

    # Can be run in batch mode, or not.
    batchable: true

    # Can be run Joined with other tests to run all together, or not.
    joinable: true

    # On Linux 64-bit machines, whether to use Valgrind to check for bad memory
    # accesses or memory leaks. On other architectures, the test will be run
    # as-is, without Valgrind.
    # Options:
    #   true: run the test with Valgrind
    #   false: run the without Valgrind
    #   "leaks": run the test with Valgrind, but do not check for memory leaks
    valgrind: false   # Can use Valgrind to check for memory leaks, or not (Linux 64Bit only).

    # Checks that the specified piece of C-code is within the generated C-code.
    ccodecheck: "'Assert error message'"

    # Command the test should use to run. If left out or an empty string is
    # provided, the command is taken to be:
    # "nim $target --hints:on -d:testing --nimblePath:build/deps/pkgs $options $file"
    # Subject to variable interpolation.
    cmd: "nim c -r $file"

    # Maximum generated temporary intermediate code file size for the test.
    maxcodesize: 666

    # Timeout seconds to run the test. Fractional values are supported.
    timeout: 1.5

    # Targets to run the test into (c, cpp, objc, js). Defaults to c.
    targets: "c js"

    # flags with which to run the test, delimited by `;`
    matrix: "; -d:release; -d:caseFoo -d:release"

    # Conditions that will skip this test. Use of multiple "disabled" clauses
    # is permitted.
    disabled: "bsd"   # Can disable OSes...
    disabled: "win"
    disabled: "32bit" # ...or architectures
    disabled: "i386"
    disabled: "azure" # ...or pipeline runners
    disabled: true    # ...or can disable the test entirely

  """
  assert true
  assert 42 == 42, "Assert error message"
  ```


* As you can see the "Spec" is just a `discard """ """`.
* Spec has sane defaults, so you don't need to provide them all, any simple assert will work just fine.
* This is not the full spec of Testament, check [the Testament Spec on GitHub,
  see parseSpec()](https://github.com/nim-lang/Nim/blob/devel/testament/specs.nim#L317).
* Nim itself uses Testament, so [there are plenty of test examples](
  https://github.com/nim-lang/Nim/tree/devel/tests).
* Has some built-in CI compatibility, like Azure Pipelines, etc.


Inline hints, warnings and errors (notes)
-----------------------------------------

Testing the line, column, kind and message of hints, warnings and errors can
be written inline like so:
  ```nim
  {.warning: "warning!!"} #[tt.Warning
           ^ warning!! [User] ]#
  ```

The opening `#[tt.` marks the message line.
The `^` marks the message column.

Inline messages can be combined with `nimout` when `nimoutFull` is false (default).
This allows testing for expected messages from other modules:

  ```nim
  discard """
    nimout: "config.nims(1, 1) Hint: some hint message [User]"
  """
  {.warning: "warning!!"} #[tt.Warning
           ^ warning!! [User] ]#
  ```

Multiple messages for a line can be checked by delimiting messages with ';':

  ```nim
  discard """
    matrix: "--errorMax:0 --styleCheck:error"
  """

  proc generic_proc*[T](a_a: int) = #[tt.Error
       ^ 'generic_proc' should be: 'genericProc'; tt.Error
                        ^ 'a_a' should be: 'aA' ]#
    discard
  ```

Use `--errorMax:0` in `matrix`, or `cmd: "nim check $file"` when testing
for multiple 'Error' messages.

Output message variable interpolation
-------------------------------------

`errormsg`, `nimout`, and inline messages are subject to these variable interpolations:

* `${/}` - platform's directory separator
* `$file` - the filename (without directory) of the test

All other `$` characters need escaped as `$$`.

Cmd variable interpolation
--------------------------

The `cmd` option is subject to these variable interpolations:

* `$target` - the compilation target, e.g. `c`.
* `$options` - the options for the compiler.
* `$file` - the file path of the test.
* `$filedir` - the directory of the test file.

.. code-block:: nim

  discard """
    cmd: "nim $target --nimblePath:./nimbleDir/simplePkgs $options $file"
  """

All other `$` characters need escaped as `$$`.


Unit test Examples
==================

Expected to fail:

  ```nim
  discard """
    errormsg: "undeclared identifier: 'not_defined'"
  """
  assert not_defined == "not_defined", "not_defined is not defined"
  ```

Expected to fail with error thrown from another file:
```nim
# test.nim
discard """
  action: "reject"
  errorMsg: "I break"
  file: "breakPragma.nim"
"""
import ./breakPragma

proc x() {.justDo.} = discard

# breakPragma.nim
import std/macros

macro justDo*(procDef: typed): untyped =
  error("I break")
  return procDef
```

Expecting generated C to contain a given piece of code:

  ```nim
  discard """
    # Checks that the string "Assert error message" is in the generated 
    # C code.
    ccodecheck: "'Assert error message'"
  """
  assert 42 == 42, "Assert error message"
  ```


Non-Zero exit code:

  ```nim
  discard """
    exitcode: 1
  """
  quit "Non-Zero exit code", 1
  ```

Standard output checking:

  ```nim
  discard """

    output: '''
  0
  1
  2
  3
  4
  5
  '''

  """
  for i in 0..5: echo i
  ```

JavaScript tests:

  ```nim
  discard """
    targets: "js"
  """
  when defined(js):
    import std/jsconsole
    console.log("My Frontend Project")
  ```

Compile-time tests:

  ```nim
  discard """
    action: "compile"
  """
  static: assert 9 == 9, "Compile time assert"
  ```

Tests without Spec:

  ```nim
  assert 1 == 1
  ```


See also:
* [Unittest](unittest.html)
