=========================
Nim Experimental Features
=========================

:Authors: Andreas Rumpf
:Version: |nimversion|

.. default-role:: code
.. include:: rstcommon.rst
.. contents::


About this document
===================

This document describes features of Nim that are to be considered experimental.
Some of these are not covered by the `.experimental` pragma or
`--experimental`:option: switch because they are already behind a special syntax and
one may want to use Nim libraries using these features without using them
oneself.

.. note:: Unless otherwise indicated, these features are not to be removed,
  but refined and overhauled.


Void type
=========

The `void` type denotes the absence of any value, i.e. it is the type that contains no values. Consequently, no value can be provided for parameters of
type `void`, and no value can be returned from a function with return type `void`:

  ```nim
  proc nothing(x, y: void): void =
    echo "ha"

  nothing() # writes "ha" to stdout
  ```

The `void` type is particularly useful for generic code:

  ```nim
  proc callProc[T](p: proc (x: T), x: T) =
    when T is void:
      p()
    else:
      p(x)

  proc intProc(x: int) = discard
  proc emptyProc() = discard

  callProc[int](intProc, 12)
  callProc[void](emptyProc)
  ```

However, a `void` type cannot be inferred in generic code:

  ```nim
  callProc(emptyProc)
  # Error: type mismatch: got (proc ())
  # but expected one of:
  # callProc(p: proc (T), x: T)
  ```

The `void` type is only valid for parameters and return types; other symbols
cannot have the type `void`.

Generic `define` pragma
=======================

Aside the [typed define pragmas for constants](manual.html#implementation-specific-pragmas-compileminustime-define-pragmas),
there is a generic `{.define.}` pragma that interprets the value of the define
based on the type of the constant value.

  ```nim
  const foo {.define: "package.foo".} = 123
  const bar {.define: "package.bar".} = false
  ```

  ```cmd
  nim c -d:package.foo=456 -d:package.bar foobar.nim
  ```

The following types are supported:

* `string` and `cstring`
* Signed and unsigned integer types
* `bool`
* Enums

Top-down type inference
=======================

In expressions such as:

```nim
let a: T = ex
```

Normally, the compiler type checks the expression `ex` by itself, then
attempts to statically convert the type-checked expression to the given type
`T` as much as it can, while making sure it matches the type. The extent of
this process is limited however due to the expression usually having
an assumed type that might clash with the given type.

With top-down type inference, the expression is type checked with the
extra knowledge that it is supposed to be of type `T`. For example,
the following code is does not compile with the former method, but
compiles with top-down type inference:

```nim
let foo: (float, uint8, cstring) = (1, 2, "abc")
```

The tuple expression has an expected type of `(float, uint8, cstring)`.
Since it is a tuple literal, we can use this information to assume the types
of its elements. The expected types for the expressions `1`, `2` and `"abc"`
are respectively `float`, `uint8`, and `cstring`; and these expressions can be
statically converted to these types.

Without this information, the type of the tuple expression would have been
assumed to be `(int, int, string)`. Thus the type of the tuple expression
would not match the type of the variable, and an error would be given.

The extent of this varies, but there are some notable special cases.


Inferred generic parameters
---------------------------

In expressions making use of generic procs or templates, the expected
(unbound) types are often able to be inferred based on context.
This feature has to be enabled via `{.experimental: "inferGenericTypes".}`

  ```nim  test = "nim c $1"
  {.experimental: "inferGenericTypes".}

  import std/options

  var x = newSeq[int](1)
  # Do some work on 'x'...

  # Works!
  # 'x' is 'seq[int]' so 'newSeq[int]' is implied
  x = newSeq(10)

  # Works!
  # 'T' of 'none' is bound to the 'T' of 'noneProducer', passing it along.
  # Effectively 'none.T = noneProducer.T'
  proc noneProducer[T](): Option[T] = none()
  let myNone = noneProducer[int]()

  # Also works
  # 'myOtherNone' binds its 'T' to 'float' and 'noneProducer' inherits it
  # noneProducer.T = myOtherNone.T
  let myOtherNone: Option[float] = noneProducer()

  # Works as well
  # none.T = myOtherOtherNone.T
  let myOtherOtherNone: Option[int] = none()
  ```

This is achieved by reducing the types on the lhs and rhs until the *lhs* is left with only types such as `T`.
While lhs and rhs are reduced together, this does *not* mean that the *rhs* will also only be left
with a flat type `Z`, it may be of the form `MyType[Z]`.

After the types have been reduced, the types `T` are bound to the types that are left on the rhs.

If bindings *cannot be inferred*, compilation will fail and manual specification is required.

An example for *failing inference* can be found when passing a generic expression
to a function/template call:

  ```nim  test = "nim c $1"  status = 1
  {.experimental: "inferGenericTypes".}

  proc myProc[T](a, b: T) = discard

  # Fails! Unable to infer that 'T' is supposed to be 'int'
  myProc(newSeq[int](), newSeq(1))

  # Works! Manual specification of 'T' as 'int' necessary
  myProc(newSeq[int](), newSeq[int](1))
  ```

Combination of generic inference with the `auto` type is also unsupported:

  ```nim  test = "nim c $1"  status = 1
  {.experimental: "inferGenericTypes".}

  proc produceValue[T]: auto = default(T)
  let a: int = produceValue() # 'auto' cannot be inferred here
  ```

**Note**: The described inference does not permit the creation of overrides based on
the return type of a procedure. It is a mapping mechanism that does not attempt to 
perform deeper inference, nor does it modify what is a valid override.

  ```nim  test = "nim c $1"  status = 1
  # Doesn't affect the following code, it is invalid either way
  {.experimental: "inferGenericTypes".}

  proc a: int = 0
  proc a: float = 1.0 # Fails! Invalid code and not recommended
  ```


Sequence literals
-----------------

Top-down type inference applies to sequence literals.

```nim
let x: seq[seq[float]] = @[@[1, 2, 3], @[4, 5, 6]]
```

This behavior is tied to the `@` overloads in the `system` module,
so overloading `@` can disable this behavior. This can be circumvented by
specifying the `` system.`@` `` overload.

```nim
proc `@`(x: string): string = "@" & x

# does not compile:
let x: seq[float] = @[1, 2, 3]
# compiles:
let x: seq[float] = system.`@`([1, 2, 3])
```


Package level objects
=====================

Every Nim module resides in a (nimble) package. An object type can be attached
to the package it resides in. If that is done, the type can be referenced from
other modules as an `incomplete`:idx: object type. This feature allows to
break up recursive type dependencies across module boundaries. Incomplete
object types are always passed `byref` and can only be used in pointer like
contexts (`var/ref/ptr IncompleteObject`) in general, since the compiler does
not yet know the size of the object. To complete an incomplete object,
the `package` pragma has to be used. `package` implies `byref`.

As long as a type `T` is incomplete, no runtime type information for `T` is
available.


Example:

  ```nim
  # module A (in an arbitrary package)
  type
    Pack.SomeObject = object # declare as incomplete object of package 'Pack'
    Triple = object
      a, b, c: ref SomeObject # pointers to incomplete objects are allowed

  # Incomplete objects can be used as parameters:
  proc myproc(x: SomeObject) = discard
  ```


  ```nim
  # module B (in package "Pack")
  type
    SomeObject* {.package.} = object # Use 'package' to complete the object
      s, t: string
      x, y: int
  ```

This feature will likely be superseded in the future by support for
recursive module dependencies.


Importing private symbols
=========================

In some situations, it may be useful to import all symbols (public or private)
from a module. The syntax `import foo {.all.}` can be used to import all
symbols from the module `foo`. Note that importing private symbols is
generally not recommended.

See also the experimental [importutils](importutils.html) module.


Code reordering
===============

The code reordering feature can implicitly rearrange procedure, template, and
macro definitions along with variable declarations and initializations at the top
level scope so that, to a large extent, a programmer should not have to worry
about ordering definitions correctly or be forced to use forward declarations to
preface definitions inside a module.

..
   NOTE: The following was documentation for the code reordering precursor,
   which was {.noForward.}.

   In this mode, procedure definitions may appear out of order and the compiler
   will postpone their semantic analysis and compilation until it actually needs
   to generate code using the definitions. In this regard, this mode is similar
   to the modus operandi of dynamic scripting languages, where the function
   calls are not resolved until the code is executed. Here is the detailed
   algorithm taken by the compiler:

   1. When a callable symbol is first encountered, the compiler will only note
   the symbol callable name and it will add it to the appropriate overload set
   in the current scope. At this step, it won't try to resolve any of the type
   expressions used in the signature of the symbol (so they can refer to other
   not yet defined symbols).

   2. When a top level call is encountered (usually at the very end of the
   module), the compiler will try to determine the actual types of all of the
   symbols in the matching overload set. This is a potentially recursive process
   as the signatures of the symbols may include other call expressions, whose
   types will be resolved at this point too.

   3. Finally, after the best overload is picked, the compiler will start
   compiling the body of the respective symbol. This in turn will lead the
   compiler to discover more call expressions that need to be resolved and steps
   2 and 3 will be repeated as necessary.

   Please note that if a callable symbol is never used in this scenario, its
   body will never be compiled. This is the default behavior leading to best
   compilation times, but if exhaustive compilation of all definitions is
   required, using `nim check` provides this option as well.

Example:

  ```nim
  {.experimental: "codeReordering".}

  proc foo(x: int) =
    bar(x)

  proc bar(x: int) =
    echo(x)

  foo(10)
  ```

Variables can also be reordered as well. Variables that are *initialized* (i.e.
variables that have their declaration and assignment combined in a single
statement) can have their entire initialization statement reordered. Be wary of
what code is executed at the top level:

  ```nim
  {.experimental: "codeReordering".}

  proc a() =
    echo(foo)

  var foo = 5

  a() # outputs: "5"
  ```

..
   TODO: Let's table this for now. This is an *experimental feature* and so the
   specific manner in which `declared` operates with it can be decided in
   eventuality, because right now it works a bit weirdly.

   The values of expressions involving `declared` are decided *before* the
   code reordering process, and not after. As an example, the output of this
   code is the same as it would be with code reordering disabled.

     ```nim
     {.experimental: "codeReordering".}

     proc x() =
       echo(declared(foo))

     var foo = 4

     x() # "false"
     ```

It is important to note that reordering *only* works for symbols at top level
scope. Therefore, the following will *fail to compile:*

  ```nim
  {.experimental: "codeReordering".}

  proc a() =
    b()
    proc b() =
      echo("Hello!")

  a()
  ```

This feature will likely be replaced with a better solution to remove
the need for forward declarations.

Special Operators
=================

dot operators
-------------

.. note:: Dot operators are still experimental and so need to be enabled
  via `{.experimental: "dotOperators".}`.

Nim offers a special family of dot operators that can be used to
intercept and rewrite proc call and field access attempts, referring
to previously undeclared symbol names. They can be used to provide a
fluent interface to objects lying outside the static confines of the
type system such as values from dynamic scripting languages
or dynamic file formats such as JSON or XML.

When Nim encounters an expression that cannot be resolved by the
standard overload resolution rules, the current scope will be searched
for a dot operator that can be matched against a re-written form of
the expression, where the unknown field or proc name is passed to
an `untyped` parameter:

  ```nim
  a.b # becomes `.`(a, b)
  a.b(c, d) # becomes `.`(a, b, c, d)
  ```

The matched dot operators can be symbols of any callable kind (procs,
templates and macros), depending on the desired effect:

  ```nim
  template `.`(js: PJsonNode, field: untyped): JSON = js[astToStr(field)]

  var js = parseJson("{ x: 1, y: 2}")
  echo js.x # outputs 1
  echo js.y # outputs 2
  ```

The following dot operators are available:

operator `.`
------------
This operator will be matched against both field accesses and method calls.

operator `.()`
---------------
This operator will be matched exclusively against method calls. It has higher
precedence than the `.` operator and this allows one to handle expressions like
`x.y` and `x.y()` differently if one is interfacing with a scripting language
for example.

operator `.=`
-------------
This operator will be matched against assignments to missing fields.

  ```nim
  a.b = c # becomes `.=`(a, b, c)
  ```

Call operator
-------------
The call operator, `()`, matches all kinds of unresolved calls and takes
precedence over dot operators, however it does not match missing overloads
for existing routines. The experimental `callOperator` switch must be enabled
to use this operator.

  ```nim
  {.experimental: "callOperator".}

  template `()`(a: int, b: float): untyped = $(a, b)

  block:
    let a = 1.0
    let b = 2
    doAssert b(a) == `()`(b, a)
    doAssert a.b == `()`(b, a)

  block:
    let a = 1.0
    proc b(): int = 2
    doAssert not compiles(b(a))
    doAssert not compiles(a.b) # `()` not called

  block:
    let a = 1.0
    proc b(x: float): int = int(x + 1)
    let c = 3.0

    doAssert not compiles(a.b(c)) # gives a type mismatch error same as b(a, c)
    doAssert (a.b)(c) == `()`(a.b, c)
  ```


Extended macro pragmas
======================

Macro pragmas as described in [the manual](manual.html#userminusdefined-pragmas-macro-pragmas)
can also be applied to type, variable and constant declarations.

For types:

  ```nim
  type
    MyObject {.schema: "schema.protobuf".} = object
  ```

This is translated to a call to the `schema` macro with a `nnkTypeDef`
AST node capturing the left-hand side, remaining pragmas and the right-hand
side of the definition. The macro can return either a type section or
another `nnkTypeDef` node, both of which will replace the original row
in the type section.

In the future, this `nnkTypeDef` argument may be replaced with a unary
type section node containing the type definition, or some other node that may
be more convenient to work with. The ability to return nodes other than type
definitions may also be supported, however currently this is not convenient
when dealing with mutual type recursion. For now, macros can return an unused
type definition where the right-hand node is of kind `nnkStmtListType`.
Declarations in this node will be attached to the same scope as
the parent scope of the type section.

------

For variables and constants, it is largely the same, except a unary node with
the same kind as the section containing a single definition is passed to macros,
and macros can return any expression.

  ```nim
  var
    a = ...
    b {.importc, foo, nodecl.} = ...
    c = ...
  ```

Assuming `foo` is a macro or a template, this is roughly equivalent to:

  ```nim
  var a = ...
  foo:
    var b {.importc, nodecl.} = ...
  var c = ...
  ```


Symbols as template/macro calls (alias syntax)
==============================================

Templates and macros that have no generic parameters and no required arguments
can be called as lone symbols, i.e. without parentheses. This is useful for
repeated uses of complex expressions that cannot conveniently be represented
as runtime values.

  ```nim
  type Foo = object
    bar: int

  var foo = Foo(bar: 10)
  template bar: int = foo.bar
  assert bar == 10
  bar = 15
  assert bar == 15
  ```


Not nil annotation
==================

**Note:** This is an experimental feature. It can be enabled with
`{.experimental: "notnil".}`.

All types for which `nil` is a valid value can be annotated with the
`not nil` annotation to exclude `nil` as a valid value. Note that only local
symbols are checked.

  ```nim
  {.experimental: "notnil".}

  type
    TObj = object
    PObject = ref TObj not nil
    TProc = (proc (x, y: int)) not nil

  proc p(x: PObject) =
    echo "not nil"

  # compiler catches this:
  p(nil)

  # and also this:
  proc foo =
    var x: PObject
    p(x)

  foo()
  ```

The compiler ensures that every code path initializes variables which contain
non-nilable pointers. The details of this analysis are still to be specified
here.

.. include:: manual_experimental_strictnotnil.md


Aliasing restrictions in parameter passing
==========================================

.. note:: The aliasing restrictions are currently not enforced by the
  implementation and need to be fleshed out further.

"Aliasing" here means that the underlying storage locations overlap in memory
at runtime. An "output parameter" is a parameter of type `var T`,
an input parameter is any parameter that is not of type `var`.

1. Two output parameters should never be aliased.
2. An input and an output parameter should not be aliased.
3. An output parameter should never be aliased with a global or thread local
   variable referenced by the called proc.
4. An input parameter should not be aliased with a global or thread local
   variable updated by the called proc.

One problem with rules 3 and 4 is that they affect specific global or thread
local variables, but Nim's effect tracking only tracks "uses no global variable"
via `.noSideEffect`. The rules 3 and 4 can also be approximated by a different rule:

5. A global or thread local variable (or a location derived from such a location)
   can only passed to a parameter of a `.noSideEffect` proc.


Strict funcs
============

Since version 1.4, a stricter definition of "side effect" is available.
In addition to the existing rule that a side effect is calling a function
with side effects, the following rule is also enforced:

A store to the heap via a `ref` or `ptr` indirection is not allowed.

For example:

  ```nim
  {.experimental: "strictFuncs".}

  type
    Node = ref object
      le, ri: Node
      data: string

  func len(n: Node): int =
    # valid: len does not have side effects
    var it = n
    while it != nil:
      inc result
      it = it.ri

  func mut(n: Node) =
    var it = n
    while it != nil:
      it.data = "yeah" # forbidden mutation
      it = it.ri

  ```


View types
==========

.. tip::  `--experimental:views`:option: is more effective
  with `--experimental:strictFuncs`:option:.

A view type is a type that is or contains one of the following types:

- `lent T` (view into `T`)
- `openArray[T]` (pair of (pointer to array of `T`, size))

For example:

  ```nim
  type
    View1 = openArray[byte]
    View2 = lent string
    View3 = Table[openArray[char], int]
  ```


Exceptions to this rule are types constructed via `ptr` or `proc`.
For example, the following types are **not** view types:

  ```nim
  type
    NotView1 = proc (x: openArray[int])
    NotView2 = ptr openArray[char]
    NotView3 = ptr array[4, lent int]
  ```


The mutability aspect of a view type is not part of the type but part
of the locations it's derived from. More on this later.

A *view* is a symbol (a let, var, const, etc.) that has a view type.

Since version 1.4, Nim allows view types to be used as local variables.
This feature needs to be enabled via `{.experimental: "views".}`.

A local variable of a view type *borrows* from the locations and
it is statically enforced that the view does not outlive the location
it was borrowed from.

For example:

  ```nim
  {.experimental: "views".}

  proc take(a: openArray[int]) =
    echo a.len

  proc main(s: seq[int]) =
    var x: openArray[int] = s # 'x' is a view into 's'
    # it is checked that 'x' does not outlive 's' and
    # that 's' is not mutated.
    for i in 0 .. high(x):
      echo x[i]
    take(x)

    take(x.toOpenArray(0, 1)) # slicing remains possible
    let y = x  # create a view from a view
    take y
    # it is checked that 'y' does not outlive 'x' and
    # that 'x' is not mutated as long as 'y' lives.


  main(@[11, 22, 33])
  ```


A local variable of a view type can borrow from a location
derived from a parameter, another local variable, a global `const` or `let`
symbol or a thread-local `var` or `let`.

Let `p` the proc that is analysed for the correctness of the borrow operation.

Let `source` be one of:

- A formal parameter of `p`. Note that this does not cover parameters of
  inner procs.
- The `result` symbol of `p`.
- A local `var` or `let` or `const` of `p`. Note that this does
  not cover locals of inner procs.
- A thread-local `var` or `let`.
- A global `let` or `const`.
- A constant array/seq/object/tuple constructor.


Path expressions
----------------

A location derived from `source` is then defined as a path expression that
has `source` as the owner. A path expression `e` is defined recursively:

- `source` itself is a path expression.
- Container access like `e[i]` is a path expression.
- Tuple access `e[0]` is a path expression.
- Object field access `e.field` is a path expression.
- `system.toOpenArray(e, ...)` is a path expression.
- Pointer dereference `e[]` is a path expression.
- An address `addr e` is a path expression.
- A type conversion `T(e)` is a path expression.
- A cast expression `cast[T](e)` is a path expression.
- `f(e, ...)` is a path expression if `f`'s return type is a view type.
  Because the view can only have been borrowed from `e`, we then know
  that the owner of `f(e, ...)` is `e`.


If a view type is used as a return type, the location must borrow from a location
that is derived from the first parameter that is passed to the proc.
See [the manual](manual.html#procedures-var-return-type)
for details about how this is done for `var T`.

A mutable view can borrow from a mutable location, an immutable view can borrow
from both a mutable or an immutable location.

If a view borrows from a mutable location, the view can be used to update the
location. Otherwise it cannot be used for mutations.

The *duration* of a borrow is the span of commands beginning from the assignment
to the view and ending with the last usage of the view.

For the duration of the borrow operation, no mutations to the borrowed locations
may be performed except via the view that borrowed from the
location. The borrowed location is said to be *sealed* during the borrow.

  ```nim
  {.experimental: "views".}

  type
    Obj = object
      field: string

  proc dangerous(s: var seq[Obj]) =
    let v: lent Obj = s[0] # seal 's'
    s.setLen 0  # prevented at compile-time because 's' is sealed.
    echo v.field
  ```


The scope of the view does not matter:

  ```nim
  proc valid(s: var seq[Obj]) =
    let v: lent Obj = s[0]  # begin of borrow
    echo v.field            # end of borrow
    s.setLen 0  # valid because 'v' isn't used afterwards
  ```


The analysis requires as much precision about mutations as is reasonably obtainable,
so it is more effective with the experimental [strict funcs]
feature. In other words `--experimental:views`:option: works better
with `--experimental:strictFuncs`:option:.

The analysis is currently control flow insensitive:

  ```nim
  proc invalid(s: var seq[Obj]) =
    let v: lent Obj = s[0]
    if false:
      s.setLen 0
    echo v.field
  ```

In this example, the compiler assumes that `s.setLen 0` invalidates the
borrow operation of `v` even though a human being can easily see that it
will never do that at runtime.


Start of a borrow
-----------------

A borrow starts with one of the following:

- The assignment of a non-view-type to a view-type.
- The assignment of a location that is derived from a local parameter
  to a view-type.


End of a borrow
---------------

A borrow operation ends with the last usage of the view variable.


Reborrows
---------

A view `v` can borrow from multiple different locations. However, the borrow
is always the full span of `v`'s lifetime and every location that is borrowed
from is sealed during `v`'s lifetime.


Algorithm
---------

The following section is an outline of the algorithm that the current implementation
uses. The algorithm performs two traversals over the AST of the procedure or global
section of code that uses a view variable. No fixpoint iterations are performed, the
complexity of the analysis is O(N) where N is the number of nodes of the AST.

The first pass over the AST computes the lifetime of each local variable based on
a notion of an "abstract time", in the implementation it's a simple integer that is
incremented for every visited node.

In the second pass, information about the underlying object "graphs" is computed.
Let `v` be a parameter or a local variable. Let `G(v)` be the graph
that `v` belongs to. A graph is defined by the set of variables that belong
to the graph. Initially for all `v`: `G(v) = {v}`. Every variable can only
be part of a single graph.

Assignments like `a = b` "connect" two variables, both variables end up in the
same graph `{a, b} = G(a) = G(b)`. Unfortunately, the pattern to look for is
much more complex than that and can involve multiple assignment targets
and sources:

    f(x, y) = g(a, b)

connects `x` and `y` to `a` and `b`: `G(x) = G(y) = G(a) = G(b) = {x, y, a, b}`.
A type based alias analysis rules out some of these combinations, for example
a `string` value cannot possibly be connected to a `seq[int]`.

A pattern like `v[] = value` or `v.field = value` marks `G(v)` as mutated.
After the second pass a set of disjoint graphs was computed.

For strict functions it is then enforced that there is no graph that is both mutated
and has an element that is an immutable parameter (that is a parameter that is not
of type `var T`).

For borrow checking, a different set of checks is performed. Let `v` be the view
and `b` the location that is borrowed from.

- The lifetime of `v` must not exceed `b`'s lifetime. Note: The lifetime of
  a parameter is the complete proc body.
- If `v` is used for a mutation, `b` must be a mutable location too.
- During `v`'s lifetime, `G(b)` can only be modified by `v` (and only if
  `v` is a mutable view).
- If `v` is `result` then `b` has to be a location derived from the first
  formal parameter or from a constant location.
- A view cannot be used for a read or a write access before it was assigned to.


Concepts
========

Concepts, also known as "user-defined type classes", are used to specify an
arbitrary set of requirements that the matched type must satisfy.

Concepts are written in the following form:

  ```nim
  type
    Comparable = concept x, y
      (x < y) is bool

    Stack[T] = concept s, var v
      s.pop() is T
      v.push(T)

      s.len is Ordinal

      for value in s:
        value is T
  ```

The concept matches if:

a) all expressions within the body can be compiled for the tested type
b) all statically evaluable boolean expressions in the body are true
c) all type modifiers specified match their respective definitions

The identifiers following the `concept` keyword represent instances of the
currently matched type. You can apply any of the standard type modifiers such
as `var`, `ref`, `ptr` and `static` to denote a more specific type of
instance. You can also apply the `type` modifier to create a named instance of
the type itself:

  ```nim
  type
    MyConcept = concept x, var v, ref r, ptr p, static s, type T
      ...
  ```

Within the concept body, types can appear in positions where ordinary values
and parameters are expected. This provides a more convenient way to check for
the presence of callable symbols with specific signatures:

  ```nim
  type
    OutputStream = concept var s
      s.write(string)
  ```

In order to check for symbols accepting `type` params, you must prefix
the type with the explicit `type` modifier. The named instance of the
type, following the `concept` keyword is also considered to have the
explicit modifier and will be matched only as a type.

  ```nim
  type
    # Let's imagine a user-defined casting framework with operators
    # such as `val.to(string)` and `val.to(JSonValue)`. We can test
    # for these with the following concept:
    MyCastables = concept x
      x.to(type string)
      x.to(type JSonValue)

    # Let's define a couple of concepts, known from Algebra:
    AdditiveMonoid* = concept x, y, type T
      x + y is T
      T.zero is T # require a proc such as `int.zero` or 'Position.zero'

    AdditiveGroup* = concept x, y, type T
      x is AdditiveMonoid
      -x is T
      x - y is T
  ```

Please note that the `is` operator allows one to easily verify the precise
type signatures of the required operations, but since type inference and
default parameters are still applied in the concept body, it's also possible
to describe usage protocols that do not reveal implementation details.

Much like generics, concepts are instantiated exactly once for each tested type
and any static code included within the body is executed only once.


Concept diagnostics
-------------------

By default, the compiler will report the matching errors in concepts only when
no other overload can be selected and a normal compilation error is produced.
When you need to understand why the compiler is not matching a particular
concept and, as a result, a wrong overload is selected, you can apply the
`explain` pragma to either the concept body or a particular call-site.

  ```nim
  type
    MyConcept {.explain.} = concept ...

  overloadedProc(x, y, z) {.explain.}
  ```

This will provide Hints in the compiler output either every time the concept is
not matched or only on the particular call-site.


Generic concepts and type binding rules
---------------------------------------

The concept types can be parametric just like the regular generic types:

  ```nim
  ### matrixalgo.nim

  import std/typetraits

  type
    AnyMatrix*[R, C: static int; T] = concept m, var mvar, type M
      M.ValueType is T
      M.Rows == R
      M.Cols == C

      m[int, int] is T
      mvar[int, int] = T

      type TransposedType = stripGenericParams(M)[C, R, T]

    AnySquareMatrix*[N: static int, T] = AnyMatrix[N, N, T]

    AnyTransform3D* = AnyMatrix[4, 4, float]

  proc transposed*(m: AnyMatrix): m.TransposedType =
    for r in 0 ..< m.R:
      for c in 0 ..< m.C:
        result[r, c] = m[c, r]

  proc determinant*(m: AnySquareMatrix): int =
    ...

  proc setPerspectiveProjection*(m: AnyTransform3D) =
    ...

  --------------
  ### matrix.nim

  type
    Matrix*[M, N: static int; T] = object
      data: array[M*N, T]

  proc `[]`*(M: Matrix; m, n: int): M.T =
    M.data[m * M.N + n]

  proc `[]=`*(M: var Matrix; m, n: int; v: M.T) =
    M.data[m * M.N + n] = v

  # Adapt the Matrix type to the concept's requirements
  template Rows*(M: typedesc[Matrix]): int = M.M
  template Cols*(M: typedesc[Matrix]): int = M.N
  template ValueType*(M: typedesc[Matrix]): typedesc = M.T

  -------------
  ### usage.nim

  import matrix, matrixalgo

  var
    m: Matrix[3, 3, int]
    projectionMatrix: Matrix[4, 4, float]

  echo m.transposed.determinant
  setPerspectiveProjection projectionMatrix
  ```

When the concept type is matched against a concrete type, the unbound type
parameters are inferred from the body of the concept in a way that closely
resembles the way generic parameters of callable symbols are inferred on
call sites.

Unbound types can appear both as params to calls such as `s.push(T)` and
on the right-hand side of the `is` operator in cases such as `x.pop is T`
and `x.data is seq[T]`.

Unbound static params will be inferred from expressions involving the `==`
operator and also when types dependent on them are being matched:

  ```nim
  type
    MatrixReducer[M, N: static int; T] = concept x
      x.reduce(SquareMatrix[N, T]) is array[M, int]
  ```

The Nim compiler includes a simple linear equation solver, allowing it to
infer static params in some situations where integer arithmetic is involved.

Just like in regular type classes, Nim discriminates between `bind once`
and `bind many` types when matching the concept. You can add the `distinct`
modifier to any of the otherwise inferable types to get a type that will be
matched without permanently inferring it. This may be useful when you need
to match several procs accepting the same wide class of types:

  ```nim
  type
    Enumerable[T] = concept e
      for v in e:
        v is T

  type
    MyConcept = concept o
      # this could be inferred to a type such as Enumerable[int]
      o.foo is distinct Enumerable

      # this could be inferred to a different type such as Enumerable[float]
      o.bar is distinct Enumerable

      # it's also possible to give an alias name to a `bind many` type class
      type Enum = distinct Enumerable
      o.baz is Enum
  ```

On the other hand, using `bind once` types allows you to test for equivalent
types used in multiple signatures, without actually requiring any concrete
types, thus allowing you to encode implementation-defined types:

  ```nim
  type
    MyConcept = concept x
      type T1 = auto
      x.foo(T1)
      x.bar(T1) # both procs must accept the same type

      type T2 = seq[SomeNumber]
      x.alpha(T2)
      x.omega(T2) # both procs must accept the same type
                  # and it must be a numeric sequence
  ```

As seen in the previous examples, you can refer to generic concepts such as
`Enumerable[T]` just by their short name. Much like the regular generic types,
the concept will be automatically instantiated with the bind once auto type
in the place of each missing generic param.

Please note that generic concepts such as `Enumerable[T]` can be matched
against concrete types such as `string`. Nim doesn't require the concept
type to have the same number of parameters as the type being matched.
If you wish to express a requirement towards the generic parameters of
the matched type, you can use a type mapping operator such as `genericHead`
or `stripGenericParams` within the body of the concept to obtain the
uninstantiated version of the type, which you can then try to instantiate
in any required way. For example, here is how one might define the classic
`Functor` concept from Haskell and then demonstrate that Nim's `Option[T]`
type is an instance of it:

  ```nim  test = "nim c $1"
  import std/[sugar, typetraits]

  type
    Functor[A] = concept f
      type MatchedGenericType = genericHead(typeof(f))
        # `f` will be a value of a type such as `Option[T]`
        # `MatchedGenericType` will become the `Option` type

      f.val is A
        # The Functor should provide a way to obtain
        # a value stored inside it

      type T = auto
      map(f, A -> T) is MatchedGenericType[T]
        # And it should provide a way to map one instance of
        # the Functor to a instance of a different type, given
        # a suitable `map` operation for the enclosed values

  import std/options
  echo Option[int] is Functor # prints true
  ```


Concept derived values
----------------------

All top level constants or types appearing within the concept body are
accessible through the dot operator in procs where the concept was successfully
matched to a concrete type:

  ```nim
  type
    DateTime = concept t1, t2, type T
      const Min = T.MinDate
      T.Now is T

      t1 < t2 is bool

      type TimeSpan = typeof(t1 - t2)
      TimeSpan * int is TimeSpan
      TimeSpan + TimeSpan is TimeSpan

      t1 + TimeSpan is T

  proc eventsJitter(events: Enumerable[DateTime]): float =
    var
      # this variable will have the inferred TimeSpan type for
      # the concrete Date-like value the proc was called with:
      averageInterval: DateTime.TimeSpan

      deviation: float
    ...
  ```


Concept refinement
------------------

When the matched type within a concept is directly tested against a different
concept, we say that the outer concept is a refinement of the inner concept and
thus it is more-specific. When both concepts are matched in a call during
overload resolution, Nim will assign a higher precedence to the most specific
one. As an alternative way of defining concept refinements, you can use the
object inheritance syntax involving the `of` keyword:

  ```nim
  type
    Graph = concept g, type G of EquallyComparable, Copyable
      type
        VertexType = G.VertexType
        EdgeType = G.EdgeType

      VertexType is Copyable
      EdgeType is Copyable

      var
        v: VertexType
        e: EdgeType

    IncidendeGraph = concept of Graph
      # symbols such as variables and types from the refined
      # concept are automatically in scope:

      g.source(e) is VertexType
      g.target(e) is VertexType

      g.outgoingEdges(v) is Enumerable[EdgeType]

    BidirectionalGraph = concept g, type G
      # The following will also turn the concept into a refinement when it
      # comes to overload resolution, but it doesn't provide the convenient
      # symbol inheritance
      g is IncidendeGraph

      g.incomingEdges(G.VertexType) is Enumerable[G.EdgeType]

  proc f(g: IncidendeGraph)
  proc f(g: BidirectionalGraph) # this one will be preferred if we pass a type
                                # matching the BidirectionalGraph concept
  ```

..
  Converter type classes
  ----------------------

  Concepts can also be used to convert a whole range of types to a single type or
  a small set of simpler types. This is achieved with a `return` statement within
  the concept body:

    ```nim
    type
      Stringable = concept x
        $x is string
        return $x

      StringRefValue[CharType] = object
        base: ptr CharType
        len: int

      StringRef = concept x
        # the following would be an overloaded proc for cstring, string, seq and
        # other user-defined types, returning either a StringRefValue[char] or
        # StringRefValue[wchar]
        return makeStringRefValue(x)

    # the varargs param will here be converted to an array of StringRefValues
    # the proc will have only two instantiations for the two character types
    proc log(format: static string, varargs[StringRef])

    # this proc will allow char and wchar values to be mixed in
    # the same call at the cost of additional instantiations
    # the varargs param will be converted to a tuple
    proc log(format: static string, varargs[distinct StringRef])
    ```


..
  VTable types
  ------------

  Concepts allow Nim to define a great number of algorithms, using only
  static polymorphism and without erasing any type information or sacrificing
  any execution speed. But when polymorphic collections of objects are required,
  the user must use one of the provided type erasure techniques - either common
  base types or VTable types.

  VTable types are represented as "fat pointers" storing a reference to an
  object together with a reference to a table of procs implementing a set of
  required operations (the so called vtable).

  In contrast to other programming languages, the vtable in Nim is stored
  externally to the object, allowing you to create multiple different vtable
  views for the same object. Thus, the polymorphism in Nim is unbounded -
  any type can implement an unlimited number of protocols or interfaces not
  originally envisioned by the type's author.

  Any concept type can be turned into a VTable type by using the `vtref`
  or the `vtptr` compiler magics. Under the hood, these magics generate
  a converter type class, which converts the regular instances of the matching
  types to the corresponding VTable type.

    ```nim
    type
      IntEnumerable = vtref Enumerable[int]

      MyObject = object
        enumerables: seq[IntEnumerable]
        streams: seq[OutputStream.vtref]

    proc addEnumerable(o: var MyObject, e: IntEnumerable) =
      o.enumerables.add e

    proc addStream(o: var MyObject, e: OutputStream.vtref) =
      o.streams.add e
    ```

  The procs that will be included in the vtable are derived from the concept
  body and include all proc calls for which all param types were specified as
  concrete types. All such calls should include exactly one param of the type
  matched against the concept (not necessarily in the first position), which
  will be considered the value bound to the vtable.

  Overloads will be created for all captured procs, accepting the vtable type
  in the position of the captured underlying object.

  Under these rules, it's possible to obtain a vtable type for a concept with
  unbound type parameters or one instantiated with metatypes (type classes),
  but it will include a smaller number of captured procs. A completely empty
  vtable will be reported as an error.

  The `vtref` magic produces types which can be bound to `ref` types and
  the `vtptr` magic produced types bound to `ptr` types.


..
  deepCopy
  --------
  `=deepCopy` is a builtin that is invoked whenever data is passed to
  a `spawn`'ed proc to ensure memory safety. The programmer can override its
  behaviour for a specific `ref` or `ptr` type `T`. (Later versions of the
  language may weaken this restriction.)

  The signature has to be:

    ```nim
    proc `=deepCopy`(x: T): T
    ```

  This mechanism will be used by most data structures that support shared memory,
  like channels, to implement thread safe automatic memory management.

  The builtin `deepCopy` can even clone closures and their environments. See
  the documentation of [spawn][spawn statement] for details.


Dynamic arguments for bindSym
=============================

This experimental feature allows the symbol name argument of `macros.bindSym`
to be computed dynamically.

  ```nim
  {.experimental: "dynamicBindSym".}

  import std/macros

  macro callOp(opName, arg1, arg2): untyped =
    result = newCall(bindSym($opName), arg1, arg2)

  echo callOp("+", 1, 2)
  echo callOp("-", 5, 4)
  ```


Term rewriting macros
=====================

Term rewriting macros are macros or templates that have not only
a *name* but also a *pattern* that is searched for after the semantic checking
phase of the compiler: This means they provide an easy way to enhance the
compilation pipeline with user defined optimizations:

  ```nim
  template optMul{`*`(a, 2)}(a: int): int = a + a

  let x = 3
  echo x * 2
  ```

The compiler now rewrites `x * 2` as `x + x`. The code inside the
curly brackets is the pattern to match against. The operators `*`,  `**`,
`|`, `~` have a special meaning in patterns if they are written in infix
notation, so to match verbatim against `*` the ordinary function call syntax
needs to be used.

Term rewriting macros are applied recursively, up to a limit. This means that
if the result of a term rewriting macro is eligible for another rewriting,
the compiler will try to perform it, and so on, until no more optimizations
are applicable. To avoid putting the compiler into an infinite loop, there is
a hard limit on how many times a single term rewriting macro can be applied.
Once this limit has been passed, the term rewriting macro will be ignored.

Unfortunately optimizations are hard to get right and even this tiny example
is **wrong**:

  ```nim
  template optMul{`*`(a, 2)}(a: int): int = a + a

  proc f(): int =
    echo "side effect!"
    result = 55

  echo f() * 2
  ```

We cannot duplicate 'a' if it denotes an expression that has a side effect!
Fortunately Nim supports side effect analysis:

  ```nim
  template optMul{`*`(a, 2)}(a: int{noSideEffect}): int = a + a

  proc f(): int =
    echo "side effect!"
    result = 55

  echo f() * 2 # not optimized ;-)
  ```

You can make one overload matching with a constraint and one without, and the
one with a constraint will have precedence, and so you can handle both cases
differently.

So what about `2 * a`? We should tell the compiler `*` is commutative. We
cannot really do that however as the following code only swaps arguments
blindly:

  ```nim
  template mulIsCommutative{`*`(a, b)}(a, b: int): int = b * a
  ```

What optimizers really need to do is a *canonicalization*:

  ```nim
  template canonMul{`*`(a, b)}(a: int{lit}, b: int): int = b * a
  ```

The `int{lit}` parameter pattern matches against an expression of
type `int`, but only if it's a literal.



Parameter constraints
---------------------

The `parameter constraint`:idx: expression can use the operators `|` (or),
`&` (and) and `~` (not) and the following predicates:

===================      =====================================================
Predicate                Meaning
===================      =====================================================
`atom`                   The matching node has no children.
`lit`                    The matching node is a literal like `"abc"`, `12`.
`sym`                    The matching node must be a symbol (a bound
                         identifier).
`ident`                  The matching node must be an identifier (an unbound
                         identifier).
`call`                   The matching AST must be a call/apply expression.
`lvalue`                 The matching AST must be an lvalue.
`sideeffect`             The matching AST must have a side effect.
`nosideeffect`           The matching AST must have no side effect.
`param`                  A symbol which is a parameter.
`genericparam`           A symbol which is a generic parameter.
`module`                 A symbol which is a module.
`type`                   A symbol which is a type.
`var`                    A symbol which is a variable.
`let`                    A symbol which is a `let` variable.
`const`                  A symbol which is a constant.
`result`                 The special `result` variable.
`proc`                   A symbol which is a proc.
`method`                 A symbol which is a method.
`iterator`               A symbol which is an iterator.
`converter`              A symbol which is a converter.
`macro`                  A symbol which is a macro.
`template`               A symbol which is a template.
`field`                  A symbol which is a field in a tuple or an object.
`enumfield`              A symbol which is a field in an enumeration.
`forvar`                 A for loop variable.
`label`                  A label (used in `block` statements).
`nk*`                    The matching AST must have the specified kind.
                         (Example: `nkIfStmt` denotes an `if` statement.)
`alias`                  States that the marked parameter needs to alias
                         with *some* other parameter.
`noalias`                States that *every* other parameter must not alias
                         with the marked parameter.
===================      =====================================================

Predicates that share their name with a keyword have to be escaped with
backticks.
The `alias` and `noalias` predicates refer not only to the matching AST,
but also to every other bound parameter; syntactically they need to occur after
the ordinary AST predicates:

  ```nim
  template ex{a = b + c}(a: int{noalias}, b, c: int) =
    # this transformation is only valid if 'b' and 'c' do not alias 'a':
    a = b
    inc a, c
  ```

Another example:

  ```nim
  proc somefunc(s: string)                 = assert s == "variable"
  proc somefunc(s: string{nkStrLit})       = assert s == "literal"
  proc somefunc(s: string{nkRStrLit})      = assert s == r"raw"
  proc somefunc(s: string{nkTripleStrLit}) = assert s == """triple"""
  proc somefunc(s: static[string])         = assert s == "constant"

  # Use parameter constraints to provide overloads based on both the input parameter type and form.
  var variable = "variable"
  somefunc(variable)
  const constant = "constant"
  somefunc(constant)
  somefunc("literal")
  somefunc(r"raw")
  somefunc("""triple""")
  ```


Pattern operators
-----------------

The operators `*`,  `**`, `|`, `~` have a special meaning in patterns
if they are written in infix notation.


### The `|` operator

The `|` operator if used as infix operator creates an ordered choice:

  ```nim
  template t{0|1}(): untyped = 3
  let a = 1
  # outputs 3:
  echo a
  ```

The matching is performed after the compiler performed some optimizations like
constant folding, so the following does not work:

  ```nim
  template t{0|1}(): untyped = 3
  # outputs 1:
  echo 1
  ```

The reason is that the compiler already transformed the 1 into "1" for
the `echo` statement. However, a term rewriting macro should not change the
semantics anyway. In fact, they can be deactivated with the `--patterns:off`:option:
command line option or temporarily with the `patterns` pragma.


### The `{}` operator

A pattern expression can be bound to a pattern parameter via the `expr{param}`
notation:

  ```nim
  template t{(0|1|2){x}}(x: untyped): untyped = x + 1
  let a = 1
  # outputs 2:
  echo a
  ```


### The `~` operator

The `~` operator is the 'not' operator in patterns:

  ```nim
  template t{x = (~x){y} and (~x){z}}(x, y, z: bool) =
    x = y
    if x: x = z

  var
    a = false
    b = true
    c = false
  a = b and c
  echo a
  ```


### The `*` operator

The `*` operator can *flatten* a nested binary expression like `a & b & c`
to `&(a, b, c)`:

  ```nim
  var
    calls = 0

  proc `&&`(s: varargs[string]): string =
    result = s[0]
    for i in 1..len(s)-1: result.add s[i]
    inc calls

  template optConc{ `&&` * a }(a: string): untyped = &&a

  let space = " "
  echo "my" && (space & "awe" && "some " ) && "concat"

  # check that it's been optimized properly:
  doAssert calls == 1
  ```


The second operator of `*` must be a parameter; it is used to gather all the
arguments. The expression `"my" && (space & "awe" && "some " ) && "concat"`
is passed to `optConc` in `a` as a special list (of kind `nkArgList`)
which is flattened into a call expression; thus the invocation of `optConc`
produces:

  ```nim
  `&&`("my", space & "awe", "some ", "concat")
  ```


### The `**` operator

The `**` is much like the `*` operator, except that it gathers not only
all the arguments, but also the matched operators in reverse polish notation:

  ```nim
  import std/macros

  type
    Matrix = object
      dummy: int

  proc `*`(a, b: Matrix): Matrix = discard
  proc `+`(a, b: Matrix): Matrix = discard
  proc `-`(a, b: Matrix): Matrix = discard
  proc `$`(a: Matrix): string = result = $a.dummy
  proc mat21(): Matrix =
    result.dummy = 21

  macro optM{ (`+`|`-`|`*`) ** a }(a: Matrix): untyped =
    echo treeRepr(a)
    result = newCall(bindSym"mat21")

  var x, y, z: Matrix

  echo x + y * z - x
  ```

This passes the expression `x + y * z - x` to the `optM` macro as
an `nnkArgList` node containing:

    Arglist
      Sym "x"
      Sym "y"
      Sym "z"
      Sym "*"
      Sym "+"
      Sym "x"
      Sym "-"

(This is the reverse polish notation of `x + y * z - x`.)


Parameters
----------

Parameters in a pattern are type checked in the matching process. If a
parameter is of the type `varargs`, it is treated specially and can match
0 or more arguments in the AST to be matched against:

  ```nim
  template optWrite{
    write(f, x)
    ((write|writeLine){w})(f, y)
  }(x, y: varargs[untyped], f: File, w: untyped) =
    w(f, x, y)
  ```


noRewrite pragma
----------------

Term rewriting macros and templates are currently greedy and
they will rewrite as long as there is a match.
There was no way to ensure some rewrite happens only once,
e.g. when rewriting term to same term plus extra content.

`noRewrite` pragma can actually prevent further rewriting on marked code,
e.g. with given example `echo("ab")` will be rewritten just once:

  ```nim
  template pwnEcho{echo(x)}(x: untyped) =
    {.noRewrite.}: echo("pwned!")

  echo "ab"
  ```

`noRewrite` pragma can be useful to control term-rewriting macros recursion.



Example: Partial evaluation
---------------------------

The following example shows how some simple partial evaluation can be
implemented with term rewriting:

  ```nim
  proc p(x, y: int; cond: bool): int =
    result = if cond: x + y else: x - y

  template optP1{p(x, y, true)}(x, y: untyped): untyped = x + y
  template optP2{p(x, y, false)}(x, y: untyped): untyped = x - y
  ```


Example: Hoisting
-----------------

The following example shows how some form of hoisting can be implemented:

  ```nim
  import std/pegs

  template optPeg{peg(pattern)}(pattern: string{lit}): Peg =
    var gl {.global, gensym.} = peg(pattern)
    gl

  for i in 0 .. 3:
    echo match("(a b c)", peg"'(' @ ')'")
    echo match("W_HI_Le", peg"\y 'while'")
  ```

The `optPeg` template optimizes the case of a peg constructor with a string
literal, so that the pattern will only be parsed once at program startup and
stored in a global `gl` which is then re-used. This optimization is called
hoisting because it is comparable to classical loop hoisting.


AST based overloading
=====================

Parameter constraints can also be used for ordinary routine parameters; these
constraints then affect ordinary overloading resolution:

  ```nim
  proc optLit(a: string{lit|`const`}) =
    echo "string literal"
  proc optLit(a: string) =
    echo "no string literal"

  const
    constant = "abc"

  var
    variable = "xyz"

  optLit("literal")
  optLit(constant)
  optLit(variable)
  ```

However, the constraints `alias` and `noalias` are not available in
ordinary routines.


Parallel & Spawn
================

Nim has two flavors of parallelism:
1) `Structured`:idx: parallelism via the `parallel` statement.
2) `Unstructured`:idx: parallelism via the standalone `spawn` statement.

Nim has a builtin thread pool that can be used for CPU intensive tasks. For
IO intensive tasks the `async` and `await` features should be
used instead. Both parallel and spawn need the [threadpool](threadpool.html)
module to work.

Somewhat confusingly, `spawn` is also used in the `parallel` statement
with slightly different semantics. `spawn` always takes a call expression of
the form `f(a, ...)`. Let `T` be `f`'s return type. If `T` is `void`,
then `spawn`'s return type is also `void`, otherwise it is `FlowVar[T]`.

Within a `parallel` section, the `FlowVar[T]` is sometimes eliminated
to `T`. This happens when `T` does not contain any GC'ed memory.
The compiler can ensure the location in `location = spawn f(...)` is not
read prematurely within a `parallel` section and so there is no need for
the overhead of an indirection via `FlowVar[T]` to ensure correctness.

.. note:: Currently exceptions are not propagated between `spawn`'ed tasks!

This feature is likely to be removed in the future as external packages
can have better solutions.


Spawn statement
---------------

The `spawn`:idx: statement can be used to pass a task to the thread pool:

  ```nim
  import std/threadpool

  proc processLine(line: string) =
    discard "do some heavy lifting here"

  for x in lines("myinput.txt"):
    spawn processLine(x)
  sync()
  ```

For reasons of type safety and implementation simplicity the expression
that `spawn` takes is restricted:

* It must be a call expression `f(a, ...)`.
* `f` must be `gcsafe`.
* `f` must not have the calling convention `closure`.
* `f`'s parameters may not be of type `var`.
  This means one has to use raw `ptr`'s for data passing reminding the
  programmer to be careful.
* `ref` parameters are deeply copied, which is a subtle semantic change and
  can cause performance problems, but ensures memory safety. This deep copy
  is performed via `system.deepCopy`, so it can be overridden.
* For *safe* data exchange between `f` and the caller, a global `Channel`
  needs to be used. However, since spawn can return a result, often no further
  communication is required.


`spawn` executes the passed expression on the thread pool and returns
a `data flow variable`:idx: `FlowVar[T]` that can be read from. The reading
with the `^` operator is **blocking**. However, one can use `blockUntilAny` to
wait on multiple flow variables at the same time:

  ```nim
  import std/threadpool, ...

  # wait until 2 out of 3 servers received the update:
  proc main =
    var responses = newSeq[FlowVarBase](3)
    for i in 0..2:
      responses[i] = spawn tellServer(Update, "key", "value")
    var index = blockUntilAny(responses)
    assert index >= 0
    responses.del(index)
    discard blockUntilAny(responses)
  ```

Data flow variables ensure that no data races are possible. Due to
technical limitations, not every type `T` can be used in
a data flow variable: `T` has to be a `ref`, `string`, `seq`
or of a type that doesn't contain any GC'd type. This
restriction is not hard to work-around in practice.



Parallel statement
------------------

Example:

  ```nim  test = "nim c --threads:on $1"
  # Compute pi in an inefficient way
  import std/[strutils, math, threadpool]
  {.experimental: "parallel".}

  proc term(k: float): float = 4 * math.pow(-1, k) / (2*k + 1)

  proc pi(n: int): float =
    var ch = newSeq[float](n + 1)
    parallel:
      for k in 0..ch.high:
        ch[k] = spawn term(float(k))
    for k in 0..ch.high:
      result += ch[k]

  echo formatFloat(pi(5000))
  ```


The parallel statement is the preferred mechanism to introduce parallelism in a
Nim program. Only a subset of the Nim language is valid within a `parallel`
section. This subset is checked during semantic analysis to be free of data
races. A sophisticated `disjoint checker`:idx: ensures that no data races are
possible, even though shared memory is extensively supported!

The subset is in fact the full language with the following
restrictions / changes:

* `spawn` within a `parallel` section has special semantics.
* Every location of the form `a[i]`, `a[i..j]` and `dest` where
  `dest` is part of the pattern `dest = spawn f(...)` has to be
  provably disjoint. This is called the *disjoint check*.
* Every other complex location `loc` that is used in a spawned
  proc (`spawn f(loc)`) has to be immutable for the duration of
  the `parallel` section. This is called the *immutability check*. Currently
  it is not specified what exactly "complex location" means. We need to make
  this an optimization!
* Every array access has to be provably within bounds. This is called
  the *bounds check*.
* Slices are optimized so that no copy is performed. This optimization is not
  yet performed for ordinary slices outside of a `parallel` section.


Strict definitions and `out` parameters
=======================================

With `experimental: "strictDefs"` *every* local variable must be initialized explicitly before it can be used:

  ```nim
  {.experimental: "strictDefs".}

  proc test =
    var s: seq[string]
    s.add "abc" # invalid!

  ```

Needs to be written as:

  ```nim
  {.experimental: "strictDefs".}

  proc test =
    var s: seq[string] = @[]
    s.add "abc" # valid!

  ```

A control flow analysis is performed in order to prove that a variable has been written to
before it is used. Thus the following is valid:

  ```nim
  {.experimental: "strictDefs".}

  proc test(cond: bool) =
    var s: seq[string]
    if cond:
      s = @["y"]
    else:
      s = @[]
    s.add "abc" # valid!
  ```

In this example every path does set `s` to a value before it is used.

  ```nim
  {.experimental: "strictDefs".}

  proc test(cond: bool) =
    let s: seq[string]
    if cond:
      s = @["y"]
    else:
      s = @[]
  ```

With `experimental: "strictDefs"`, `let` statements are allowed to not have an initial value, but every path should set `s` to a value before it is used.


`out` parameters
----------------

An `out` parameter is like a `var` parameter but it must be written to before it can be used:

  ```nim
  proc myopen(f: out File; name: string): bool =
    f = default(File)
    result = open(f, name)
  ```

While it is usually the better style to use the return type in order to return results API and ABI
considerations might make this infeasible. Like for `var T` Nim maps `out T` to a hidden pointer.
For example POSIX's `stat` routine can be wrapped as:

  ```nim
  proc stat*(a1: cstring, a2: out Stat): cint {.importc, header: "<sys/stat.h>".}
  ```

When the implementation of a routine with output parameters is analysed, the compiler
checks that every path before the (implicit or explicit) return does set every output
parameter:

  ```nim
  proc p(x: out int; y: out string; cond: bool) =
    x = 4
    if cond:
      y = "abc"
    # error: not every path initializes 'y'
  ```


Out parameters and exception handling
-------------------------------------

The analysis should take exceptions into account (but currently does not):

  ```nim
  proc p(x: out int; y: out string; cond: bool) =
    x = canRaise(45)
    y = "abc" # <-- error: not every path initializes 'y'
  ```

Once the implementation takes exceptions into account it is easy enough to
use `outParam = default(typeof(outParam))` in the beginning of the proc body.

Out parameters and inheritance
------------------------------

It is not valid to pass an lvalue of a supertype to an `out T` parameter:

  ```nim
  type
    Superclass = object of RootObj
      a: int
    Subclass = object of Superclass
      s: string

  proc init(x: out Superclass) =
    x = Superclass(a: 8)

  var v: Subclass
  init v
  use v.s # the 's' field was never initialized!
  ```

However, in the future this could be allowed and provide a better way to write object
constructors that take inheritance into account.


**Note**: The implementation of "strict definitions" and "out parameters" is experimental but the concept
is solid and it is expected that eventually this mode becomes the default in later versions.


Strict case objects
===================

With `experimental: "strictCaseObjects"` *every* field access is checked to be valid at compile-time.
The field is within a `case` section of an `object`.

  ```nim
  {.experimental: "strictCaseObjects".}

  type
    Foo = object
      case b: bool
      of false:
        s: string
      of true:
        x: int

  var x = Foo(b: true, x: 4)
  case x.b
  of true:
    echo x.x # valid
  of false:
    echo "no"

  case x.b
  of false:
    echo x.x # error: field access outside of valid case branch: x.x
  of true:
    echo "no"

  ```

**Note**: The implementation of "strict case objects" is experimental but the concept
is solid and it is expected that eventually this mode becomes the default in later versions.


Quirky routines
===============

The default code generation strategy of exceptions under the ARC/ORC model is the so called
`--exceptions:goto` implementation. This implementation inserts a check after every call that
can potentially raise an exception. A typical instruction sequence for this on
for a x86 64 bit machine looks like:

  ```
  cmp DWORD PTR [rbx], 0
  je  .L1
  ```

This is a memory fetch followed by jump. (An ideal implementation would
use the carry flag and a single instruction like ``jc .L1``.)

This overhead might not be desired and depending on the semantics of the routine may not be required
either.
So it can be disabled via a `.quirky` annotation:

  ```nim
  proc wontRaise(x: int) {.quirky.} =
    if x != 0:
      # because of `quirky` this will continue even if `write` raised an IO exception:
      write x
      wontRaise(x-1)

  wontRaise 10

  ```

If the used exception model is not `--exceptions:goto` then the `quirky` pragma has no effect and is
ignored.

The `quirky` pragma can also be be pushed in order to affect a group of routines and whether
the compiler supports the pragma can be checked with `defined(nimHasQuirky)`:

  ```nim
  when defined(nimHasQuirky):
    {.push quirky: on.}

  proc doRaise() = raise newException(ValueError, "")

  proc f(): string = "abc"

  proc q(cond: bool) =
    if cond:
      doRaise()
    echo f()

  q(true)

  when defined(nimHasQuirky):
    {.pop.}
  ```

**Warning**: The `quirky` pragma only affects code generation, no check for validity is performed!


Threading under ARC/ORC
=======================

ARC/ORC supports a shared heap out of the box. This means that messages can be sent between
threads without copies. However, without copying the data there is an inherent danger of
data races. Data races are prevented at compile-time if it is enforced that
only **isolated** subgraphs can be sent around.


Isolation
---------

The standard library module `isolation.nim` provides a generic type `Isolated[T]` that
captures the important notion that nothing else can reference the graph that is wrapped
inside `Isolated[T]`. It is what a channel implementation should use in order to enforce
the freedom of data races:

  ```nim
  proc send*[T](c: var Channel[T]; msg: sink Isolated[T])
  proc recv*[T](c: var Channel[T]): T
    ## Note: Returns T, not Isolated[T] for convenience.

  proc recvIso*[T](c: var Channel[T]): Isolated[T]
    ## remembers the data is Isolated[T].
  ```

In order to create an `Isolated` graph one has to use either `isolate` or `unsafeIsolate`.
`unsafeIsolate` is as its name says unsafe and no checking is performed. It should be considered
to be as dangerous as a `cast` operation.


Construction must ensure that the invariant holds, namely that the wrapped `T`
is free of external aliases into it. `isolate` ensures this invariant. It is
inspired by Pony's `recover` construct:

  ```nim
  func isolate(x: sink T): Isolated[T] {.magic: "Isolate".}
  ```


As you can see, this is a new builtin because the check it performs on `x` is non-trivial:

If `T` does not contain a `ref` or `closure` type, it is isolated. Else the syntactic
structure of `x` is analyzed:

- Literals like `nil`, `4`, `"abc"` are isolated.
- A local variable or a routine parameter is isolated if either of these conditions is true:
  1. Its type is annotated with the `.sendable` pragma. Note `Isolated[T]` is annotated as
     `.sendable`.
  2. Its type contains the potentially dangerous `ref` and `proc {.closure}` types
     only in places that are protected via a `.sendable` container.

- An array constructor `[x...]` is isolated if every element `x` is isolated.
- An object constructor `Obj(x...)` is isolated if every element `x` is isolated.
- An `if` or `case` expression is isolated if all possible values the expression
  may return are isolated.
- A type conversion `C(x)` is isolated if `x` is isolated. Analogous for `cast`
  expressions.
- A function call `f(x...)` is isolated if `f` is `.noSideEffect` and for every argument `x`:
  - `x` is isolated **or**
  - `f`'s return type cannot *alias* `x`'s type. This is checked via a form of alias analysis as explained in the next paragraph.



Alias analysis
--------------

We start with an important, simple case that must be valid: Sending the result
of `parseJson` to a channel. Since the signature
is `func parseJson(input: string): JsonNode` it is easy to see that JsonNode
can never simply be a view into `input` which is a `string`.

A different case is the identity function `id`, `send id(myJsonGraph)` must be
invalid because we do not know how many aliases into `myJsonGraph` exist
elsewhere.

In general type `A` can alias type `T` if:

- `A` and `T` are the same types.
- `A` is a distinct type derived from `T`.
- `A` is a field inside `T` if `T` is a final object type.
- `T` is an inheritable object type. (An inherited type could always contain
  a `field: A`).
- `T` is a closure type. Reason: `T`'s environment can contain a field of
  type `A`.
- `A` is the element type of `T` if `T` is an array, sequence or pointer type.




Sendable pragma
---------------

A container type can be marked as `.sendable`. `.sendable` declares that the type
encapsulates a `ref` type effectively so that a variable of this container type
can be used in an `isolate` context:

  ```nim
  type
    Isolated*[T] {.sendable.} = object ## Isolated data can only be moved, not copied.
      value: T

  proc `=copy`*[T](dest: var Isolated[T]; src: Isolated[T]) {.error.}

  proc `=sink`*[T](dest: var Isolated[T]; src: Isolated[T]) {.inline.} =
    # delegate to value's sink operation
    `=sink`(dest.value, src.value)

  proc `=destroy`*[T](dest: var Isolated[T]) {.inline.} =
    # delegate to value's destroy operation
    `=destroy`(dest.value)
  ```

The `.sendable` pragma itself is an experimenal, unchecked, unsafe annotation. It is
currently only used by `Isolated[T]`.

Virtual pragma
==============

`virtual` is designed to extend or create virtual functions when targeting the cpp backend. When a proc is marked with virtual, it forward declares the proc header within the type's body.

Here's an example of how to use the virtual pragma:

```nim
proc newCpp*[T](): ptr T {.importcpp: "new '*0()".}
type
  Foo = object of RootObj
  FooPtr = ptr Foo
  Boo = object of Foo
  BooPtr = ptr Boo

proc salute(self: FooPtr) {.virtual.} =
  echo "hello foo"

proc salute(self: BooPtr) {.virtual.} =
  echo "hello boo"

let foo = newCpp[Foo]()
let boo = newCpp[Boo]()
let booAsFoo = cast[FooPtr](newCpp[Boo]())

foo.salute() # prints hello foo
boo.salute() # prints hello boo
booAsFoo.salute() # prints hello boo
```
In this example, the `salute` function is virtual in both Foo and Boo types. This allows for polymorphism.

The virtual pragma also supports a special syntax to express Cpp constraints. Here's how it works:

`$1` refers to the function name
`'idx` refers to the type of the argument at the position idx. Where idx = 1 is the `this` argument.
`#idx` refers to the argument name.

The return type can be referred to as `-> '0`, but this is optional and often not needed.

 ```nim
 {.emit:"""/*TYPESECTION*/
#include <iostream>
  class CppPrinter {
  public:

    virtual void printConst(char* message) const {
        std::cout << "Const Message: " << message << std::endl;
    }
    virtual void printConstRef(char* message, const int& flag) const {
        std::cout << "Const Ref Message: " << message << std::endl;
    }
};
""".}

type
  CppPrinter {.importcpp, inheritable.} = object
  NimPrinter {.exportc.} = object of CppPrinter

proc printConst(self: CppPrinter; message:cstring) {.importcpp.}
CppPrinter().printConst(message)

# override is optional.
proc printConst(self: NimPrinter; message: cstring) {.virtual: "$1('2 #2) const override".} =
  echo "NimPrinter: " & $message

proc printConstRef(self: NimPrinter; message: cstring; flag:int32) {.virtual: "$1('2 #2, const '3& #3 ) const override".} =
  echo "NimPrinterConstRef: " & $message

NimPrinter().printConst(message)
var val: int32 = 10
NimPrinter().printConstRef(message, val)

```

Constructor pragma
==================

The `constructor` pragma can be used in two ways: in conjunction with `importcpp` to import a C++ constructor, and to declare constructors that operate similarly to `virtual`.

Consider:

```nim
type Foo* = object
  x: int32

proc makeFoo(x: int32): Foo {.constructor.} =
  result.x = x
```

It forward declares the constructor in the type definition. When the constructor has parameters, it also generates a default constructor. One can avoid this behaviour by using `noDecl` in a default constructor.

Like `virtual`, `constructor` also supports a syntax that allows to express C++ constraints.

For example:

```nim
{.emit:"""/*TYPESECTION*/
struct CppClass {
  int x;
  int y;
  CppClass(int inX, int inY) {
    this->x = inX;
    this->y = inY;
  }
  //CppClass() = default;
};
""".}

type
  CppClass* {.importcpp, inheritable.} = object
    x: int32
    y: int32
  NimClass* = object of CppClass

proc makeNimClass(x: int32): NimClass {.constructor:"NimClass('1 #1) : CppClass(0, #1)".} =
  result.x = x

# Optional: define the default constructor explicitly
proc makeCppClass(): NimClass {.constructor: "NimClass() : CppClass(0, 0)".} =
  result.x = 1
```

In the example above `CppClass` has a deleted default constructor. Notice how by using the constructor syntax, one can call the appropriate constructor.

Notice when calling a constructor in the section of a global variable initialization, it will be called before `NimMain` meaning Nim is not fully initialized.

Constructor Initializer
=======================

By default Nim initializes `importcpp` types with `{}`. This can be problematic when importing
types with a deleted default constructor. In order to avoid this, one can specify default values for a constructor by specifying default values for the proc params in the `constructor` proc.

For example:

```nim

{.emit: """/*TYPESECTION*/
struct CppStruct {
  CppStruct(int x, char* y): x(x), y(y){}
  int x;
  char* y;
};
""".}
type
  CppStruct {.importcpp, inheritable.} = object

proc makeCppStruct(a: cint = 5, b:cstring = "hello"): CppStruct {.importcpp: "CppStruct(@)", constructor.}

(proc (s: CppStruct) = echo "hello")(makeCppStruct()) 
# If one removes a default value from the constructor and passes it to the call explicitly, the C++ compiler will complain.

```
Skip initializers in fields members
===================================

By using `noInit` in a type or field declaration, the compiler will skip the initializer. By doing so one can explicitly initialize those values in the constructor of the type owner.

For example:

```nim

{.emit: """/*TYPESECTION*/
  struct Foo {
    Foo(int a){};
  };
  struct Boo {
    Boo(int a){};
  };

  """.}

type 
  Foo {.importcpp.} = object
  Boo {.importcpp, noInit.} = object
  Test {.exportc.} = object
    foo {.noInit.}: Foo
    boo: Boo

proc makeTest(): Test {.constructor: "Test() : foo(10), boo(1)".} = 
  discard

proc main() = 
  var t = makeTest()

main()

```

Will produce: 

```cpp

struct Test {
	Foo foo; 
	Boo boo;
  N_LIB_PRIVATE N_NOCONV(, Test)(void);
};

```

Notice that without `noInit` it would produce `Foo foo {}` and `Boo boo {}`


Member pragma
=============

Like the `constructor` and `virtual` pragmas, the `member` pragma can be used to attach a procedure to a C++ type. It's more flexible than the `virtual` pragma in the sense that it accepts not only names but also operators and destructors.

For example:

```nim
proc print(s: cstring) {.importcpp: "printf(@)", header: "<stdio.h>".}

type
  Doo {.exportc.} = object
    test: int

proc memberProc(f: Doo) {.member.} = 
  echo $f.test

proc destructor(f: Doo) {.member: "~'1()", used.} = 
  print "destructing\n"

proc `==`(self, other: Doo): bool {.member: "operator==('2 const & #2) const -> '0".} = 
  self.test == other.test

let doo = Doo(test: 2)
doo.memberProc()
echo doo == Doo(test: 1)

```

Will print:
```
2
false
destructing
destructing
```

Notice how the C++ destructor is called automatically. Also notice the double implementation of `==` as an operator in Nim but also in C++. This is useful if you need the type to match some C++ `concept` or `trait` when interoping. 

A side effect of being able to declare C++ operators, is that you can now also create a
C++ functor to have seamless interop with C++ lambdas (syntactic sugar for functors).

For example:

```nim
type
  NimFunctor = object
    discard
proc invoke(f: NimFunctor; n: int) {.member: "operator ()('2 #2)".} = 
  echo "FunctorSupport!"

{.experimental: "callOperator".}
proc `()`(f: NimFunctor; n:int) {.importcpp: "#(@)" .} 
NimFunctor()(1)
```
Notice we use the overload of `()` to have the same semantics in Nim, but on the `importcpp` we import the functor as a function. 
This allows to easy interop with functions that accepts for example a `const` operator in its signature. 


Injected symbols in generic procs and templates
===============================================

With the experimental option `openSym`, captured symbols in generic routine and
template bodies may be replaced by symbols injected locally by templates/macros
at instantiation time. `bind` may be used to keep the captured symbols over the
injected ones regardless of enabling the options, but other methods like
renaming the captured symbols should be used instead so that the code is not
affected by context changes.

Since this change may affect runtime behavior, the experimental switch
`openSym` needs to be enabled; and a warning is given in the case where an
injected symbol would replace a captured symbol not bound by `bind` and
the experimental switch isn't enabled.

```nim
const value = "captured"
template foo(x: int, body: untyped): untyped =
  let value {.inject.} = "injected"
  body

proc old[T](): string =
  foo(123):
    return value # warning: a new `value` has been injected, use `bind` or turn on `experimental:openSym`
echo old[int]() # "captured"

template oldTempl(): string =
  block:
    foo(123):
      value # warning: a new `value` has been injected, use `bind` or turn on `experimental:openSym`
echo oldTempl() # "captured"

{.experimental: "openSym".}

proc bar[T](): string =
  foo(123):
    return value
assert bar[int]() == "injected" # previously it would be "captured"

proc baz[T](): string =
  bind value
  foo(123):
    return value
assert baz[int]() == "captured"

template barTempl(): string =
  block:
    foo(123):
      value
assert barTempl() == "injected" # previously it would be "captured"

template bazTempl(): string =
  bind value
  block:
    foo(123):
      value
assert bazTempl() == "captured"
```

This option also generates a new node kind `nnkOpenSym` which contains
exactly 1 `nnkSym` node. In the future this might be merged with a slightly
modified `nnkOpenSymChoice` node but macros that want to support the
experimental feature should still handle `nnkOpenSym`, as the node kind would
simply not be generated as opposed to being removed.

Another experimental switch `genericsOpenSym` exists that enables this behavior
at instantiation time, meaning templates etc can enable it specifically when
they are being called. However this does not generate `nnkOpenSym` nodes
(unless the other switch is enabled) and so doesn't reflect the regular
behavior of the switch.

```nim
const value = "captured"
template foo(x: int, body: untyped): untyped =
  let value {.inject.} = "injected"
  {.push experimental: "genericsOpenSym".}
  body
  {.pop.}

proc bar[T](): string =
  foo(123):
    return value
echo bar[int]() # "injected"

template barTempl(): string =
  block:
    var res: string
    foo(123):
      res = value
    res
assert barTempl() == "injected"
```


VTable for methods
==================

Methods now support implementations based on a VTable by using `--experimental:vtables`. Note that the option needs to enabled
globally. The virtual method table is stored in the type info of
an object, which is an array of function pointers.

```nim
method foo(x: Base, ...) {.base.}
method foo(x: Derived, ...) {.base.}
```

It roughly generates a dispatcher like

```nim
proc foo_dispatch(x: Base, ...) =
  x.typeinfo.vtable[method_index](x, ...) # method_index is the index of the sorted order of a method
```

Methods are required to be in the same module where their type has been defined.

```nim
# types.nim
type
  Base* = ref object
```

```nim
import types

method foo(x: Base) {.base.} = discard
```

It gives an error: method `foo` can be defined only in the same module with its type (Base).


asmSyntax pragma
================

The `asmSyntax` pragma is used to specify target inline assembler syntax in an `asm` statement.

It prevents compiling code with different of the target CC inline asm syntax, i.e. it will not allow gcc inline asm code to be compiled with vcc.

```nim
proc nothing() =
  asm {.asmSyntax: "gcc".}"""
    nop
  """
```

The current C(C++) backend implementation cannot generate code for gcc and for vcc at the same time. For example, `{.asmSyntax: "vcc".}` with the ICC compiler will not generate code with intel asm syntax, even though ICC can use both gcc-like and vcc-like asm.

Type-bound overloads
====================

With the experimental option `--experimental:typeBoundOps`, each "root"
nominal type (namely `object`, `enum`, `distinct`, direct `Foo = ref object`
types as well as their generic versions) can have operations attached to it.
Exported top-level routines declared in the same scope as a nominal type
with a parameter having a type directly deriving from that nominal type (i.e.
with `var`/`sink`/`typedesc` modifiers or being in a generic constraint)
are considered "attached" to the respective nominal type.
This applies to every parameter regardless of placement.

When a call to a symbol is openly overloaded and overload matching starts,
for all arguments in the call that have already undergone type checking,
routines with the same name attached to the root nominal type (if it exists)
of each given argument are added as a candidate to the overload match.
This also happens as arguments gradually get typed after every match to an overload.
This is so that the only overloads considered out of scope are
attached to the types of the given arguments, and that matches to
`untyped` or missing parameters are not influenced by outside overloads.

If no overloads with a given name are in scope, then overload matching
will not begin, and so type-bound overloads are not considered for that name.
Similarly, if the only overloads with a given name require a parameter to be
`untyped` or missing, then type-bound overloads will not be considered for
the argument in that position.
Generally this means that a "base" overload with a compliant signature should
be in scope so that type-bound overloads can be used.

In the case of ambiguity between distinct local/imported and type-bound symbols
in overload matching, type-bound symbols are considered as a less specific
scope than imports.

An example with the `hash` interface in the standard library is as follows:

```nim
# objs.nim
import std/hashes

type
  Obj* = object
    x*, y*: int
    z*: string # to be ignored for equality

proc `==`*(a, b: Obj): bool =
  a.x == b.x and a.y == b.y

proc hash*(a: Obj): Hash =
  $!(hash(a.x) &! hash(a.y))

# here both `==` and `hash` are attached to Obj
# 1. they are both exported
# 2. they are in the same scope as Obj
# 3. they have parameters with types directly deriving from Obj
# 4. Obj is nominal
```

```nim
# main.nim
{.experimental: "typeBoundOps".}
from objs import Obj # objs.hash, objs.`==` not imported
import std/tables
# tables use `hash`, only using the overloads in `std/hashes` and
# the ones in instantiation scope (in this case, there are none)

var t: Table[Obj, int]
# because tables use `hash` and `==` in a compliant way,
# the overloads bound to Obj are also considered, and in this case match best
t[Obj(x: 3, y: 4, z: "debug")] = 34
# if `hash` for all objects as in `std/hashes` was used, this would error: 
echo t[Obj(x: 3, y: 4, z: "ignored")] # 34
```

Another example, this time with `$` and indirect imports:

```nim
# foo.nim
type Foo* = object
  x*, y*: int

proc `$`*(f: Foo): string =
  "Foo(" & $f.x & ", " & $f.y & ")"
```

```nim
# bar.nim
import foo

proc makeFoo*(x, y: int): Foo =
  Foo(x: x, y: y)

proc useFoo*(f: Foo) =
  echo "used: ", f # directly calls `foo.$` from scope
```

```nim
# debugger.nim
proc debug*[T](obj: T) =
  echo "debugging: ", obj # calls generic `$`
```

```nim
# main.nim
{.experimental: "typeBoundOps".}
import bar, debugger # `foo` not imported, so `foo.$` not in scope

let f = makeFoo(123, 456)
useFoo(f) # used: Foo(123, 456)
debug(f) # debugging: Foo(123, 456)
```
