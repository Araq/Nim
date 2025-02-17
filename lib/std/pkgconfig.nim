#
#
#            Nim's Runtime (and compile-time) Library
#        (c) Copyright 2024 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements a compile-time procedure for calling ``pkg-config``.
##
## https://www.freedesktop.org/wiki/Software/pkg-config/

from std/envvars import getEnv

proc pkgConfig*(args: string): string {.compiletime.} =
  ## Call **pkg-config** with ``args``.
  ## If ``$PKG_CONFIG`` is set in the environment then it will
  ## be used instead of ``pkg-config`` from ``$PATH``.
  ##
  ## ```nim
  ## import std/pkgconfig
  ##
  ## discard pkgConfig" --atleast-version=3 openssl"
  ##   # If the available openssl version is less than 3.0.0
  ##   # then pkg-config returns non-zero and a defect is raised.
  ##
  ## {.passC: pkgConfig" --cflags openssl".}
  ## {.passL: pkgConfig" --libs openssl".}
  ##   # Pass command-line arguments from pkg-config to the compiler.
  ## ```
  var cmd = getEnv("PKG_CONFIG", "pkg-config") & " " & args
  var code: int
  (result, code) = gorgeEx(cmd)
  if code != 0:
    var msg = cmd
    msg.add "\nPKG_CONFIG="
    msg.add getEnv("PKG_CONFIG")
    msg.add "\nPKG_CONFIG_PATH="
    msg.add getEnv("PKG_CONFIG_PATH")
    msg.add '\n'
    msg.add result
    raise newException(AssertionDefect, msg)
