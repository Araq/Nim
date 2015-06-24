The Git stuff
=============

General commit rules
--------------------

1. All changes introduced by the commit (diff lines) must be related to the
   subject of the commit.

   If you change some other unrelated to the subject parts of the file, because
   your editor reformatted automatically the code or whatever different reason,
   this should be excluded from the commit.

   *Tip:* Never commit everything as is using ``git commit -a``, but review
   carefully your changes with ``git add -p``.

2. Changes should not introduce any trailing whitespace.

   Always check your changes for whitespace errors using ``git diff --check``
   or add following ``pre-commit`` hook:

   .. code-block:: sh

      #!/bin/sh
      git diff --check --cached || exit $?

   No sane programming or markup language cares about trailing whitespace, so
   tailing whitespace is just a noise you should not introduce to the
   repository.

3. Describe your commit well following the 50/72 rule on commit messages:

   Start with the commit subject as single line maximum of 50 characters,
   without trailing period, briefly describing the change.

   Optionally put the detailed description as a blocks of text wrapped to 72
   characters, separated by single blank line from the other parts (including
   the subject).

4. Don't squash commits in your pull request. It makes it harder to
   follow the discussion if you can't see what changed after a
   conversation.

More information
----------------

For more information on how to produce great commits and describe them well read:

* `How to Write a Git Commit Message <http://chris.beams.io/posts/git-commit/>`_
* `A Note About Git Commit Messages <http://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html>`_
* `Guide by github, scroll down a bit <https://guides.github.com/activities/contributing-to-open-source/>`_

Deprecation
===========

Backward compatibility is important, so if you are renaming a proc or
a type, you can use


.. code-block:: nim

  {.deprecated [oldName: new_name].}

Or you can simply use

.. code-block:: nim

  proc oldProc() {.deprecated.}

to mark a symbol as deprecated. Works for procs/types/vars/consts,
etc.

`Deprecated pragma in the manual. <http://nim-lang.org/docs/manual.html#pragmas-deprecated-pragma>`_

Writing tests
=============

Not all the tests follow this scheme, feel free to change the ones
that don't. Always leave the code cleaner than you found it.

Stdlib
------

If you change the stdlib (anything under ``lib/``), put a test in the
file you changed. Add the tests under an ``when isMainModule:``
condition so they only get executed when the tester is building the
file. Each test should be in a separate ``block:`` statement, such that
each has its own scope. Use boolean conditions and ``doAssert`` for the
testing by itself, don't rely on echo statements or similar.

Sample test:

.. code-block:: nim

  when isMainModule:
    block: # newSeqWith tests
      var seq2D = newSeqWith(4, newSeq[bool](2))
      seq2D[0][0] = true
      seq2D[1][0] = true
      seq2D[0][1] = true
      doAssert seq2D == @[@[true, true], @[true, false], @[false, false], @[false, false]]

Compiler
--------

The tests for the compiler work differently, they are all located in
``tests/``. Each test has its own file, which is different from the
stdlib tests. At the beginning of every test is the expected side of
the test. Possible keys are:

- output: The expected output, most likely via ``echo``
- exitcode: Exit code of the test (via ``exit(number)``)
- errormsg: The expected error message
- file: The file the errormsg
- line: The line the errormsg was produced at

An example for a test:

.. code-block:: nim

  discard """
    errormsg: "type mismatch: got (PTest)"
  """

  type
    PTest = ref object

  proc test(x: PTest, y: int) = nil

  var buf: PTest
  buf.test()

Running tests
=============

You can run the tests with

.. code-block:: bash

  ./koch tests

which will run a good subset of tests. Some tests may fail. If you
only want to run failing tests, go for

.. code-block:: bash

  ./koch tests --failing all

You can also run only a single category of tests. For a list of
categories, see ``tests/testament/categories.nim``, at the bottom.

.. code-block:: bash

  ./koch tests c lib

Comparing tests
===============

Because some tests fail in the current ``devel`` branch, not every fail
after your change is necessarily caused by your changes.

The tester can compare two test runs. First, you need to create the
reference test. You'll also need to the commit id, because that's what
the tester needs to know in order to compare the two.

.. code-block:: bash

  git checkout devel
  DEVEL_COMMIT=$(git rev-parse HEAD)
  ./koch tests

Then switch over to your changes and run the tester again.

.. code-block:: bash

  git checkout your-changes
  ./koch tests

Then you can ask the tester to create a ``testresults.html`` which will
tell you if any new tests passed/failed.

.. code-block:: bash

  ./koch --print html $DEVEL_COMMIT
