Version 0.15.0 released
=======================

.. container:: metadata

  Posted by Dominik Picheta on 17/09/2016

Some text here.

Changes affecting backwards compatibility
-----------------------------------------

- De-deprecated ``re.nim`` because we have too much code using it
  and it got the basic API right.

- ``split`` with ``set[char]`` as a delimiter in ``strutils.nim``
  no longer strips and splits characters out of the target string
  by the entire set of characters. Instead, it now behaves in a
  similar fashion to ``split`` with ``string`` and ``char``
  delimiters.

Library Additions
-----------------

- Added ``readHeaderRow`` and ``rowEntry`` to ``parsecsv.nim`` to provide
  a lightweight alternative to python's ``csv.DictReader``.
- Added ``setStdIoUnbuffered`` proc to ``system.nim`` to enable unbuffered I/O.

- Added ``center`` and ``rsplit`` to ``strutils.nim`` to
  provide similar Python functionality for Nim's strings.

- Added ``isTitle``, ``title``, ``swapCase``, ``isUpper``, ``toUpper``,
  ``isLower``, ``toLower``, ``isAlpha``, ``isSpace``, and ``capitalize``
  to ``unicode.nim`` to provide unicode aware case manipulation and case
  testing.

- Added a new module ``lib/pure/strmisc.nim`` to hold uncommon string
  operations. Currently contains ``partition``, ``rpartition``
  and ``expandTabs``.

- Split out ``walkFiles`` in ``os.nim`` to three separate procs in order
  to make a clear distinction of functionality. ``walkPattern`` iterates
  over both files and directories, while ``walkFiles`` now only iterates
  over files and ``walkDirs`` only iterates over directories.

Compiler Additions
------------------

Language Additions
------------------

Bugfixes
--------
