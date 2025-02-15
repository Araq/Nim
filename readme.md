# <img src="https://raw.githubusercontent.com/nim-lang/assets/master/Art/logo-crown.png" height="28px"/> Nim

[![Build Status](https://dev.azure.com/nim-lang/Nim/_apis/build/status/nim-lang.Nim?branchName=devel)](https://dev.azure.com/nim-lang/Nim/_build/latest?definitionId=1&branchName=devel)

This repository contains the Nim compiler, Nim's stdlib, tools, and documentation.
For more information about Nim, including downloads and documentation for
the latest release, check out [Nim's website][nim-site] or [bleeding edge docs](https://nim-lang.github.io/Nim/).

## Community

[![Join the IRC chat][badge-nim-irc]][nim-irc]
[![Join the Discord server][badge-nim-discord]][nim-discord]
[![Join the Gitter chat][badge-nim-gitter]][nim-gitter]
[![Join the Matrix room](https://img.shields.io/matrix/nim-lang:matrix.org?color=blue&style=flat&logo=matrix)](https://matrix.to/#/#nim-lang:matrix.org)
[![Get help][badge-nim-forum-gethelp]][nim-forum]
[![View Nim posts on Stack Overflow][badge-nim-stackoverflow]][nim-stackoverflow-newest]
[![Follow @nim_lang on Twitter][badge-nim-twitter]][nim-twitter]

* The [forum][nim-forum] - the best place to ask questions and to discuss Nim.
* [#nim IRC Channel (Libera Chat)][nim-irc] - a place to discuss Nim in real-time.
  Also where most development decisions get made.
* [Discord][nim-discord] - an additional place to discuss Nim in real-time. Most
  channels there are bridged to IRC.
* [Gitter][nim-gitter] - an additional place to discuss Nim in real-time. There
  is a bridge between Gitter and the IRC channel.
* [Matrix][nim-matrix] - the main room to discuss Nim in real-time. [Matrix space][nim-matrix-space] contains a list of rooms, most of them are bridged to IRC.
* [Telegram][nim-telegram] - an additional place to discuss Nim in real-time. There
  is the official Telegram channel. Not bridged to IRC.
* [Stack Overflow][nim-stackoverflow] - a popular Q/A site for programming related
  topics that includes posts about Nim.
* [GitHub Wiki][nim-wiki] - Misc user-contributed content.

## Compiling

The compiler currently officially supports the following platform and
architecture combinations:

| Operating System               | Architectures Supported                          |
|--------------------------------|----------------------------------------|
| Windows (Windows XP or greater) | x86 and x86_64                             |
| Linux (most distributions)     | x86, x86_64, ppc64, and armv6l             |
| Mac OS X (10.04 or greater)    | x86, x86_64, ppc64, and Apple Silicon (ARM64) |

More platforms are supported, however, they are not tested regularly and they
may not be as stable as the above-listed platforms.

Compiling the Nim compiler is quite straightforward if you follow these steps:

First, the C source of an older version of the Nim compiler is needed to
bootstrap the latest version because the Nim compiler itself is written in the
Nim programming language. Those C sources are available within the
[``nim-lang/csources_v2``][csources-v2-repo] repository.

Next, to build from source you will need:

  * A C compiler such as ``gcc`` 6.x/later or an alternative such as ``clang``,
    ``Visual C++`` or ``Intel C++``. It is recommended to use ``gcc`` 6.x or
    later.
  * Either ``git`` or ``wget`` to download the needed source repositories.
  * The ``build-essential`` package when using ``gcc`` on Ubuntu (and likely
    other distros as well).
  * On Windows MinGW 4.3.0 (GCC 8.10) is the minimum recommended compiler.
  * Nim hosts a known working MinGW distribution:
    * [MinGW32.7z](https://nim-lang.org/download/mingw32.7z)
    * [MinGW64.7z](https://nim-lang.org/download/mingw64.7z)

**Windows Note: Cygwin and similar POSIX runtime environments are not supported.**

Then, if you are on a \*nix system or Windows, the following steps should compile
Nim from source using ``gcc``, ``git``, and the ``koch`` build tool.

**Note: The following commands are for the development version of the compiler.**
For most users, installing the latest stable version is enough. Check out
the installation instructions on the website to do so: https://nim-lang.org/install.html.

For package maintainers: see [packaging guidelines](https://nim-lang.github.io/Nim/packaging.html).

First, get Nim from GitHub:

```
git clone https://github.com/nim-lang/Nim.git
cd Nim
```

Next, run the appropriate build shell script for your platform:

* `build_all.sh` (Linux, Mac)
* `build_all.bat` (Windows)

Finally, once you have finished the build steps (on Windows, Mac, or Linux) you
should add the ``bin`` directory to your PATH.

See also [bootstrapping the compiler](https://nim-lang.github.io/Nim/intern.html#bootstrapping-the-compiler).

See also [reproducible builds](https://nim-lang.github.io/Nim/intern.html#bootstrapping-the-compiler-reproducible-builds).

## Koch

``koch`` is the build tool used to build various parts of Nim and to generate
documentation and the website, among other things. The ``koch`` tool can also
be used to run the Nim test suite.

Assuming that you added Nim's ``bin`` directory to your PATH, you may execute
the tests using ``./koch tests``. The tests take a while to run, but you
can run a subset of tests by specifying a category (for example
``./koch tests cat async``).

For more information on the ``koch`` build tool please see the documentation
within the [doc/koch.md](https://nim-lang.github.io/Nim/koch.html) file.

## Nimble

``nimble`` is Nim's package manager. To learn more about it, see the
[``nim-lang/nimble``][nimble-repo] repository.

## Contributors

This project exists thanks to all the people who contribute.
<a href="https://github.com/nim-lang/Nim/graphs/contributors"><img src="https://opencollective.com/Nim/contributors.svg?width=890" /></a>

## Contributing

[![Backers on Open Collective](https://opencollective.com/nim/backers/badge.svg)](#backers) [![Sponsors on Open Collective](https://opencollective.com/nim/sponsors/badge.svg)](#sponsors)
[![Donate Bitcoins][badge-nim-bitcoin]][nim-bitcoin]
[![Open Source Helpers](https://www.codetriage.com/nim-lang/nim/badges/users.svg)](https://www.codetriage.com/nim-lang/nim)

See [detailed contributing guidelines](https://nim-lang.github.io/Nim/contributing.html).
We welcome all contributions to Nim regardless of how small or large
they are. Everything from spelling fixes to new modules to be included in the
standard library are welcomed and appreciated. Before you start contributing,
you should familiarize yourself with the following repository structure:

* ``bin/``, ``build/`` - these directories are empty, but are used when Nim is built.
* ``compiler/`` - the compiler source code. Also includes plugins within ``compiler/plugins``.
* ``nimsuggest`` - the nimsuggest tool that previously lived in the [``nim-lang/nimsuggest``][nimsuggest-repo] repository.
* ``config/`` - the configuration for the compiler and documentation generator.
* ``doc/`` - the documentation files in reStructuredText format.
* ``lib/`` - the standard library, including:
    * ``pure/`` - modules in the standard library written in pure Nim.
    * ``impure/`` - modules in the standard library written in pure Nim with
    dependencies written in other languages.
    * ``wrappers/`` - modules that wrap dependencies written in other languages.
* ``tests/`` - contains categorized tests for the compiler and standard library.
* ``tools/`` - the tools including ``niminst`` (mostly invoked via
  ``koch``).
* ``koch.nim`` - the tool used to bootstrap Nim, generate C sources, build the website,
  and generate the documentation.

If you are not familiar with making a pull request using GitHub and/or git, please
read [this guide][pull-request-instructions].

Ideally, you should make sure that all tests pass before submitting a pull request.
However, if you are short on time, you can just run the tests specific to your
changes by only running the corresponding categories of tests. CI verifies
that all tests pass before allowing the pull request to be accepted, so only
running specific tests should be harmless.
Integration tests should go in ``tests/untestable``.

If you're looking for ways to contribute, please look at our [issue tracker][nim-issues].
There are always plenty of issues labeled [``Easy``][nim-issues-easy]; these should
be a good starting point for an initial contribution to Nim.

You can also help with the development of Nim by making donations. Donations can be
made using:

* [Open Collective](https://opencollective.com/nim)
* [Bitcoin][nim-bitcoin]

If you have any questions feel free to submit a question on the
[Nim forum][nim-forum], or via IRC on [the \#nim channel][nim-irc].


## Backers

Thank you to all our backers! [[Become a backer](https://opencollective.com/Nim#backer)]

<a href="https://opencollective.com/Nim#backers" target="_blank"><img src="https://opencollective.com/Nim/backers.svg?width=890"></a>


## Sponsors

Support this project by becoming a sponsor. Your logo will show up here with a link to your website. [[Become a sponsor](https://opencollective.com/Nim#sponsor)]

<a href="https://opencollective.com/Nim/sponsor/0/website" target="_blank"><img src="https://opencollective.com/Nim/sponsor/0/avatar.svg"></a>
<a href="https://opencollective.com/Nim/sponsor/1/website" target="_blank"><img src="https://opencollective.com/Nim/sponsor/1/avatar.svg"></a>
<a href="https://opencollective.com/Nim/sponsor/2/website" target="_blank"><img src="https://opencollective.com/Nim/sponsor/2/avatar.svg"></a>
<a href="https://opencollective.com/Nim/sponsor/3/website" target="_blank"><img src="https://opencollective.com/Nim/sponsor/3/avatar.svg"></a>
<a href="https://opencollective.com/Nim/sponsor/4/website" target="_blank"><img src="https://opencollective.com/Nim/sponsor/4/avatar.svg"></a>
<a href="https://opencollective.com/Nim/sponsor/5/website" target="_blank"><img src="https://opencollective.com/Nim/sponsor/5/avatar.svg"></a>
<a href="https://opencollective.com/Nim/sponsor/6/website" target="_blank"><img src="https://opencollective.com/Nim/sponsor/6/avatar.svg"></a>
<a href="https://opencollective.com/Nim/sponsor/7/website" target="_blank"><img src="https://opencollective.com/Nim/sponsor/7/avatar.svg"></a>
<a href="https://opencollective.com/Nim/sponsor/8/website" target="_blank"><img src="https://opencollective.com/Nim/sponsor/8/avatar.svg"></a>
<a href="https://opencollective.com/Nim/sponsor/9/website" target="_blank"><img src="https://opencollective.com/Nim/sponsor/9/avatar.svg"></a>

You can also see a list of all our sponsors/backers from various payment services on the [sponsors page](https://nim-lang.org/sponsors.html) of our website.

## License
The compiler and the standard library are licensed under the MIT license, except
for some modules which explicitly state otherwise. As a result, you may use any
compatible license (essentially any license) for your own programs developed with
Nim. You are explicitly permitted to develop commercial applications using Nim.

Please read the [copying.txt](copying.txt) file for more details.

Copyright © 2006-2025 Andreas Rumpf, all rights reserved.

[nim-site]: https://nim-lang.org
[nim-forum]: https://forum.nim-lang.org
[nim-issues]: https://github.com/nim-lang/Nim/issues
[nim-issues-easy]: https://github.com/nim-lang/Nim/labels/Easy
[nim-irc]: https://web.libera.chat/#nim
[nim-twitter]: https://twitter.com/nim_lang
[nim-stackoverflow]: https://stackoverflow.com/questions/tagged/nim-lang
[nim-stackoverflow-newest]: https://stackoverflow.com/questions/tagged/nim-lang?sort=newest&pageSize=15
[nim-discord]: https://discord.gg/nim
[nim-gitter]: https://gitter.im/nim-lang/Nim
[nim-matrix]: https://matrix.to/#/#nim-lang:matrix.org
[nim-matrix-space]: https://matrix.to/#/#nim:envs.net
[nim-telegram]: https://t.me/nim_lang
[nim-bitcoin]: https://blockchain.info/address/1BXfuKM2uvoD6mbx4g5xM3eQhLzkCK77tJ
[nimble-repo]: https://github.com/nim-lang/nimble
[nimsuggest-repo]: https://github.com/nim-lang/nimsuggest
[csources-repo-deprecated]: https://github.com/nim-lang/csources
[csources-v2-repo]: https://github.com/nim-lang/csources_v2
[badge-nim-irc]: https://img.shields.io/badge/chat-on_irc-blue.svg?style=flat-square
[badge-nim-discord]: https://img.shields.io/discord/371759389889003530?color=blue&label=discord&logo=discord&logoColor=gold&style=flat-square
[badge-nim-gitter]: https://img.shields.io/badge/chat-on_gitter-blue.svg?style=flat-square
[badge-nim-forum-gethelp]: https://img.shields.io/badge/Forum-get%20help-4eb899.svg?style=flat-square
[badge-nim-twitter]: https://img.shields.io/twitter/follow/nim_lang.svg?style=social
[badge-nim-stackoverflow]: https://img.shields.io/badge/stackoverflow-nim_tag-yellow.svg?style=flat-square
[badge-nim-bitcoin]: https://img.shields.io/badge/bitcoin-1BXfuKM2uvoD6mbx4g5xM3eQhLzkCK77tJ-D69134.svg?style=flat-square
[pull-request-instructions]: https://help.github.com/articles/using-pull-requests/
[nim-wiki]: https://github.com/nim-lang/Nim/wiki
