===================================
   Nim DocGen Tools Guide
===================================

:Author: Erik O'Leary
:Version: |nimversion|

.. default-role:: code
.. include:: rstcommon.rst
.. contents::

.. importdoc:: markdown_rst.md, compiler/docgen.nim

Introduction
============

This document describes the `documentation generation tools`:idx: built into
the [Nim compiler](nimc.html), which can generate HTML, Latex and JSON output
from input ``.nim`` files and projects.
The output documentation will include the module
dependencies (`import`), any top-level documentation comments (`##`), and
exported symbols (`*`), including procedures, types, and variables.

===================   ==============
command               output format
===================   ==============
`nim doc`:cmd:        ``.html`` HTML
`nim doc2tex`:cmd:    ``.tex`` LaTeX
`nim jsondoc`:cmd:    ``.json`` JSON
===================   ==============

Nim can generate HTML and LaTeX from input Markdown and
RST (reStructuredText) files as well, which is intended for writing
standalone documents like user's guides and technical specifications.
See [Nim-flavored Markdown and reStructuredText] document for the description
of this feature and particularly section [Command line usage] for the full
list of supported commands.

Quick start
-----------

Generate HTML documentation for a file:

  ```cmd
  nim doc <filename>.nim
  ```

Generate HTML documentation for a whole project:

  ```cmd
  # delete any htmldocs/*.idx file before starting
  nim doc --project --index:on --git.url:<url> --git.commit:<tag> --outdir:htmldocs <main_filename>.nim
  # this will generate html files, a theindex.html index, css and js under `htmldocs`
  # See also `--docroot` to specify a relative root.
  # to get search (dochacks.js) to work locally, you need a server otherwise
  # CORS will prevent opening file:// urls; this works:
  python3 -m http.server 7029 --directory htmldocs
  # When --outdir is omitted it defaults to $projectPath/htmldocs,
  # or `$nimcache/htmldocs` with `--usenimcache` which avoids clobbering your sources;
  # and likewise without `--project`.
  # Adding `-r` will open in a browser directly.
  # Use `--showNonExports` to show non-exported fields of an exported type.
  ```

Documentation Comments
----------------------

Any comments which are preceded by a double-hash (`##`), are interpreted as
documentation.  Comments are parsed as RST (see [reference](
https://docutils.sourceforge.net/docs/user/rst/quickref.html)), providing
Nim module authors the ability to easily generate richly formatted
documentation with only their well-documented code!
Basic Markdown syntax is also supported inside the doc comments.

Example:

  ```nim
  type Person* = object
    ## This type contains a description of a person
    name: string
    age: int
  ```

Outputs:

    Person* = object
      name: string
      age: int

  This type contains a description of a person

Field documentation comments can be added to fields like so:

  ```nim
  var numValues: int ## \
    ## `numValues` stores the number of values
  ```

Note that without the `*` following the name of the type, the documentation for
this type would not be generated. Documentation will only be generated for
*exported* types/procedures/etc.

It's recommended to always add exactly **one** space after `##` for readability
of comments — this extra space will be cropped from the parsed comments and
won't influence RST formatting.

.. note:: Generally, this baseline indentation level inside a documentation
   comment may not be 1: it can be any since it is determined by the offset
   of the first non-whitespace character in the comment.
   After that indentation **must** be consistent on the following lines of
   the same comment.
   If you still need to add an additional indentation at the very beginning
   (for RST block quote syntax) use backslash \\ before it:

     ```nim
     ## \
     ##
     ##    Block quote at the first line.
     ##
     ## Paragraph.
     ```

Structuring output directories
------------------------------

Basic directory for output is set by `--outdir:OUTDIR`:option: switch,
by default `OUTDIR` is ``htmldocs`` sub-directory in the directory of
the processed file.

There are 2 basic options as to how generated HTML output files are stored:

1) complex hierarchy when docgen-compiling with `--project`:option:,
   which follows directory structure of the project itself.
   So `nim doc`:cmd: replicates project's directory structure
   inside `--outdir:OUTDIR`:option: directory.
   `--project`:option: is well suited for projects that have 1 main module.
   File name clashes are impossible in this case.

2) flattened structure, where user-provided script goes through all
   needed input files and calls commands like `nim doc`:cmd:
   with `--outdir:OUTDIR`:option: switch, thus putting all HTML (and
   ``.idx``) files into 1 directory.

   .. Important:: Make sure that you don't have files with same base name
     like ``x.nim`` and ``x.md`` in the same package, otherwise you'll
     have name conflict for ``x.html``.

   .. Tip:: To structure your output directories and avoid file name
     clashes you can split your project into
     different *packages* -- parts of your repository that are
     docgen-compiled with different `--outdir:OUTDIR`:option: options.

     An example of such strategy is Nim repository itself which has:

     * its stdlib ``.nim`` files from different directories and ``.md``
       documentation from ``doc/`` directory are all docgen-compiled
       into `--outdir:web/upload/<version>/`:option: directory
     * its ``.nim`` files from ``compiler/`` directory are docgen-compiled
       into `--outdir:web/upload/<version>/compiler/`:option: directory.
       Interestingly, it's compiled with complex hierarchy using
       `--project`:option: switch.

     Contents of ``web/upload/<version>`` are then deployed into Nim's
     Web server.

     This output directory structure allows to work correctly with files like
     ``compiler/docgen.nim`` (implementation) and ``doc/docgen.md`` (user
     documentation) in 1 repository.


Index files
-----------

Index (``.idx``) files are used for 2 different purposes:

1. easy cross-referencing between different ``.nim`` and/or ``.md`` / ``.rst``
   files described in [Nim external referencing]
2. creating a whole-project index for searching of symbols and keywords,
   see [Buildindex command].


Document Types
==============

Example of Nim file input
-------------------------

The following examples will generate documentation for this sample
*Nim* module, aptly named ``doc/docgen_sample.nim``:

   ```nim file=docgen_sample.nim
   ```

All the below commands save their output to ``htmldocs`` directory relative to
the directory of file;
hence the output for this sample will be in ``doc/htmldocs``.

HTML
----

The generation of HTML documents is done via the `doc`:option: command. This command
takes either a single ``.nim`` file, outputting a single ``.html`` file with the same
base filename, or multiple ``.nim`` files, outputting multiple ``.html`` files and,
optionally, an index file.

The `doc`:option: command:

  ```cmd
  nim doc docgen_sample.nim
  ```

Partial Output:

    ...
    proc helloWorld(times: int) {.raises: [], tags: [].}
    ...

The full output can be seen here: [docgen_sample.html](docgen_sample.html).
It runs after semantic checking and includes pragmas attached implicitly by the
compiler.

LaTeX
-----

LaTeX files are intended to be converted to PDF, especially for offline
reading or making hard copies. (LaTeX output is oftentimes better than
HTML -> PDF conversion).

The `doc2tex`:option: command:

  ```cmd
  nim doc2tex docgen_sample.nim
  cd htmldocs
  xelatex docgen_sample.tex
  xelatex docgen_sample.tex
  # It is usually necessary to run `xelatex` 2 times (or even 3 times for
  # large documents) to get all labels generated.
  # That depends on this warning in the end of `xelatex` output:
  #   LaTeX Warning: Label(s) may have changed. Rerun to get cross-references right.
  ```

The output is ``docgen_sample.pdf``.

JSON
----

The generation of JSON documents is done via the `jsondoc`:option: command.
This command takes in a ``.nim`` file and outputs a ``.json`` file with
the same base filename.
Note that this tool is built off of the `doc`:option: command
(previously `doc2`:option:), and contains the same information.

The `jsondoc`:option: command:

  ```cmd
  nim jsondoc docgen_sample.nim
  ```

Output:

    {
      "orig": "docgen_sample.nim",
      "nimble": "",
      "moduleDescription": "This module is a sample",
      "entries": [
        {
          "name": "helloWorld",
          "type": "skProc",
          "line": 5,
          "col": 0,
          "description": "Takes an integer and outputs as many &quot;hello world!&quot;s",
          "code": "proc helloWorld(times: int) {.raises: [], tags: [].}"
        }
      ]
    }

Similarly to the old `doc`:option: command, the old `jsondoc`:option: command has been
renamed to `jsondoc0`:option:.

The `jsondoc0`:option: command:

  ```cmd
  nim jsondoc0 docgen_sample.nim
  ```

Output:

    [
      {
        "comment": "This module is a sample."
      },
      {
        "name": "helloWorld",
        "type": "skProc",
        "description": "Takes an integer and outputs as many &quot;hello world!&quot;s",
        "code": "proc helloWorld*(times: int)"
      }
    ]

Note that the `jsondoc`:option: command outputs its JSON without pretty-printing it,
while `jsondoc0`:option: outputs pretty-printed JSON.


Simple documentation links
==========================

It's possible to use normal Markdown/RST syntax to *manually*
reference Nim symbols using HTML anchors, however Nim has an *automatic*
facility that makes referencing inside ``.nim`` and ``.md/.rst`` files and
between them easy and seamless.
The point is that such links will be resolved automatically
by `nim doc`:cmd: (or `md2html`:option:, or `jsondoc`:option:,
or `doc2tex`:option:, ...). And, unlike manual links, such automatic
links **check** that their target exists -- a warning is emitted for
any broken link, so you avoid broken links in your project.

Nim treats both ``.md/.rst`` files and ``.nim`` modules (their doc comment
part) as *documents* uniformly.
Hence all directions of referencing are equally possible having the same syntax:

1. ``.md/rst`` -> itself (internal). See [Markup local referencing].
2. ``.md/rst`` -> external ``.md/rst``. See [Markup external referencing].
   To summarize, referencing in `.md`/`.rst` files was already described in
   [Nim-flavored Markdown and reStructuredText]
   (particularly it described usage of index files for referencing),
   while in this document we focus on Nim-specific details.
3. ``.md/rst`` -> external ``.nim``. See [Nim external referencing].
4. ``.nim`` -> itself (internal). See [Nim local referencing].
5. ``.nim`` -> external ``.md/rst``. See [Markup external referencing].
6. ``.nim`` -> external ``.nim``. See [Nim external referencing].

To put it shortly, local referencing always works out of the box,
external referencing requires to use ``.. importdoc:: <file>``
directive to import `file` and to ensure that the corresponding
``.idx`` file was generated.

Syntax for referencing is basically the same as for normal markup.
Recall from [Referencing] that our parser supports two equivalent syntaxes
for referencing, Markdown and RST one.
So to reference ``proc f`` one should use something like that,
depending on markup type:

    Markdown                    RST

    Ref. [proc f] or [f]        Ref. `proc f`_ or just f_ for a one-word case

Nim local referencing
---------------------

You can reference Nim identifiers from Nim documentation comments
inside their ``.nim`` file (or inside a ``.rst`` file included from
a ``.nim``).
This pertains to any exported symbol like `proc`, `const`, `iterator`, etc.
Link text is either one word or a group of words enclosed by delimiters
(brackets ``[...]`` for Markdown or backticks `\`...\`_` for RST).
Link text will be displayed *as is* while *link target* will be set to
the anchor [^1] of Nim symbol that corresponds to link text.

[^1] anchors' format is described in [HTML anchor generation] section below.

If you have a constant:

  ```Nim
  const pi* = 3.14
  ```

then it should be referenced in one of the 2 forms:

A. non-qualified (no symbol kind specification):

       pi_

B. qualified (with symbol kind specification):

       `const pi`_

For routine kinds there are more options. Consider this definition:

  ```Nim
  proc foo*(a: int, b: float): string
  ```

Generally following syntax is allowed for referencing `foo`:

*  short (without parameters):

   A. non-qualified:

          foo_

   B. qualified:

          `proc foo`_

*  longer variants (with parameters):

   A. non-qualified:

      1) specifying parameters names:

             `foo(a, b)`_

      2) specifying parameters types:

             `foo(int, float)`_

      3) specifying both names and types:

             `foo(a: int, b: float)`_

      4) output parameter can also be specified if you wish:

             `foo(a: int, b: float): string`_

   B. qualified: all 4 options above are valid.
      Particularly you can use the full format:

          `proc foo(a: int, b: float): string`_

.. Tip:: Avoid cluttering your text with extraneous information by using
   one of shorter forms:

       binarySearch_
       `binarySearch(a, key, cmp)`_

   Brevity is better for reading! If you use a short form and have an
   ambiguity problem (see below) then just add some additional info.

Symbol kind like `proc` can also be specified in the postfix form:

    `foo proc`_
    `walkDir(d: string) iterator`_

.. Warning:: An ambiguity in resolving documentation links may arise because of:

   1. clash with other RST anchors
      * manually setup anchors
      * automatically set up, e.g. section names
   2. collision with other Nim symbols:

      * routines with different parameters can exist e.g. for
        `proc` and `template`. In this case they are split between their
        corresponding sections in output file. Qualified references are
        useful in this case -- just disambiguate by referring to these
        sections explicitly:

            See `foo proc`_ and `foo template`_.

      * because in Nim `proc` and `iterator` belong to different namespaces,
        so there can be a collision even if parameters are the same.
        Use `\`proc foo\`_`:literal: or `\`iterator foo\`_`:literal: then.

   Any ambiguity is always reported with Nim compiler warnings and an anchor
   with higher priority is selected. Manual anchors have highest
   priority, then go automatic RST anchors; then Nim-generated anchors
   (while procs have higher priority than other Nim symbol kinds).

Generic parameters can also be used. All in all, this long form will be
recognized fine:

    `proc binarySearch*[T; K](a: openArray[T], key: K, cmp: proc(T, K)): int`_

**Limitations**:

1. The parameters of a nested routine type can be specified only with types
   (without parameter names, see form A.2 above).
   E.g. for this signature:

      ```Nim
      proc binarySearch*[T, K](a: openArray[T]; key: K;
                               cmp: proc (x: T; y: K): int {.closure.}): int
                                          ~~    ~~   ~~~~~
      ```

   you cannot use names underlined by `~~` so it must be referenced with
   ``cmp: proc(T, K)``. Hence these forms are valid:

       `binarySearch(a: openArray[T], key: K, cmp: proc(T, K))`_
       `binarySearch(openArray[T], K, proc(T, K))`_
       `binarySearch(a, key, cmp)`_
2. Default values in routine parameters are not recognized, one needs to
   specify the type and/or name instead. E.g. for referencing `proc f(x = 7)`
   use one of the mentioned forms:

       `f(int)`_ or `f(x)`_ or `f(x: int)`_.
3. Generic parameters must be given the same way as in the
   definition of referenced symbol.

   * their names should be the same
   * parameters list should be given the same way, e.g. without substitutions
     between commas (,) and semicolons (;).

.. Note:: A bit special case is operators
   (as their signature is also defined with `\``):

      ```Nim
      func `$`(x: MyType): string
      func `[]`*[T](x: openArray[T]): T
      ```

   A short form works without additional backticks:

       `$`_
       `[]`_

   However for fully-qualified reference copy-pasting backticks (`) into other
   backticks will not work in our RST parser (because we use Markdown-like
   inline markup rules). You need either to delete backticks or keep
   them and escape with backslash \\:

       no backticks: `func $`_
       escaped:  `func \`$\``_
       no backticks: `func [][T](x: openArray[T]): T`_
       escaped:  `func \`[]\`[T](x: openArray[T]): T`_

.. Note:: Types that defined as `enum`, or `object`, or `tuple` can also be
   referenced with those names directly (instead of `type`):

       type CopyFlag = enum
         ...
       ## Ref. `CopyFlag enum`_

Nim external referencing
------------------------

Just like for [Markup external referencing], which saves markup anchors,
the Nim symbols are also saved in ``.idx`` files, so one needs
to generate them beforehand, and they should be loaded by
an ``.. importdoc::`` directive. Arguments to ``.. importdoc::`` is a
comma-separated list of Nim modules or Markdown/RST documents.

`--index:only`:option: tells Nim to only generate ``.idx`` file and
do **not** attempt to generate HTML/LaTeX output.
For ``.nim`` modules there are 2 alternatives to work with ``.idx`` files:

1. using [Project switch] implies generation of ``.idx`` files,
   however, if ``importdoc`` is called on upper modules as its arguments,
   their ``.idx`` are not yet created. Thus one should generate **all**
   required ``.idx`` first:
     ```cmd
     nim doc --project --index:only <main>.nim
     nim doc --project <main>.nim
     ```
2. or run `nim doc --index:only <module.nim>`:cmd: command for **all** (used)
   Nim modules in your project. Then run `nim doc <module.nim>` on them for
   output HTML generation.

   .. Warning:: A mere `nim doc --index:on`:cmd: may fail on an attempt to do
      ``importdoc`` from another module (for which ``.idx`` was not yet
      generated), that's why `--index:only`:option: shall be used instead.

   For ``.md``/``.rst`` markup documents point 2 is the only option.

Then, you can freely use something like this in ``your_module.nim``:

  ```nim
  ## .. importdoc::  user_manual.md, another_module.nim

  ...
  ## Ref. [some section from User Manual].

  ...
  ## Ref. [proc f]
  ## (assuming you have a proc `f` in ``another_module``).
  ```

and compile it by `nim doc`:cmd:. Note that link text will
be automatically prefixed by the module name of symbol,
so you will see something like "Ref. [another_module: proc f](#)"
in the generated output.

It's also possible to reference a whole module by prefixing or
suffixing full canonical module name with "module":

    Ref. [module subdir/name] or [subdir/name module].

Markup documents as a whole can be referenced just by their title
(or by their file name if the title was not set) without any prefix.

.. Tip:: During development process the stage of ``.idx`` files generation
  can be done only *once*, after that you use already generated ``.idx``
  files while working with a document *being developed* (unless you do
  incompatible changes to *referenced* documents).

.. Hint:: After changing a *referenced* document file one may need
  to regenerate its corresponding ``.idx`` file to get correct results.
  Of course, when referencing *internally* inside any given ``.nim`` file,
  it's not needed, one can even immediately use any freshly added anchor
  (a document's own ``.idx`` file is not used for resolving its internal links).

If an ``importdoc`` directive fails to find a ``.idx``, then an error
is emitted.

In case of such compilation failures please note that:

* **all** relative paths, given to ``importdoc``, relate to insides of
  ``OUTDIR``, and **not** project's directory structure.

* ``importdoc`` searches for ``.idx`` in `--outdir:OUTDIR`:option: directory
  (``htmldocs`` by default) and **not** around original modules, so:

  .. Tip:: look into ``OUTDIR`` to understand what's going on.

* also keep in mind that ``.html`` and ``.idx`` files should always be
  output to the same directory, so check this and, if it's not true, check
  that both runs *with* and *without* `--index:only`:option: have all
  other options the same.

To summarize, for 2 basic options of [Structuring output directories]
compilation options are different:

1) complex hierarchy with `--project`:option: switch.

   As the **original** project's directory structure is replicated in
   `OUTDIR`, all passed paths are related to this structure also.

   E.g. if a module ``path1/module.nim`` does
   ``.. importdoc:: path2/another.nim`` then docgen tries to load file
   ``OUTDIR/path1/path2/another.idx``.

   .. Note:: markup documents are just placed into the specified directory
     `OUTDIR`:option: by default (i.e. they are **not** affected by
     `--project`:option:), so if you have ``PROJECT/doc/manual.md``
     document and want to use complex hierarchy (with ``doc/``),
     compile it with `--docroot`:option:\:
       ```cmd
       # 1st stage
       nim md2html --outdir:OUTDIR --docroot:/absolute/path/to/PROJECT \
            --index:only PROJECT/doc/manual.md
       ...
       # 2nd stage
       nim md2html --outdir:OUTDIR --docroot:/absolute/path/to/PROJECT \
                         PROJECT/doc/manual.md
       ```

     Then the output file will be placed as ``OUTDIR/doc/manual.idx``.
     So if you have ``PROJECT/path1/module.nim``, then ``manual.md`` can
     be referenced as ``../doc/manual.md``.

2) flattened structure.

   E.g. if a module ``path1/module.nim`` does
   ``.. importdoc:: path2/another.nim`` then docgen tries to load
   ``OUTDIR/path2/another.idx``, so the path ``path1``
   does not matter and providing ``path2`` can be useful only
   in the case it contains another package that was placed there
   using `--outdir:OUTDIR/path2`:option:.

   The links' text will be prefixed as ``another: ...`` in both cases.

   .. Warning:: Again, the same `--outdir:OUTDIR`:option: option should
     be provided to both `doc --index:only`:option: /
     `md2html --index:only`:option: and final generation by
     `doc`:option:/`md2html`:option: inside 1 package.

To temporarily disable ``importdoc``, e.g. if you don't need
correct link resolution at the moment, use a `--noImportdoc`:option: switch
(only warnings about unresolved links will be generated for external references).

Related Options
===============

Project switch
--------------

  ```cmd
  nim doc --project filename.nim
  ```

This will recursively generate documentation of all Nim modules imported
into the input module that belong to the Nimble package that ``filename.nim``
belongs to. The index files and the corresponding ``theindex.html`` will
also be generated.


Index switch
------------

  ```cmd
  nim doc --index:on filename.nim
  ```

This will generate an index of all the exported symbols in the input Nim
module, and put it into a neighboring file with the extension of ``.idx``. The
index file is line-oriented (newlines have to be escaped). Each line
represents a tab-separated record of several columns, the first two mandatory,
the rest optional. See the [Index (idx) file format] section for details.

.. Note:: `--index`:option: switch only affects creation of ``.idx``
  index files, while user-searchable Index HTML file is created by
  `buildIndex`:option: command.

Buildindex command
------------------

Once index files have been generated for one or more modules, the Nim
compiler command `nim buildIndex directory`:cmd: can be run to go over all the index
files in the specified directory to generate a [theindex.html](theindex.html)
file:

  ```cmd
  nim buildIndex -o:path/to/htmldocs/theindex.html path/to/htmldocs
  ```

See source switch
-----------------

  ```cmd
  nim doc --git.url:<url> filename.nim
  ```

With the `git.url`:option: switch the *See source* hyperlink will appear below each
documented item in your source code pointing to the implementation of that
item on a GitHub repository.
You can click the link to see the implementation of the item.

The `git.commit`:option: switch overrides the hardcoded `devel` branch in
``config/nimdoc.cfg``.
This is useful to link to a different branch e.g. `--git.commit:master`:option:,
or to a tag e.g. `--git.commit:1.2.3`:option: or a commit.

Source URLs are generated as ``href="${url}/tree/${commit}/${path}#L${line}"``
by default and thus compatible with GitHub but not with GitLab.

Similarly, `git.devel`:option: switch overrides the hardcoded `devel` branch
for the `Edit` link which is also useful if you have a different working
branch than `devel` e.g. `--git.devel:master`:option:.

Edit URLs are generated as ``href="${url}/tree/${devel}/${path}#L${line}"``
by default.

You can edit ``config/nimdoc.cfg`` and modify the ``doc.item.seesrc`` value
with a hyperlink to your own code repository.

In the case of Nim's own documentation, the `commit` value is just a commit
hash to append to a formatted URL to https://github.com/nim-lang/Nim.


Other Input Formats
===================

The *Nim compiler* also has support for RST (reStructuredText) files with
the `rst2html`:option: and `rst2tex`:option: commands. Documents like this one are
initially written in a dialect of RST which adds support for Nim source code
highlighting with the ``.. code-block:: nim`` prefix. ``code-block`` also
supports highlighting of a few other languages supported by the
[packages/docutils/highlite module](highlite.html).

See [Markdown and RST markup languages](markdown_rst.html) for
usage of those commands.

HTML anchor generation
======================

When you run the `rst2html`:option: command, all sections in the RST document will
get an anchor you can hyperlink to. Usually, you can guess the anchor lower
casing the section title and replacing spaces with dashes, and in any case, you
can get it from the table of contents. But when you run the `doc`:option:
command to generate API documentation, some symbol get one or two anchors at
the same time: a numerical identifier, or a plain name plus a complex name.

The numerical identifier is just a random number. The number gets assigned
according to the section and position of the symbol in the file being processed
and you should not rely on it being constant: if you add or remove a symbol the
numbers may shuffle around.

The plain name of a symbol is a simplified version of its fully exported
signature. Variables or constants have the same plain name symbol as their
complex name. The plain name for procs, templates, and other callable types
will be their unquoted value after removing parameters, return types, and
pragmas. The plain name allows short and nice linking of symbols that works
unless you have a module with collisions due to overloading.

If you hyperlink a plain name symbol and there are other matches on the same
HTML file, most browsers will go to the first one. To differentiate the rest,
you will need to use the complex name. A complex name for a callable type is
made up of several parts:

  (**plain symbol**)(**.type**),(**first param**)?(**,param type**)\*

The first thing to note is that all callable types have at least a comma, even
if they don't have any parameters. If there are parameters, they are
represented by their types and will be comma-separated. To the plain symbol a
suffix may be added depending on the type of the callable:

==============   ==============
Callable type    Suffix
==============   ==============
`proc`, `func`   *empty string*
`macro`          ``.m``
`method`         ``.e``
`iterator`       ``.i``
`template`       ``.t``
`converter`      ``.c``
==============   ==============

The relationship of type to suffix is made by the proc `complexName` in the
``compiler/docgen.nim`` file. Here are some examples of complex names for
symbols in the [system module](system.html).

* `type SomeSignedInt = int | int8 | int16 | int32 | int64` **=>**
  [#SomeSignedInt](system.html#SomeSignedInt)
* `var globalRaiseHook: proc (e: ref E_Base): bool {.nimcall.}` **=>**
  [#globalRaiseHook](system.html#globalRaiseHook)
* `const NimVersion = "0.0.0"` **=>**
  [#NimVersion](system.html#NimVersion)
* `proc getTotalMem(): int {.rtl, raises: [], tags: [].}` **=>**
  [#getTotalMem](system.html#getTotalMem)
* `proc len[T](x: seq[T]): int {.magic: "LengthSeq", noSideEffect.}` **=>**
  [#len,seq[T]](system.html#len,seq[T])
* `iterator pairs[T](a: seq[T]): tuple[key: int, val: T] {.inline.}` **=>**
  [#pairs.i,seq[T]](iterators.html#pairs.i,seq[T])
* `template newException[](exceptn: typedesc; message: string;
    parentException: ref Exception = nil): untyped` **=>**
  [#newException.t,typedesc,string,ref.Exception](
  system.html#newException.t,typedesc,string,ref.Exception)


Index (idx) file format
=======================

Files with the ``.idx`` extension are generated when you use the [Index
switch] along with commands to generate
documentation from source or text files. You can programmatically generate
indices with the [setIndexTerm()](
rstgen.html#setIndexTerm,RstGenerator,string,string,string,string,string)
and `writeIndexFile() <rstgen.html#writeIndexFile,RstGenerator,string>`_ procs.
The purpose of `idx` files is to hold the interesting symbols and their HTML
references so they can be later concatenated into a big index file with
[mergeIndexes()](rstgen.html#mergeIndexes,string).  This section documents
the file format in detail.

Index files are line-oriented and tab-separated (newline and tab characters
have to be escaped). Each line represents a record with 6 fields.
The content of these columns is:

0. Discriminator tag denoting type of the index entry, allowed values are:
   `markupTitle`
   : a title for ``.md``/``.rst`` document
   `nimTitle`
   : a title of ``.nim`` module
   `heading`
   : heading of sections, can be both in Nim and markup files
   `idx`
   : terms marked with :idx: role
   `nim`
   : a Nim symbol
   `nimgrp`
   : a Nim group for overloadable symbols like `proc`s
1. Mandatory term being indexed. Terms can include quoting according to
   Nim's rules (e.g. \`^\`).
2. Base filename plus anchor hyperlink (e.g. ``algorithm.html#*,int,SortOrder``).
3. Optional human-readable string to display as a hyperlink. If the value is not
   present or is the empty string, the hyperlink will be rendered
   using the term. Prefix whitespace indicates that this entry is
   not for an API symbol but for a TOC entry.
4. Optional title or description of the hyperlink. Browsers usually display
   this as a tooltip after hovering a moment over the hyperlink.
5. A line number of file where the entry was defined.

The index generation tools differentiate between documentation
generated from ``.nim`` files and documentation generated from ``.md`` or
``.rst`` files by tag `nimTitle` or `markupTitle` in the 1st line of
the ``.idx`` file.

.. TODO Normal symbols are added to the index with surrounding whitespaces removed. An
  exception to this are the table of content (TOC) entries. TOC entries are added to
  the index file with their third column having as much prefix spaces as their
  level is in the TOC (at least 1 character). The prefix whitespace helps to
  filter TOC entries from API or text symbols. This is important because the
  amount of spaces is used to replicate the hierarchy for document TOCs in the
  final index, and TOC entries found in ``.nim`` files are discarded.


Additional resources
====================

* [Nim Compiler User Guide](nimc.html#compiler-usage-commandminusline-switches)

* already mentioned documentation for
  [Markdown and RST markup languages](markdown_rst.html), which also
  contains the list of implemented features of these markup languages.

* the implementation is in [module compiler/docgen].

The output for HTML and LaTeX comes from the ``config/nimdoc.cfg`` and
``config/nimdoc.tex.cfg`` configuration files. You can add and modify these
files to your project to change the look of the docgen output.

You can import the [packages/docutils/rstgen module](rstgen.html) in your
programs if you want to reuse the compiler's documentation generation procs.
