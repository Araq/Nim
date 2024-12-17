.. default-role:: code
.. include:: ../doc/rstcommon.rst

The System module imports several separate modules, and their documentation
is in separate files:

* `iterators <iterators.html>`_
* `exceptions <exceptions.html>`_
* `assertions <assertions.html>`_
* `dollars <dollars.html>`_
* `ctypes <ctypes.html>`_
* `repr_v2 <repr_v2.html>`_


Here is a short overview of the most commonly used functions from the
`system` module. Function names in the tables below are clickable and
will take you to the full documentation of the function.

There are many more functions available than the ones listed in this overview.
Use the table of contents on the left-hand side and/or `Ctrl+F` to navigate
through this module.


Strings and characters
----------------------

=============================     =======================================
Proc                              Usage
=============================     =======================================
`len(s)<#len,string>`_            Return the length of a string
`chr(i)<#chr,range[]>`_           Convert an `int` in the range `0..255`
                                  to a character
`ord(c)<#ord,T>`_                 Return `int` value of a character
`a & b<#&,string,string>`_        Concatenate two strings
`s.add(c)<#add,string,char>`_     Add character to the string
`$<dollars.html>`_                Convert various types to string
=============================     =======================================

**See also:**
* `strutils module <strutils.html>`_ for common string functions
* `strformat module <strformat.html>`_ for string interpolation and formatting
* `unicode module <unicode.html>`_ for Unicode UTF-8 handling
* `strscans <strscans.html>`_ for `scanf` and `scanp` macros, which offer
  easier substring extraction than regular expressions
* `strtabs module <strtabs.html>`_ for efficient hash tables
  (dictionaries, in some programming languages) mapping from strings to strings



Seqs
----

=============================================================  ==========================================
Proc                                                           Usage
=============================================================  ==========================================
`newSeq<#newSeq>`_                                             Create a new sequence of a given length
`newSeqOfCap<#newSeqOfCap,Natural>`_                           Create a new sequence with zero length
                                                               and a given capacity
`setLen<#setLen,seq[T],Natural>`_                              Set the length of a sequence
`len<#len,seq[T]>`_                                            Return the length of a sequence
`@<#@,openArray[T]>`_                                          Turn an array into a sequence
`add<#add,seq[T],sinkT>`_                                      Add an item to the sequence
`insert<#insert,seq[T],sinkT>`_                                Insert an item at a specific position
`delete<#delete,seq[T],Natural>`_                              Delete an item while preserving the
                                                               order of elements (`O(n)` operation)
`del<#del,seq[T],Natural>`_                                    `O(1)` removal, doesn't preserve the order
`pop<#pop,seq[T]>`_                                            Remove and return last item of a sequence
`x & y<#&,seq[T],seq[T]>`_                                     Concatenate two sequences
`x[a .. b]<#[],openArray[T],HSlice[U: Ordinal,V: Ordinal]>`_   Slice of a sequence (both ends included)
`x[a .. ^b]<#[],openArray[T],HSlice[U: Ordinal,V: Ordinal]>`_  Slice of a sequence but `b` is a 
                                                               reversed index (both ends included)
`x[a ..< b]<#[],openArray[T],HSlice[U: Ordinal,V: Ordinal]>`_  Slice of a sequence (excluded upper bound)
=============================================================  ==========================================

**See also:**
* `sequtils module <sequtils.html>`_ for operations on container
  types (including strings)
* `json module <json.html>`_ for a structure which allows heterogeneous members
* `lists module <lists.html>`_ for linked lists



Sets
----

Built-in bit sets.

===============================     ======================================
Proc                                Usage
===============================     ======================================
`incl<#incl,set[T],T>`_             Include element `y` in the set `x`
`excl<#excl,set[T],T>`_             Exclude element `y` from the set `x`
`card<#card,set[T]>`_               Return the cardinality of the set,
                                    i.e. the number of elements
`a * b<#*,set[T],set[T]>`_          Intersection
`a + b<#+,set[T],set[T]>`_          Union
`a - b<#-,set[T],set[T]>`_          Difference
`contains<#contains,set[T],T>`_     Check if an element is in the set
[a < b](#<,set[T],set[T])           Check if `a` is a subset of `b`
===============================     ======================================

**See also:**
* `setutils module <setutils.html>`_ for bit set convenience functions
* `sets module <sets.html>`_ for hash sets
* `intsets module <intsets.html>`_ for efficient int sets



Numbers
-------

==============================    ==================================     =====================
Proc                              Usage                                  Also known as
                                                                         (in other languages)
==============================    ==================================     =====================
`div<#div,int,int>`_              Integer division                       `//`
`mod<#mod,int,int>`_              Integer modulo (remainder)             `%`
`shl<#shl,int,SomeInteger>`_      Shift left                             `<<`
`shr<#shr,int,SomeInteger>`_      Shift right                            `>>`
`ashr<#ashr,int,SomeInteger>`_    Arithmetic shift right
`and<#and,int,int>`_              Bitwise `and`                          `&`
`or<#or,int,int>`_                Bitwise `or`                           `|`
`xor<#xor,int,int>`_              Bitwise `xor`                          `^`
`not<#not,int>`_                  Bitwise `not` (complement)             `~`
`toInt<#toInt,float>`_            Convert floating-point number
                                  into an `int`
`toFloat<#toFloat,int>`_          Convert an integer into a `float`
==============================    ==================================     =====================

**See also:**
* `math module <math.html>`_ for mathematical operations like trigonometric
  functions, logarithms, square and cubic roots, etc.
* `complex module <complex.html>`_ for operations on complex numbers
* `rationals module <rationals.html>`_ for rational numbers



Ordinals
--------

`Ordinal type <#Ordinal>`_ includes integer, bool, character, and enumeration
types, as well as their subtypes.

=====================     =======================================
Proc                      Usage
=====================     =======================================
succ_                     Successor of the value
pred_                     Predecessor of the value
inc_                      Increment the ordinal
dec_                      Decrement the ordinal
`high<#high,T>`_          Return the highest possible value
`low<#low,T>`_            Return the lowest possible value
`ord<#ord,T>`_            Return `int` value of an ordinal value
=====================     =======================================



Misc
----

====================================================  ============================================
Proc                                                  Usage
====================================================  ============================================
`is<#is,T,S>`_                                        Check if two arguments are of the same type
`isnot<#isnot.t,untyped,untyped>`_                    Negated version of `is`
`!=<#!%3D.t,untyped,untyped>`_                        Not equals
`addr<#addr,T>`_                                      Take the address of a memory location
`T and F<#and,bool,bool>`_                            Boolean `and`
`T or F<#or,bool,bool>`_                              Boolean `or`
`T xor F<#xor,bool,bool>`_                            Boolean `xor` (exclusive or)
`not T<#not,bool>`_                                   Boolean `not`
`a[^x]<#^.t,int>`_                                    Take the element at the reversed index `x`
`a .. b<#..,sinkT,sinkU>`_                            Binary slice that constructs an interval
                                                      `[a, b]`
`a ..^ b<#..^.t,untyped,untyped>`_                    Interval `[a, b]` but `b` as reversed index
[a ..< b](#..<.t,untyped,untyped)                     Interval `[a, b)` (excluded upper bound)
[runnableExamples](#runnableExamples,string,untyped)  Create testable documentation
====================================================  ============================================
