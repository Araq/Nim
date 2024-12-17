=====================
Nim Tutorial (Part I)
=====================

:Author: Andreas Rumpf
:Version: |nimversion|

.. default-role:: code
.. include:: rstcommon.rst
.. contents::

Introduction
============

>  "Der Mensch ist doch ein Augentier -- Schöne Dinge wünsch' ich mir."


This document is a tutorial for the programming language *Nim*.

This tutorial assumes that you are familiar with basic programming concepts
like variables, types, or statements.

Here are several other resources for learning Nim:

* [Nim Basics tutorial](https://narimiran.github.io/nim-basics/) - a gentle 
  introduction of the concepts mentioned above
* [Learn Nim in 5 minutes](https://learnxinyminutes.com/docs/nim/) - quick,
  five-minute introduction to Nim
* [The Nim manual](manual.html) - many more examples of the advanced language features

All code examples in this tutorial, as well as the ones found in the rest of
Nim's documentation, follow the [Nim style guide](nep1.html).


The first program
=================

We start the tour with a modified "hello world" program:

  ```Nim  test = "nim c $1"
  # This is a comment
  echo "What's your name? "
  var name: string = readLine(stdin)
  echo "Hi, ", name, "!"
  ```


Save this code to the file "greetings.nim". Now compile and run it:
  ```cmd
  nim compile --run greetings.nim
  ```

With the ``--run`` [switch](nimc.html#compiler-usage-commandminusline-switches) Nim
executes the file automatically after compilation. You can give your program
command-line arguments by appending them after the filename:
  ```cmd
  nim compile --run greetings.nim arg1 arg2
  ```

Commonly used commands and switches have abbreviations, so you can also use:
  ```cmd
  nim c -r greetings.nim
  ```

This is a **debug version**.
To compile a release version use:
  ```cmd
  nim c -d:release greetings.nim
  ```

By default, the Nim compiler generates a large number of runtime checks
aiming for your debugging pleasure. With ``-d:release`` some checks are
[turned off and optimizations are turned on](
nimc.html#compiler-usage-compileminustime-symbols).

For benchmarking or production code, use the ``-d:release`` switch.
For comparing the performance with unsafe languages like C, use the ``-d:danger`` switch
in order to get meaningful, comparable results. Otherwise, Nim might be handicapped
by checks that are **not even available** for C.

Though it should be pretty obvious what the program does, I will explain the
syntax: statements which are not indented are executed when the program
starts. Indentation is Nim's way of grouping statements. Indentation is
done with spaces only, tabulators are not allowed.

String literals are enclosed in double-quotes. The `var` statement declares
a new variable named `name` of type `string` with the value that is
returned by the [readLine](syncio.html#readLine,File) procedure. Since the
compiler knows that [readLine](syncio.html#readLine,File) returns a string,
you can leave out the type in the declaration (this is called `local type
inference`:idx:). So this will work too:

  ```Nim  test = "nim c $1"
  var name = readLine(stdin)
  ```

Note that this is basically the only form of type inference that exists in
Nim: it is a good compromise between brevity and readability.

The "hello world" program contains several identifiers that are already known
to the compiler: `echo`, [readLine](syncio.html#readLine,File), etc.
These built-ins are declared in the [system](system.html) module which is implicitly
imported by any other module.


Lexical elements
================

Let us look at Nim's lexical elements in more detail: like other
programming languages Nim consists of (string) literals, identifiers,
keywords, comments, operators, and other punctuation marks.


String and character literals
-----------------------------

String literals are enclosed in double-quotes; character literals in single
quotes. Special characters are escaped with ``\``: ``\n`` means newline, ``\t``
means tabulator, etc. There are also *raw* string literals:

  ```Nim
  r"C:\program files\nim"
  ```

In raw literals, the backslash is not an escape character.

The third and last way to write string literals is *long-string literals*.
They are written with three quotes: `""" ... """`; they can span over
multiple lines and the ``\`` is not an escape character either. They are very
useful for embedding HTML code templates for example.


Comments
--------

Comments start anywhere outside a string or character literal with the
hash character `#`. Documentation comments start with `##`:

  ```nim  test = "nim c $1"
  # A comment.

  var myVariable: int ## a documentation comment
  ```


Documentation comments are tokens; they are only allowed at certain places in
the input file as they belong to the syntax tree! This feature enables simpler
documentation generators.

Multiline comments are started with `#[` and terminated with `]#`.  Multiline
comments can also be nested.

  ```nim  test = "nim c $1"
  #[
  You can have any Nim code text commented
  out inside this with no indentation restrictions.
        yes("May I ask a pointless question?")
    #[
       Note: these can be nested!!
    ]#
  ]#
  ```


Numbers
-------

Numerical literals are written as in most other languages. As a special twist,
underscores are allowed for better readability: `1_000_000` (one million).
A number that contains a dot (or 'e' or 'E') is a floating-point literal:
`1.0e9` (one billion). Hexadecimal literals are prefixed with `0x`,
binary literals with `0b` and octal literals with `0o`. A leading zero
alone does not produce an octal.


The var statement
=================
The var statement declares a new local or global variable:

  ```nim
  var x, y: int # declares x and y to have the type `int`
  ```

Indentation can be used after the `var` keyword to list a whole section of
variables:

  ```nim  test = "nim c $1"
  var
    x, y: int
    # a comment can occur here too
    a, b, c: string
  ```


Constants
=========

Constants are symbols which are bound to a value. The constant's value
cannot change. The compiler must be able to evaluate the expression in a
constant declaration at compile time:

  ```nim  test = "nim c $1"
  const x = "abc" # the constant x contains the string "abc"
  ```

Indentation can be used after the `const` keyword to list a whole section of
constants:

  ```nim  test = "nim c $1"
  const
    x = 1
    # a comment can occur here too
    y = 2
    z = y + 5 # computations are possible
  ```


The let statement
=================
The `let` statement works like the `var` statement but the declared
symbols are *single assignment* variables: After the initialization their
value cannot change:

  ```nim
  let x = "abc" # introduces a new variable `x` and binds a value to it
  x = "xyz"     # Illegal: assignment to `x`
  ```

The difference between `let` and `const` is: `let` introduces a variable
that can not be re-assigned, `const` means "enforce compile time evaluation
and put it into a data section":

  ```nim
  const input = readLine(stdin) # Error: constant expression expected
  ```

  ```nim  test = "nim c $1"
  let input = readLine(stdin)   # works
  ```


The assignment statement
========================

The assignment statement assigns a new value to a variable or more generally
to a storage location:

  ```nim
  var x = "abc" # introduces a new variable `x` and assigns a value to it
  x = "xyz"     # assigns a new value to `x`
  ```

`=` is the *assignment operator*. The assignment operator can be
overloaded. You can declare multiple variables with a single assignment
statement and all the variables will have the same value:

  ```nim  test = "nim c $1"
  var x, y = 3  # assigns 3 to the variables `x` and `y`
  echo "x ", x  # outputs "x 3"
  echo "y ", y  # outputs "y 3"
  x = 42        # changes `x` to 42 without changing `y`
  echo "x ", x  # outputs "x 42"
  echo "y ", y  # outputs "y 3"
  ```


Control flow statements
=======================

The greetings program consists of 3 statements that are executed sequentially.
Only the most primitive programs can get away with that: branching and looping
are needed too.


If statement
------------

The if statement is one way to branch the control flow:

  ```nim  test = "nim c $1"
  let name = readLine(stdin)
  if name == "":
    echo "Poor soul, you lost your name?"
  elif name == "name":
    echo "Very funny, your name is name."
  else:
    echo "Hi, ", name, "!"
  ```

There can be zero or more `elif` parts, and the `else` part is optional.
The keyword `elif` is short for `else if`, and is useful to avoid
excessive indentation. (The `""` is the empty string. It contains no
characters.)


Case statement
--------------

Another way to branch is provided by the case statement. A case statement allows
for multiple branches:

  ```nim  test = "nim c $1"
  let name = readLine(stdin)
  case name
  of "":
    echo "Poor soul, you lost your name?"
  of "name":
    echo "Very funny, your name is name."
  of "Dave", "Frank":
    echo "Cool name!"
  else:
    echo "Hi, ", name, "!"
  ```

As it can be seen, for an `of` branch a comma-separated list of values is also
allowed.

The case statement can deal with integers, other ordinal types, and strings.
(What an ordinal type is will be explained soon.)
For integers or other ordinal types value ranges are also possible:

  ```nim
  # this statement will be explained later:
  from std/strutils import parseInt

  echo "A number please: "
  let n = parseInt(readLine(stdin))
  case n
  of 0..2, 4..7: echo "The number is in the set: {0, 1, 2, 4, 5, 6, 7}"
  of 3, 8: echo "The number is 3 or 8"
  ```

However, the above code **does not compile**: the reason is that you have to cover
every value that `n` may contain, but the code only handles the values
`0..8`. Since it is not very practical to list every other possible integer
(though it is possible thanks to the range notation), we fix this by telling
the compiler that for every other value nothing should be done:

  ```nim
  ...
  case n
  of 0..2, 4..7: echo "The number is in the set: {0, 1, 2, 4, 5, 6, 7}"
  of 3, 8: echo "The number is 3 or 8"
  else: discard
  ```

The empty [discard statement] is a *do
nothing* statement. The compiler knows that a case statement with an else part
cannot fail and thus the error disappears. Note that it is impossible to cover
all possible string values: that is why string cases always need an `else`
branch.

In general, the case statement is used for subrange types or enumerations where
it is of great help that the compiler checks that you covered any possible
value.


While statement
---------------

The while statement is a simple looping construct:

  ```nim  test = "nim c $1"
  echo "What's your name? "
  var name = readLine(stdin)
  while name == "":
    echo "Please tell me your name: "
    name = readLine(stdin) # no `var`, because we do not declare a new variable here
  ```

The example uses a while loop to keep asking the users for their name, as long
as the user types in nothing (only presses RETURN).


For statement
-------------

The `for` statement is a construct to loop over any element an *iterator*
provides. The example uses the built-in [countup](
system.html#countup.i,T,T,Positive) iterator:

  ```nim  test = "nim c $1"
  echo "Counting to ten: "
  for i in countup(1, 10):
    echo i
  # --> Outputs 1 2 3 4 5 6 7 8 9 10 on different lines
  ```

The variable `i` is implicitly declared by the
`for` loop and has the type `int`, because that is what [countup](
system.html#countup.i,T,T,Positive) returns. `i` runs through the values
1, 2, .., 10. Each value is `echo`-ed. This code does the same:

  ```nim
  echo "Counting to 10: "
  var i = 1
  while i <= 10:
    echo i
    inc i # increment i by 1
  # --> Outputs 1 2 3 4 5 6 7 8 9 10 on different lines
  ```

Since counting up occurs so often in programs, Nim also has a [..](
system.html#...i,T,T) iterator that does the same:

  ```nim
  for i in 1 .. 10:
    ...
  ```

Counting down can be achieved as easily (but is less often needed):

  ```nim
  echo "Counting down from 10 to 1: "
  for i in countdown(10, 1):
    echo i
  # --> Outputs 10 9 8 7 6 5 4 3 2 1 on different lines
  ```

Zero-indexed counting has two shortcuts `..<` and `.. ^1`
([backward index operator](system.html#^.t%2Cint)) to simplify
counting to one less than the higher index:

  ```nim
  for i in 0 ..< 10:
    ...  # the same as 0 .. 9
  ```

or

  ```nim
  var s = "some string"
  for i in 0 ..< s.len:
    ...
  ```

or

  ```nim
  var s = "some string"
  for idx, c in s[0 .. ^1]:
    ... # ^1 is the last element, ^2 would be one before it, and so on
  ```

Other useful iterators for collections (like arrays and sequences) are
* `items` and `mitems`, which provides immutable and mutable elements respectively, and
* `pairs` and `mpairs` which provides the element and an index number (immutable and mutable respectively)

  ```nim  test = "nim c $1"
  for index, item in ["a","b"].pairs:
    echo item, " at index ", index
  # => a at index 0
  # => b at index 1
  ```

Scopes and the block statement
------------------------------

Control flow statements have a feature not covered yet: they open a
new scope. This means that in the following example, `x` is not accessible
outside the loop:

  ```nim  test = "nim c $1"  status = 1
  while false:
    var x = "hi"
  echo x # does not work
  ```

A while (for) statement introduces an implicit block. Identifiers
are only visible within the block they have been declared. The `block`
statement can be used to open a new block explicitly:

  ```nim  test = "nim c $1"  status = 1
  block myblock:
    var x = "hi"
  echo x # does not work either
  ```

The block's *label* (`myblock` in the example) is optional.


Break statement
---------------

A block can be left prematurely with a `break` statement. The break statement
can leave a `while`, `for`, or a `block` statement. It leaves the
innermost construct, unless a label of a block is given:

  ```nim  test = "nim c $1"
  block myblock:
    echo "entering block"
    while true:
      echo "looping"
      break # leaves the loop, but not the block
    echo "still in block"
  echo "outside the block"

  block myblock2:
    echo "entering block"
    while true:
      echo "looping"
      break myblock2 # leaves the block (and the loop)
    echo "still in block" # it won't be printed
  echo "outside the block"
  ```


Continue statement
------------------

Like in many other programming languages, a `continue` statement starts
the next iteration immediately:

  ```nim  test = "nim c $1"
  for i in 1 .. 5:
    if i <= 3: continue
    echo i # will only print 4 and 5
  ```


When statement
--------------

Example:

  ```nim  test = "nim c $1"
  when system.hostOS == "windows":
    echo "running on Windows!"
  elif system.hostOS == "linux":
    echo "running on Linux!"
  elif system.hostOS == "macosx":
    echo "running on Mac OS X!"
  else:
    echo "unknown operating system"
  ```

The `when` statement is almost identical to the `if` statement, but with these
differences:

* Each condition must be a constant expression since it is evaluated by the
  compiler.
* The statements within a branch do not open a new scope.
* The compiler checks the semantics and produces code *only* for the statements
  that belong to the first condition that evaluates to `true`.

The `when` statement is useful for writing platform-specific code, similar to
the `#ifdef`:c: construct in the C programming language.


Statements and indentation
==========================

Now that we covered the basic control flow statements, let's return to Nim
indentation rules.

In Nim, there is a distinction between *simple statements* and *complex
statements*. *Simple statements* cannot contain other statements:
Assignment, procedure calls, or the `return` statement are all simple
statements. *Complex statements* like `if`, `when`, `for`, `while` can
contain other statements. To avoid ambiguities, complex statements must always
be indented, but single simple statements do not:

  ```nim
  # no indentation needed for single-assignment statement:
  if x: x = false

  # indentation needed for nested if statement:
  if x:
    if y:
      y = false
    else:
      y = true

  # indentation needed, because two statements follow the condition:
  if x:
    x = false
    y = false
  ```


*Expressions* are parts of a statement that usually result in a value. The
condition in an if statement is an example of an expression. Expressions can
contain indentation at certain places for better readability:

  ```nim
  if thisIsaLongCondition() and
      thisIsAnotherLongCondition(1,
         2, 3, 4):
    x = true
  ```

As a rule of thumb, indentation within expressions is allowed after operators,
an open parenthesis and after commas.

With parenthesis and semicolons `(;)` you can use statements where only
an expression is allowed:

  ```nim  test = "nim c $1"
  # computes fac(4) at compile time:
  const fac4 = (var x = 1; for i in 1..4: x *= i; x)
  ```


Procedures
==========

To define new commands like [echo](system.html#echo,varargs[typed,])
and [readLine](syncio.html#readLine,File) in the examples, the concept of a
*procedure* is needed. You might be used to them being called *methods* or
*functions* in other languages, but Nim
[differentiates these concepts](tut1.html#procedures-funcs-and-methods). In
Nim, new procedures are defined with the `proc` keyword:

  ```nim  test = "nim c $1"
  proc yes(question: string): bool =
    echo question, " (y/n)"
    while true:
      case readLine(stdin)
      of "y", "Y", "yes", "Yes": return true
      of "n", "N", "no", "No": return false
      else: echo "Please be clear: yes or no"

  if yes("Should I delete all your important files?"):
    echo "I'm sorry Dave, I'm afraid I can't do that."
  else:
    echo "I think you know what the problem is just as well as I do."
  ```

This example shows a procedure named `yes` that asks the user a `question`
and returns true if they answered "yes" (or something similar) and returns
false if they answered "no" (or something similar). A `return` statement
leaves the procedure (and therefore the while loop) immediately. The
`(question: string): bool` syntax describes that the procedure expects a
parameter named `question` of type `string` and returns a value of type
`bool`. The `bool` type is built-in: the only valid values for `bool` are
`true` and `false`.
The conditions in if or while statements must be of type `bool`.

Some terminology: in the example `question` is called a (formal) *parameter*,
`"Should I..."` is called an *argument* that is passed to this parameter.


Result variable
---------------

A procedure that returns a value has an implicit `result` variable declared
that represents the return value. A `return` statement with no expression is
shorthand for `return result`. The `result` value is always returned
automatically at the end of a procedure if there is no `return` statement at
the exit.

  ```nim  test = "nim c $1"
  proc sumTillNegative(x: varargs[int]): int =
    for i in x:
      if i < 0:
        return
      result = result + i

  echo sumTillNegative() # echoes 0
  echo sumTillNegative(3, 4, 5) # echoes 12
  echo sumTillNegative(3, 4 , -1 , 6) # echoes 7
  ```

The `result` variable is already implicitly declared at the start of the
function, so declaring it again with 'var result', for example, would shadow it
with a normal variable of the same name. The result variable is also already
initialized with the type's default value. Note that referential data types will
be `nil` at the start of the procedure, and thus may require manual
initialization.

A procedure that does not have any `return` statement and does not use the
special `result` variable returns the value of its last expression. For example,
this procedure

  ```nim  test = "nim c $1"
  proc helloWorld(): string =
    "Hello, World!"
  ```

returns the string "Hello, World!".

Parameters
----------

Parameters are immutable in the procedure body. By default, their value cannot be
changed because this allows the compiler to implement parameter passing in the
most efficient way. If a mutable variable is needed inside the procedure, it has
to be declared with `var` in the procedure body. Shadowing the parameter name
is possible, and actually an idiom:

  ```nim  test = "nim c $1"
  proc printSeq(s: seq, nprinted: int = -1) =
    var nprinted = if nprinted == -1: s.len else: min(nprinted, s.len)
    for i in 0 ..< nprinted:
      echo s[i]
  ```

If the procedure needs to modify the argument for the
caller, a `var` parameter can be used:

  ```nim  test = "nim c $1"
  proc divmod(a, b: int; res, remainder: var int) =
    res = a div b        # integer division
    remainder = a mod b  # integer modulo operation

  var
    x, y: int
  divmod(8, 5, x, y) # modifies x and y
  echo x
  echo y
  ```

In the example, `res` and `remainder` are `var parameters`.
Var parameters can be modified by the procedure and the changes are
visible to the caller. Note that the above example would better make use of
a tuple as a return value instead of using var parameters.


Discard statement
-----------------

To call a procedure that returns a value just for its side effects and ignoring
its return value, a `discard` statement **must** be used. Nim does not
allow silently throwing away a return value:

  ```nim
  discard yes("May I ask a pointless question?")
  ```


The return value can be ignored implicitly if the called proc/iterator has
been declared with the `discardable` pragma:

  ```nim  test = "nim c $1"
  proc p(x, y: int): int {.discardable.} =
    return x + y

  p(3, 4) # now valid
  ```


Named arguments
---------------

Often a procedure has many parameters and it is not clear in which order the
parameters appear. This is especially true for procedures that construct a
complex data type. Therefore, the arguments to a procedure can be named, so
that it is clear which argument belongs to which parameter:

  ```nim
  proc createWindow(x, y, width, height: int; title: string;
                    show: bool): Window =
     ...

  var w = createWindow(show = true, title = "My Application",
                       x = 0, y = 0, height = 600, width = 800)
  ```

Now that we use named arguments to call `createWindow` the argument order
does not matter anymore. Mixing named arguments with ordered arguments is
also possible, but not very readable:

  ```nim
  var w = createWindow(0, 0, title = "My Application",
                       height = 600, width = 800, true)
  ```

The compiler checks that each parameter receives exactly one argument.


Default values
--------------

To make the `createWindow` proc easier to use it should provide `default
values`; these are values that are used as arguments if the caller does not
specify them:

  ```nim
  proc createWindow(x = 0, y = 0, width = 500, height = 700,
                    title = "unknown",
                    show = true): Window =
     ...

  var w = createWindow(title = "My Application", height = 600, width = 800)
  ```

Now the call to `createWindow` only needs to set the values that differ
from the defaults.

Note that type inference works for parameters with default values; there is
no need to write `title: string = "unknown"`, for example.


Overloaded procedures
---------------------

Nim provides the ability to overload procedures similar to C++:

  ```nim
  proc toString(x: int): string =
    result =
      if x < 0: "negative"
      elif x > 0: "positive"
      else: "zero"

  proc toString(x: bool): string =
    result =
      if x: "yep"
      else: "nope"

  assert toString(13) == "positive" # calls the toString(x: int) proc
  assert toString(true) == "yep"    # calls the toString(x: bool) proc
  ```

(Note that `toString` is usually the [$](dollars.html) operator in
Nim.) The compiler chooses the most appropriate proc for the `toString`
calls. How this overloading resolution algorithm works exactly is not
discussed here -- see the manual for details. Ambiguous calls are reported as errors.


Operators
---------

The Nim standard library makes heavy use of overloading - one reason for this is that
each operator like `+` is just an overloaded proc. The parser lets you
use operators in *infix notation* (`a + b`) or *prefix notation* (`+ a`).
An infix operator always receives two arguments, a prefix operator always one.
(Postfix operators are not possible, because this would be ambiguous: does
`a @ @ b` mean `(a) @ (@b)` or `(a@) @ (b)`? It always means
`(a) @ (@b)`, because there are no postfix operators in Nim.)

Apart from a few built-in keyword operators such as `and`, `or`, `not`,
operators always consist of these characters:
`+  -  *  \  /  <  >  =  @  $  ~  &  %  !  ?  ^  .  |`

User-defined operators are allowed. Nothing stops you from defining your own
`@!?+~` operator, but doing so may reduce readability.

The operator's precedence is determined by its first character. The details
can be [found in the manual](manual.html#syntax-precedence).

To define a new operator enclose the operator in backticks "`":

  ```nim
  proc `$` (x: myDataType): string = ...
  # now the $ operator also works with myDataType, overloading resolution
  # ensures that $ works for built-in types just like before
  ```

The "`" notation can also be used to call an operator just like any other
procedure:

  ```nim  test = "nim c $1"
  if `==`( `+`(3, 4), 7): echo "true"
  ```


Forward declarations
--------------------

Every variable, procedure, etc. needs to be declared before it can be used.
(The reason for this is that it is non-trivial to avoid this need in a
language that supports metaprogramming as extensively as Nim does.)
However, this cannot be done for mutually recursive procedures:

  ```nim
  # forward declaration:
  proc even(n: int): bool
  ```

  ```nim
  proc odd(n: int): bool =
    assert(n >= 0) # makes sure we don't run into negative recursion
    if n == 0: false
    else:
      n == 1 or even(n-1)

  proc even(n: int): bool =
    assert(n >= 0) # makes sure we don't run into negative recursion
    if n == 1: false
    else:
      n == 0 or odd(n-1)
  ```

Here `odd` depends on `even` and vice versa. Thus `even` needs to be
introduced to the compiler before it is completely defined. The syntax for
such a forward declaration is simple: just omit the `=` and the
procedure's body. The `assert` just adds border conditions, and will be
covered later in [Modules] section.

Later versions of the language will weaken the requirements for forward
declarations.

The example also shows that a proc's body can consist of a single expression
whose value is then returned implicitly.


Funcs and methods
-----------------

As mentioned in the introduction, Nim differentiates between procedures,
functions, and methods, defined by the `proc`, `func`, and `method` keywords
respectively. In some ways, Nim is a bit more pedantic in its definitions than
other languages.

Functions are closer to the concept of a pure mathematical
function, which might be familiar to you if you've ever done functional
programming. Essentially they are procedures with additional limitations set on
them: they can't access global state (except `const`) and can't produce
side-effects. The `func` keyword is basically an alias for `proc` tagged
with `{.noSideEffects.}`. Functions can still change their mutable arguments
however, which are those marked as `var`, along with any `ref` objects.

Unlike procedures, methods are dynamically dispatched. This sounds a bit
complicated, but it is a concept closely related to inheritance and object-oriented
programming. If you overload a procedure (two procedures with the same name but
of different types or with different sets of arguments are said to be overloaded), the procedure to use is determined
at compile-time. Methods, on the other hand, depend on objects that inherit from
the `RootObj`. This is something that is covered in much greater depth in
the [second part of the tutorial](tut2.html#object-oriented-programming-dynamic-dispatch).


Iterators
=========

Let's return to the simple counting example:

  ```nim  test = "nim c $1"
  echo "Counting to ten: "
  for i in countup(1, 10):
    echo i
  ```

Can a [countup](system.html#countup.i,T,T,Positive) proc be written that
supports this loop? Let's try:

  ```nim
  proc countup(a, b: int): int =
    var res = a
    while res <= b:
      return res
      inc(res)
  ```

However, this does not work. The problem is that the procedure should not
only `return`, but return and **continue** after an iteration has
finished. This *return and continue* is called a `yield` statement. Now
the only thing left to do is to replace the `proc` keyword by `iterator`
and here it is -- our first iterator:

  ```nim  test = "nim c $1"
  iterator countup(a, b: int): int =
    var res = a
    while res <= b:
      yield res
      inc(res)
  ```

Iterators look very similar to procedures, but there are several
important differences:

* Iterators can only be called from for loops.
* Iterators cannot contain a `return` statement (and procs cannot contain a
  `yield` statement).
* Iterators have no implicit `result` variable.
* Iterators do not support recursion.
* Iterators cannot be forward declared, because the compiler must be able to inline an iterator.
  (This restriction will be gone in a future version of the compiler.)

However, you can also use a closure iterator to get a different set of
restrictions. See [first-class iterators](
manual.html#iterators-and-the-for-statement-firstminusclass-iterators)
for details. Iterators can have the same name and parameters as a proc since
essentially they have their own namespaces. Therefore, it is common to
wrap iterators in procs of the same name which accumulate the result of the
iterator and return it as a sequence, like `split` from the [strutils module](
strutils.html).


Basic types
===========

This section deals with the basic built-in types and the operations
that are available for them in detail.

Booleans
--------

Nim's boolean type is called `bool` and consists of the two
pre-defined values `true` and `false`. Conditions in `while`,
`if`, `elif`, and `when` statements must be of type bool.

The operators `not, and, or, xor, <, <=, >, >=, !=, ==` are defined
for the bool type. The `and` and `or` operators perform short-circuit
evaluation. For example:

  ```nim
  while p != nil and p.name != "xyz":
    # p.name is not evaluated if p == nil
    p = p.next
  ```


Characters
----------

The *character type* is called `char`. Its size is always one byte, so
it cannot represent most UTF-8 characters, but it *can* represent one of the bytes
that makes up a multibyte UTF-8 character.
The reason for this is efficiency: for the overwhelming majority of use-cases,
the resulting programs will still handle UTF-8 properly as UTF-8 was especially
designed for this.
Character literals are enclosed in single quotes.

Chars can be compared with the `==`, `<`, `<=`, `>`, `>=` operators.
The `$` operator converts a `char` to a `string`. Chars cannot be mixed
with integers; to get the ordinal value of a `char` use the `ord` proc.
Converting from an integer to a `char` is done with the `chr` proc.


Strings
-------

String variables are **mutable**, so appending to a string
is possible, and quite efficient. Strings in Nim are both zero-terminated and have a
length field. A string's length can be retrieved with the builtin `len`
procedure; the length never counts the terminating zero. Accessing the
terminating zero is an error, it only exists so that a Nim string can be converted
to a `cstring` without doing a copy.

The assignment operator for strings copies the string. You can use the `&`
operator to concatenate strings and `add` to append to a string.

Strings are compared using their lexicographical order. All the comparison operators
are supported. By convention, all strings are UTF-8 encoded, but this is not
enforced. For example, when reading strings from binary files, they are merely
a sequence of bytes. The index operation `s[i]` means the i-th *char* of
`s`, not the i-th *unichar*.

A string variable is initialized with the empty string `""`.


Integers
--------

Nim has these integer types built-in:
`int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64`.

The default integer type is `int`. Integer literals can have a *type suffix*
to specify a non-default integer type:


  ```nim  test = "nim c $1"
  let
    x = 0     # x is of type `int`
    y = 0'i8  # y is of type `int8`
    z = 0'i32 # z is of type `int32`
    u = 0'u   # u is of type `uint`
  ```

Most often integers are used for counting objects that reside in memory, so
`int` has the same size as a pointer.

The common operators `+ - * div mod  <  <=  ==  !=  >  >=` are defined for
integers. The `and or xor not` operators are also defined for integers and
provide *bitwise* operations. Left bit shifting is done with the `shl`, right
shifting with the `shr` operator. Bit shifting operators always treat their
arguments as *unsigned*. For `arithmetic bit shifts`:idx: ordinary
multiplication or division can be used.

Unsigned operations all wrap around; they cannot lead to over- or under-flow
errors.

Lossless `Automatic type conversion`:idx: is performed in expressions where different
kinds of integer types are used. However, if the type conversion
would cause loss of information, the `RangeDefect`:idx: is raised (if the error
cannot be detected at compile time).


Floats
------

Nim has these floating-point types built-in: `float float32 float64`.

The default float type is `float`. In the current implementation,
`float` is always 64-bits.

Float literals can have a *type suffix* to specify a non-default float
type:

  ```nim  test = "nim c $1"
  var
    x = 0.0      # x is of type `float`
    y = 0.0'f32  # y is of type `float32`
    z = 0.0'f64  # z is of type `float64`
  ```

The common operators `+ - * /  <  <=  ==  !=  >  >=` are defined for
floats and follow the IEEE-754 standard.

Automatic type conversion in expressions with different kinds of floating-point types is performed: the smaller type is converted to the larger. Integer
types are **not** converted to floating-point types automatically, nor vice
versa. Use the [toInt](system.html#toInt,float) and
[toFloat](system.html#toFloat,int) procs for these conversions.


Type Conversion
---------------

Conversion between numerical types is performed by using the
type as a function:

  ```nim  test = "nim c $1"
  var
    x: int32 = 1.int32   # same as calling int32(1)
    y: int8  = int8('a') # 'a' == 97'i8
    z: float = 2.5       # int(2.5) rounds down to 2
    sum: int = int(x) + int(y) + int(z) # sum == 100
  ```


Internal type representation
============================

As mentioned earlier, the built-in [$](dollars.html) (stringify) operator
turns any basic type into a string, which you can then print to the console
using the `echo` proc. However, advanced types, and your own custom types,
won't work with the `$` operator until you define it for them.
Sometimes you just want to debug the current value of a complex type without
having to write its `$` operator.  You can use then the [repr](
system.html#repr,T) proc which works with any type and even complex data
graphs with cycles. The following example shows that even for basic types
there is a difference between the `$` and `repr` outputs:

  ```nim  test = "nim c $1"
  var
    myBool = true
    myCharacter = 'n'
    myString = "nim"
    myInteger = 42
    myFloat = 3.14
  echo myBool, ":", repr(myBool)
  # --> true:true
  echo myCharacter, ":", repr(myCharacter)
  # --> n:'n'
  echo myString, ":", repr(myString)
  # --> nim:0x10fa8c050"nim"
  echo myInteger, ":", repr(myInteger)
  # --> 42:42
  echo myFloat, ":", repr(myFloat)
  # --> 3.14:3.14
  ```


Advanced types
==============

In Nim new types can be defined within a `type` statement:

  ```nim  test = "nim c $1"
  type
    biggestInt = int64      # biggest integer type that is available
    biggestFloat = float64  # biggest float type that is available
  ```

Enumeration and object types may only be defined within a
`type` statement.


Enumerations
------------

A variable of an enumeration type can only be assigned one of the enumeration's specified values.
These values are a set of ordered symbols. Each symbol is mapped
to an integer value internally. The first symbol is represented
at runtime by 0, the second by 1, and so on. For example:

  ```nim  test = "nim c $1"
  type
    Direction = enum
      north, east, south, west

  var x = south     # `x` is of type `Direction`; its value is `south`
  echo x            # prints "south"

  if x == Direction.south:
    echo "It's south!"
  ```

All the comparison operators can be used with enumeration types.

An enumeration's symbol can be qualified to avoid ambiguities:
`Direction.south`.

The `$` operator can convert any enumeration value to its name, and the `ord`
proc can convert it to its underlying integer value.

For better interfacing to other programming languages, the symbols of enum
types can be assigned an explicit ordinal value. However, the ordinal values
must be in ascending order.


Ordinal types
-------------

Enumerations, integer types, `char` and `bool` (and
subranges) are called ordinal types. Ordinal types have quite
a few special operations:


=================     ========================================================
Operation             Comment
=================     ========================================================
`ord(x)`              returns the integer value that is used to
                      represent `x`'s value
`inc(x)`              increments `x` by one
`inc(x, n)`           increments `x` by `n`; `n` is an integer
`dec(x)`              decrements `x` by one
`dec(x, n)`           decrements `x` by `n`; `n` is an integer
`succ(x)`             returns the successor of `x`
`succ(x, n)`          returns the `n`'th successor of `x`
`pred(x)`             returns the predecessor of `x`
`pred(x, n)`          returns the `n`'th predecessor of `x`
=================     ========================================================


The [inc](system.html#inc,T,int), [dec](system.html#dec,T,int), [succ](
system.html#succ,T,int) and [pred](system.html#pred,T,int) operations can
fail by raising an `RangeDefect` or `OverflowDefect`. (If the code has been
compiled with the proper runtime checks turned on.)


Subranges
---------

A subrange type is a range of values from an integer or enumeration type
(the base type). Example:

  ```nim  test = "nim c $1"
  type
    MySubrange = range[0..5]
  ```


`MySubrange` is a subrange of `int` which can only hold the values 0
to 5. Assigning any other value to a variable of type `MySubrange` is a
compile-time or runtime error. Assignments from the base type to one of its
subrange types (and vice versa) are allowed.

The `system` module defines the important [Natural](system.html#Natural)
type as `range[0..high(int)]` ([high](system.html#high,typedesc[T]) returns
the maximal value). Other programming languages may suggest the use of unsigned
integers for natural numbers. This is often **unwise**: you don't want unsigned
arithmetic (which wraps around) just because the numbers cannot be negative.
Nim's `Natural` type helps to avoid this common programming error.


Sets
----

.. include:: sets_fragment.txt

Arrays
------

An array is a simple fixed-length container. Each element in
an array has the same type. The array's index type can be any ordinal type.

Arrays can be constructed using `[]`:

  ```nim  test = "nim c $1"
  type
    IntArray = array[0..5, int] # an array that is indexed with 0..5
  var
    x: IntArray
  x = [1, 2, 3, 4, 5, 6]
  for i in low(x) .. high(x):
    echo x[i]
  ```

The notation `x[i]` is used to access the i-th element of `x`.
Array access is always bounds checked (at compile-time or at runtime). These
checks can be disabled via pragmas or invoking the compiler with the
``--bound_checks:off`` command line switch.

Arrays are value types, like any other Nim type. The assignment operator
copies the whole array contents.

The built-in [len](system.html#len,TOpenArray) proc returns the array's
length. [low(a)](system.html#low,openArray[T]) returns the lowest valid index
for the array `a` and [high(a)](system.html#high,openArray[T]) the highest
valid index.

  ```nim  test = "nim c $1"
  type
    Direction = enum
      north, east, south, west
    BlinkLights = enum
      off, on, slowBlink, mediumBlink, fastBlink
    LevelSetting = array[north..west, BlinkLights]
  var
    level: LevelSetting
  level[north] = on
  level[south] = slowBlink
  level[east] = fastBlink
  echo level        # --> [on, fastBlink, slowBlink, off]
  echo low(level)   # --> north
  echo len(level)   # --> 4
  echo high(level)  # --> west
  ```

The syntax for nested arrays (multidimensional) in other languages is a matter
of appending more brackets because usually each dimension is restricted to the
same index type as the others. In Nim you can have different dimensions with
different index types, so the nesting syntax is slightly different. Building on
the previous example where a level is defined as an array of enums indexed by
yet another enum, we can add the following lines to add a light tower type
subdivided into height levels accessed through their integer index:

  ```nim
  type
    LightTower = array[1..10, LevelSetting]
  var
    tower: LightTower
  tower[1][north] = slowBlink
  tower[1][east] = mediumBlink
  echo len(tower)     # --> 10
  echo len(tower[1])  # --> 4
  echo tower          # --> [[slowBlink, mediumBlink, ...more output..
  # The following lines don't compile due to type mismatch errors
  #tower[north][east] = on
  #tower[0][1] = on
  ```

Note how the built-in `len` proc returns only the array's first dimension
length.  Another way of defining the `LightTower` to better illustrate its
nested nature would be to omit the previous definition of the `LevelSetting`
type and instead write it embedded directly as the type of the first dimension:

  ```nim
  type
    LightTower = array[1..10, array[north..west, BlinkLights]]
  ```

It is quite common to have arrays start at zero, so there's a shortcut syntax
to specify a range from zero to the specified index minus one:

  ```nim  test = "nim c $1"
  type
    IntArray = array[0..5, int] # an array that is indexed with 0..5
    QuickArray = array[6, int]  # an array that is indexed with 0..5
  var
    x: IntArray
    y: QuickArray
  x = [1, 2, 3, 4, 5, 6]
  y = x
  for i in low(x) .. high(x):
    echo x[i], y[i]
  ```


Sequences
---------

Sequences are similar to arrays but of dynamic length which may change
during runtime (like strings). Since sequences are resizable they are always
allocated on the heap and garbage collected.

Sequences are always indexed with an `int` starting at position 0.  The [len](
system.html#len,seq[T]), [low](system.html#low,openArray[T]) and [high](
system.html#high,openArray[T]) operations are available for sequences too.
The notation `x[i]` can be used to access the i-th element of `x`.

Sequences can be constructed by the array constructor `[]` in conjunction
with the array to sequence operator `@`. Another way to allocate space for
a sequence is to call the built-in [newSeq](system.html#newSeq) procedure.

A sequence may be passed to an openarray parameter.

Example:

  ```nim  test = "nim c $1"
  var
    x: seq[int] # a reference to a sequence of integers
  x = @[1, 2, 3, 4, 5, 6] # the @ turns the array into a sequence allocated on the heap
  ```

Sequence variables are initialized with `@[]`.

The `for` statement can be used with one or two variables when used with a
sequence. When you use the one variable form, the variable will hold the value
provided by the sequence. The `for` statement is looping over the results
from the [items()](iterators.html#items.i,seq[T]) iterator from the [system](
system.html) module.  But if you use the two-variable form, the first
variable will hold the index position and the second variable will hold the
value. Here the `for` statement is looping over the results from the
[pairs()](iterators.html#pairs.i,seq[T]) iterator from the [system](
system.html) module.  Examples:

  ```nim  test = "nim c $1"
  for value in @[3, 4, 5]:
    echo value
  # --> 3
  # --> 4
  # --> 5

  for i, value in @[3, 4, 5]:
    echo "index: ", $i, ", value:", $value
  # --> index: 0, value:3
  # --> index: 1, value:4
  # --> index: 2, value:5
  ```


Open arrays
-----------

**Note**: Openarrays can only be used for parameters.

Often fixed-size arrays turn out to be too inflexible; procedures should be
able to deal with arrays of different sizes. The `openarray`:idx: type allows
this. Openarrays are always indexed with an `int` starting at position 0.
The [len](system.html#len,TOpenArray), [low](system.html#low,openArray[T])
and [high](system.html#high,openArray[T]) operations are available for open
arrays too.  Any array with a compatible base type can be passed to an
openarray parameter, the index type does not matter.

  ```nim  test = "nim c $1"
  var
    fruits:   seq[string]       # reference to a sequence of strings that is initialized with '@[]'
    capitals: array[3, string]  # array of strings with a fixed size

  capitals = ["New York", "London", "Berlin"]   # array 'capitals' allows assignment of only three elements
  fruits.add("Banana")          # sequence 'fruits' is dynamically expandable during runtime
  fruits.add("Mango")

  proc openArraySize(oa: openArray[string]): int =
    oa.len

  assert openArraySize(fruits) == 2     # procedure accepts a sequence as parameter
  assert openArraySize(capitals) == 3   # but also an array type
  ```

The openarray type cannot be nested: multidimensional openarrays are not
supported because this is seldom needed and cannot be done efficiently.


Varargs
-------

A `varargs` parameter is like an openarray parameter. However, it is
also a means to implement passing a variable number of
arguments to a procedure. The compiler converts the list of arguments
to an array automatically:

  ```nim  test = "nim c $1"
  proc myWriteln(f: File, a: varargs[string]) =
    for s in items(a):
      write(f, s)
    write(f, "\n")

  myWriteln(stdout, "abc", "def", "xyz")
  # is transformed by the compiler to:
  myWriteln(stdout, ["abc", "def", "xyz"])
  ```

This transformation is only done if the varargs parameter is the
last parameter in the procedure header. It is also possible to perform
type conversions in this context:

  ```nim  test = "nim c $1"
  proc myWriteln(f: File, a: varargs[string, `$`]) =
    for s in items(a):
      write(f, s)
    write(f, "\n")

  myWriteln(stdout, 123, "abc", 4.0)
  # is transformed by the compiler to:
  myWriteln(stdout, [$123, $"abc", $4.0])
  ```

In this example [$](dollars.html) is applied to any argument that is passed
to the parameter `a`. Note that [$](dollars.html) applied to strings is a
nop.


Slices
------

Slices look similar to subranges types in syntax but are used in a different
context. A slice is just an object of type Slice which contains two bounds,
`a` and `b`. By itself a slice is not very useful, but other collection types
define operators which accept Slice objects to define ranges.

  ```nim  test = "nim c $1"
  var
    a = "Nim is a programming language"
    b = "Slices are useless."

  echo a[7 .. 12] # --> 'a prog'
  b[11 .. ^2] = "useful"
  echo b # --> 'Slices are useful.'
  ```

In the previous example slices are used to modify a part of a string. The
slice's bounds can hold any value supported by
their type, but it is the proc using the slice object which defines what values
are accepted.

To understand the different ways of specifying the indices of
strings, arrays, sequences, etc., it must be remembered that Nim uses
zero-based indices.

So the string `b` is of length 19, and two different ways of specifying the
indices are

  ```nim
  "Slices are useless."
   |          |     |
   0         11    17   using indices
  ^19        ^8    ^2   using ^ syntax
  ```

where `b[0 .. ^1]` is equivalent to `b[0 .. b.len-1]` and `b[0 ..< b.len]`, and it
can be seen that the `^1` provides a shorthand way of specifying the `b.len-1`. See
the [backwards index operator](system.html#^.t%2Cint).

In the above example, because the string ends in a period, to get the portion of the
string that is "useless" and replace it with "useful".

`b[11 .. ^2]` is the portion "useless", and `b[11 .. ^2] = "useful"` replaces the
"useless" portion with "useful", giving the result "Slices are useful."

Note 1: alternate ways of writing this are `b[^8 .. ^2] = "useful"` or
as `b[11 .. b.len-2] = "useful"` or as `b[11 ..< b.len-1] = "useful"`.

Note 2: As the `^` template returns a [distinct int](manual.html#types-distinct-type)
of type `BackwardsIndex`, we can have a `lastIndex` constant defined as `const lastIndex = ^1`,
and later used as `b[0 .. lastIndex]`.

Objects
-------

The default type to pack different values together in a single
structure with a name is the object type. An object is a value type,
which means that when an object is assigned to a new variable all its
components are copied as well.

Each object type `Foo` has a constructor `Foo(field: value, ...)`
where all of its fields can be initialized. Unspecified fields will
get their default value.

  ```nim
  type
    Person = object
      name: string
      age: int

  var person1 = Person(name: "Peter", age: 30)

  echo person1.name # "Peter"
  echo person1.age  # 30

  var person2 = person1 # copy of person 1

  person2.age += 14

  echo person1.age # 30
  echo person2.age # 44


  # the order may be changed
  let person3 = Person(age: 12, name: "Quentin")

  # not every member needs to be specified
  let person4 = Person(age: 3)
  # unspecified members will be initialized with their default
  # values. In this case it is the empty string.
  doAssert person4.name == ""
  ```


Object fields that should be visible from outside the defining module have to
be marked with `*`.

  ```nim  test = "nim c $1"
  type
    Person* = object # the type is visible from other modules
      name*: string  # the field of this type is visible from other modules
      age*: int
  ```

Tuples
------

Tuples are very much like what you have seen so far from objects. They
are value types where the assignment operator copies each component.
Unlike object types though, tuple types are structurally typed,
meaning different tuple-types are *equivalent* if they specify fields of
the same type and of the same name in the same order.

The constructor `()` can be used to construct tuples. The order of the
fields in the constructor must match the order in the tuple's
definition. But unlike objects, a name for the tuple type may not be
used here.


Like the object type the notation `t.field` is used to access a
tuple's field. Another notation that is not available for objects is
`t[i]` to access the `i`'th field. Here `i` must be a constant
integer.

  ```nim  test = "nim c $1"
  type
    # type representing a person:
    # A person consists of a name and an age.
    Person = tuple
      name: string
      age: int

    # Alternative syntax for an equivalent type.
    PersonX = tuple[name: string, age: int]

    # anonymous field syntax
    PersonY = (string, int)

  var
    person: Person
    personX: PersonX
    personY: PersonY

  person = (name: "Peter", age: 30)
  # Person and PersonX are equivalent
  personX = person

  # Create a tuple with anonymous fields:
  personY = ("Peter", 30)

  # A tuple with anonymous fields is compatible with a tuple that has
  # field names.
  person = personY
  personY = person

  # Usually used for short tuple initialization syntax
  person = ("Peter", 30)

  echo person.name # "Peter"
  echo person.age  # 30

  echo person[0] # "Peter"
  echo person[1] # 30

  # You don't need to declare tuples in a separate type section.
  var building: tuple[street: string, number: int]
  building = ("Rue del Percebe", 13)
  echo building.street

  # The following line does not compile, they are different tuples!
  #person = building
  # --> Error: type mismatch: got (tuple[street: string, number: int])
  #     but expected 'Person'
  ```

Even though you don't need to declare a type for a tuple to use it, tuples
created with different field names will be considered different objects despite
having the same field types.

Tuples can be *unpacked* during variable assignment. This can
be handy to assign directly the fields of the tuples to individually named
variables. An example of this is the [splitFile](os.html#splitFile,string)
proc from the [os module](os.html) which returns the directory, name, and
extension of a path at the same time. For tuple unpacking to work you must
use parentheses around the values you want to assign the unpacking to,
otherwise, you will be assigning the same value to all the individual
variables! For example:

  ```nim  test = "nim c $1"
  import std/os

  let
    path = "usr/local/nimc.html"
    (dir, name, ext) = splitFile(path)
    baddir, badname, badext = splitFile(path)
  echo dir      # outputs "usr/local"
  echo name     # outputs "nimc"
  echo ext      # outputs ".html"
  # All the following output the same line:
  # "(dir: usr/local, name: nimc, ext: .html)"
  echo baddir
  echo badname
  echo badext
  ```

Tuple unpacking is also supported in for-loops:

  ```nim  test = "nim c $1"
  let a = [(10, 'a'), (20, 'b'), (30, 'c')]

  for (x, c) in a:
    echo x
  # This will output: 10; 20; 30

  # Accessing the index is also possible:
  for i, (x, c) in a:
    echo i, c
  # This will output: 0a; 1b; 2c
  ```

Fields of tuples are always public, they don't need to be explicitly
marked to be exported, unlike for example fields in an object type.


Reference and pointer types
---------------------------

References (similar to pointers in other programming languages) are a
way to introduce many-to-one relationships. This means different references can
point to and modify the same location in memory.

Nim distinguishes between `traced`:idx: and `untraced`:idx: references.
Untraced references are also called *pointers*. Traced references point to
objects in a garbage-collected heap, untraced references point to
manually allocated objects or objects elsewhere in memory. Thus,
untraced references are *unsafe*. However, for certain low-level operations
(e.g. accessing the hardware), untraced references are necessary.

Traced references are declared with the **ref** keyword; untraced references
are declared with the **ptr** keyword.

The empty `[]` subscript notation can be used to *de-refer* a reference,
meaning to retrieve the item the reference points to. The `.` (access a
tuple/object field operator) and `[]` (array/string/sequence index operator)
operators perform implicit dereferencing operations for reference types:

  ```nim  test = "nim c $1"
  type
    Node = ref object
      le, ri: Node
      data: int

  var n = Node(data: 9)
  echo n.data
  # no need to write n[].data; in fact n[].data is highly discouraged!
  ```

To allocate a new traced object, the built-in procedure `new` can be used:

  ```nim
  var n: Node
  new(n)
  ```

To deal with untraced memory, the procedures `alloc`, `dealloc` and
`realloc` can be used. The [system](system.html)
module's documentation contains further details.

If a reference points to *nothing*, it has the value `nil`.


Procedural type
---------------

A procedural type is a (somewhat abstract) pointer to a procedure.
`nil` is an allowed value for a variable of a procedural type.
Nim uses procedural types to achieve `functional`:idx: programming
techniques.

Example:

  ```nim  test = "nim c $1"
  proc greet(name: string): string =
    "Hello, " & name & "!"

  proc bye(name: string): string =
    "Goodbye, " & name & "."

  proc communicate(greeting: proc (x: string): string, name: string) =
    echo greeting(name)

  communicate(greet, "John")
  communicate(bye, "Mary")
  ```

A subtle issue with procedural types is that the calling convention of the
procedure influences the type compatibility: procedural types are only compatible
if they have the same calling convention. The different calling conventions are
listed in the [manual](manual.html#types-procedural-type).

Distinct type
-------------

A Distinct type allows for the creation of a new type that "does not imply a
subtype relationship between it and its base type".
You must **explicitly** define all behavior for the distinct type.
To help with this, both the distinct type and its base type can cast from one
type to the other.
Examples are provided in the [manual](manual.html#types-distinct-type).

Modules
=======

Nim supports splitting a program into pieces with a *module* concept.
Each module is in its own file. Modules enable `information hiding`:idx: and
`separate compilation`:idx:. A module may gain access to the symbols of another
module by using the `import`:idx: statement. Only top-level symbols that are marked
with an asterisk (`*`) are exported:

  ```nim
  # Module A
  var
    x*, y: int

  proc `*` *(a, b: seq[int]): seq[int] =
    # allocate a new sequence:
    newSeq(result, len(a))
    # multiply two int sequences:
    for i in 0 ..< len(a): result[i] = a[i] * b[i]

  when isMainModule:
    # test the new `*` operator for sequences:
    assert(@[1, 2, 3] * @[1, 2, 3] == @[1, 4, 9])
  ```

The above module exports `x` and `*`, but not `y`.

A module's top-level statements are executed at the start of the program.
This can be used to initialize complex data structures for example.

Each module has a special magic constant `isMainModule` that is true if the
module is compiled as the main file. This is very useful to embed tests within
the module as shown by the above example.

A symbol of a module *can* be *qualified* with the `module.symbol` syntax. And if
a symbol is ambiguous, it *must* be qualified. A symbol is ambiguous
if it is defined in two (or more) different modules and both modules are
imported by a third one:

  ```nim
  # Module A
  var x*: string
  ```

  ```nim
  # Module B
  var x*: int
  ```

  ```nim
  # Module C
  import A, B
  write(stdout, x) # error: x is ambiguous
  write(stdout, A.x) # okay: qualifier used

  var x = 4
  write(stdout, x) # not ambiguous: uses the module C's x
  ```


But this rule does not apply to procedures or iterators. Here the overloading
rules apply:

  ```nim
  # Module A
  proc x*(a: int): string = $a
  ```

  ```nim
  # Module B
  proc x*(a: string): string = $a
  ```

  ```nim
  # Module C
  import A, B
  write(stdout, x(3))   # no error: A.x is called
  write(stdout, x(""))  # no error: B.x is called

  proc x*(a: int): string = discard
  write(stdout, x(3))   # ambiguous: which `x` is to call?
  ```


Excluding symbols
-----------------

The normal `import` statement will bring in all exported symbols.
These can be limited by naming symbols that should be excluded using
the `except` qualifier.

  ```nim
  import mymodule except y
  ```


From statement
--------------

We have already seen the simple `import` statement that just imports all
exported symbols. An alternative that only imports listed symbols is the
`from import` statement:

  ```nim
  from mymodule import x, y, z
  ```

The `from` statement can also force namespace qualification on
symbols, thereby making symbols available, but needing to be qualified
in order to be used.

  ```nim
  from mymodule import x, y, z

  x()           # use x without any qualification
  ```

  ```nim
  from mymodule import nil

  mymodule.x()  # must qualify x with the module name as prefix

  x()           # using x here without qualification is a compile error
  ```

Since module names are generally long to be descriptive, you can also
define a shorter alias to use when qualifying symbols.

  ```nim
  from mymodule as m import nil

  m.x()         # m is aliasing mymodule
  ```


Include statement
-----------------

The `include` statement does something fundamentally different than
importing a module: it merely includes the contents of a file. The `include`
statement is useful to split up a large module into several files:

  ```nim
  include fileA, fileB, fileC
  ```



Part 2
======

So, now that we are done with the basics, let's see what Nim offers apart
from a nice syntax for procedural programming: [Part II](tut2.html)


.. _strutils: strutils.html
.. _system: system.html
