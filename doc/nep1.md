============================
Standard Library Style Guide
============================

:Author: Clay Sweetser, Dominik Picheta
:Version: |nimversion|

.. default-role:: code
.. include:: rstcommon.rst
.. contents::


Introduction
============
Although Nim supports a variety of code and formatting styles, it is
nevertheless beneficial that certain community efforts, such as the standard
library, should follow a consistent set of style guidelines when suitable.
This enhancement proposal aims to list a series of guidelines that the standard
library should follow.

Note that there can be exceptions to these rules. Nim being as flexible as it
is, there will be parts of this style guide that don't make sense in certain
contexts. Furthermore, just as
[Python's style guide](https://legacy.python.org/dev/peps/pep-0008/) changes
over time, this style guide will too.

These rules will only be enforced for contributions to the Nim
codebase and official projects, such as the Nim compiler, the standard library,
and the various official tools such as C2Nim.

----------------
Style Guidelines
----------------

Spacing and Whitespace Conventions
-----------------------------------

- Lines should be no longer than 80 characters. Limiting the amount of
  information present on each line makes for more readable code - the reader
  has smaller chunks to process.

- Two spaces should be used for indentation of blocks; tabstops are not allowed
  (the compiler enforces this). Using spaces means that the appearance of code
  is more consistent across editors. Unlike spaces, tabstop width varies across
  editors, and not all editors provide means of changing this width.

- Although use of whitespace for stylistic reasons other than the ones endorsed
  by this guide are allowed, careful thought should be put into such practices.
  Not all editors support automatic alignment of code sections, and re-aligning
  long sections of code by hand can quickly become tedious.

    ```nim
    # This is bad, as the next time someone comes
    # to edit this code block, they
    # must re-align all the assignments again:
    type
      WordBool*    = int16
      CalType*     = int
      ... # 5 lines later
      CalId*       = int
      LongLong*    = int64
      LongLongPtr* = ptr LongLong
    ```


Naming Conventions
------------------

- Type identifiers should be in PascalCase. All other identifiers should be in
  camelCase with the exception of constants which **may** use PascalCase but
  are not required to.

    ```nim
    # Constants can start with either a lower case or upper case letter.
    const aConstant = 42
    const FooBar = 4.2

    var aVariable = "Meep" # Variables must start with a lowercase letter.

    # Types must start with an uppercase letter.
    type
      FooBar = object
    ```

  For constants coming from a C/C++ wrapper, ALL_UPPERCASE are allowed, but ugly.
  (Why shout CONSTANT? Constants do no harm, variables do!)

- When naming types that come in value, pointer, and reference varieties, use a
  regular name for the variety that is to be used the most, and add a "Obj",
  "Ref", or "Ptr" suffix for the other varieties. If there is no single variety
  that will be used the most, add the suffixes to the pointer variants only. The
  same applies to C/C++ wrappers.

    ```nim
    type
      Handle = object # Will be used most often
        fd: int64
      HandleRef = ref Handle # Will be used less often
    ```

- Exception and Error types should have the "Error" or "Defect" suffix.

    ```nim
    type
      ValueError = object of CatchableError
      AssertionDefect = object of Defect
      Foo = object of Exception # bad style, try to inherit CatchableError or Defect
    ```

- Unless marked with the `{.pure.}` pragma, members of enums should have an
  identifying prefix, such as an abbreviation of the enum's name.

    ```nim
    type
      PathComponent = enum
        pcDir
        pcLinkToDir
        pcFile
        pcLinkToFile
    ```

- Non-pure enum values should use camelCase whereas pure enum values should use
  PascalCase.

    ```nim
    type
      PathComponent {.pure.} = enum
        Dir
        LinkToDir
        File
        LinkToFile
    ```

- In the age of HTTP, HTML, FTP, TCP, IP, UTF, WWW it is foolish to pretend
  these are somewhat special words requiring all uppercase. Instead treat them
  as what they are: Real words. So it's `parseUrl` rather than
  `parseURL`, `checkHttpHeader` instead of `checkHTTPHeader` etc.

- Operations like `mitems` or `mpairs` (or the now deprecated `mget`)
  that allow a *mutating view* into some data structure should start with an `m`.
- When both in-place mutation and 'returns transformed copy' are available the latter
  is a past participle of the former:

  - reverse and reversed in algorithm
  - sort and sorted
  - rotate and rotated

- When the 'returns transformed copy' version already exists like `strutils.replace`
  an in-place version should get an ``-In`` suffix (`replaceIn` for this example).


- Use `subjectVerb`, not `verbSubject`, e.g.: `fileExists`, not `existsFile`.

The stdlib API is designed to be **easy to use** and consistent. Ease of use is
measured by the number of calls to achieve a concrete high level action. The
ultimate goal is that the programmer can *guess* a name.

The library uses a simple naming scheme that makes use of common abbreviations
to keep the names short but meaningful.


===================     ============   ======================================
English word            To use         Notes
===================     ============   ======================================
initialize              initFoo        initializes a value type `Foo`
new                     newFoo         initializes a reference type `Foo`
                                       via `new` or a value type `Foo`
                                       with reference semantics.
this or self            self           for method like procs, e.g.:
                                       `proc fun(self: Foo, a: int)`
                                       rationale: `self` is more unique in English
                                       than `this`, and `foo` would not be DRY.
find                    find           should return the position where
                                       something was found; for a bool result
                                       use `contains`
contains                contains       often short for `find() >= 0`
append                  add            use `add` instead of `append`
compare                 cmp            should return an int with the
                                       `< 0` `== 0` or `> 0` semantics;
                                       for a bool result use `sameXYZ`
put                     put, `[]=`     consider overloading `[]=` for put
get                     get, `[]`      consider overloading `[]` for get;
                                       consider to not use `get` as a
                                       prefix: `len` instead of `getLen`
length                  len            also used for *number of elements*
size                    size, len      size should refer to a byte size
capacity                cap
memory                  mem            implies a low-level operation
items                   items          default iterator over a collection
pairs                   pairs          iterator over (key, value) pairs
delete                  delete, del    del is supposed to be faster than
                                       delete, because it does not keep
                                       the order; delete keeps the order
remove                  delete, del    inconsistent right now
include                 incl
exclude                 excl
command                 cmd
execute                 exec
environment             env
variable                var
value                   value, val     val is preferred, inconsistent right
                                       now
executable              exe
directory               dir
path                    path           path is the string "/usr/bin" (for
                                       example), dir is the content of
                                       "/usr/bin"; inconsistent right now
extension               ext
separator               sep
column                  col, column    col is preferred, inconsistent right
                                       now
application             app
configuration           cfg
message                 msg
argument                arg
object                  obj
parameter               param
operator                opr
procedure               proc
function                func
coordinate              coord
rectangle               rect
point                   point
symbol                  sym
literal                 lit
string                  str
identifier              ident
indentation             indent
===================     ============   ======================================


Coding Conventions
------------------

- The `return` statement should ideally be used when its control-flow properties
  are required. Use a procedure's implicit `result` variable whenever possible.
  This improves readability.

    ```nim
    proc repeat(text: string, x: int): string =
      result = ""

      for i in 0..x:
        result.add($i)
    ```

- Use a proc when possible, only using the more powerful facilities of macros,
  templates, iterators, and converters when necessary.

- Use the `let` statement (not the `var` statement) when declaring variables that
  do not change within their scope. Using the `let` statement ensures that
  variables remain immutable, and gives those who read the code a better idea
  of the code's purpose.


Conventions for multi-line statements and expressions
-----------------------------------------------------

- Tuples which are longer than one line should indent their parameters.

    ```nim
    type
      LongTupleA = tuple[
        wordyTupleMemberOne: int, wordyTupleMemberTwo: string,
        wordyTupleMemberThree: float]
    ```

- Similarly, any procedure and procedure type declarations that are longer
  than one line should do the same thing. Double indent may be used to
  distinguish them from the body that follows - this applies to all constructs
  with a body (if, while, etc).

    ```nim
    type
      EventCallback = proc(
        timeReceived: Time, errorCode: int, event: Event,
        output: var string)

    proc lotsOfArguments(
        argOne: string, argTwo: int, argThree: float,
        argFour: proc(), argFive: bool, argSix: int
    ): GenericType[int, string] {.heyLookALongPragma.} =
      discard
    ```

- Multi-line procedure calls should continue indented (like multi-line procedure
  declarations).

    ```nim
    startProcess(
      nimExecutable, currentDirectory, compilerArguments
      environment, processOptions)
    ```

Previous versions of this guide advocated vertical alignment along the opening
brace / parenthesis - both styles are permissible with a preference for the
current style in new code.

Miscellaneous
-------------

- Use `a..b` instead of `a .. b`, except when `b` contains an operator, for example `a .. -3`.
  Likewise with `a..<b`, `a..^b` and other operators starting with `..`.

- Use `std` prefix for standard library modules, namely use `std/os` for single module and
  use `std/[os, sysrand, posix]` for multiple modules.

- Prefer multiline triple quote literals to start with a newline; it's semantically identical
  (it's a feature of triple quote literals) but clearer because it aligns with the next line:

  use this:

    ```nim
    let a = """
    foo
    bar
    """
    ```

  instead of:

    ```nim
    let a = """foo
    bar
    """
    ```

- A getter API for a private field `foo` should preferably be named `foo`, not `getFoo`.
  A getter-like API should preferably be named `getFoo`, not `foo` if:
    * the API has side effects
    * or the cost is not `O(1)`
  For in between cases, there is no clear guideline.

- Likewise with a setter API, replacing `foo` with `foo=` and `getFoo` with `setFoo`
  in the above text.
