#
#
#            Nim's Runtime Library
#        (c) Copyright 2020 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module provides access to the inferred .raises effects
## for Nim's macro system.
## **Since**: Version 1.4.
##
## One can test for the existence of this standard module
## via `defined(nimHasEffectTraitsModule)`.

import std/macros

when defined(nimPreviewSlimSystem):
  import std/assertions

proc getRaisesListImpl(n: NimNode): NimNode = raiseAssert "see compiler/vmops.nim"
proc getTagsListImpl(n: NimNode): NimNode = raiseAssert "see compiler/vmops.nim"
proc getForbidsListImpl(n: NimNode): NimNode = raiseAssert "see compiler/vmops.nim"
proc isGcSafeImpl(n: NimNode): bool = raiseAssert "see compiler/vmops.nim"
proc hasNoSideEffectsImpl(n: NimNode): bool = raiseAssert "see compiler/vmops.nim"

proc getRaisesList*(fn: NimNode): NimNode =
  ## Extracts the `.raises` list of the func/proc/etc `fn`.
  ## `fn` has to be a resolved symbol of kind `nnkSym`. This
  ## implies that the macro that calls this proc should accept `typed`
  ## arguments and not `untyped` arguments.
  expectKind fn, nnkSym
  result = getRaisesListImpl(fn)

proc getTagsList*(fn: NimNode): NimNode =
  ## Extracts the `.tags` list of the func/proc/etc `fn`.
  ## `fn` has to be a resolved symbol of kind `nnkSym`. This
  ## implies that the macro that calls this proc should accept `typed`
  ## arguments and not `untyped` arguments.
  expectKind fn, nnkSym
  result = getTagsListImpl(fn)

proc getForbidsList*(fn: NimNode): NimNode =
  ## Extracts the `.forbids` list of the func/proc/etc `fn`.
  ## `fn` has to be a resolved symbol of kind `nnkSym`. This
  ## implies that the macro that calls this proc should accept `typed`
  ## arguments and not `untyped` arguments.
  expectKind fn, nnkSym
  result = getForbidsListImpl(fn)

proc isGcSafe*(fn: NimNode): bool =
  ## Return true if the func/proc/etc `fn` is `gcsafe`.
  ## `fn` has to be a resolved symbol of kind `nnkSym`. This
  ## implies that the macro that calls this proc should accept `typed`
  ## arguments and not `untyped` arguments.
  expectKind fn, nnkSym
  result = isGcSafeImpl(fn)

proc hasNoSideEffects*(fn: NimNode): bool =
  ## Return true if the func/proc/etc `fn` has `noSideEffect`.
  ## `fn` has to be a resolved symbol of kind `nnkSym`. This
  ## implies that the macro that calls this proc should accept `typed`
  ## arguments and not `untyped` arguments.
  expectKind fn, nnkSym
  result = hasNoSideEffectsImpl(fn)
