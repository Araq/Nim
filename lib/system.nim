#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#


## The compiler depends on the System module to work properly and the System
## module depends on the compiler. Most of the routines listed here use
## special compiler magic.
##
## Each module implicitly imports the System module; it must not be listed
## explicitly. Because of this there cannot be a user-defined module named
## `system`.
##
## System module
## =============
##
## .. include:: ./system_overview.rst


include "system/basic_types"

func zeroDefault*[T](_: typedesc[T]): T {.magic: "ZeroDefault".} =
  ## Returns the binary zeros representation of the type `T`. It ignores
  ## default fields of an object.
  ##
  ## See also:
  ## * `default <#default,typedesc[T]>`_

include "system/compilation"

{.push warning[GcMem]: off, warning[Uninit]: off.}
# {.push hints: off.}

type
  `static`*[T] {.magic: "Static".}
    ## Meta type representing all values that can be evaluated at compile-time.
    ##
    ## The type coercion `static(x)` can be used to force the compile-time
    ## evaluation of the given expression `x`.

  `type`*[T] {.magic: "Type".}
    ## Meta type representing the type of all type values.
    ##
    ## The coercion `type(x)` can be used to obtain the type of the given
    ## expression `x`.

type
  TypeOfMode* = enum ## Possible modes of `typeof`.
    typeOfProc,      ## Prefer the interpretation that means `x` is a proc call.
    typeOfIter       ## Prefer the interpretation that means `x` is an iterator call.

proc typeof*(x: untyped; mode = typeOfIter): typedesc {.
  magic: "TypeOf", noSideEffect, compileTime.} =
  ## Builtin `typeof` operation for accessing the type of an expression.
  ## Since version 0.20.0.
  runnableExamples:
    proc myFoo(): float = 0.0
    iterator myFoo(): string = yield "abc"
    iterator myFoo2(): string = yield "abc"
    iterator myFoo3(): string {.closure.} = yield "abc"
    doAssert type(myFoo()) is string
    doAssert typeof(myFoo()) is string
    doAssert typeof(myFoo(), typeOfIter) is string
    doAssert typeof(myFoo3) is iterator

    doAssert typeof(myFoo(), typeOfProc) is float
    doAssert typeof(0.0, typeOfProc) is float
    doAssert typeof(myFoo3, typeOfProc) is iterator
    doAssert not compiles(typeof(myFoo2(), typeOfProc))
      # this would give: Error: attempting to call routine: 'myFoo2'
      # since `typeOfProc` expects a typed expression and `myFoo2()` can
      # only be used in a `for` context.

proc `or`*(a, b: typedesc): typedesc {.magic: "TypeTrait", noSideEffect.}
  ## Constructs an `or` meta class.

proc `and`*(a, b: typedesc): typedesc {.magic: "TypeTrait", noSideEffect.}
  ## Constructs an `and` meta class.

proc `not`*(a: typedesc): typedesc {.magic: "TypeTrait", noSideEffect.}
  ## Constructs an `not` meta class.

when defined(nimHasIterable):
  type
    iterable*[T] {.magic: IterableType.}  ## Represents an expression that yields `T`

type
  Ordinal*[T] {.magic: Ordinal.} ## Generic ordinal type. Includes integer,
                                  ## bool, character, and enumeration types
                                  ## as well as their subtypes. See also
                                  ## `SomeOrdinal`.


proc `addr`*[T](x: T): ptr T {.magic: "Addr", noSideEffect.} =
  ## Builtin `addr` operator for taking the address of a memory location.
  ##
  ## .. note:: This works for `let` variables or parameters
  ##   for better interop with C. When you use it to write a wrapper
  ##   for a C library and take the address of `let` variables or parameters,
  ##   you should always check that the original library
  ##   does never write to data behind the pointer that is returned from
  ##   this procedure.
  ##
  ## Cannot be overloaded.
  ##
  ##   ```nim
  ##   var
  ##     buf: seq[char] = @['a','b','c']
  ##     p = buf[1].addr
  ##   echo p.repr # ref 0x7faa35c40059 --> 'b'
  ##   echo p[]    # b
  ##   ```
  discard

proc unsafeAddr*[T](x: T): ptr T {.magic: "Addr", noSideEffect.} =
  ## .. warning:: `unsafeAddr` is a deprecated alias for `addr`,
  ##    use `addr` instead.
  discard


const ThisIsSystem = true

const arcLikeMem = defined(gcArc) or defined(gcAtomicArc) or defined(gcOrc)

when defined(nimAllowNonVarDestructor) and arcLikeMem:
  proc new*[T](a: var ref T, finalizer: proc (x: T) {.nimcall.}) {.
    magic: "NewFinalize", noSideEffect.}
    ## Creates a new object of type `T` and returns a safe (traced)
    ## reference to it in `a`.
    ##
    ## When the garbage collector frees the object, `finalizer` is called.
    ## The `finalizer` may not keep a reference to the
    ## object pointed to by `x`. The `finalizer` cannot prevent the GC from
    ## freeing the object.
    ##
    ## **Note**: The `finalizer` refers to the type `T`, not to the object!
    ## This means that for each object of type `T` the finalizer will be called!

  proc new*[T](a: var ref T, finalizer: proc (x: ref T) {.nimcall.}) {.
    magic: "NewFinalize", noSideEffect, deprecated: "pass a finalizer of the 'proc (x: T) {.nimcall.}' type".}

else:
  proc new*[T](a: var ref T, finalizer: proc (x: ref T) {.nimcall.}) {.
    magic: "NewFinalize", noSideEffect.}
    ## Creates a new object of type `T` and returns a safe (traced)
    ## reference to it in `a`.
    ##
    ## When the garbage collector frees the object, `finalizer` is called.
    ## The `finalizer` may not keep a reference to the
    ## object pointed to by `x`. The `finalizer` cannot prevent the GC from
    ## freeing the object.
    ##
    ## **Note**: The `finalizer` refers to the type `T`, not to the object!
    ## This means that for each object of type `T` the finalizer will be called!

proc `=wasMoved`*[T](obj: var T) {.magic: "WasMoved", noSideEffect.} =
  ## Generic `wasMoved`:idx: implementation that can be overridden.

proc wasMoved*[T](obj: var T) {.inline, noSideEffect.} =
  ## Resets an object `obj` to its initial (binary zero) value to signify
  ## it was "moved" and to signify its destructor should do nothing and
  ## ideally be optimized away.
  {.cast(raises: []), cast(tags: []).}:
    `=wasMoved`(obj)

proc move*[T](x: var T): T {.magic: "Move", noSideEffect.} =
  result = x
  {.cast(raises: []), cast(tags: []).}:
    `=wasMoved`(x)

when defined(nimHasEnsureMove):
  proc ensureMove*[T](x: T): T {.magic: "EnsureMove", noSideEffect.} =
    ## Ensures that `x` is moved to the new location, otherwise it gives
    ## an error at the compile time.
    runnableExamples:
      proc foo =
        var x = "Hello"
        let y = ensureMove(x)
        doAssert y == "Hello"
      foo()
    discard "implemented in injectdestructors"

type
  range*[T]{.magic: "Range".}         ## Generic type to construct range types.
  array*[I, T]{.magic: "Array".}      ## Generic type to construct
                                      ## fixed-length arrays.
  openArray*[T]{.magic: "OpenArray".} ## Generic type to construct open arrays.
                                      ## Open arrays are implemented as a
                                      ## pointer to the array data and a
                                      ## length field.
  varargs*[T]{.magic: "Varargs".}     ## Generic type to construct a varargs type.
  seq*[T]{.magic: "Seq".}             ## Generic type to construct sequences.
  set*[T]{.magic: "Set".}             ## Generic type to construct bit sets.

type
  UncheckedArray*[T]{.magic: "UncheckedArray".}
  ## Array with no bounds checking.

type sink*[T]{.magic: "BuiltinType".}
type lent*[T]{.magic: "BuiltinType".}

proc high*[T: Ordinal|enum|range](x: T): T {.magic: "High", noSideEffect,
  deprecated: "Deprecated since v1.4; there should not be `high(value)`. Use `high(type)`.".}
  ## Returns the highest possible value of an ordinal value `x`.
  ##
  ## As a special semantic rule, `x` may also be a type identifier.
  ##
  ## **This proc is deprecated**, use this one instead:
  ## * `high(typedesc) <#high,typedesc[T]>`_
  ##
  ## ```nim
  ## high(2) # => 9223372036854775807
  ## ```

proc high*[T: Ordinal|enum|range](x: typedesc[T]): T {.magic: "High", noSideEffect.}
  ## Returns the highest possible value of an ordinal or enum type.
  ##
  ## `high(int)` is Nim's way of writing `INT_MAX`:idx: or `MAX_INT`:idx:.
  ##   ```nim
  ##   high(int) # => 9223372036854775807
  ##   ```
  ##
  ## See also:
  ## * `low(typedesc) <#low,typedesc[T]>`_

proc high*[T](x: openArray[T]): int {.magic: "High", noSideEffect.}
  ## Returns the highest possible index of a sequence `x`.
  ##   ```nim
  ##   var s = @[1, 2, 3, 4, 5, 6, 7]
  ##   high(s) # => 6
  ##   for i in low(s)..high(s):
  ##     echo s[i]
  ##   ```
  ##
  ## See also:
  ## * `low(openArray) <#low,openArray[T]>`_

proc high*[I, T](x: array[I, T]): I {.magic: "High", noSideEffect.}
  ## Returns the highest possible index of an array `x`.
  ##
  ## For empty arrays, the return type is `int`.
  ##   ```nim
  ##   var arr = [1, 2, 3, 4, 5, 6, 7]
  ##   high(arr) # => 6
  ##   for i in low(arr)..high(arr):
  ##     echo arr[i]
  ##   ```
  ##
  ## See also:
  ## * `low(array) <#low,array[I,T]>`_

proc high*[I, T](x: typedesc[array[I, T]]): I {.magic: "High", noSideEffect.}
  ## Returns the highest possible index of an array type.
  ##
  ## For empty arrays, the return type is `int`.
  ##   ```nim
  ##   high(array[7, int]) # => 6
  ##   ```
  ##
  ## See also:
  ## * `low(typedesc[array]) <#low,typedesc[array[I,T]]>`_

proc high*(x: cstring): int {.magic: "High", noSideEffect.}
  ## Returns the highest possible index of a compatible string `x`.
  ## This is sometimes an O(n) operation.
  ##
  ## See also:
  ## * `low(cstring) <#low,cstring>`_

proc high*(x: string): int {.magic: "High", noSideEffect.}
  ## Returns the highest possible index of a string `x`.
  ##   ```nim
  ##   var str = "Hello world!"
  ##   high(str) # => 11
  ##   ```
  ##
  ## See also:
  ## * `low(string) <#low,string>`_

proc low*[T: Ordinal|enum|range](x: T): T {.magic: "Low", noSideEffect,
  deprecated: "Deprecated since v1.4; there should not be `low(value)`. Use `low(type)`.".}
  ## Returns the lowest possible value of an ordinal value `x`. As a special
  ## semantic rule, `x` may also be a type identifier.
  ##
  ## **This proc is deprecated**, use this one instead:
  ## * `low(typedesc) <#low,typedesc[T]>`_
  ##
  ## ```nim
  ## low(2) # => -9223372036854775808
  ## ```

proc low*[T: Ordinal|enum|range](x: typedesc[T]): T {.magic: "Low", noSideEffect.}
  ## Returns the lowest possible value of an ordinal or enum type.
  ##
  ## `low(int)` is Nim's way of writing `INT_MIN`:idx: or `MIN_INT`:idx:.
  ##   ```nim
  ##   low(int) # => -9223372036854775808
  ##   ```
  ##
  ## See also:
  ## * `high(typedesc) <#high,typedesc[T]>`_

proc low*[T](x: openArray[T]): int {.magic: "Low", noSideEffect.}
  ## Returns the lowest possible index of a sequence `x`.
  ##   ```nim
  ##   var s = @[1, 2, 3, 4, 5, 6, 7]
  ##   low(s) # => 0
  ##   for i in low(s)..high(s):
  ##     echo s[i]
  ##   ```
  ##
  ## See also:
  ## * `high(openArray) <#high,openArray[T]>`_

proc low*[I, T](x: array[I, T]): I {.magic: "Low", noSideEffect.}
  ## Returns the lowest possible index of an array `x`.
  ##
  ## For empty arrays, the return type is `int`.
  ##   ```nim
  ##   var arr = [1, 2, 3, 4, 5, 6, 7]
  ##   low(arr) # => 0
  ##   for i in low(arr)..high(arr):
  ##     echo arr[i]
  ##   ```
  ##
  ## See also:
  ## * `high(array) <#high,array[I,T]>`_

proc low*[I, T](x: typedesc[array[I, T]]): I {.magic: "Low", noSideEffect.}
  ## Returns the lowest possible index of an array type.
  ##
  ## For empty arrays, the return type is `int`.
  ##   ```nim
  ##   low(array[7, int]) # => 0
  ##   ```
  ##
  ## See also:
  ## * `high(typedesc[array]) <#high,typedesc[array[I,T]]>`_

proc low*(x: cstring): int {.magic: "Low", noSideEffect.}
  ## Returns the lowest possible index of a compatible string `x`.
  ##
  ## See also:
  ## * `high(cstring) <#high,cstring>`_

proc low*(x: string): int {.magic: "Low", noSideEffect.}
  ## Returns the lowest possible index of a string `x`.
  ##   ```nim
  ##   var str = "Hello world!"
  ##   low(str) # => 0
  ##   ```
  ##
  ## See also:
  ## * `high(string) <#high,string>`_

when not defined(gcArc) and not defined(gcOrc) and not defined(gcAtomicArc):
  proc shallowCopy*[T](x: var T, y: T) {.noSideEffect, magic: "ShallowCopy".}
    ## Use this instead of `=` for a `shallow copy`:idx:.
    ##
    ## The shallow copy only changes the semantics for sequences and strings
    ## (and types which contain those).
    ##
    ## Be careful with the changed semantics though!
    ## There is a reason why the default assignment does a deep copy of sequences
    ## and strings.

# :array|openArray|string|seq|cstring|tuple
proc `[]`*[I: Ordinal;T](a: T; i: I): T {.
  noSideEffect, magic: "ArrGet".}
proc `[]=`*[I: Ordinal;T,S](a: T; i: I;
  x: sink S) {.noSideEffect, magic: "ArrPut".}
proc `=`*[T](dest: var T; src: T) {.noSideEffect, magic: "Asgn".}
proc `=copy`*[T](dest: var T; src: T) {.noSideEffect, magic: "Asgn".}

proc arrGet[I: Ordinal;T](a: T; i: I): T {.
  noSideEffect, magic: "ArrGet".}
proc arrPut[I: Ordinal;T,S](a: T; i: I;
  x: S) {.noSideEffect, magic: "ArrPut".}


when defined(nimAllowNonVarDestructor) and arcLikeMem and defined(nimPreviewNonVarDestructor):
  proc `=destroy`*[T](x: T) {.inline, magic: "Destroy".} =
    ## Generic `destructor`:idx: implementation that can be overridden.
    discard
else:
  proc `=destroy`*[T](x: var T) {.inline, magic: "Destroy".} =
    ## Generic `destructor`:idx: implementation that can be overridden.
    discard

  when defined(nimAllowNonVarDestructor) and arcLikeMem:
    proc `=destroy`*(x: string) {.inline, magic: "Destroy", enforceNoRaises.} =
      discard

    proc `=destroy`*[T](x: seq[T]) {.inline, magic: "Destroy".} =
      discard

    proc `=destroy`*[T](x: ref T) {.inline, magic: "Destroy".} =
      discard

when defined(nimHasDup):
  proc `=dup`*[T](x: T): T {.inline, magic: "Dup".} =
    ## Generic `dup`:idx: implementation that can be overridden.
    discard

proc `=sink`*[T](x: var T; y: T) {.inline, nodestroy, magic: "Asgn".} =
  ## Generic `sink`:idx: implementation that can be overridden.
  when defined(gcArc) or defined(gcOrc) or defined(gcAtomicArc):
    x = y
  else:
    shallowCopy(x, y)

when defined(nimHasTrace):
  proc `=trace`*[T](x: var T; env: pointer) {.inline, magic: "Trace".} =
    ## Generic `trace`:idx: implementation that can be overridden.
    discard

type
  HSlice*[T, U] = object   ## "Heterogeneous" slice type.
    a*: T                  ## The lower bound (inclusive).
    b*: U                  ## The upper bound (inclusive).
  Slice*[T] = HSlice[T, T] ## An alias for `HSlice[T, T]`.

proc `..`*[T, U](a: sink T, b: sink U): HSlice[T, U] {.noSideEffect, inline, magic: "DotDot".} =
  ## Binary `slice`:idx: operator that constructs an interval `[a, b]`, both `a`
  ## and `b` are inclusive.
  ##
  ## Slices can also be used in the set constructor and in ordinal case
  ## statements, but then they are special-cased by the compiler.
  ##   ```nim
  ##   let a = [10, 20, 30, 40, 50]
  ##   echo a[2 .. 3] # @[30, 40]
  ##   ```
  result = HSlice[T, U](a: a, b: b)

proc `..`*[T](b: sink T): HSlice[int, T]
  {.noSideEffect, inline, magic: "DotDot", deprecated: "replace `..b` with `0..b`".} =
  ## Unary `slice`:idx: operator that constructs an interval `[default(int), b]`.
  ##   ```nim
  ##   let a = [10, 20, 30, 40, 50]
  ##   echo a[.. 2] # @[10, 20, 30]
  ##   ```
  result = HSlice[int, T](a: 0, b: b)

when defined(hotCodeReloading):
  {.pragma: hcrInline, inline.}
else:
  {.pragma: hcrInline.}

include "system/arithmetics"
include "system/comparisons"

const
  appType* {.magic: "AppType".}: string = ""
    ## A string that describes the application type. Possible values:
    ## `"console"`, `"gui"`, `"lib"`.

include "system/inclrtl"

const NoFakeVars = defined(nimscript) ## `true` if the backend doesn't support \
  ## "fake variables" like `var EBADF {.importc.}: cint`.

const notJSnotNims = not defined(js) and not defined(nimscript)

when not defined(js) and not defined(nimSeqsV2):
  type
    TGenericSeq {.compilerproc, pure, inheritable.} = object
      len, reserved: int
      when defined(gogc):
        elemSize: int
        elemAlign: int
    PGenericSeq {.exportc.} = ptr TGenericSeq
    # len and space without counting the terminating zero:
    NimStringDesc {.compilerproc, final.} = object of TGenericSeq
      data: UncheckedArray[char]
    NimString = ptr NimStringDesc

when notJSnotNims:
  include "system/hti"

type
  byte* = uint8 ## This is an alias for `uint8`, that is an unsigned
                ## integer, 8 bits wide.

  Natural* = range[0..high(int)]
    ## is an `int` type ranging from zero to the maximum value
    ## of an `int`. This type is often useful for documentation and debugging.

  Positive* = range[1..high(int)]
    ## is an `int` type ranging from one to the maximum value
    ## of an `int`. This type is often useful for documentation and debugging.

type
  RootObj* {.compilerproc, inheritable.} =
    object ## The root of Nim's object hierarchy.
           ##
           ## Objects should inherit from `RootObj` or one of its descendants.
           ## However, objects that have no ancestor are also allowed.
  RootRef* = ref RootObj ## Reference to `RootObj`.

const NimStackTraceMsgs = compileOption("stacktraceMsgs")

type
  RootEffect* {.compilerproc.} = object of RootObj ## \
    ## Base effect class.
    ##
    ## Each effect should inherit from `RootEffect` unless you know what
    ## you're doing.

type
  StackTraceEntry* = object ## In debug mode exceptions store the stack trace that led
                            ## to them. A `StackTraceEntry` is a single entry of the
                            ## stack trace.
    procname*: cstring      ## Name of the proc that is currently executing.
    line*: int              ## Line number of the proc that is currently executing.
    filename*: cstring      ## Filename of the proc that is currently executing.
    when NimStackTraceMsgs:
      frameMsg*: string     ## When a stacktrace is generated in a given frame and
                            ## rendered at a later time, we should ensure the stacktrace
                            ## data isn't invalidated; any pointer into PFrame is
                            ## subject to being invalidated so shouldn't be stored.
    when defined(nimStackTraceOverride):
      programCounter*: uint ## Program counter - will be used to get the rest of the info,
                            ## when `$` is called on this type. We can't use
                            ## "cuintptr_t" in here.
      procnameStr*, filenameStr*: string ## GC-ed alternatives to "procname" and "filename"

  Exception* {.compilerproc, magic: "Exception".} = object of RootObj ## \
    ## Base exception class.
    ##
    ## Each exception has to inherit from `Exception`. See the full `exception
    ## hierarchy <manual.html#exception-handling-exception-hierarchy>`_.
    parent*: ref Exception ## Parent exception (can be used as a stack).
    name*: cstring         ## The exception's name is its Nim identifier.
                           ## This field is filled automatically in the
                           ## `raise` statement.
    msg* {.exportc: "message".}: string ## The exception's message. Not
                                        ## providing an exception message
                                        ## is bad style.
    when defined(js):
      trace*: string
    else:
      trace*: seq[StackTraceEntry]
    up: ref Exception # used for stacking exceptions. Not exported!

  Defect* = object of Exception ## \
    ## Abstract base class for all exceptions that Nim's runtime raises
    ## but that are strictly uncatchable as they can also be mapped to
    ## a `quit` / `trap` / `exit` operation.

  CatchableError* = object of Exception ## \
    ## Abstract class for all exceptions that are catchable.

when defined(nimIcIntegrityChecks):
  include "system/exceptions"
else:
  import system/exceptions
  export exceptions

when defined(js) or defined(nimdoc):
  type
    JsRoot* = ref object of RootObj
      ## Root type of the JavaScript object hierarchy

proc unsafeNew*[T](a: var ref T, size: Natural) {.magic: "New", noSideEffect.}
  ## Creates a new object of type `T` and returns a safe (traced)
  ## reference to it in `a`.
  ##
  ## This is **unsafe** as it allocates an object of the passed `size`.
  ## This should only be used for optimization purposes when you know
  ## what you're doing!
  ##
  ## See also:
  ## * `new <#new,ref.T,proc(ref.T)>`_

proc sizeof*[T](x: T): int {.magic: "SizeOf", noSideEffect.}
  ## Returns the size of `x` in bytes.
  ##
  ## Since this is a low-level proc,
  ## its usage is discouraged - using `new <#new,ref.T,proc(ref.T)>`_ for
  ## the most cases suffices that one never needs to know `x`'s size.
  ##
  ## As a special semantic rule, `x` may also be a type identifier
  ## (`sizeof(int)` is valid).
  ##
  ## Limitations: If used for types that are imported from C or C++,
  ## sizeof should fallback to the `sizeof` in the C compiler. The
  ## result isn't available for the Nim compiler and therefore can't
  ## be used inside of macros.
  ##   ```nim
  ##   sizeof('A') # => 1
  ##   sizeof(2) # => 8
  ##   ```

proc alignof*[T](x: T): int {.magic: "AlignOf", noSideEffect.}
proc alignof*(x: typedesc): int {.magic: "AlignOf", noSideEffect.}

proc offsetOfDotExpr(typeAccess: typed): int {.magic: "OffsetOf", noSideEffect, compileTime.}

template offsetOf*[T](t: typedesc[T]; member: untyped): int =
  var tmp {.noinit.}: ptr T
  offsetOfDotExpr(tmp[].member)

template offsetOf*[T](value: T; member: untyped): int =
  offsetOfDotExpr(value.member)

#proc offsetOf*(memberaccess: typed): int {.magic: "OffsetOf", noSideEffect.}

proc sizeof*(x: typedesc): int {.magic: "SizeOf", noSideEffect.}


proc newSeq*[T](s: var seq[T], len: Natural) {.magic: "NewSeq", noSideEffect.}
  ## Creates a new sequence of type `seq[T]` with length `len`.
  ##
  ## This is equivalent to `s = @[]; setlen(s, len)`, but more
  ## efficient since no reallocation is needed.
  ##
  ## Note that the sequence will be filled with zeroed entries.
  ## After the creation of the sequence you should assign entries to
  ## the sequence instead of adding them. Example:
  ##   ```nim
  ##   var inputStrings: seq[string]
  ##   newSeq(inputStrings, 3)
  ##   assert len(inputStrings) == 3
  ##   inputStrings[0] = "The fourth"
  ##   inputStrings[1] = "assignment"
  ##   inputStrings[2] = "would crash"
  ##   #inputStrings[3] = "out of bounds"
  ##   ```

proc newSeq*[T](len = 0.Natural): seq[T] =
  ## Creates a new sequence of type `seq[T]` with length `len`.
  ##
  ## Note that the sequence will be filled with zeroed entries.
  ## After the creation of the sequence you should assign entries to
  ## the sequence instead of adding them.
  ##   ```nim
  ##   var inputStrings = newSeq[string](3)
  ##   assert len(inputStrings) == 3
  ##   inputStrings[0] = "The fourth"
  ##   inputStrings[1] = "assignment"
  ##   inputStrings[2] = "would crash"
  ##   #inputStrings[3] = "out of bounds"
  ##   ```
  ##
  ## See also:
  ## * `newSeqOfCap <#newSeqOfCap,Natural>`_
  ## * `newSeqUninit <#newSeqUninit,Natural>`_
  newSeq(result, len)

proc newSeqOfCap*[T](cap: Natural): seq[T] {.
  magic: "NewSeqOfCap", noSideEffect.} =
  ## Creates a new sequence of type `seq[T]` with length zero and capacity
  ## `cap`. Example:
  ##   ```nim
  ##   var x = newSeqOfCap[int](5)
  ##   assert len(x) == 0
  ##   x.add(10)
  ##   assert len(x) == 1
  ##   ```
  discard

func len*[TOpenArray: openArray|varargs](x: TOpenArray): int {.magic: "LengthOpenArray".} =
  ## Returns the length of an openArray.
  runnableExamples:
    proc bar[T](a: openArray[T]): int = len(a)
    assert bar([1,2]) == 2
    assert [1,2].len == 2

func len*(x: string): int {.magic: "LengthStr".} =
  ## Returns the length of a string.
  runnableExamples:
    assert "abc".len == 3
    assert "".len == 0
    assert string.default.len == 0

proc len*(x: cstring): int {.magic: "LengthStr", noSideEffect.} =
  ## Returns the length of a compatible string. This is an O(n) operation except
  ## in js at runtime.
  ##
  ## **Note:** On the JS backend this currently counts UTF-16 code points
  ## instead of bytes at runtime (not at compile time). For now, if you
  ## need the byte length of the UTF-8 encoding, convert to string with
  ## `$` first then call `len`.
  runnableExamples:
    doAssert len(cstring"abc") == 3
    doAssert len(cstring r"ab\0c") == 5 # \0 is escaped
    doAssert len(cstring"ab\0c") == 5 # ditto
    var a: cstring = "ab\0c"
    when defined(js): doAssert a.len == 4 # len ignores \0 for js
    else: doAssert a.len == 2 # \0 is a null terminator
    static:
      var a2: cstring = "ab\0c"
      doAssert a2.len == 2 # \0 is a null terminator, even in js vm

func len*(x: (type array)|array): int {.magic: "LengthArray".} =
  ## Returns the length of an array or an array type.
  ## This is roughly the same as `high(T)-low(T)+1`.
  runnableExamples:
    var a = [1, 1, 1]
    assert a.len == 3
    assert array[0, float].len == 0
    static: assert array[-2..2, float].len == 5

func len*[T](x: seq[T]): int {.magic: "LengthSeq".} =
  ## Returns the length of `x`.
  runnableExamples:
    assert @[0, 1].len == 2
    assert seq[int].default.len == 0
    assert newSeq[int](3).len == 3
    let s = newSeqOfCap[int](3)
    assert s.len == 0
  # xxx this gives cgen error: assert newSeqOfCap[int](3).len == 0

func ord*[T: Ordinal|enum](x: T): int {.magic: "Ord".} =
  ## Returns the internal `int` value of `x`, including for enum with holes
  ## and distinct ordinal types.
  runnableExamples:
    assert ord('A') == 65
    type Foo = enum
      f0 = 0, f1 = 3
    assert f1.ord == 3
    type Bar = distinct int
    assert 3.Bar.ord == 3

func chr*(u: range[0..255]): char {.magic: "Chr".} =
  ## Converts `u` to a `char`, same as `char(u)`.
  runnableExamples:
    doAssert chr(65) == 'A'
    doAssert chr(255) == '\255'
    doAssert chr(255) == char(255)
    doAssert not compiles chr(256)
    doAssert not compiles char(256)
    var x = 256
    doAssertRaises(RangeDefect): discard chr(x)
    doAssertRaises(RangeDefect): discard char(x)


include "system/setops"


proc contains*[U, V, W](s: HSlice[U, V], value: W): bool {.noSideEffect, inline.} =
  ## Checks if `value` is within the range of `s`; returns true if
  ## `value >= s.a and value <= s.b`.
  ##   ```nim
  ##   assert((1..3).contains(1) == true)
  ##   assert((1..3).contains(2) == true)
  ##   assert((1..3).contains(4) == false)
  ##   ```
  result = s.a <= value and value <= s.b

when not defined(nimHasCallsitePragma):
  {.pragma: callsite.}

template `in`*(x, y: untyped): untyped {.dirty, callsite.} = contains(y, x)
  ## Sugar for `contains`.
  ##   ```nim
  ##   assert(1 in (1..3) == true)
  ##   assert(5 in (1..3) == false)
  ##   ```
template `notin`*(x, y: untyped): untyped {.dirty, callsite.} = not contains(y, x)
  ## Sugar for `not contains`.
  ##   ```nim
  ##   assert(1 notin (1..3) == false)
  ##   assert(5 notin (1..3) == true)
  ##   ```

proc `is`*[T, S](x: T, y: S): bool {.magic: "Is", noSideEffect.}
  ## Checks if `T` is of the same type as `S`.
  ##
  ## For a negated version, use `isnot <#isnot.t,untyped,untyped>`_.
  ##
  ##   ```nim
  ##   assert 42 is int
  ##   assert @[1, 2] is seq
  ##
  ##   proc test[T](a: T): int =
  ##     when (T is int):
  ##       return a
  ##     else:
  ##       return 0
  ##
  ##   assert(test[int](3) == 3)
  ##   assert(test[string]("xyz") == 0)
  ##   ```
template `isnot`*(x, y: untyped): untyped {.callsite.} = not (x is y)
  ## Negated version of `is <#is,T,S>`_. Equivalent to `not(x is y)`.
  ##   ```nim
  ##   assert 42 isnot float
  ##   assert @[1, 2] isnot enum
  ##   ```

when (defined(nimOwnedEnabled) and not defined(nimscript)) or defined(nimFixedOwned):
  type owned*[T]{.magic: "BuiltinType".} ## type constructor to mark a ref/ptr or a closure as `owned`.
else:
  template owned*(t: typedesc): typedesc = t

when defined(nimOwnedEnabled) and not defined(nimscript):
  proc new*[T](a: var owned(ref T)) {.magic: "New", noSideEffect.}
    ## Creates a new object of type `T` and returns a safe (traced)
    ## reference to it in `a`.

  proc new*(t: typedesc): auto =
    ## Creates a new object of type `T` and returns a safe (traced)
    ## reference to it as result value.
    ##
    ## When `T` is a ref type then the resulting type will be `T`,
    ## otherwise it will be `ref T`.
    when (t is ref):
      var r: owned t
    else:
      var r: owned(ref t)
    new(r)
    return r

  proc unown*[T](x: T): T {.magic: "Unown", noSideEffect.}
    ## Use the expression `x` ignoring its ownership attribute.


else:
  template unown*(x: typed): untyped = x

  proc new*[T](a: var ref T) {.magic: "New", noSideEffect.}
    ## Creates a new object of type `T` and returns a safe (traced)
    ## reference to it in `a`.

  proc new*(t: typedesc): auto =
    ## Creates a new object of type `T` and returns a safe (traced)
    ## reference to it as result value.
    ##
    ## When `T` is a ref type then the resulting type will be `T`,
    ## otherwise it will be `ref T`.
    when (t is ref):
      var r: t
    else:
      var r: ref t
    new(r)
    return r


template disarm*(x: typed) =
  ## Useful for `disarming` dangling pointers explicitly for `--newruntime`.
  ## Regardless of whether `--newruntime` is used or not
  ## this sets the pointer or callback `x` to `nil`. This is an
  ## experimental API!
  x = nil

proc `of`*[T, S](x: T, y: typedesc[S]): bool {.magic: "Of", noSideEffect.} =
  ## Checks if `x` is an instance of `y`.
  runnableExamples:
    type
      Base = ref object of RootObj
      Sub1 = ref object of Base
      Sub2 = ref object of Base
      Unrelated = ref object

    var base: Base = Sub1() # downcast
    doAssert base of Base # generates `CondTrue` (statically true)
    doAssert base of Sub1
    doAssert base isnot Sub1
    doAssert not (base of Sub2)

    base = Sub2() # re-assign
    doAssert base of Sub2
    doAssert Sub2(base) != nil # upcast
    doAssertRaises(ObjectConversionDefect): discard Sub1(base)

    var sub1 = Sub1()
    doAssert sub1 of Base
    doAssert sub1.Base of Sub1

    doAssert not compiles(base of Unrelated)

proc cmp*[T](x, y: T): int =
  ## Generic compare proc.
  ##
  ## Returns:
  ## * a value less than zero, if `x < y`
  ## * a value greater than zero, if `x > y`
  ## * zero, if `x == y`
  ##
  ## This is useful for writing generic algorithms without performance loss.
  ## This generic implementation uses the `==` and `<` operators.
  ##   ```nim
  ##   import std/algorithm
  ##   echo sorted(@[4, 2, 6, 5, 8, 7], cmp[int])
  ##   ```
  if x == y: return 0
  if x < y: return -1
  return 1

proc cmp*(x, y: string): int {.noSideEffect.}
  ## Compare proc for strings. More efficient than the generic version.
  ##
  ## **Note**: The precise result values depend on the used C runtime library and
  ## can differ between operating systems!

proc `@`* [IDX, T](a: sink array[IDX, T]): seq[T] {.magic: "ArrToSeq", noSideEffect.}
  ## Turns an array into a sequence.
  ##
  ## This most often useful for constructing
  ## sequences with the array constructor: `@[1, 2, 3]` has the type
  ## `seq[int]`, while `[1, 2, 3]` has the type `array[0..2, int]`.
  ##
  ##   ```nim
  ##   let
  ##     a = [1, 3, 5]
  ##     b = "foo"
  ##
  ##   echo @a # => @[1, 3, 5]
  ##   echo @b # => @['f', 'o', 'o']
  ##   ```

proc default*[T](_: typedesc[T]): T {.magic: "Default", noSideEffect.} =
  ## Returns the default value of the type `T`. Contrary to `zeroDefault`, it takes default fields
  ## of an object into consideration.
  ##
  ## See also:
  ## * `zeroDefault <#zeroDefault,typedesc[T]>`_
  ##
  runnableExamples("-d:nimPreviewRangeDefault"):
    assert (int, float).default == (0, 0.0)
    type Foo = object
      a: range[2..6]
    var x = Foo.default
    assert x.a == 2


proc reset*[T](obj: var T) {.noSideEffect.} =
  ## Resets an object `obj` to its default value.
  when nimvm:
    obj = default(typeof(obj))
  else:
    when defined(gcDestructors):
      {.cast(noSideEffect), cast(raises: []), cast(tags: []).}:
        `=destroy`(obj)
        `=wasMoved`(obj)
    else:
      obj = default(typeof(obj))

proc setLen*[T](s: var seq[T], newlen: Natural) {.
  magic: "SetLengthSeq", noSideEffect, nodestroy.}
  ## Sets the length of seq `s` to `newlen`. `T` may be any sequence type.
  ##
  ## If the current length is greater than the new length,
  ## `s` will be truncated.
  ##   ```nim
  ##   var x = @[10, 20]
  ##   x.setLen(5)
  ##   x[4] = 50
  ##   assert x == @[10, 20, 0, 0, 50]
  ##   x.setLen(1)
  ##   assert x == @[10]
  ##   ```

proc setLen*(s: var string, newlen: Natural) {.
  magic: "SetLengthStr", noSideEffect.}
  ## Sets the length of string `s` to `newlen`.
  ##
  ## If the current length is greater than the new length,
  ## `s` will be truncated.
  ##   ```nim
  ##   var myS = "Nim is great!!"
  ##   myS.setLen(3) # myS <- "Nim"
  ##   echo myS, " is fantastic!!"
  ##   ```

proc newString*(len: Natural): string {.
  magic: "NewString", importc: "mnewString", noSideEffect.}
  ## Returns a new string of length `len`.
  ## One needs to fill the string character after character
  ## with the index operator `s[i]`.
  ##
  ## This procedure exists only for optimization purposes;
  ## the same effect can be achieved with the `&` operator or with `add`.

proc newStringOfCap*(cap: Natural): string {.
  magic: "NewStringOfCap", importc: "rawNewString", noSideEffect.}
  ## Returns a new string of length `0` but with capacity `cap`.
  ##
  ## This procedure exists only for optimization purposes; the same effect can
  ## be achieved with the `&` operator or with `add`.

proc `&`*(x: string, y: char): string {.
  magic: "ConStrStr", noSideEffect.}
  ## Concatenates `x` with `y`.
  ##   ```nim
  ##   assert("ab" & 'c' == "abc")
  ##   ```
proc `&`*(x, y: char): string {.
  magic: "ConStrStr", noSideEffect.}
  ## Concatenates characters `x` and `y` into a string.
  ##   ```nim
  ##   assert('a' & 'b' == "ab")
  ##   ```
proc `&`*(x, y: string): string {.
  magic: "ConStrStr", noSideEffect.}
  ## Concatenates strings `x` and `y`.
  ##   ```nim
  ##   assert("ab" & "cd" == "abcd")
  ##   ```
proc `&`*(x: char, y: string): string {.
  magic: "ConStrStr", noSideEffect.}
  ## Concatenates `x` with `y`.
  ##   ```nim
  ##   assert('a' & "bc" == "abc")
  ##   ```

# implementation note: These must all have the same magic value "ConStrStr" so
# that the merge optimization works properly.

proc add*(x: var string, y: char) {.magic: "AppendStrCh", noSideEffect.}
  ## Appends `y` to `x` in place.
  ##   ```nim
  ##   var tmp = ""
  ##   tmp.add('a')
  ##   tmp.add('b')
  ##   assert(tmp == "ab")
  ##   ```

proc add*(x: var string, y: string) {.magic: "AppendStrStr", noSideEffect.} =
  ## Concatenates `x` and `y` in place.
  ##
  ## See also `strbasics.add`.
  runnableExamples:
    var tmp = ""
    tmp.add("ab")
    tmp.add("cd")
    assert tmp == "abcd"

type
  Endianness* = enum ## Type describing the endianness of a processor.
    littleEndian, bigEndian

const
  cpuEndian* {.magic: "CpuEndian".}: Endianness = littleEndian
    ## The endianness of the target CPU. This is a valuable piece of
    ## information for low-level code only. This works thanks to compiler
    ## magic.

  hostOS* {.magic: "HostOS".}: string = ""
    ## A string that describes the host operating system.
    ##
    ## Possible values:
    ## `"windows"`, `"macosx"`, `"linux"`, `"netbsd"`, `"freebsd"`,
    ## `"openbsd"`, `"solaris"`, `"aix"`, `"haiku"`, `"standalone"`.

  hostCPU* {.magic: "HostCPU".}: string = ""
    ## A string that describes the host CPU.
    ##
    ## Possible values:
    ## `"i386"`, `"alpha"`, `"powerpc"`, `"powerpc64"`, `"powerpc64el"`,
    ## `"sparc"`, `"amd64"`, `"mips"`, `"mipsel"`, `"arm"`, `"arm64"`,
    ## `"mips64"`, `"mips64el"`, `"riscv32"`, `"riscv64"`, `"loongarch64"`.

  seqShallowFlag = low(int)
  strlitFlag = 1 shl (sizeof(int)*8 - 2) # later versions of the codegen \
  # emit this flag
  # for string literals, it allows for some optimizations.

const
  hasThreadSupport = compileOption("threads") and not defined(nimscript)
  hasSharedHeap = defined(boehmgc) or defined(gogc) # don't share heaps; every thread has its own

when notJSnotNims and not defined(nimSeqsV2):
  template space(s: PGenericSeq): int =
    s.reserved and not (seqShallowFlag or strlitFlag)

when hasThreadSupport and defined(tcc) and not compileOption("tlsEmulation"):
  # tcc doesn't support TLS
  {.error: "`--tlsEmulation:on` must be used when using threads with tcc backend".}

when defined(boehmgc):
  when defined(windows):
    when sizeof(int) == 8:
      const boehmLib = "boehmgc64.dll"
    else:
      const boehmLib = "boehmgc.dll"
  elif defined(macosx):
    const boehmLib = "libgc.dylib"
  elif defined(openbsd):
    const boehmLib = "libgc.so.(4|5).0"
  elif defined(freebsd):
    const boehmLib = "libgc-threaded.so.1"
  else:
    const boehmLib = "libgc.so.1"
  {.pragma: boehmGC, noconv, dynlib: boehmLib.}

when not defined(nimPreviewSlimSystem):
  type TaintedString* {.deprecated: "Deprecated since 1.5".} = string


when defined(profiler) and not defined(nimscript):
  proc nimProfile() {.compilerproc, noinline.}
when hasThreadSupport:
  {.pragma: rtlThreadVar, threadvar.}
else:
  {.pragma: rtlThreadVar.}

const
  QuitSuccess* = 0
    ## is the value that should be passed to `quit <#quit,int>`_ to indicate
    ## success.

  QuitFailure* = 1
    ## is the value that should be passed to `quit <#quit,int>`_ to indicate
    ## failure.

when not defined(js) and hostOS != "standalone":
  var programResult* {.compilerproc, exportc: "nim_program_result".}: int
    ## deprecated, prefer `quit` or `exitprocs.getProgramResult`, `exitprocs.setProgramResult`.

import std/private/since
import system/ctypes
export ctypes

proc align(address, alignment: int): int =
  if alignment == 0: # Actually, this is illegal. This branch exists to actively
                     # hide problems.
    result = address
  else:
    result = (address + (alignment - 1)) and not (alignment - 1)

include system/rawquits
when defined(genode):
  export GenodeEnv

template sysAssert(cond: bool, msg: string) =
  when defined(useSysAssert):
    if not cond:
      cstderr.rawWrite "[SYSASSERT] "
      cstderr.rawWrite msg
      cstderr.rawWrite "\n"
      rawQuit 1

const hasAlloc = (hostOS != "standalone" or not defined(nogc)) and not defined(nimscript)

when notJSnotNims and hasAlloc and not defined(nimSeqsV2):
  proc addChar(s: NimString, c: char): NimString {.compilerproc, benign.}

when defined(nimscript) or not defined(nimSeqsV2):
  proc add*[T](x: var seq[T], y: sink T) {.magic: "AppendSeqElem", noSideEffect.}
    ## Generic proc for adding a data item `y` to a container `x`.
    ##
    ## For containers that have an order, `add` means *append*. New generic
    ## containers should also call their adding proc `add` for consistency.
    ## Generic code becomes much easier to write if the Nim naming scheme is
    ## respected.
    ##   ```nim
    ##   var s: seq[string] = @["test2","test2"]
    ##   s.add("test")
    ##   assert s == @["test2", "test2", "test"]
    ##   ```

when false: # defined(gcDestructors):
  proc add*[T](x: var seq[T], y: sink openArray[T]) {.noSideEffect.} =
    ## Generic proc for adding a container `y` to a container `x`.
    ##
    ## For containers that have an order, `add` means *append*. New generic
    ## containers should also call their adding proc `add` for consistency.
    ## Generic code becomes much easier to write if the Nim naming scheme is
    ## respected.
    ##   ```nim
    ##   var s: seq[string] = @["test2","test2"]
    ##   s.add("test") # s <- @[test2, test2, test]
    ##   ```
    ##
    ## See also:
    ## * `& proc <#&,seq[T],seq[T]>`_
    {.noSideEffect.}:
      let xl = x.len
      setLen(x, xl + y.len)
      for i in 0..high(y):
        when nimvm:
          # workaround the fact that the VM does not yet
          # handle sink parameters properly:
          x[xl+i] = y[i]
        else:
          x[xl+i] = move y[i]
else:
  proc add*[T](x: var seq[T], y: openArray[T]) {.noSideEffect.} =
    ## Generic proc for adding a container `y` to a container `x`.
    ##
    ## For containers that have an order, `add` means *append*. New generic
    ## containers should also call their adding proc `add` for consistency.
    ## Generic code becomes much easier to write if the Nim naming scheme is
    ## respected.
    ##
    ## See also:
    ## * `& proc <#&,seq[T],seq[T]>`_
    runnableExamples:
      var a = @["a1", "a2"]
      a.add(["b1", "b2"])
      assert a == @["a1", "a2", "b1", "b2"]
      var c = @["c0", "c1", "c2", "c3"]
      a.add(c.toOpenArray(1, 2))
      assert a == @["a1", "a2", "b1", "b2", "c1", "c2"]

    {.noSideEffect.}:
      let xl = x.len
      setLen(x, xl + y.len)
      for i in 0..high(y): x[xl+i] = y[i]


when defined(nimSeqsV2):
  template movingCopy(a, b: typed) =
    a = move(b)
else:
  template movingCopy(a, b: typed) =
    shallowCopy(a, b)

proc del*[T](x: var seq[T], i: Natural) {.noSideEffect.} =
  ## Deletes the item at index `i` by putting `x[high(x)]` into position `i`.
  ##
  ## This is an `O(1)` operation.
  ##
  ## See also:
  ## * `delete <#delete,seq[T],Natural>`_ for preserving the order
  runnableExamples:
    var a = @[10, 11, 12, 13, 14]
    a.del(2)
    assert a == @[10, 11, 14, 13]
  let xl = x.len - 1
  movingCopy(x[i], x[xl])
  setLen(x, xl)

proc insert*[T](x: var seq[T], item: sink T, i = 0.Natural) {.noSideEffect.} =
  ## Inserts `item` into `x` at position `i`.
  ##   ```nim
  ##   var i = @[1, 3, 5]
  ##   i.insert(99, 0) # i <- @[99, 1, 3, 5]
  ##   ```
  {.noSideEffect.}:
    template defaultImpl =
      let xl = x.len
      setLen(x, xl+1)
      var j = xl-1
      while j >= i:
        movingCopy(x[j+1], x[j])
        dec(j)
    when nimvm:
      defaultImpl()
    else:
      when defined(js):
        var it : T
        {.emit: "`x` = `x` || []; `x`.splice(`i`, 0, `it`);".}
      else:
        defaultImpl()
    x[i] = item

when not defined(nimV2):
  proc repr*[T](x: T): string {.magic: "Repr", noSideEffect.}
    ## Takes any Nim variable and returns its string representation.
    ## No trailing newline is inserted (so `echo` won't add an empty newline).
    ## Use `-d:nimLegacyReprWithNewline` to revert to old behavior where newlines
    ## were added in some cases.
    ##
    ## It works even for complex data graphs with cycles. This is a great
    ## debugging tool.
    ##   ```nim
    ##   var s: seq[string] = @["test2", "test2"]
    ##   var i = @[1, 2, 3, 4, 5]
    ##   echo repr(s) # => 0x1055eb050[0x1055ec050"test2", 0x1055ec078"test2"]
    ##   echo repr(i) # => 0x1055ed050[1, 2, 3, 4, 5]
    ##   ```

when not defined(nimPreviewSlimSystem):
  type
    csize* {.importc: "size_t", nodecl, deprecated: "use `csize_t` instead".} = int
      ## This isn't the same as `size_t` in *C*. Don't use it.

const
  Inf* = 0x7FF0000000000000'f64
    ## Contains the IEEE floating point value of positive infinity.
  NegInf* = 0xFFF0000000000000'f64
    ## Contains the IEEE floating point value of negative infinity.
  NaN* = 0x7FF7FFFFFFFFFFFF'f64
    ## Contains an IEEE floating point value of *Not A Number*.
    ##
    ## Note that you cannot compare a floating point value to this value
    ## and expect a reasonable result - use the `isNaN` or `classify` procedure
    ## in the `math module <math.html>`_ for checking for NaN.

proc high*(T: typedesc[SomeFloat]): T = Inf
proc low*(T: typedesc[SomeFloat]): T = NegInf

proc toFloat*(i: int): float {.noSideEffect, inline.} =
  ## Converts an integer `i` into a `float`. Same as `float(i)`.
  ##
  ## If the conversion fails, `ValueError` is raised.
  ## However, on most platforms the conversion cannot fail.
  ##
  ##   ```nim
  ##   let
  ##     a = 2
  ##     b = 3.7
  ##
  ##   echo a.toFloat + b # => 5.7
  ##   ```
  float(i)

proc toBiggestFloat*(i: BiggestInt): BiggestFloat {.noSideEffect, inline.} =
  ## Same as `toFloat <#toFloat,int>`_ but for `BiggestInt` to `BiggestFloat`.
  BiggestFloat(i)

proc toInt*(f: float): int {.noSideEffect.} =
  ## Converts a floating point number `f` into an `int`.
  ##
  ## Conversion rounds `f` half away from 0, see
  ## `Round half away from zero
  ## <https://en.wikipedia.org/wiki/Rounding#Round_half_away_from_zero>`_,
  ## as opposed to a type conversion which rounds towards zero.
  ##
  ## Note that some floating point numbers (e.g. infinity or even 1e19)
  ## cannot be accurately converted.
  ##   ```nim
  ##   doAssert toInt(0.49) == 0
  ##   doAssert toInt(0.5) == 1
  ##   doAssert toInt(-0.5) == -1 # rounding is symmetrical
  ##   ```
  if f >= 0: int(f+0.5) else: int(f-0.5)

proc toBiggestInt*(f: BiggestFloat): BiggestInt {.noSideEffect.} =
  ## Same as `toInt <#toInt,float>`_ but for `BiggestFloat` to `BiggestInt`.
  if f >= 0: BiggestInt(f+0.5) else: BiggestInt(f-0.5)

proc `/`*(x, y: int): float {.inline, noSideEffect.} =
  ## Division of integers that results in a float.
  ##   ```nim
  ##   echo 7 / 5 # => 1.4
  ##   ```
  ##
  ## See also:
  ## * `div <system.html#div,int,int>`_
  ## * `mod <system.html#mod,int,int>`_
  result = toFloat(x) / toFloat(y)

{.push stackTrace: off.}

when defined(js):
  proc js_abs[T: SomeNumber](x: T): T {.importc: "Math.abs".}
else:
  proc c_fabs(x: cdouble): cdouble {.importc: "fabs", header: "<math.h>".}
  proc c_fabsf(x: cfloat): cfloat {.importc: "fabsf", header: "<math.h>".}

proc abs*[T: float64 | float32](x: T): T {.noSideEffect, inline.} =
  when nimvm:
    if x < 0.0: result = -x
    elif x == 0.0: result = 0.0 # handle 0.0, -0.0
    else: result = x # handle NaN, > 0
  else:
    when defined(js): result = js_abs(x)
    else:
      when T is float64:
        result = c_fabs(x)
      else:
        result = c_fabsf(x)

func abs*(x: int): int {.magic: "AbsI", inline.} =
  if x < 0: -x else: x
func abs*(x: int8): int8 {.magic: "AbsI", inline.} =
  if x < 0: -x else: x
func abs*(x: int16): int16 {.magic: "AbsI", inline.} =
  if x < 0: -x else: x
func abs*(x: int32): int32 {.magic: "AbsI", inline.} =
  if x < 0: -x else: x
func abs*(x: int64): int64 {.magic: "AbsI", inline.} =
  ## Returns the absolute value of `x`.
  ##
  ## If `x` is `low(x)` (that is -MININT for its type),
  ## an overflow exception is thrown (if overflow checking is turned on).
  result = if x < 0: -x else: x

{.pop.} # stackTrace: off

when not defined(nimPreviewSlimSystem):
  proc addQuitProc*(quitProc: proc() {.noconv.}) {.
    importc: "atexit", header: "<stdlib.h>", deprecated: "use exitprocs.addExitProc".}
    ## Adds/registers a quit procedure.
    ##
    ## Each call to `addQuitProc` registers another quit procedure. Up to 30
    ## procedures can be registered. They are executed on a last-in, first-out
    ## basis (that is, the last function registered is the first to be executed).
    ## `addQuitProc` raises an EOutOfIndex exception if `quitProc` cannot be
    ## registered.
    # Support for addQuitProc() is done by Ansi C's facilities here.
    # In case of an unhandled exception the exit handlers should
    # not be called explicitly! The user may decide to do this manually though.

proc swap*[T](a, b: var T) {.magic: "Swap", noSideEffect.}
  ## Swaps the values `a` and `b`.
  ##
  ## This is often more efficient than `tmp = a; a = b; b = tmp`.
  ## Particularly useful for sorting algorithms.
  ##
  ##   ```nim
  ##   var
  ##     a = 5
  ##     b = 9
  ##
  ##   swap(a, b)
  ##
  ##   assert a == 9
  ##   assert b == 5
  ##   ```

when not defined(js) and not defined(booting) and defined(nimTrMacros):
  template swapRefsInArray*{swap(arr[a], arr[b])}(arr: openArray[ref], a, b: int) =
    # Optimize swapping of array elements if they are refs. Default swap
    # implementation will cause unsureAsgnRef to be emitted which causes
    # unnecessary slow down in this case.
    swap(cast[ptr pointer](addr arr[a])[], cast[ptr pointer](addr arr[b])[])

when not defined(nimscript):
  {.push stackTrace: off, profiler: off.}

  when not defined(nimPreviewSlimSystem):
    import std/sysatomics
    export sysatomics
  else:
    import std/sysatomics

  {.pop.}

include "system/memalloc"


proc `|`*(a, b: typedesc): typedesc = discard

include "system/iterators_1"


proc len*[U: Ordinal; V: Ordinal](x: HSlice[U, V]): int {.noSideEffect, inline.} =
  ## Length of ordinal slice. When x.b < x.a returns zero length.
  ##   ```nim
  ##   assert((0..5).len == 6)
  ##   assert((5..2).len == 0)
  ##   ```
  result = max(0, ord(x.b) - ord(x.a) + 1)

proc isNil*[T](x: ref T): bool {.noSideEffect, magic: "IsNil".}

proc isNil*[T](x: ptr T): bool {.noSideEffect, magic: "IsNil".}
proc isNil*(x: pointer): bool {.noSideEffect, magic: "IsNil".}
proc isNil*(x: cstring): bool {.noSideEffect, magic: "IsNil".}
proc isNil*[T: proc | iterator {.closure.}](x: T): bool {.noSideEffect, magic: "IsNil".}
  ## Fast check whether `x` is nil. This is sometimes more efficient than
  ## `== nil`.

when defined(nimHasTopDownInference):
  # magic used for seq type inference
  proc `@`*[T](a: openArray[T]): seq[T] {.magic: "OpenArrayToSeq".} =
    ## Turns an *openArray* into a sequence.
    ##
    ## This is not as efficient as turning a fixed length array into a sequence
    ## as it always copies every element of `a`.
    newSeq(result, a.len)
    for i in 0..a.len-1: result[i] = a[i]
else:
  proc `@`*[T](a: openArray[T]): seq[T] =
    ## Turns an *openArray* into a sequence.
    ##
    ## This is not as efficient as turning a fixed length array into a sequence
    ## as it always copies every element of `a`.
    newSeq(result, a.len)
    for i in 0..a.len-1: result[i] = a[i]


when defined(nimSeqsV2):

  proc `&`*[T](x, y: sink seq[T]): seq[T] {.noSideEffect.} =
    ## Concatenates two sequences.
    ##
    ## Requires copying of the sequences.
    ##   ```nim
    ##   assert(@[1, 2, 3, 4] & @[5, 6] == @[1, 2, 3, 4, 5, 6])
    ##   ```
    ##
    ## See also:
    ## * `add(var seq[T], openArray[T]) <#add,seq[T],openArray[T]>`_
    newSeq(result, x.len + y.len)
    for i in 0..x.len-1:
      result[i] = move(x[i])
    for i in 0..y.len-1:
      result[i+x.len] = move(y[i])

  proc `&`*[T](x: sink seq[T], y: sink T): seq[T] {.noSideEffect.} =
    ## Appends element y to the end of the sequence.
    ##
    ## Requires copying of the sequence.
    ##   ```nim
    ##   assert(@[1, 2, 3] & 4 == @[1, 2, 3, 4])
    ##   ```
    ##
    ## See also:
    ## * `add(var seq[T], T) <#add,seq[T],sinkT>`_
    newSeq(result, x.len + 1)
    for i in 0..x.len-1:
      result[i] = move(x[i])
    result[x.len] = move(y)

  proc `&`*[T](x: sink T, y: sink seq[T]): seq[T] {.noSideEffect.} =
    ## Prepends the element x to the beginning of the sequence.
    ##
    ## Requires copying of the sequence.
    ##   ```nim
    ##   assert(1 & @[2, 3, 4] == @[1, 2, 3, 4])
    ##   ```
    newSeq(result, y.len + 1)
    result[0] = move(x)
    for i in 0..y.len-1:
      result[i+1] = move(y[i])

else:

  proc `&`*[T](x, y: seq[T]): seq[T] {.noSideEffect.} =
    ## Concatenates two sequences.
    ##
    ## Requires copying of the sequences.
    ##   ```nim
    ##   assert(@[1, 2, 3, 4] & @[5, 6] == @[1, 2, 3, 4, 5, 6])
    ##   ```
    ##
    ## See also:
    ## * `add(var seq[T], openArray[T]) <#add,seq[T],openArray[T]>`_
    newSeq(result, x.len + y.len)
    for i in 0..x.len-1:
      result[i] = x[i]
    for i in 0..y.len-1:
      result[i+x.len] = y[i]

  proc `&`*[T](x: seq[T], y: T): seq[T] {.noSideEffect.} =
    ## Appends element y to the end of the sequence.
    ##
    ## Requires copying of the sequence.
    ##   ```nim
    ##   assert(@[1, 2, 3] & 4 == @[1, 2, 3, 4])
    ##   ```
    ##
    ## See also:
    ## * `add(var seq[T], T) <#add,seq[T],sinkT>`_
    newSeq(result, x.len + 1)
    for i in 0..x.len-1:
      result[i] = x[i]
    result[x.len] = y

  proc `&`*[T](x: T, y: seq[T]): seq[T] {.noSideEffect.} =
    ## Prepends the element x to the beginning of the sequence.
    ##
    ## Requires copying of the sequence.
    ##   ```nim
    ##   assert(1 & @[2, 3, 4] == @[1, 2, 3, 4])
    ##   ```
    newSeq(result, y.len + 1)
    result[0] = x
    for i in 0..y.len-1:
      result[i+1] = y[i]


proc instantiationInfo*(index = -1, fullPaths = false): tuple[
  filename: string, line: int, column: int] {.magic: "InstantiationInfo", noSideEffect.}
  ## Provides access to the compiler's instantiation stack line information
  ## of a template.
  ##
  ## While similar to the `caller info`:idx: of other languages, it is determined
  ## at compile time.
  ##
  ## This proc is mostly useful for meta programming (eg. `assert` template)
  ## to retrieve information about the current filename and line number.
  ## Example:
  ##
  ##   ```nim
  ##   import std/strutils
  ##
  ##   template testException(exception, code: untyped): typed =
  ##     try:
  ##       let pos = instantiationInfo()
  ##       discard(code)
  ##       echo "Test failure at $1:$2 with '$3'" % [pos.filename,
  ##         $pos.line, astToStr(code)]
  ##       assert false, "A test expecting failure succeeded?"
  ##     except exception:
  ##       discard
  ##
  ##   proc tester(pos: int): int =
  ##     let
  ##       a = @[1, 2, 3]
  ##     result = a[pos]
  ##
  ##   when isMainModule:
  ##     testException(IndexDefect, tester(30))
  ##     testException(IndexDefect, tester(1))
  ##     # --> Test failure at example.nim:20 with 'tester(1)'
  ##   ```


when notJSnotNims:
  import system/ansi_c
  import system/memory


{.push stackTrace: off.}

when not defined(js) and hasThreadSupport and hostOS != "standalone":
  import std/private/syslocks
  include "system/threadlocalstorage"

when not defined(js) and defined(nimV2):
  type
    DestructorProc = proc (p: pointer) {.nimcall, benign, raises: [].}
    TNimTypeV2 {.compilerproc.} = object
      destructor: pointer
      size: int
      align: int16
      depth: int16
      display: ptr UncheckedArray[uint32] # classToken
      when defined(nimTypeNames) or defined(nimArcIds):
        name: cstring
      traceImpl: pointer
      typeInfoV1: pointer # for backwards compat, usually nil
      flags: int
      when defined(gcDestructors):
        when defined(cpp):
          vTable: ptr UncheckedArray[pointer] # vtable for types
        else:
          vTable: UncheckedArray[pointer] # vtable for types
    PNimTypeV2 = ptr TNimTypeV2

proc supportsCopyMem(t: typedesc): bool {.magic: "TypeTrait".}

when notJSnotNims and defined(nimSeqsV2):
  include "system/strs_v2"
  include "system/seqs_v2"

when not defined(js):
  template newSeqImpl(T, len) =
    result = newSeqOfCap[T](len)
    {.cast(noSideEffect).}:
      when defined(nimSeqsV2):
        cast[ptr int](addr result)[] = len
      else:
        var s = cast[PGenericSeq](result)
        s.len = len

  proc newSeqUninitialized*[T: SomeNumber](len: Natural): seq[T] {.deprecated: "Use `newSeqUninit` instead".} =
    ## Creates a new sequence of type `seq[T]` with length `len`.
    ##
    ## Only available for numbers types. Note that the sequence will be
    ## uninitialized. After the creation of the sequence you should assign
    ## entries to the sequence instead of adding them.
    ## Example:
    ##   ```nim
    ##   var x = newSeqUninitialized[int](3)
    ##   assert len(x) == 3
    ##   x[0] = 10
    ##   ```
    result = newSeqOfCap[T](len)
    when defined(nimSeqsV2):
      cast[ptr int](addr result)[] = len
    else:
      var s = cast[PGenericSeq](result)
      s.len = len

  func newSeqUninit*[T](len: Natural): seq[T] =
    ## Creates a new sequence of type `seq[T]` with length `len`.
    ##
    ## Only available for types, which don't contain
    ## managed memory or have destructors.
    ## Note that the sequence will be uninitialized.
    ## After the creation of the sequence you should assign
    ## entries to the sequence instead of adding them.
    runnableExamples:
      var x = newSeqUninit[int](3)
      assert len(x) == 3
      x[0] = 10
    when supportsCopyMem(T):
      when nimvm:
        result = newSeq[T](len)
      else:
        newSeqImpl(T, len)
    else:
      {.error: "The type T cannot contain managed memory or have destructors".}

  proc newStringUninit*(len: Natural): string =
    ## Returns a new string of length `len` but with uninitialized
    ## content. One needs to fill the string character after character
    ## with the index operator `s[i]`.
    ##
    ## This procedure exists only for optimization purposes;
    ## the same effect can be achieved with the `&` operator or with `add`.
    when nimvm:
      result = newString(len)
    else:
      result = newStringOfCap(len)
      when defined(nimSeqsV2):
        let s = cast[ptr NimStringV2](addr result)
        if len > 0:
          s.len = len
          s.p.data[len] = '\0'
      else:
        let s = cast[NimString](result)
        s.len = len
        s.data[len] = '\0'
else:
  proc newStringUninit*(len: Natural): string {.
    magic: "NewString", importc: "mnewString", noSideEffect.}

{.pop.}

when not defined(nimscript):
  proc writeStackTrace*() {.tags: [], gcsafe, raises: [].}
    ## Writes the current stack trace to `stderr`. This is only works
    ## for debug builds. Since it's usually used for debugging, this
    ## is proclaimed to have no IO effect!

when not declared(sysFatal):
  include "system/fatal"

type
  PFrame* = ptr TFrame  ## Represents a runtime frame of the call stack;
                        ## part of the debugger API.
  # keep in sync with nimbase.h `struct TFrame_`
  TFrame* {.importc, nodecl, final.} = object ## The frame itself.
    prev*: PFrame       ## Previous frame; used for chaining the call stack.
    procname*: cstring  ## Name of the proc that is currently executing.
    line*: int          ## Line number of the proc that is currently executing.
    filename*: cstring  ## Filename of the proc that is currently executing.
    len*: int16         ## Length of the inspectable slots.
    calldepth*: int16   ## Used for max call depth checking.
    when NimStackTraceMsgs:
      frameMsgLen*: int   ## end position in frameMsgBuf for this frame.

when defined(nimV2):
  var
    framePtr {.threadvar.}: PFrame

  include system/arc

template newException*(exceptn: typedesc, message: string;
                       parentException: ref Exception = nil): untyped =
  ## Creates an exception object of type `exceptn` and sets its `msg` field
  ## to `message`. Returns the new exception object.
  (ref exceptn)(msg: message, parent: parentException)

when not defined(nimPreviewSlimSystem):
  import std/assertions
  export assertions

import system/iterators
export iterators


proc find*[T, S](a: T, item: S): int {.inline.}=
  ## Returns the first index of `item` in `a` or -1 if not found. This requires
  ## appropriate `items` and `==` operations to work.
  result = 0
  for i in items(a):
    if i == item: return
    inc(result)
  result = -1

proc contains*[T](a: openArray[T], item: T): bool {.inline.}=
  ## Returns true if `item` is in `a` or false if not found. This is a shortcut
  ## for `find(a, item) >= 0`.
  ##
  ## This allows the `in` operator: `a.contains(item)` is the same as
  ## `item in a`.
  ##   ```nim
  ##   var a = @[1, 3, 5]
  ##   assert a.contains(5)
  ##   assert 3 in a
  ##   assert 99 notin a
  ##   ```
  return find(a, item) >= 0

proc pop*[T](s: var seq[T]): T {.inline, noSideEffect.} =
  ## Returns the last item of `s` and decreases `s.len` by one. This treats
  ## `s` as a stack and implements the common *pop* operation.
  ##
  ## Raises `IndexDefect` if `s` is empty.
  runnableExamples:
    var a = @[1, 3, 5, 7]
    let b = pop(a)
    assert b == 7
    assert a == @[1, 3, 5]

  var L = s.len-1
  when defined(nimV2):
    result = move s[L]
    shrink(s, L)
  else:
    result = s[L]
    setLen(s, L)

proc `==`*[T: tuple|object](x, y: T): bool =
  ## Generic `==` operator for tuples that is lifted from the components.
  ## of `x` and `y`.
  for a, b in fields(x, y):
    if a != b: return false
  return true

proc `<=`*[T: tuple](x, y: T): bool =
  ## Generic lexicographic `<=` operator for tuples that is lifted from the
  ## components of `x` and `y`. This implementation uses `cmp`.
  for a, b in fields(x, y):
    var c = cmp(a, b)
    if c < 0: return true
    if c > 0: return false
  return true

proc `<`*[T: tuple](x, y: T): bool =
  ## Generic lexicographic `<` operator for tuples that is lifted from the
  ## components of `x` and `y`. This implementation uses `cmp`.
  for a, b in fields(x, y):
    var c = cmp(a, b)
    if c < 0: return true
    if c > 0: return false
  return false


include "system/gc_interface"

# we have to compute this here before turning it off in except.nim anyway ...
const NimStackTrace = compileOption("stacktrace")

import system/coro_detection

{.push checks: off.}
# obviously we cannot generate checking operations here :-)
# because it would yield into an endless recursion
# however, stack-traces are available for most parts
# of the code

when notJSnotNims:
  var
    globalRaiseHook*: proc (e: ref Exception): bool {.nimcall, benign.}
      ## With this hook you can influence exception handling on a global level.
      ## If not nil, every 'raise' statement ends up calling this hook.
      ##
      ## .. warning:: Ordinary application code should never set this hook! You better know what you do when setting this.
      ##
      ## If `globalRaiseHook` returns false, the exception is caught and does
      ## not propagate further through the call stack.

    localRaiseHook* {.threadvar.}: proc (e: ref Exception): bool {.nimcall, benign.}
      ## With this hook you can influence exception handling on a
      ## thread local level.
      ## If not nil, every 'raise' statement ends up calling this hook.
      ##
      ## .. warning:: Ordinary application code should never set this hook! You better know what you do when setting this.
      ##
      ## If `localRaiseHook` returns false, the exception
      ## is caught and does not propagate further through the call stack.

    outOfMemHook*: proc () {.nimcall, tags: [], benign, raises: [].}
      ## Set this variable to provide a procedure that should be called
      ## in case of an `out of memory`:idx: event. The standard handler
      ## writes an error message and terminates the program.
      ##
      ## `outOfMemHook` can be used to raise an exception in case of OOM like so:
      ##
      ##   ```nim
      ##   var gOutOfMem: ref EOutOfMemory
      ##   new(gOutOfMem) # need to be allocated *before* OOM really happened!
      ##   gOutOfMem.msg = "out of memory"
      ##
      ##   proc handleOOM() =
      ##     raise gOutOfMem
      ##
      ##   system.outOfMemHook = handleOOM
      ##   ```
      ##
      ## If the handler does not raise an exception, ordinary control flow
      ## continues and the program is terminated.
    unhandledExceptionHook*: proc (e: ref Exception) {.nimcall, tags: [], benign, raises: [].}
      ## Set this variable to provide a procedure that should be called
      ## in case of an `unhandle exception` event. The standard handler
      ## writes an error message and terminates the program, except when
      ## using `--os:any`

when defined(js) or defined(nimdoc):
  proc add*(x: var string, y: cstring) {.asmNoStackFrame.} =
    ## Appends `y` to `x` in place.
    runnableExamples:
      var tmp = ""
      tmp.add(cstring("ab"))
      tmp.add(cstring("cd"))
      doAssert tmp == "abcd"
    {.emit: """
      if (`x` === null) { `x` = []; }
      var off = `x`.length;
      `x`.length += `y`.length;
      for (var i = 0; i < `y`.length; ++i) {
        `x`[off+i] = `y`.charCodeAt(i);
      }
    """.}
  proc add*(x: var cstring, y: cstring) {.magic: "AppendStrStr".} =
    ## Appends `y` to `x` in place.
    ## Only implemented for JS backend.
    runnableExamples:
      when defined(js):
        var tmp: cstring = ""
        tmp.add(cstring("ab"))
        tmp.add(cstring("cd"))
        doAssert tmp == cstring("abcd")

elif hasAlloc:
  {.push stackTrace: off, profiler: off.}
  proc add*(x: var string, y: cstring) =
    var i = 0
    if y != nil:
      while y[i] != '\0':
        add(x, y[i])
        inc(i)
  {.pop.}

proc echo*(x: varargs[typed, `$`]) {.magic: "Echo", benign, sideEffect.}
  ## Writes and flushes the parameters to the standard output.
  ##
  ## Special built-in that takes a variable number of arguments. Each argument
  ## is converted to a string via `$`, so it works for user-defined
  ## types that have an overloaded `$` operator.
  ## It is roughly equivalent to `writeLine(stdout, x); flushFile(stdout)`, but
  ## available for the JavaScript target too.
  ##
  ## Unlike other IO operations this is guaranteed to be thread-safe as
  ## `echo` is very often used for debugging convenience. If you want to use
  ## `echo` inside a `proc without side effects
  ## <manual.html#pragmas-nosideeffect-pragma>`_ you can use `debugEcho
  ## <#debugEcho,varargs[typed,]>`_ instead.

proc debugEcho*(x: varargs[typed, `$`]) {.magic: "Echo", noSideEffect,
                                          tags: [], raises: [].}
  ## Same as `echo <#echo,varargs[typed,]>`_, but as a special semantic rule,
  ## `debugEcho` pretends to be free of side effects, so that it can be used
  ## for debugging routines marked as `noSideEffect
  ## <manual.html#pragmas-nosideeffect-pragma>`_.

when hostOS == "standalone" and defined(nogc):
  proc nimToCStringConv(s: NimString): cstring {.compilerproc, inline.} =
    if s == nil or s.len == 0: result = cstring""
    else: result = cast[cstring](addr s.data)

proc getTypeInfo*[T](x: T): pointer {.magic: "GetTypeInfo", benign.}
  ## Get type information for `x`.
  ##
  ## Ordinary code should not use this, but the `typeinfo module
  ## <typeinfo.html>`_ instead.


when not defined(js):

  proc likelyProc(val: bool): bool {.importc: "NIM_LIKELY", nodecl, noSideEffect.}
  proc unlikelyProc(val: bool): bool {.importc: "NIM_UNLIKELY", nodecl, noSideEffect.}

template likely*(val: bool): bool =
  ## Hints the optimizer that `val` is likely going to be true.
  ##
  ## You can use this template to decorate a branch condition. On certain
  ## platforms this can help the processor predict better which branch is
  ## going to be run. Example:
  ##   ```nim
  ##   for value in inputValues:
  ##     if likely(value <= 100):
  ##       process(value)
  ##     else:
  ##       echo "Value too big!"
  ##   ```
  ##
  ## On backends without branch prediction (JS and the nimscript VM), this
  ## template will not affect code execution.
  when nimvm:
    val
  else:
    when defined(js):
      val
    else:
      likelyProc(val)

template unlikely*(val: bool): bool =
  ## Hints the optimizer that `val` is likely going to be false.
  ##
  ## You can use this proc to decorate a branch condition. On certain
  ## platforms this can help the processor predict better which branch is
  ## going to be run. Example:
  ##   ```nim
  ##   for value in inputValues:
  ##     if unlikely(value > 100):
  ##       echo "Value too big!"
  ##     else:
  ##       process(value)
  ##   ```
  ##
  ## On backends without branch prediction (JS and the nimscript VM), this
  ## template will not affect code execution.
  when nimvm:
    val
  else:
    when defined(js):
      val
    else:
      unlikelyProc(val)

import system/dollars
export dollars

when defined(nimAuditDelete):
  {.pragma: auditDelete, deprecated: "review this call for out of bounds behavior".}
else:
  {.pragma: auditDelete.}

proc delete*[T](x: var seq[T], i: Natural) {.noSideEffect, systemRaisesDefect, auditDelete.} =
  ## Deletes the item at index `i` by moving all `x[i+1..^1]` items by one position.
  ##
  ## This is an `O(n)` operation.
  ##
  ## See also:
  ## * `del <#del,seq[T],Natural>`_ for O(1) operation
  ##
  runnableExamples:
    var s = @[1, 2, 3, 4, 5]
    s.delete(2)
    doAssert s == @[1, 2, 4, 5]

  when not defined(nimAuditDelete):
    if i > high(x):
      # xxx this should call `raiseIndexError2(i, high(x))` after some refactoring
      raise (ref IndexDefect)(msg: "index out of bounds: '" & $i & "' < '" & $x.len & "' failed")

  template defaultImpl =
    let xl = x.len
    for j in i.int..xl-2: movingCopy(x[j], x[j+1])
    setLen(x, xl-1)

  when nimvm:
    defaultImpl()
  else:
    when defined(js):
      {.emit: "`x`.splice(`i`, 1);".}
    else:
      defaultImpl()


const
  NimVersion*: string = $NimMajor & "." & $NimMinor & "." & $NimPatch
    ## is the version of Nim as a string.

when not defined(js):
  {.push stackTrace: off, profiler: off.}

  when hasAlloc:
    when not defined(gcRegions) and not usesDestructors:
      proc initGC() {.gcsafe, raises: [].}

    proc initStackBottom() {.inline, compilerproc.} =
      # WARNING: This is very fragile! An array size of 8 does not work on my
      # Linux 64bit system. -- That's because the stack direction is the other
      # way around.
      when declared(nimGC_setStackBottom):
        var locals {.volatile, noinit.}: pointer
        locals = addr(locals)
        nimGC_setStackBottom(locals)

    proc initStackBottomWith(locals: pointer) {.inline, compilerproc.} =
      # We need to keep initStackBottom around for now to avoid
      # bootstrapping problems.
      when declared(nimGC_setStackBottom):
        nimGC_setStackBottom(locals)

    when not usesDestructors:
      {.push profiler: off.}
      var
        strDesc = TNimType(size: sizeof(string), kind: tyString, flags: {ntfAcyclic})
      {.pop.}

  {.pop.}


when not defined(js):
  # ugly hack, see the accompanying .pop for
  # the mysterious error message
  {.push stackTrace: off, profiler: off.}

when notJSnotNims:
  proc zeroMem(p: pointer, size: Natural) =
    nimZeroMem(p, size)
    when declared(memTrackerOp):
      memTrackerOp("zeroMem", p, size)
  proc copyMem(dest, source: pointer, size: Natural) =
    nimCopyMem(dest, source, size)
    when declared(memTrackerOp):
      memTrackerOp("copyMem", dest, size)
  proc moveMem(dest, source: pointer, size: Natural) =
    c_memmove(dest, source, csize_t(size))
    when declared(memTrackerOp):
      memTrackerOp("moveMem", dest, size)
  proc equalMem(a, b: pointer, size: Natural): bool =
    nimCmpMem(a, b, size) == 0
  proc cmpMem(a, b: pointer, size: Natural): int =
    nimCmpMem(a, b, size).int

when not defined(js) or defined(nimscript):
  # nimscript can be defined if config file for js compilation
  proc cmp(x, y: string): int =
    when nimvm:
      if x < y: result = -1
      elif x > y: result = 1
      else: result = 0
    else:
      when not defined(nimscript): # avoid semantic checking
        let minlen = min(x.len, y.len)
        result = int(nimCmpMem(x.cstring, y.cstring, cast[csize_t](minlen)))
        if result == 0:
          result = x.len - y.len

  when declared(newSeq):
    proc cstringArrayToSeq*(a: cstringArray, len: Natural): seq[string] =
      ## Converts a `cstringArray` to a `seq[string]`. `a` is supposed to be
      ## of length `len`.
      if a == nil: return @[]
      newSeq(result, len)
      for i in 0..len-1: result[i] = $a[i]

    proc cstringArrayToSeq*(a: cstringArray): seq[string] =
      ## Converts a `cstringArray` to a `seq[string]`. `a` is supposed to be
      ## terminated by `nil`.
      if a == nil: return @[]
      var L = 0
      while a[L] != nil: inc(L)
      result = cstringArrayToSeq(a, L)


when not defined(js) and declared(alloc0) and declared(dealloc):
  proc allocCStringArray*(a: openArray[string]): cstringArray =
    ## Creates a NULL terminated cstringArray from `a`. The result has to
    ## be freed with `deallocCStringArray` after it's not needed anymore.
    result = cast[cstringArray](alloc0((a.len+1) * sizeof(cstring)))

    let x = cast[ptr UncheckedArray[string]](a)
    for i in 0 .. a.high:
      result[i] = cast[cstring](alloc0(x[i].len+1))
      copyMem(result[i], addr(x[i][0]), x[i].len)

  proc deallocCStringArray*(a: cstringArray) =
    ## Frees a NULL terminated cstringArray.
    var i = 0
    while a[i] != nil:
      dealloc(a[i])
      inc(i)
    dealloc(a)

when notJSnotNims and not gotoBasedExceptions:
  type
    PSafePoint = ptr TSafePoint
    TSafePoint {.compilerproc, final.} = object
      prev: PSafePoint # points to next safe point ON THE STACK
      status: int
      context: C_JmpBuf
    SafePoint = TSafePoint

when not defined(js):
  when declared(initAllocator):
    initAllocator()
  when hasThreadSupport:
    when hostOS != "standalone":
      include system/threadimpl
      when not defined(nimPreviewSlimSystem):
        import std/typedthreads
        export typedthreads

  elif not defined(nogc) and not defined(nimscript):
    when not defined(useNimRtl) and not defined(createNimRtl): initStackBottom()
    when declared(initGC): initGC()

when notJSnotNims:
  proc setControlCHook*(hook: proc () {.noconv.})
    ## Allows you to override the behaviour of your application when CTRL+C
    ## is pressed. Only one such hook is supported.
    ## Example:
    ##
    ##   ```nim
    ##   proc ctrlc() {.noconv.} =
    ##     echo "Ctrl+C fired!"
    ##     # do clean up stuff
    ##     quit()
    ##
    ##   setControlCHook(ctrlc)
    ##   ```

  when not defined(noSignalHandler) and not defined(useNimRtl):
    proc unsetControlCHook*()
      ## Reverts a call to setControlCHook.

  when hostOS != "standalone":
    proc getStackTrace*(): string {.gcsafe.}
      ## Gets the current stack trace. This only works for debug builds.

    proc getStackTrace*(e: ref Exception): string {.gcsafe.}
      ## Gets the stack trace associated with `e`, which is the stack that
      ## lead to the `raise` statement. This only works for debug builds.

  {.push stackTrace: off, profiler: off.}
  when defined(memtracker):
    include "system/memtracker"

  when hostOS == "standalone":
    include "system/embedded"
  else:
    include "system/excpt"
  include "system/chcks"

  # we cannot compile this with stack tracing on
  # as it would recurse endlessly!
  include "system/integerops"
  {.pop.}


when not defined(js):
  # this is a hack: without this when statement, you would get:
  # Error: system module needs: nimGCvisit
  {.pop.} # stackTrace: off, profiler: off



when notJSnotNims:
  when hostOS != "standalone" and hostOS != "any":
    type
      LibHandle = pointer       # private type
      ProcAddr = pointer        # library loading and loading of procs:

    proc nimLoadLibrary(path: string): LibHandle {.compilerproc, hcrInline, nonReloadable.}
    proc nimUnloadLibrary(lib: LibHandle) {.compilerproc, hcrInline, nonReloadable.}
    proc nimGetProcAddr(lib: LibHandle, name: cstring): ProcAddr {.compilerproc, hcrInline, nonReloadable.}

    proc nimLoadLibraryError(path: string) {.compilerproc, hcrInline, nonReloadable.}

    include "system/dyncalls"

  import system/countbits_impl
  include "system/sets"

  when defined(gogc):
    const GenericSeqSize = (3 * sizeof(int))
  else:
    const GenericSeqSize = (2 * sizeof(int))

  proc getDiscriminant(aa: pointer, n: ptr TNimNode): uint =
    sysAssert(n.kind == nkCase, "getDiscriminant: node != nkCase")
    var d: uint
    var a = cast[uint](aa)
    case n.typ.size
    of 1: d = uint(cast[ptr uint8](a + uint(n.offset))[])
    of 2: d = uint(cast[ptr uint16](a + uint(n.offset))[])
    of 4: d = uint(cast[ptr uint32](a + uint(n.offset))[])
    of 8: d = uint(cast[ptr uint64](a + uint(n.offset))[])
    else:
      d = 0'u
      sysAssert(false, "getDiscriminant: invalid n.typ.size")
    return d

  proc selectBranch(aa: pointer, n: ptr TNimNode): ptr TNimNode =
    var discr = getDiscriminant(aa, n)
    if discr < cast[uint](n.len):
      result = n.sons[discr]
      if result == nil: result = n.sons[n.len]
      # n.sons[n.len] contains the `else` part (but may be nil)
    else:
      result = n.sons[n.len]

when notJSnotNims and hasAlloc:
  {.push profiler: off.}
  include "system/mmdisp"
  {.pop.}
  {.push stackTrace: off, profiler: off.}
  when not defined(nimSeqsV2):
    include "system/sysstr"
  {.pop.}

  include "system/strmantle"
  include "system/assign"

  when not defined(nimV2):
    include "system/repr"

when notJSnotNims and hasThreadSupport and hostOS != "standalone":
  when not defined(nimPreviewSlimSystem):
    include "system/channels_builtin"


when notJSnotNims and hostOS != "standalone":
  proc getCurrentException*(): ref Exception {.compilerRtl, inl, benign.} =
    ## Retrieves the current exception; if there is none, `nil` is returned.
    result = currException

  proc nimBorrowCurrentException(): ref Exception {.compilerRtl, inl, benign, nodestroy.} =
    # .nodestroy here so that we do not produce a write barrier as the
    # C codegen only uses it in a borrowed way:
    result = currException

  proc getCurrentExceptionMsg*(): string {.inline, benign.} =
    ## Retrieves the error message that was attached to the current
    ## exception; if there is none, `""` is returned.
    return if currException == nil: "" else: currException.msg

  proc setCurrentException*(exc: ref Exception) {.inline, benign.} =
    ## Sets the current exception.
    ##
    ## .. warning:: Only use this if you know what you are doing.
    currException = exc
elif defined(nimscript):
  proc getCurrentException*(): ref Exception {.compilerRtl.} = discard

when notJSnotNims:
  {.push stackTrace: off, profiler: off.}
  when (defined(profiler) or defined(memProfiler)):
    include "system/profiler"
  {.pop.}

  proc rawProc*[T: proc {.closure.} | iterator {.closure.}](x: T): pointer {.noSideEffect, inline.} =
    ## Retrieves the raw proc pointer of the closure `x`. This is
    ## useful for interfacing closures with C/C++, hash computations, etc.
    ## If `rawEnv(x)` returns `nil`, the proc which the result points to
    ## takes as many parameters as `x`, but with `{.nimcall.}` as its calling
    ## convention instead of `{.closure.}`, otherwise it takes one more parameter
    ## which is a `pointer`, and it still has `{.nimcall.}` as its calling convention.
    ## To invoke the resulted proc, what this returns has to be casted into a `proc`,
    ## not a `ptr proc`, and, in a case where `rawEnv(x)` returns non-`nil`,
    ## the last and additional argument has to be the result of `rawEnv(x)`.
    ## This is not available for the JS target.
    #[
    The conversion from function pointer to `void*` is a tricky topic, but this
    should work at least for c++ >= c++11, e.g. for `dlsym` support.
    refs: https://gcc.gnu.org/bugzilla/show_bug.cgi?id=57869,
    https://stackoverflow.com/questions/14125474/casts-between-pointer-to-function-and-pointer-to-object-in-c-and-c
    ]#
    runnableExamples:
      proc makeClosure(x: int): (proc(y: int): int) =
        var n = x
        result = (
          proc(y: int): int =
            n += y
            return n
        )

      var
        c1 = makeClosure(10)
        e = c1.rawEnv()
        p = c1.rawProc()

      if e.isNil():
        let c2 = cast[proc(y: int): int {.nimcall.}](p)
        echo c2(2)
      else:
        let c3 = cast[proc(y: int; env: pointer): int {.nimcall.}](p)
        echo c3(3, e)
    result = nil
    {.emit: """
    `result` = (void*)`x`.ClP_0;
    """.}

  proc rawEnv*[T: proc {.closure.} | iterator {.closure.}](x: T): pointer {.noSideEffect, inline.} =
    ## Retrieves the raw environment pointer of the closure `x`. See also `rawProc`.
    ## This is not available for the JS target.
    result = nil
    {.emit: """
    `result` = `x`.ClE_0;
    """.}

proc finished*[T: iterator {.closure.}](x: T): bool {.noSideEffect, inline, magic: "Finished".} =
  ## It can be used to determine if a first class iterator has finished.
  result = false
  when defined(js):
    # TODO: mangle `:state`
    {.emit: """
    `result` = (`x`.ClE_0).HEX3Astate < 0;
    """.}
  else:
    {.emit: """
    `result` = ((NI*) `x`.ClE_0)[1] < 0;
    """.}

from std/private/digitsutils import addInt
export addInt

when defined(js) and not defined(nimscript):
  # nimscript can be defined if config file for js compilation
  include "system/jssys"
  include "system/reprjs"


when defined(nimNoQuit):
  proc quit*(errorcode: int = QuitSuccess) = discard "ignoring quit"

elif defined(nimdoc):
  proc quit*(errorcode: int = QuitSuccess) {.magic: "Exit", noreturn.}
    ## Stops the program immediately with an exit code.
    ##
    ## Before stopping the program the "exit procedures" are called in the
    ## opposite order they were added with `addExitProc <exitprocs.html#addExitProc,proc)>`_.
    ##
    ## The proc `quit(QuitSuccess)` is called implicitly when your nim
    ## program finishes without incident for platforms where this is the
    ## expected behavior. A raised unhandled exception is
    ## equivalent to calling `quit(QuitFailure)`.
    ##
    ## Note that this is a *runtime* call and using `quit` inside a macro won't
    ## have any compile time effect. If you need to stop the compiler inside a
    ## macro, use the `error <manual.html#pragmas-error-pragma>`_ or `fatal
    ## <manual.html#pragmas-fatal-pragma>`_ pragmas.
    ##
    ## .. warning:: `errorcode` gets saturated when it exceeds the valid range
    ##    on the specific platform. On Posix, the valid range is `low(int8)..high(int8)`.
    ##    On Windows, the valid range is `low(int32)..high(int32)`. For instance,
    ##    `quit(int(0x100000000))` is equal to `quit(127)` on Linux.
    ##
    ## .. danger:: In almost all cases, in particular in library code, prefer
    ##   alternatives, e.g. `raiseAssert` or raise a `Defect`.
    ##   `quit` bypasses regular control flow in particular `defer`,
    ##   `try`, `catch`, `finally` and `destructors`, and exceptions that may have been
    ##   raised by an `addExitProc` proc, as well as cleanup code in other threads.
    ##   It does *not* call the garbage collector to free all the memory,
    ##   unless an `addExitProc` proc calls `GC_fullCollect <#GC_fullCollect>`_.

elif defined(genode):
  proc quit*(errorcode: int = QuitSuccess) {.inline, noreturn.} =
    rawQuit(errorcode)

elif defined(js) and defined(nodejs) and not defined(nimscript):
  proc quit*(errorcode: int = QuitSuccess) {.magic: "Exit",
    importc: "process.exit", noreturn.}

else:
  proc quit*(errorcode: int = QuitSuccess) {.inline, noreturn.} =
    when defined(posix): # posix uses low 8 bits
      type ExitCodeRange = int8
    else: # win32 uses low 32 bits
      type ExitCodeRange = cint
    when sizeof(errorcode) > sizeof(ExitCodeRange):
      if errorcode < low(ExitCodeRange):
        rawQuit(low(ExitCodeRange).cint)
      elif errorcode > high(ExitCodeRange):
        rawQuit(high(ExitCodeRange).cint)
      else:
        rawQuit(errorcode.cint)
    else:
      rawQuit(errorcode.cint)

proc quit*(errormsg: string, errorcode = QuitFailure) {.noreturn.} =
  ## A shorthand for `echo(errormsg); quit(errorcode)`.
  when defined(nimscript) or defined(js) or (hostOS == "standalone"):
    echo errormsg
  else:
    when nimvm:
      echo errormsg
    else:
      cstderr.rawWrite(errormsg)
      cstderr.rawWrite("\n")
  quit(errorcode)

{.pop.} # checks: off
# {.pop.} # hints: off

include "system/indices"

proc `&=`*(x: var string, y: string) {.magic: "AppendStrStr", noSideEffect.}
  ## Appends in place to a string.
  ##   ```nim
  ##   var a = "abc"
  ##   a &= "de" # a <- "abcde"
  ##   ```

template `&=`*(x, y: typed) =
  ## Generic 'sink' operator for Nim.
  ##
  ## If not specialized further, an alias for `add`.
  add(x, y)

when compileOption("rangechecks"):
  template rangeCheck*(cond) =
    ## Helper for performing user-defined range checks.
    ## Such checks will be performed only when the `rangechecks`
    ## compile-time option is enabled.
    if not cond: sysFatal(RangeDefect, "range check failed")
else:
  template rangeCheck*(cond) = discard

when not defined(gcArc) and not defined(gcOrc) and not defined(gcAtomicArc):
  proc shallow*[T](s: var seq[T]) {.noSideEffect, inline.} =
    ## Marks a sequence `s` as `shallow`:idx:. Subsequent assignments will not
    ## perform deep copies of `s`.
    ##
    ## This is only useful for optimization purposes.
    if s.len == 0: return
    when not defined(js) and not defined(nimscript) and not defined(nimSeqsV2):
      var s = cast[PGenericSeq](s)
      {.noSideEffect.}:
        s.reserved = s.reserved or seqShallowFlag

  proc shallow*(s: var string) {.noSideEffect, inline.} =
    ## Marks a string `s` as `shallow`:idx:. Subsequent assignments will not
    ## perform deep copies of `s`.
    ##
    ## This is only useful for optimization purposes.
    when not defined(js) and not defined(nimscript) and not defined(nimSeqsV2):
      var s = cast[PGenericSeq](s)
      if s == nil:
        s = cast[PGenericSeq](newString(0))
      # string literals cannot become 'shallow':
      if (s.reserved and strlitFlag) == 0:
        {.noSideEffect.}:
          s.reserved = s.reserved or seqShallowFlag

type
  NimNodeObj = object

  NimNode* {.magic: "PNimrodNode".} = ref NimNodeObj
    ## Represents a Nim AST node. Macros operate on this type.

type
  ForLoopStmt* {.compilerproc.} = object ## \
    ## A special type that marks a macro as a `for-loop macro`:idx:.
    ## See `"For Loop Macro" <manual.html#macros-for-loop-macro>`_.

macro varargsLen*(x: varargs[untyped]): int {.since: (1, 1).} =
  ## returns number of variadic arguments in `x`
  proc varargsLenImpl(x: NimNode): NimNode {.magic: "LengthOpenArray", noSideEffect.}
  varargsLenImpl(x)

when defined(nimV2):
  import system/repr_v2
  export repr_v2

proc repr*[T, U](x: HSlice[T, U]): string =
  ## Generic `repr` operator for slices that is lifted from the components
  ## of `x`. Example:
  ##   ```Nim
  ##   $(1 .. 5) == "1 .. 5"
  ##   ```
  result = repr(x.a)
  result.add(" .. ")
  result.add(repr(x.b))

when hasAlloc or defined(nimscript):
  proc insert*(x: var string, item: string, i = 0.Natural) {.noSideEffect.} =
    ## Inserts `item` into `x` at position `i`.
    ##   ```nim
    ##   var a = "abc"
    ##   a.insert("zz", 0) # a <- "zzabc"
    ##   ```
    if item.len == 0: # prevents self-assignment
      return
    var xl = x.len
    setLen(x, xl+item.len)
    var j = xl-1
    while j >= i:
      when defined(gcArc) or defined(gcOrc) or defined(gcAtomicArc):
        x[j+item.len] = move x[j]
      else:
        shallowCopy(x[j+item.len], x[j])
      dec(j)
    j = 0
    while j < item.len:
      x[j+i] = item[j]
      inc(j)

when declared(initDebugger):
  initDebugger()

proc addEscapedChar*(s: var string, c: char) {.noSideEffect, inline.} =
  ## Adds a char to string `s` and applies the following escaping:
  ##
  ## * replaces any ``\`` by `\\`
  ## * replaces any `'` by `\'`
  ## * replaces any `"` by `\"`
  ## * replaces any `\a` by `\\a`
  ## * replaces any `\b` by `\\b`
  ## * replaces any `\t` by `\\t`
  ## * replaces any `\n` by `\\n`
  ## * replaces any `\v` by `\\v`
  ## * replaces any `\f` by `\\f`
  ## * replaces any `\r` by `\\r`
  ## * replaces any `\e` by `\\e`
  ## * replaces any other character not in the set `{\21..\126}`
  ##   by `\xHH` where `HH` is its hexadecimal value
  ##
  ## The procedure has been designed so that its output is usable for many
  ## different common syntaxes.
  ##
  ## .. warning:: This is **not correct** for producing ANSI C code!
  ##
  case c
  of '\a': s.add "\\a" # \x07
  of '\b': s.add "\\b" # \x08
  of '\t': s.add "\\t" # \x09
  of '\n': s.add "\\n" # \x0A
  of '\v': s.add "\\v" # \x0B
  of '\f': s.add "\\f" # \x0C
  of '\r': (when defined(nimLegacyAddEscapedCharx0D): s.add "\\c" else: s.add "\\r") # \x0D
  of '\e': s.add "\\e" # \x1B
  of '\\': s.add("\\\\")
  of '\'': s.add("\\'")
  of '\"': s.add("\\\"")
  of {'\32'..'\126'} - {'\\', '\'', '\"'}: s.add(c)
  else:
    s.add("\\x")
    const HexChars = "0123456789ABCDEF"
    let n = ord(c)
    s.add(HexChars[int((n and 0xF0) shr 4)])
    s.add(HexChars[int(n and 0xF)])

proc addQuoted*[T](s: var string, x: T) =
  ## Appends `x` to string `s` in place, applying quoting and escaping
  ## if `x` is a string or char.
  ##
  ## See `addEscapedChar <#addEscapedChar,string,char>`_
  ## for the escaping scheme. When `x` is a string, characters in the
  ## range `{\128..\255}` are never escaped so that multibyte UTF-8
  ## characters are untouched (note that this behavior is different from
  ## `addEscapedChar`).
  ##
  ## The Nim standard library uses this function on the elements of
  ## collections when producing a string representation of a collection.
  ## It is recommended to use this function as well for user-side collections.
  ## Users may overload `addQuoted` for custom (string-like) types if
  ## they want to implement a customized element representation.
  ##
  ##   ```nim
  ##   var tmp = ""
  ##   tmp.addQuoted(1)
  ##   tmp.add(", ")
  ##   tmp.addQuoted("string")
  ##   tmp.add(", ")
  ##   tmp.addQuoted('c')
  ##   assert(tmp == """1, "string", 'c'""")
  ##   ```
  when T is string or T is cstring:
    s.add("\"")
    for c in x:
      # Only ASCII chars are escaped to avoid butchering
      # multibyte UTF-8 characters.
      if c <= 127.char:
        s.addEscapedChar(c)
      else:
        s.add c
    s.add("\"")
  elif T is char:
    s.add("'")
    s.addEscapedChar(x)
    s.add("'")
  # prevent temporary string allocation
  elif T is SomeInteger:
    s.addInt(x)
  elif T is SomeFloat:
    s.addFloat(x)
  elif compiles(s.add(x)):
    s.add(x)
  else:
    s.add($x)

proc locals*(): RootObj {.magic: "Plugin", noSideEffect.} =
  ## Generates a tuple constructor expression listing all the local variables
  ## in the current scope.
  ##
  ## This is quite fast as it does not rely
  ## on any debug or runtime information. Note that in contrast to what
  ## the official signature says, the return type is *not* `RootObj` but a
  ## tuple of a structure that depends on the current scope. Example:
  ##
  ##   ```nim
  ##   proc testLocals() =
  ##     var
  ##       a = "something"
  ##       b = 4
  ##       c = locals()
  ##       d = "super!"
  ##
  ##     b = 1
  ##     for name, value in fieldPairs(c):
  ##       echo "name ", name, " with value ", value
  ##     echo "B is ", b
  ##   # -> name a with value something
  ##   # -> name b with value 4
  ##   # -> B is 1
  ##   ```
  discard

when hasAlloc and notJSnotNims:
  # XXX how to implement 'deepCopy' is an open problem.
  proc deepCopy*[T](x: var T, y: T) {.noSideEffect, magic: "DeepCopy".} =
    ## Performs a deep copy of `y` and copies it into `x`.
    ##
    ## This is also used by the code generator
    ## for the implementation of `spawn`.
    ##
    ## For `--mm:arc` or `--mm:orc` deepcopy support has to be enabled
    ## via `--deepcopy:on`.
    discard

  proc deepCopy*[T](y: T): T =
    ## Convenience wrapper around `deepCopy` overload.
    deepCopy(result, y)

  include "system/deepcopy"

proc procCall*(x: untyped) {.magic: "ProcCall", compileTime.} =
  ## Special magic to prohibit dynamic binding for `method`:idx: calls.
  ## This is similar to `super`:idx: in ordinary OO languages.
  ##   ```nim
  ##   # 'someMethod' will be resolved fully statically:
  ##   procCall someMethod(a, b)
  ##   ```
  discard


proc `==`*(x, y: cstring): bool {.magic: "EqCString", noSideEffect,
                                   inline.} =
  ## Checks for equality between two `cstring` variables.
  proc strcmp(a, b: cstring): cint {.noSideEffect,
    importc, header: "<string.h>".}
  if pointer(x) == pointer(y): result = true
  elif pointer(x) == nil or pointer(y) == nil: result = false
  else: result = strcmp(x, y) == 0

template closureScope*(body: untyped): untyped =
  ## Useful when creating a closure in a loop to capture local loop variables by
  ## their current iteration values.
  ##
  ## Note: This template may not work in some cases, use
  ## `capture <sugar.html#capture.m,varargs[typed],untyped>`_ instead.
  ##
  ## Example:
  ##
  ##   ```nim
  ##   var myClosure : proc()
  ##   # without closureScope:
  ##   for i in 0 .. 5:
  ##     let j = i
  ##     if j == 3:
  ##       myClosure = proc() = echo j
  ##   myClosure() # outputs 5. `j` is changed after closure creation
  ##   # with closureScope:
  ##   for i in 0 .. 5:
  ##     closureScope: # Everything in this scope is locked after closure creation
  ##       let j = i
  ##       if j == 3:
  ##         myClosure = proc() = echo j
  ##   myClosure() # outputs 3
  ##   ```
  (proc() = body)()

template once*(body: untyped): untyped =
  ## Executes a block of code only once (the first time the block is reached).
  ##   ```nim
  ##   proc draw(t: Triangle) =
  ##     once:
  ##       graphicsInit()
  ##     line(t.p1, t.p2)
  ##     line(t.p2, t.p3)
  ##     line(t.p3, t.p1)
  ##   ```
  var alreadyExecuted {.global.} = false
  if not alreadyExecuted:
    alreadyExecuted = true
    body

{.pop.} # warning[GcMem]: off, warning[Uninit]: off

proc substr*(s: openArray[char]): string =
  ## Copies a slice of `s` into a new string and returns this new
  ## string.
  runnableExamples:
    let a = "abcdefgh"
    assert a.substr(2, 5) == "cdef"
    assert a.substr(2) == "cdefgh"
    assert a.substr(5, 99) == "fgh"
  result = newString(s.len)
  for i, ch in s:
    result[i] = ch

proc substr*(s: string, first, last: int): string = # A bug with `magic: Slice` requires this to exist this way
  ## Copies a slice of `s` into a new string and returns this new
  ## string.
  ##
  ## The bounds `first` and `last` denote the indices of
  ## the first and last characters that shall be copied. If `last`
  ## is omitted, it is treated as `high(s)`. If `last >= s.len`, `s.len`
  ## is used instead: This means `substr` can also be used to `cut`:idx:
  ## or `limit`:idx: a string's length.
  runnableExamples:
    let a = "abcdefgh"
    assert a.substr(2, 5) == "cdef"
    assert a.substr(2) == "cdefgh"
    assert a.substr(5, 99) == "fgh"

  let first = max(first, 0)
  let L = max(min(last, high(s)) - first + 1, 0)
  result = newString(L)
  for i in 0 .. L-1:
    result[i] = s[i+first]

proc substr*(s: string, first = 0): string =
  result = substr(s, first, high(s))

when defined(nimconfig):
  include "system/nimscript"

when not defined(js):
  proc toOpenArray*[T](x: ptr UncheckedArray[T]; first, last: int): openArray[T] {.
    magic: "Slice".}
  proc toOpenArray*(x: cstring; first, last: int): openArray[char] {.
    magic: "Slice".}
  proc toOpenArrayByte*(x: cstring; first, last: int): openArray[byte] {.
    magic: "Slice".}

proc toOpenArray*[T](x: seq[T]; first, last: int): openArray[T] {.
  magic: "Slice".}
  ## Allows passing the slice of `x` from the element at `first` to the element
  ## at `last` to `openArray[T]` parameters without copying it.
  ##
  ## Example:
  ##   ```nim
  ##   proc test(x: openArray[int]) =
  ##     doAssert x == [1, 2, 3]
  ##
  ##   let s = @[0, 1, 2, 3, 4]
  ##   s.toOpenArray(1, 3).test
  ##   ```

proc toOpenArray*[T](x: openArray[T]; first, last: int): openArray[T] {.
  magic: "Slice".}
proc toOpenArray*[I, T](x: array[I, T]; first, last: I): openArray[T] {.
  magic: "Slice".}
proc toOpenArray*(x: string; first, last: int): openArray[char] {.
  magic: "Slice".}

proc toOpenArrayByte*(x: string; first, last: int): openArray[byte] {.
  magic: "Slice".}
proc toOpenArrayByte*(x: openArray[char]; first, last: int): openArray[byte] {.
  magic: "Slice".}
proc toOpenArrayByte*(x: seq[char]; first, last: int): openArray[byte] {.
  magic: "Slice".}

proc toOpenArrayChar*(x: openArray[byte]; first, last: int): openArray[char] {.
  magic: "Slice".}

when defined(genode):
  var componentConstructHook*: proc (env: GenodeEnv) {.nimcall.}
    ## Hook into the Genode component bootstrap process.
    ##
    ## This hook is called after all globals are initialized.
    ## When this hook is set the component will not automatically exit,
    ## call `quit` explicitly to do so. This is the only available method
    ## of accessing the initial Genode environment.

  proc nim_component_construct(env: GenodeEnv) {.exportc.} =
    ## Procedure called during `Component::construct` by the loader.
    if componentConstructHook.isNil:
      env.rawQuit(programResult)
        # No native Genode application initialization,
        # exit as would POSIX.
    else:
      componentConstructHook(env)
        # Perform application initialization
        # and return to thread entrypoint.


when not defined(nimPreviewSlimSystem):
  import std/widestrs
  export widestrs

when notJSnotNims:
  when defined(windows) and compileOption("threads"):
    when not declared(addSysExitProc):
      proc addSysExitProc(quitProc: proc() {.noconv.}) {.importc: "atexit", header: "<stdlib.h>".}
    var echoLock: SysLock
    initSysLock echoLock
    addSysExitProc(proc() {.noconv.} = deinitSys(echoLock))

  const stdOutLock = compileOption("threads") and
                    not defined(windows) and
                    not defined(android) and
                    not defined(nintendoswitch) and
                    not defined(freertos) and
                    not defined(zephyr) and
                    not defined(nuttx) and
                    hostOS != "any"

  proc raiseEIO(msg: string) {.noinline, noreturn.} =
    raise newException(IOError, msg)

  proc echoBinSafe(args: openArray[string]) {.compilerproc.} =
    when defined(androidNDK):
      # When running nim in android app, stdout goes nowhere, so echo gets ignored
      # To redirect echo to the android logcat, use -d:androidNDK
      const ANDROID_LOG_VERBOSE = 2.cint
      proc android_log_print(prio: cint, tag: cstring, fmt: cstring): cint
        {.importc: "__android_log_print", header: "<android/log.h>", varargs, discardable.}
      var s = ""
      for arg in args:
        s.add arg
      android_log_print(ANDROID_LOG_VERBOSE, "nim", s)
    else:
      # flockfile deadlocks some versions of Android 5.x.x
      when stdOutLock:
        proc flockfile(f: CFilePtr) {.importc, nodecl.}
        proc funlockfile(f: CFilePtr) {.importc, nodecl.}
        flockfile(cstdout)
      when defined(windows) and compileOption("threads"):
        acquireSys echoLock
      for s in args:
        when defined(windows):
          # equivalent to syncio.writeWindows
          proc writeWindows(f: CFilePtr; s: string; doRaise = false) =
            # Don't ask why but the 'printf' family of function is the only thing
            # that writes utf-8 strings reliably on Windows. At least on my Win 10
            # machine. We also enable `setConsoleOutputCP(65001)` now by default.
            # But we cannot call printf directly as the string might contain \0.
            # So we have to loop over all the sections separated by potential \0s.
            var i = int c_fprintf(f, "%s", s)
            while i < s.len:
              if s[i] == '\0':
                let w = c_fputc('\0', f)
                if w != 0:
                  if doRaise: raiseEIO("cannot write string to file")
                  break
                inc i
              else:
                let w = c_fprintf(f, "%s", unsafeAddr s[i])
                if w <= 0:
                  if doRaise: raiseEIO("cannot write string to file")
                  break
                inc i, w
          writeWindows(cstdout, s)
        else:
          discard c_fwrite(s.cstring, cast[csize_t](s.len), 1, cstdout)
      const linefeed = "\n"
      discard c_fwrite(linefeed.cstring, linefeed.len, 1, cstdout)
      discard c_fflush(cstdout)
      when stdOutLock:
        funlockfile(cstdout)
      when defined(windows) and compileOption("threads"):
        releaseSys echoLock

when not defined(nimPreviewSlimSystem):
  import std/syncio
  export syncio

when not defined(createNimHcr) and not defined(nimscript):
  include nimhcr

when notJSnotNims and not defined(nimSeqsV2):
  proc prepareMutation*(s: var string) {.inline.} =
    ## String literals (e.g. "abc", etc) in the ARC/ORC mode are "copy on write",
    ## therefore you should call `prepareMutation` before modifying the strings
    ## via `addr`.
    runnableExamples:
      var x = "abc"
      var y = "defgh"
      prepareMutation(y) # without this, you may get a `SIGBUS` or `SIGSEGV`
      moveMem(addr y[0], addr x[0], x.len)
      assert y == "abcgh"
    discard

proc arrayWith*[T](y: T, size: static int): array[size, T] {.raises: [].} =
  ## Creates a new array filled with `y`.
  result = zeroDefault(array[size, T])
  for i in 0..size-1:
    result[i] = y

proc arrayWithDefault*[T](size: static int): array[size, T] {.raises: [].} =
  ## Creates a new array filled with `default(T)`.
  result = zeroDefault(array[size, T])
  for i in 0..size-1:
    result[i] = default(T)
