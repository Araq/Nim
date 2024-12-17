=========================
  niminst User's manual
=========================

:Author: Andreas Rumpf
:Version: |nimversion|

.. default-role:: code
.. include:: rstcommon.rst
.. contents::

Introduction
============

niminst is a tool to generate an installer for a Nim program. Currently
it can create an installer for Windows
via [Inno Setup](https://www.jrsoftware.org/isinfo.php) as well as
installation/deinstallation scripts for UNIX. Later versions will support
Linux' package management systems.

niminst works by reading a configuration file that contains all the
information that it needs to generate an installer for the different operating
systems.


Configuration file
==================

niminst uses the Nim [parsecfg](parsecfg.html) module to parse the
configuration file. Here's an example of how the syntax looks like:

.. include:: mytest.cfg
     :literal:

The value of a key-value pair can reference user-defined variables via
the `$variable` notation: They can be defined in the command line with the
`--var:name=value`:option: switch. This is useful to not hard-coding the
program's version number into the configuration file, for instance.

It follows a description of each possible section and how it affects the
generated installers.


Project section
---------------
The project section gathers general information about your project. It must
contain the following key-value pairs:

====================   =======================================================
Key                    description
====================   =======================================================
`Name`                 the project's name; this needs to be a single word
`DisplayName`          the project's long name; this can contain spaces. If
                       not specified, this is the same as `Name`.
`Version`              the project's version
`OS`                   the OSes to generate C code for; for example:
                       `"windows;linux;macosx"`
`CPU`                  the CPUs to generate C code for; for example:
                       `"i386;amd64;powerpc"`
`Authors`              the project's authors
`Description`          the project's description
`App`                  the application's type: "Console" or "GUI". If
                       "Console", niminst generates a special batch file
                       for Windows to open up the command-line shell.
`License`              the filename of the application's license
====================   =======================================================


`files` key
-------------

Many sections support the `files` key. Listed filenames
can be separated by semicolon or the `files` key can be repeated. Wildcards
in filenames are supported. If it is a directory name, all files in the
directory are used:

    [Config]
    Files: "configDir"
    Files: "otherconfig/*.conf;otherconfig/*.cfg"


Config section
--------------

The `config` section currently only supports the `files` key. Listed files
will be installed into the OS's configuration directory.


Documentation section
---------------------

The `documentation` section supports the `files` key.
Listed files will be installed into the OS's native documentation directory
(which might be ``$appdir/doc``).

There is a `start` key which determines whether the Windows installer
generates a link to e.g. the ``index.html`` of your documentation.


Other section
-------------

The `other` section currently only supports the `files` key.
Listed files will be installed into the application installation directory
(`$appdir`).


Lib section
-----------

The `lib` section currently only supports the `files` key.
Listed files will be installed into the OS's native library directory
(which might be `$appdir/lib`).


Windows section
---------------

The `windows` section supports the `files` key for Windows-specific files.
Listed files will be installed into the application installation directory
(`$appdir`).

Other possible options are:

====================   =======================================================
Key                    description
====================   =======================================================
`BinPath`              paths to add to the Windows `%PATH%` environment
                       variable. Example: ``BinPath: r"bin;dist\mingw\bin"``
`InnoSetup`            boolean flag whether an Inno Setup installer should be
                       generated for Windows. Example: `InnoSetup: "Yes"`
====================   =======================================================


UnixBin section
---------------

The `UnixBin` section currently only supports the `files` key.
Listed files will be installed into the OS's native bin directory
(e.g. ``/usr/local/bin``). The exact location depends on the
installation path the user specifies when running the `install.sh` script.


Unix section
------------

Possible options are:

====================   =======================================================
Key                    description
====================   =======================================================
`InstallScript`        boolean flag whether an installation shell script
                       should be generated. Example: `InstallScript: "Yes"`
`UninstallScript`      boolean flag whether a de-installation shell script
                       should be generated.
                       Example: `UninstallScript: "Yes"`
====================   =======================================================


InnoSetup section
-----------------

Possible options are:

====================   =======================================================
Key                    description
====================   =======================================================
`path`                 Path to Inno Setup.
                       Example: ``path = r"c:\inno setup 5\iscc.exe"``
`flags`                Flags to pass to Inno Setup.
                       Example: `flags = "/Q"`
====================   =======================================================


C_Compiler section
------------------

Possible options are:

====================   =======================================================
Key                    description
====================   =======================================================
`path`                 Path to the C compiler.
`flags`                Flags to pass to the C Compiler.
                       Example: `flags = "-w"`
====================   =======================================================


Real-world example
==================

The installers for the Nim compiler itself are generated by niminst. Have a
look at its configuration file:

.. include:: ../compiler/installer.ini
     :literal:

