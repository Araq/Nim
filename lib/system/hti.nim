#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

type
  # This should be the same as ast.TTypeKind
  # many enum fields are not used at runtime
  TNimKind = enum
    tyNone,
    tyBool,
    tyChar,
    tyEmpty,
    tyArrayConstr,
    tyNil,
    tyUntyped,
    tyTyped,
    tyTypeDesc,
    tyGenericInvocation, # ``T[a, b]`` for types to invoke
    tyGenericBody,       # ``T[a, b, body]`` last parameter is the body
    tyGenericInst,       # ``T[a, b, realInstance]`` instantiated generic type
    tyGenericParam,      # ``a`` in the example
    tyDistinct,          # distinct type
    tyEnum,
    tyOrdinal,
    tyArray,
    tyObject,
    tyTuple,             # WARNING: The compiler uses tyTuple for pure objects!
    tySet,
    tyRange,
    tyPtr,
    tyRef,
    tyVar,
    tySequence,
    tyProc,
    tyPointer,
    tyOpenArray,
    tyString,
    tyCstring,
    tyForward,
    tyInt,
    tyInt8,
    tyInt16,
    tyInt32,
    tyInt64,
    tyFloat,
    tyFloat32,
    tyFloat64,
    tyFloat128,
    tyUInt,
    tyUInt8,
    tyUInt16,
    tyUInt32,
    tyUInt64,
    tyOwned, tyUnused1, tyUnused2,
    tyVarargsHidden,
    tyUncheckedArray,
    tyErrorHidden,
    tyBuiltInTypeClassHidden,
    tyUserTypeClassHidden,
    tyUserTypeClassInstHidden,
    tyCompositeTypeClassHidden,
    tyInferredHidden,
    tyAndHidden, tyOrHidden, tyNotHidden,
    tyAnythingHidden,
    tyStaticHidden,
    tyFromExprHidden,
    tyOptDeprecated,
    tyVoidHidden

  TNimNodeKind = enum nkNone, nkSlot, nkList, nkCase
  TNimNode {.compilerproc.} = object
    kind: TNimNodeKind
    offset: int
    typ: ptr TNimType
    name: cstring
    len: int
    sons: ptr array[0x7fff, ptr TNimNode]

  TNimTypeFlag = enum
    ntfNoRefs = 0,     # type contains no tyRef, tySequence, tyString
    ntfAcyclic = 1,    # type cannot form a cycle
    ntfEnumHole = 2    # enum has holes and thus `$` for them needs the slow
                       # version
  TNimType {.compilerproc.} = object
    when defined(gcHooks):
      head*: pointer
    size*: int
    align*: int
    kind: TNimKind
    flags: set[TNimTypeFlag]
    base*: ptr TNimType
    node: ptr TNimNode # valid for tyRecord, tyObject, tyTuple, tyEnum
    finalizer*: pointer # the finalizer for the type
    marker*: proc (p: pointer, op: int) {.nimcall, benign, tags: [], raises: [].} # marker proc for GC
    deepcopy: proc (p: pointer): pointer {.nimcall, benign, tags: [], raises: [].}
    when defined(nimSeqsV2):
      typeInfoV2*: pointer
    when defined(nimTypeNames):
      name: cstring
      nextType: ptr TNimType
      instances: int # count the number of instances
      sizes: int # sizes of all instances in bytes

when defined(gcHooks):
  type
    PNimType* = ptr TNimType
else:
  type
    PNimType = ptr TNimType

when defined(nimTypeNames):
  # Declare this variable only once in system.nim
  when declared(ThisIsSystem):
    var nimTypeRoot {.compilerproc.}: PNimType
  else:
    var nimTypeRoot {.importc.}: PNimType

# node.len may be the ``first`` element of a set
