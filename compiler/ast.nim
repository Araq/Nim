#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# abstract syntax tree + symbol table

import
  lineinfos, options, ropes, idents, int128, wordrecg

import std/[tables, hashes]
from std/strutils import toLowerAscii

when defined(nimPreviewSlimSystem):
  import std/assertions

export int128

import nodekinds
export nodekinds

type
  TCallingConvention* = enum
    ccNimCall = "nimcall"           # nimcall, also the default
    ccStdCall = "stdcall"           # procedure is stdcall
    ccCDecl = "cdecl"               # cdecl
    ccSafeCall = "safecall"         # safecall
    ccSysCall = "syscall"           # system call
    ccInline = "inline"             # proc should be inlined
    ccNoInline = "noinline"         # proc should not be inlined
    ccFastCall = "fastcall"         # fastcall (pass parameters in registers)
    ccThisCall = "thiscall"         # thiscall (parameters are pushed right-to-left)
    ccClosure  = "closure"          # proc has a closure
    ccNoConvention = "noconv"       # needed for generating proper C procs sometimes
    ccMember = "member"             # proc is a (cpp) member

  TNodeKinds* = set[TNodeKind]

type
  TSymFlag* = enum    # 63 flags!
    sfUsed,           # read access of sym (for warnings) or simply used
    sfExported,       # symbol is exported from module
    sfFromGeneric,    # symbol is instantiation of a generic; this is needed
                      # for symbol file generation; such symbols should always
                      # be written into the ROD file
    sfGlobal,         # symbol is at global scope

    sfForward,        # symbol is forward declared
    sfWasForwarded,   # symbol had a forward declaration
                      # (implies it's too dangerous to patch its type signature)
    sfImportc,        # symbol is external; imported
    sfExportc,        # symbol is exported (under a specified name)
    sfMangleCpp,      # mangle as cpp (combines with `sfExportc`)
    sfVolatile,       # variable is volatile
    sfRegister,       # variable should be placed in a register
    sfPure,           # object is "pure" that means it has no type-information
                      # enum is "pure", its values need qualified access
                      # variable is "pure"; it's an explicit "global"
    sfNoSideEffect,   # proc has no side effects
    sfSideEffect,     # proc may have side effects; cannot prove it has none
    sfMainModule,     # module is the main module
    sfSystemModule,   # module is the system module
    sfNoReturn,       # proc never returns (an exit proc)
    sfAddrTaken,      # the variable's address is taken (ex- or implicitly);
                      # *OR*: a proc is indirectly called (used as first class)
    sfCompilerProc,   # proc is a compiler proc, that is a C proc that is
                      # needed for the code generator
    sfEscapes         # param escapes
                      # currently unimplemented
    sfDiscriminant,   # field is a discriminant in a record/object
    sfRequiresInit,   # field must be initialized during construction
    sfDeprecated,     # symbol is deprecated
    sfExplain,        # provide more diagnostics when this symbol is used
    sfError,          # usage of symbol should trigger a compile-time error
    sfShadowed,       # a symbol that was shadowed in some inner scope
    sfThread,         # proc will run as a thread
                      # variable is a thread variable
    sfCppNonPod,      # tells compiler to treat such types as non-pod's, so that
                      # `thread_local` is used instead of `__thread` for
                      # {.threadvar.} + `--threads`. Only makes sense for importcpp types.
                      # This has a performance impact so isn't set by default.
    sfCompileTime,    # proc can be evaluated at compile time
    sfConstructor,    # proc is a C++ constructor
    sfDispatcher,     # copied method symbol is the dispatcher
                      # deprecated and unused, except for the con
    sfBorrow,         # proc is borrowed
    sfInfixCall,      # symbol needs infix call syntax in target language;
                      # for interfacing with C++, JS
    sfNamedParamCall, # symbol needs named parameter call syntax in target
                      # language; for interfacing with Objective C
    sfDiscardable,    # returned value may be discarded implicitly
    sfOverridden,     # proc is overridden
    sfCallsite        # A flag for template symbols to tell the
                      # compiler it should use line information from
                      # the calling side of the macro, not from the
                      # implementation.
    sfGenSym          # symbol is 'gensym'ed; do not add to symbol table
    sfNonReloadable   # symbol will be left as-is when hot code reloading is on -
                      # meaning that it won't be renamed and/or changed in any way
    sfGeneratedOp     # proc is a generated '='; do not inject destructors in it
                      # variable is generated closure environment; requires early
                      # destruction for --newruntime.
    sfTemplateParam   # symbol is a template parameter
    sfCursor          # variable/field is a cursor, see RFC 177 for details
    sfInjectDestructors # whether the proc needs the 'injectdestructors' transformation
    sfNeverRaises     # proc can never raise an exception, not even OverflowDefect
                      # or out-of-memory
    sfSystemRaisesDefect # proc in the system can raise defects
    sfUsedInFinallyOrExcept  # symbol is used inside an 'except' or 'finally'
    sfSingleUsedTemp  # For temporaries that we know will only be used once
    sfNoalias         # 'noalias' annotation, means C's 'restrict'
                      # for templates and macros, means cannot be called
                      # as a lone symbol (cannot use alias syntax)
    sfEffectsDelayed  # an 'effectsDelayed' parameter
    sfGeneratedType   # A anonymous generic type that is generated by the compiler for
                      # objects that do not have generic parameters in case one of the
                      # object fields has one.
                      #
                      # This is disallowed but can cause the typechecking to go into
                      # an infinite loop, this flag is used as a sentinel to stop it.
    sfVirtual         # proc is a C++ virtual function
    sfByCopy          # param is marked as pass bycopy
    sfMember          # proc is a C++ member of a type
    sfCodegenDecl     # type, proc, global or proc param is marked as codegenDecl
    sfWasGenSym       # symbol was 'gensym'ed
    sfForceLift       # variable has to be lifted into closure environment

    sfDirty           # template is not hygienic (old styled template) module,
                      # compiled from a dirty-buffer
    sfCustomPragma    # symbol is custom pragma template
    sfBase,           # a base method
    sfGoto            # var is used for 'goto' code generation
    sfAnon,           # symbol name that was generated by the compiler
                      # the compiler will avoid printing such names
                      # in user messages.
    sfAllUntyped      # macro or template is immediately expanded in a generic context
    sfTemplateRedefinition # symbol is a redefinition of an earlier template

  TSymFlags* = set[TSymFlag]

const
  sfNoInit* = sfMainModule       # don't generate code to init the variable

  sfNoForward* = sfRegister
    # forward declarations are not required (per module)
  sfReorder* = sfForward
    # reordering pass is enabled

  sfCompileToCpp* = sfInfixCall       # compile the module as C++ code
  sfCompileToObjc* = sfNamedParamCall # compile the module as Objective-C code
  sfExperimental* = sfOverridden       # module uses the .experimental switch
  sfWrittenTo* = sfBorrow             # param is assigned to
                                      # currently unimplemented
  sfCppMember* = { sfVirtual, sfMember, sfConstructor } # proc is a C++ member, meaning it will be attached to the type definition

const
  # getting ready for the future expr/stmt merge
  nkWhen* = nkWhenStmt
  nkWhenExpr* = nkWhenStmt
  nkEffectList* = nkArgList
  # hacks ahead: an nkEffectList is a node with 4 children:
  exceptionEffects* = 0 # exceptions at position 0
  requiresEffects* = 1      # 'requires' annotation
  ensuresEffects* = 2     # 'ensures' annotation
  tagEffects* = 3       # user defined tag ('gc', 'time' etc.)
  pragmasEffects* = 4    # not an effect, but a slot for pragmas in proc type
  forbiddenEffects* = 5    # list of illegal effects
  effectListLen* = 6    # list of effects list
  nkLastBlockStmts* = {nkRaiseStmt, nkReturnStmt, nkBreakStmt, nkContinueStmt}
                        # these must be last statements in a block

type
  TTypeKind* = enum  # order is important!
                     # Don't forget to change hti.nim if you make a change here
                     # XXX put this into an include file to avoid this issue!
                     # several types are no longer used (guess which), but a
                     # spot in the sequence is kept for backwards compatibility
                     # (apparently something with bootstrapping)
                     # if you need to add a type, they can apparently be reused
    tyNone, tyBool, tyChar,
    tyEmpty, tyAlias, tyNil, tyUntyped, tyTyped, tyTypeDesc,
    tyGenericInvocation, # ``T[a, b]`` for types to invoke
    tyGenericBody,       # ``T[a, b, body]`` last parameter is the body
    tyGenericInst,       # ``T[a, b, realInstance]`` instantiated generic type
                         # realInstance will be a concrete type like tyObject
                         # unless this is an instance of a generic alias type.
                         # then realInstance will be the tyGenericInst of the
                         # completely (recursively) resolved alias.

    tyGenericParam,      # ``a`` in the above patterns
    tyDistinct,
    tyEnum,
    tyOrdinal,           # integer types (including enums and boolean)
    tyArray,
    tyObject,
    tyTuple,
    tySet,
    tyRange,
    tyPtr, tyRef,
    tyVar,
    tySequence,
    tyProc,
    tyPointer, tyOpenArray,
    tyString, tyCstring, tyForward,
    tyInt, tyInt8, tyInt16, tyInt32, tyInt64, # signed integers
    tyFloat, tyFloat32, tyFloat64, tyFloat128,
    tyUInt, tyUInt8, tyUInt16, tyUInt32, tyUInt64,
    tyOwned, tySink, tyLent,
    tyVarargs,
    tyUncheckedArray
      # An array with boundaries [0,+∞]

    tyError # used as erroneous type (for idetools)
      # as an erroneous node should match everything

    tyBuiltInTypeClass
      # Type such as the catch-all object, tuple, seq, etc

    tyUserTypeClass
      # the body of a user-defined type class

    tyUserTypeClassInst
      # Instance of a parametric user-defined type class.
      # Structured similarly to tyGenericInst.
      # tyGenericInst represents concrete types, while
      # this is still a "generic param" that will bind types
      # and resolves them during sigmatch and instantiation.

    tyCompositeTypeClass
      # Type such as seq[Number]
      # The notes for tyUserTypeClassInst apply here as well
      # sons[0]: the original expression used by the user.
      # sons[1]: fully expanded and instantiated meta type
      # (potentially following aliases)

    tyInferred
      # In the initial state `base` stores a type class constraining
      # the types that can be inferred. After a candidate type is
      # selected, it's stored in `last`. Between `base` and `last`
      # there may be 0, 2 or more types that were also considered as
      # possible candidates in the inference process (i.e. last will
      # be updated to store a type best conforming to all candidates)

    tyAnd, tyOr, tyNot
      # boolean type classes such as `string|int`,`not seq`,
      # `Sortable and Enumable`, etc

    tyAnything
      # a type class matching any type

    tyStatic
      # a value known at compile type (the underlying type is .base)

    tyFromExpr
      # This is a type representing an expression that depends
      # on generic parameters (the expression is stored in t.n)
      # It will be converted to a real type only during generic
      # instantiation and prior to this it has the potential to
      # be any type.

    tyConcept
      # new style concept.

    tyVoid
      # now different from tyEmpty, hurray!
    tyIterable

static:
  # remind us when TTypeKind stops to fit in a single 64-bit word
  # assert TTypeKind.high.ord <= 63
  discard

const
  tyPureObject* = tyTuple
  GcTypeKinds* = {tyRef, tySequence, tyString}

  tyTypeClasses* = {tyBuiltInTypeClass, tyCompositeTypeClass,
                    tyUserTypeClass, tyUserTypeClassInst,
                    tyAnd, tyOr, tyNot, tyAnything}

  tyMetaTypes* = {tyGenericParam, tyTypeDesc, tyUntyped} + tyTypeClasses
  tyUserTypeClasses* = {tyUserTypeClass, tyUserTypeClassInst}
  # consider renaming as `tyAbstractVarRange`
  abstractVarRange* = {tyGenericInst, tyRange, tyVar, tyDistinct, tyOrdinal,
                       tyTypeDesc, tyAlias, tyInferred, tySink, tyOwned}
  abstractInst* = {tyGenericInst, tyDistinct, tyOrdinal, tyTypeDesc, tyAlias,
                   tyInferred, tySink, tyOwned} # xxx what about tyStatic?

type
  TTypeKinds* = set[TTypeKind]

  TNodeFlag* = enum
    nfNone,
    nfBase2,    # nfBase10 is default, so not needed
    nfBase8,
    nfBase16,
    nfAllConst, # used to mark complex expressions constant; easy to get rid of
                # but unfortunately it has measurable impact for compilation
                # efficiency
    nfTransf,   # node has been transformed
    nfNoRewrite # node should not be transformed anymore
    nfSem       # node has been checked for semantics
    nfLL        # node has gone through lambda lifting
    nfDotField  # the call can use a dot operator
    nfDotSetter # the call can use a setter dot operarator
    nfExplicitCall # x.y() was used instead of x.y
    nfExprCall  # this is an attempt to call a regular expression
    nfIsRef     # this node is a 'ref' node; used for the VM
    nfIsPtr     # this node is a 'ptr' node; used for the VM
    nfPreventCg # this node should be ignored by the codegen
    nfBlockArg  # this a stmtlist appearing in a call (e.g. a do block)
    nfFromTemplate # a top-level node returned from a template
    nfDefaultParam # an automatically inserter default parameter
    nfDefaultRefsParam # a default param value references another parameter
                       # the flag is applied to proc default values and to calls
    nfExecuteOnReload  # A top-level statement that will be executed during reloads
    nfLastRead  # this node is a last read
    nfFirstWrite # this node is a first write
    nfHasComment # node has a comment
    nfSkipFieldChecking # node skips field visable checking
    nfDisabledOpenSym # temporary: node should be nkOpenSym but cannot
                      # because openSym experimental switch is disabled
                      # gives warning instead

  TNodeFlags* = set[TNodeFlag]
  TTypeFlag* = enum   # keep below 32 for efficiency reasons (now: 47)
    tfVarargs,        # procedure has C styled varargs
                      # tyArray type represeting a varargs list
    tfNoSideEffect,   # procedure type does not allow side effects
    tfFinal,          # is the object final?
    tfInheritable,    # is the object inheritable?
    tfHasOwned,       # type contains an 'owned' type and must be moved
    tfEnumHasHoles,   # enum cannot be mapped into a range
    tfShallow,        # type can be shallow copied on assignment
    tfThread,         # proc type is marked as ``thread``; alias for ``gcsafe``
    tfFromGeneric,    # type is an instantiation of a generic; this is needed
                      # because for instantiations of objects, structural
                      # type equality has to be used
    tfUnresolved,     # marks unresolved typedesc/static params: e.g.
                      # proc foo(T: typedesc, list: seq[T]): var T
                      # proc foo(L: static[int]): array[L, int]
                      # can be attached to ranges to indicate that the range
                      # can be attached to generic procs with free standing
                      # type parameters: e.g. proc foo[T]()
                      # depends on unresolved static params.
    tfResolved        # marks a user type class, after it has been bound to a
                      # concrete type (lastSon becomes the concrete type)
    tfRetType,        # marks return types in proc (used to detect type classes
                      # used as return types for return type inference)
    tfCapturesEnv,    # whether proc really captures some environment
    tfByCopy,         # pass object/tuple by copy (C backend)
    tfByRef,          # pass object/tuple by reference (C backend)
    tfIterator,       # type is really an iterator, not a tyProc
    tfPartial,        # type is declared as 'partial'
    tfNotNil,         # type cannot be 'nil'
    tfRequiresInit,   # type contains a "not nil" constraint somewhere or
                      # a `requiresInit` field, so the default zero init
                      # is not appropriate
    tfNeedsFullInit,  # object type marked with {.requiresInit.}
                      # all fields must be initialized
    tfVarIsPtr,       # 'var' type is translated like 'ptr' even in C++ mode
    tfHasMeta,        # type contains "wildcard" sub-types such as generic params
                      # or other type classes
    tfHasGCedMem,     # type contains GC'ed memory
    tfPacked
    tfHasStatic
    tfGenericTypeParam
    tfImplicitTypeParam
    tfInferrableStatic
    tfConceptMatchedTypeSym
    tfExplicit        # for typedescs, marks types explicitly prefixed with the
                      # `type` operator (e.g. type int)
    tfWildcard        # consider a proc like foo[T, I](x: Type[T, I])
                      # T and I here can bind to both typedesc and static types
                      # before this is determined, we'll consider them to be a
                      # wildcard type.
    tfHasAsgn         # type has overloaded assignment operator
    tfBorrowDot       # distinct type borrows '.'
    tfTriggersCompileTime # uses the NimNode type which make the proc
                          # implicitly '.compiletime'
    tfRefsAnonObj     # used for 'ref object' and 'ptr object'
    tfCovariant       # covariant generic param mimicking a ptr type
    tfWeakCovariant   # covariant generic param mimicking a seq/array type
    tfContravariant   # contravariant generic param
    tfCheckedForDestructor # type was checked for having a destructor.
                           # If it has one, t.destructor is not nil.
    tfAcyclic # object type was annotated as .acyclic
    tfIncompleteStruct # treat this type as if it had sizeof(pointer)
    tfCompleteStruct
      # (for importc types); type is fully specified, allowing to compute
      # sizeof, alignof, offsetof at CT
    tfExplicitCallConv
    tfIsConstructor
    tfEffectSystemWorkaround
    tfIsOutParam
    tfSendable
    tfImplicitStatic

  TTypeFlags* = set[TTypeFlag]

  TSymKind* = enum        # the different symbols (start with the prefix sk);
                          # order is important for the documentation generator!
    skUnknown,            # unknown symbol: used for parsing assembler blocks
                          # and first phase symbol lookup in generics
    skConditional,        # symbol for the preprocessor (may become obsolete)
    skDynLib,             # symbol represents a dynamic library; this is used
                          # internally; it does not exist in Nim code
    skParam,              # a parameter
    skGenericParam,       # a generic parameter; eq in ``proc x[eq=`==`]()``
    skTemp,               # a temporary variable (introduced by compiler)
    skModule,             # module identifier
    skType,               # a type
    skVar,                # a variable
    skLet,                # a 'let' symbol
    skConst,              # a constant
    skResult,             # special 'result' variable
    skProc,               # a proc
    skFunc,               # a func
    skMethod,             # a method
    skIterator,           # an iterator
    skConverter,          # a type converter
    skMacro,              # a macro
    skTemplate,           # a template; currently also misused for user-defined
                          # pragmas
    skField,              # a field in a record or object
    skEnumField,          # an identifier in an enum
    skForVar,             # a for loop variable
    skLabel,              # a label (for block statement)
    skStub,               # symbol is a stub and not yet loaded from the ROD
                          # file (it is loaded on demand, which may
                          # mean: never)
    skPackage,            # symbol is a package (used for canonicalization)
  TSymKinds* = set[TSymKind]

const
  routineKinds* = {skProc, skFunc, skMethod, skIterator,
                   skConverter, skMacro, skTemplate}
  ExportableSymKinds* = {skVar, skLet, skConst, skType, skEnumField, skStub} + routineKinds

  tfUnion* = tfNoSideEffect
  tfGcSafe* = tfThread
  tfObjHasKids* = tfEnumHasHoles
  tfReturnsNew* = tfInheritable
  tfNonConstExpr* = tfExplicitCallConv
    ## tyFromExpr where the expression shouldn't be evaluated as a static value
  tfGenericHasDestructor* = tfExplicitCallConv
    ## tyGenericBody where an instance has a generated destructor
  skError* = skUnknown

var
  eqTypeFlags* = {tfIterator, tfNotNil, tfVarIsPtr, tfGcSafe, tfNoSideEffect, tfIsOutParam}
    ## type flags that are essential for type equality.
    ## This is now a variable because for emulation of version:1.0 we
    ## might exclude {tfGcSafe, tfNoSideEffect}.

type
  TMagic* = enum # symbols that require compiler magic:
    mNone,
    mDefined, mDeclared, mDeclaredInScope, mCompiles, mArrGet, mArrPut, mAsgn,
    mLow, mHigh, mSizeOf, mAlignOf, mOffsetOf, mTypeTrait,
    mIs, mOf, mAddr, mType, mTypeOf,
    mPlugin, mEcho, mShallowCopy, mSlurp, mStaticExec, mStatic,
    mParseExprToAst, mParseStmtToAst, mExpandToAst, mQuoteAst,
    mInc, mDec, mOrd,
    mNew, mNewFinalize, mNewSeq, mNewSeqOfCap,
    mLengthOpenArray, mLengthStr, mLengthArray, mLengthSeq,
    mIncl, mExcl, mCard, mChr,
    mGCref, mGCunref,
    mAddI, mSubI, mMulI, mDivI, mModI,
    mSucc, mPred,
    mAddF64, mSubF64, mMulF64, mDivF64,
    mShrI, mShlI, mAshrI, mBitandI, mBitorI, mBitxorI,
    mMinI, mMaxI,
    mAddU, mSubU, mMulU, mDivU, mModU,
    mEqI, mLeI, mLtI,
    mEqF64, mLeF64, mLtF64,
    mLeU, mLtU,
    mEqEnum, mLeEnum, mLtEnum,
    mEqCh, mLeCh, mLtCh,
    mEqB, mLeB, mLtB,
    mEqRef, mLePtr, mLtPtr,
    mXor, mEqCString, mEqProc,
    mUnaryMinusI, mUnaryMinusI64, mAbsI, mNot,
    mUnaryPlusI, mBitnotI,
    mUnaryPlusF64, mUnaryMinusF64,
    mCharToStr, mBoolToStr,
    mCStrToStr,
    mStrToStr, mEnumToStr,
    mAnd, mOr,
    mImplies, mIff, mExists, mForall, mOld,
    mEqStr, mLeStr, mLtStr,
    mEqSet, mLeSet, mLtSet, mMulSet, mPlusSet, mMinusSet, mXorSet,
    mConStrStr, mSlice,
    mDotDot, # this one is only necessary to give nice compile time warnings
    mFields, mFieldPairs, mOmpParFor,
    mAppendStrCh, mAppendStrStr, mAppendSeqElem,
    mInSet, mRepr, mExit,
    mSetLengthStr, mSetLengthSeq,
    mIsPartOf, mAstToStr, mParallel,
    mSwap, mIsNil, mArrToSeq, mOpenArrayToSeq,
    mNewString, mNewStringOfCap, mParseBiggestFloat,
    mMove, mEnsureMove, mWasMoved, mDup, mDestroy, mTrace,
    mDefault, mUnown, mFinished, mIsolate, mAccessEnv, mAccessTypeField,
    mArray, mOpenArray, mRange, mSet, mSeq, mVarargs,
    mRef, mPtr, mVar, mDistinct, mVoid, mTuple,
    mOrdinal, mIterableType,
    mInt, mInt8, mInt16, mInt32, mInt64,
    mUInt, mUInt8, mUInt16, mUInt32, mUInt64,
    mFloat, mFloat32, mFloat64, mFloat128,
    mBool, mChar, mString, mCstring,
    mPointer, mNil, mExpr, mStmt, mTypeDesc,
    mVoidType, mPNimrodNode, mSpawn, mDeepCopy,
    mIsMainModule, mCompileDate, mCompileTime, mProcCall,
    mCpuEndian, mHostOS, mHostCPU, mBuildOS, mBuildCPU, mAppType,
    mCompileOption, mCompileOptionArg,
    mNLen, mNChild, mNSetChild, mNAdd, mNAddMultiple, mNDel,
    mNKind, mNSymKind,

    mNccValue, mNccInc, mNcsAdd, mNcsIncl, mNcsLen, mNcsAt,
    mNctPut, mNctLen, mNctGet, mNctHasNext, mNctNext,

    mNIntVal, mNFloatVal, mNSymbol, mNIdent, mNGetType, mNStrVal, mNSetIntVal,
    mNSetFloatVal, mNSetSymbol, mNSetIdent, mNSetStrVal, mNLineInfo,
    mNNewNimNode, mNCopyNimNode, mNCopyNimTree, mStrToIdent, mNSigHash, mNSizeOf,
    mNBindSym, mNCallSite,
    mEqIdent, mEqNimrodNode, mSameNodeType, mGetImpl, mNGenSym,
    mNHint, mNWarning, mNError,
    mInstantiationInfo, mGetTypeInfo, mGetTypeInfoV2,
    mNimvm, mIntDefine, mStrDefine, mBoolDefine, mGenericDefine, mRunnableExamples,
    mException, mBuiltinType, mSymOwner, mUncheckedArray, mGetImplTransf,
    mSymIsInstantiationOf, mNodeId, mPrivateAccess, mZeroDefault


const
  # things that we can evaluate safely at compile time, even if not asked for it:
  ctfeWhitelist* = {mNone, mSucc,
    mPred, mInc, mDec, mOrd, mLengthOpenArray,
    mLengthStr, mLengthArray, mLengthSeq,
    mArrGet, mArrPut, mAsgn, mDestroy,
    mIncl, mExcl, mCard, mChr,
    mAddI, mSubI, mMulI, mDivI, mModI,
    mAddF64, mSubF64, mMulF64, mDivF64,
    mShrI, mShlI, mBitandI, mBitorI, mBitxorI,
    mMinI, mMaxI,
    mAddU, mSubU, mMulU, mDivU, mModU,
    mEqI, mLeI, mLtI,
    mEqF64, mLeF64, mLtF64,
    mLeU, mLtU,
    mEqEnum, mLeEnum, mLtEnum,
    mEqCh, mLeCh, mLtCh,
    mEqB, mLeB, mLtB,
    mEqRef, mEqProc, mLePtr, mLtPtr, mEqCString, mXor,
    mUnaryMinusI, mUnaryMinusI64, mAbsI, mNot, mUnaryPlusI, mBitnotI,
    mUnaryPlusF64, mUnaryMinusF64,
    mCharToStr, mBoolToStr,
    mCStrToStr,
    mStrToStr, mEnumToStr,
    mAnd, mOr,
    mEqStr, mLeStr, mLtStr,
    mEqSet, mLeSet, mLtSet, mMulSet, mPlusSet, mMinusSet, mXorSet,
    mConStrStr, mAppendStrCh, mAppendStrStr, mAppendSeqElem,
    mInSet, mRepr, mOpenArrayToSeq}

  generatedMagics* = {mNone, mIsolate, mFinished, mOpenArrayToSeq}
    ## magics that are generated as normal procs in the backend

type
  ItemId* = object
    module*: int32
    item*: int32

proc `$`*(x: ItemId): string =
  "(module: " & $x.module & ", item: " & $x.item & ")"

proc `==`*(a, b: ItemId): bool {.inline.} =
  a.item == b.item and a.module == b.module

proc hash*(x: ItemId): Hash =
  var h: Hash = hash(x.module)
  h = h !& hash(x.item)
  result = !$h


type
  PNode* = ref TNode
  TNodeSeq* = seq[PNode]
  PType* = ref TType
  PSym* = ref TSym
  TNode*{.final, acyclic.} = object # on a 32bit machine, this takes 32 bytes
    when defined(useNodeIds):
      id*: int
    typField: PType
    info*: TLineInfo
    flags*: TNodeFlags
    case kind*: TNodeKind
    of nkCharLit..nkUInt64Lit:
      intVal*: BiggestInt
    of nkFloatLit..nkFloat128Lit:
      floatVal*: BiggestFloat
    of nkStrLit..nkTripleStrLit:
      strVal*: string
    of nkSym:
      sym*: PSym
    of nkIdent:
      ident*: PIdent
    else:
      sons*: TNodeSeq
    when defined(nimsuggest):
      endInfo*: TLineInfo

  TStrTable* = object         # a table[PIdent] of PSym
    counter*: int
    data*: seq[PSym]

  # -------------- backend information -------------------------------
  TLocKind* = enum
    locNone,                  # no location
    locTemp,                  # temporary location
    locLocalVar,              # location is a local variable
    locGlobalVar,             # location is a global variable
    locParam,                 # location is a parameter
    locField,                 # location is a record field
    locExpr,                  # "location" is really an expression
    locProc,                  # location is a proc (an address of a procedure)
    locData,                  # location is a constant
    locCall,                  # location is a call expression
    locOther                  # location is something other
  TLocFlag* = enum
    lfIndirect,               # backend introduced a pointer
    lfNoDeepCopy,             # no need for a deep copy
    lfNoDecl,                 # do not declare it in C
    lfDynamicLib,             # link symbol to dynamic library
    lfExportLib,              # export symbol for dynamic library generation
    lfHeader,                 # include header file for symbol
    lfImportCompilerProc,     # ``importc`` of a compilerproc
    lfSingleUse               # no location yet and will only be used once
    lfEnforceDeref            # a copyMem is required to dereference if this a
                              # ptr array due to C array limitations.
                              # See #1181, #6422, #11171
    lfPrepareForMutation      # string location is about to be mutated (V2)
  TStorageLoc* = enum
    OnUnknown,                # location is unknown (stack, heap or static)
    OnStatic,                 # in a static section
    OnStack,                  # location is on hardware stack
    OnHeap                    # location is on heap or global
                              # (reference counting needed)
  TLocFlags* = set[TLocFlag]
  TLoc* = object
    k*: TLocKind              # kind of location
    storage*: TStorageLoc
    flags*: TLocFlags         # location's flags
    lode*: PNode              # Node where the location came from; can be faked
    snippet*: Rope            # C code snippet of location (code generators)

  # ---------------- end of backend information ------------------------------

  TLibKind* = enum
    libHeader, libDynamic

  TLib* = object              # also misused for headers!
                              # keep in sync with PackedLib
    kind*: TLibKind
    generated*: bool          # needed for the backends:
    isOverridden*: bool
    name*: Rope
    path*: PNode              # can be a string literal!


  CompilesId* = int ## id that is used for the caching logic within
                    ## ``system.compiles``. See the seminst module.
  TInstantiation* = object
    sym*: PSym
    concreteTypes*: seq[PType]
    compilesId*: CompilesId

  PInstantiation* = ref TInstantiation

  TScope* {.acyclic.} = object
    depthLevel*: int
    symbols*: TStrTable
    parent*: PScope
    allowPrivateAccess*: seq[PSym] #  # enable access to private fields

  PScope* = ref TScope

  PLib* = ref TLib
  TSym* {.acyclic.} = object # Keep in sync with PackedSym
    itemId*: ItemId
    # proc and type instantiations are cached in the generic symbol
    case kind*: TSymKind
    of routineKinds:
      #procInstCache*: seq[PInstantiation]
      gcUnsafetyReason*: PSym  # for better error messages regarding gcsafe
      transformedBody*: PNode  # cached body after transf pass
    of skLet, skVar, skField, skForVar:
      guard*: PSym
      bitsize*: int
      alignment*: int # for alignment
    else: nil
    magic*: TMagic
    typ*: PType
    name*: PIdent
    info*: TLineInfo
    when defined(nimsuggest):
      endInfo*: TLineInfo
      hasUserSpecifiedType*: bool  # used for determining whether to display inlay type hints
    ownerField: PSym
    flags*: TSymFlags
    ast*: PNode               # syntax tree of proc, iterator, etc.:
                              # the whole proc including header; this is used
                              # for easy generation of proper error messages
                              # for variant record fields the discriminant
                              # expression
                              # for modules, it's a placeholder for compiler
                              # generated code that will be appended to the
                              # module after the sem pass (see appendToModule)
    options*: TOptions
    position*: int            # used for many different things:
                              # for enum fields its position;
                              # for fields its offset
                              # for parameters its position (starting with 0)
                              # for a conditional:
                              # 1 iff the symbol is defined, else 0
                              # (or not in symbol table)
                              # for modules, an unique index corresponding
                              # to the module's fileIdx
                              # for variables a slot index for the evaluator
    offset*: int32            # offset of record field
    disamb*: int32            # disambiguation number; the basic idea is that
                              # `<procname>__<module>_<disamb>` is unique
    loc*: TLoc
    annex*: PLib              # additional fields (seldom used, so we use a
                              # reference to another object to save space)
    when hasFFI:
      cname*: string          # resolved C declaration name in importc decl, e.g.:
                              # proc fun() {.importc: "$1aux".} => cname = funaux
    constraint*: PNode        # additional constraints like 'lit|result'; also
                              # misused for the codegenDecl and virtual pragmas in the hope
                              # it won't cause problems
                              # for skModule the string literal to output for
                              # deprecated modules.
    instantiatedFrom*: PSym   # for instances, the generic symbol where it came from.
    when defined(nimsuggest):
      allUsages*: seq[TLineInfo]

  TTypeSeq* = seq[PType]

  TTypeAttachedOp* = enum ## as usual, order is important here
    attachedWasMoved,
    attachedDestructor,
    attachedAsgn,
    attachedDup,
    attachedSink,
    attachedTrace,
    attachedDeepCopy

  TType* {.acyclic.} = object # \
                              # types are identical iff they have the
                              # same id; there may be multiple copies of a type
                              # in memory!
                              # Keep in sync with PackedType
    itemId*: ItemId
    kind*: TTypeKind          # kind of type
    callConv*: TCallingConvention # for procs
    flags*: TTypeFlags        # flags of the type
    sons: TTypeSeq           # base types, etc.
    n*: PNode                 # node for types:
                              # for range types a nkRange node
                              # for record types a nkRecord node
                              # for enum types a list of symbols
                              # if kind == tyInt: it is an 'int literal(x)' type
                              # for procs and tyGenericBody, it's the
                              # formal param list
                              # for concepts, the concept body
                              # else: unused
    ownerField: PSym          # the 'owner' of the type
    sym*: PSym                # types have the sym associated with them
                              # it is used for converting types to strings
    size*: BiggestInt         # the size of the type in bytes
                              # -1 means that the size is unkwown
    align*: int16             # the type's alignment requirements
    paddingAtEnd*: int16      #
    loc*: TLoc
    typeInst*: PType          # for generic instantiations the tyGenericInst that led to this
                              # type.
    uniqueId*: ItemId         # due to a design mistake, we need to keep the real ID here as it
                              # is required by the --incremental:on mode.

  TPair* = object
    key*, val*: RootRef

  TPairSeq* = seq[TPair]

  TNodePair* = object
    h*: Hash                 # because it is expensive to compute!
    key*: PNode
    val*: int

  TNodePairSeq* = seq[TNodePair]
  TNodeTable* = object # the same as table[PNode] of int;
                                # nodes are compared by structure!
    counter*: int
    data*: TNodePairSeq

  TObjectSeq* = seq[RootRef]
  TObjectSet* = object
    counter*: int
    data*: TObjectSeq

  TImplication* = enum
    impUnknown, impNo, impYes

template nodeId(n: PNode): int = cast[int](n)

template typ*(n: PNode): PType =
  n.typField

proc owner*(s: PSym|PType): PSym {.inline.} =
  result = s.ownerField

proc setOwner*(s: PSym|PType, owner: PSym) {.inline.} =
  s.ownerField = owner

type Gconfig = object
  # we put comments in a side channel to avoid increasing `sizeof(TNode)`, which
  # reduces memory usage given that `PNode` is the most allocated type by far.
  comments: Table[int, string] # nodeId => comment
  useIc*: bool

var gconfig {.threadvar.}: Gconfig

proc setUseIc*(useIc: bool) = gconfig.useIc = useIc

proc comment*(n: PNode): string =
  if nfHasComment in n.flags and not gconfig.useIc:
    # IC doesn't track comments, see `packed_ast`, so this could fail
    result = gconfig.comments[n.nodeId]
  else:
    result = ""

proc `comment=`*(n: PNode, a: string) =
  let id = n.nodeId
  if a.len > 0:
    # if needed, we could periodically cleanup gconfig.comments when its size increases,
    # to ensure only live nodes (and with nfHasComment) have an entry in gconfig.comments;
    # for compiling compiler, the waste is very small:
    # num calls to newNodeImpl: 14984160 (num of PNode allocations)
    # size of gconfig.comments: 33585
    # num of nodes with comments that were deleted and hence wasted: 3081
    n.flags.incl nfHasComment
    gconfig.comments[id] = a
  elif nfHasComment in n.flags:
    n.flags.excl nfHasComment
    gconfig.comments.del(id)

# BUGFIX: a module is overloadable so that a proc can have the
# same name as an imported module. This is necessary because of
# the poor naming choices in the standard library.

const
  OverloadableSyms* = {skProc, skFunc, skMethod, skIterator,
    skConverter, skModule, skTemplate, skMacro, skEnumField}

  GenericTypes*: TTypeKinds = {tyGenericInvocation, tyGenericBody,
    tyGenericParam}

  StructuralEquivTypes*: TTypeKinds = {tyNil, tyTuple, tyArray,
    tySet, tyRange, tyPtr, tyRef, tyVar, tyLent, tySequence, tyProc, tyOpenArray,
    tyVarargs}

  ConcreteTypes*: TTypeKinds = { # types of the expr that may occur in::
                                 # var x = expr
    tyBool, tyChar, tyEnum, tyArray, tyObject,
    tySet, tyTuple, tyRange, tyPtr, tyRef, tyVar, tyLent, tySequence, tyProc,
    tyPointer,
    tyOpenArray, tyString, tyCstring, tyInt..tyInt64, tyFloat..tyFloat128,
    tyUInt..tyUInt64}
  IntegralTypes* = {tyBool, tyChar, tyEnum, tyInt..tyInt64,
    tyFloat..tyFloat128, tyUInt..tyUInt64} # weird name because it contains tyFloat
  ConstantDataTypes*: TTypeKinds = {tyArray, tySet,
                                    tyTuple, tySequence}
  NilableTypes*: TTypeKinds = {tyPointer, tyCstring, tyRef, tyPtr,
    tyProc, tyError} # TODO
  PtrLikeKinds*: TTypeKinds = {tyPointer, tyPtr} # for VM
  PersistentNodeFlags*: TNodeFlags = {nfBase2, nfBase8, nfBase16,
                                      nfDotSetter, nfDotField,
                                      nfIsRef, nfIsPtr, nfPreventCg, nfLL,
                                      nfFromTemplate, nfDefaultRefsParam,
                                      nfExecuteOnReload, nfLastRead,
                                      nfFirstWrite, nfSkipFieldChecking,
                                      nfDisabledOpenSym}
  namePos* = 0
  patternPos* = 1    # empty except for term rewriting macros
  genericParamsPos* = 2
  paramsPos* = 3
  pragmasPos* = 4
  miscPos* = 5  # used for undocumented and hacky stuff
  bodyPos* = 6       # position of body; use rodread.getBody() instead!
  resultPos* = 7
  dispatcherPos* = 8

  nfAllFieldsSet* = nfBase2

  nkIdentKinds* = {nkIdent, nkSym, nkAccQuoted, nkOpenSymChoice,
                   nkClosedSymChoice, nkOpenSym}

  nkPragmaCallKinds* = {nkExprColonExpr, nkCall, nkCallStrLit}
  nkLiterals* = {nkCharLit..nkTripleStrLit}
  nkFloatLiterals* = {nkFloatLit..nkFloat128Lit}
  nkLambdaKinds* = {nkLambda, nkDo}
  declarativeDefs* = {nkProcDef, nkFuncDef, nkMethodDef, nkIteratorDef, nkConverterDef}
  routineDefs* = declarativeDefs + {nkMacroDef, nkTemplateDef}
  procDefs* = nkLambdaKinds + declarativeDefs
  callableDefs* = nkLambdaKinds + routineDefs

  nkSymChoices* = {nkClosedSymChoice, nkOpenSymChoice}
  nkStrKinds* = {nkStrLit..nkTripleStrLit}

  skLocalVars* = {skVar, skLet, skForVar, skParam, skResult}
  skProcKinds* = {skProc, skFunc, skTemplate, skMacro, skIterator,
                  skMethod, skConverter}

  defaultSize = -1
  defaultAlignment = -1
  defaultOffset* = -1

proc getPIdent*(a: PNode): PIdent {.inline.} =
  ## Returns underlying `PIdent` for `{nkSym, nkIdent}`, or `nil`.
  case a.kind
  of nkSym: a.sym.name
  of nkIdent: a.ident
  of nkOpenSymChoice, nkClosedSymChoice: a.sons[0].sym.name
  of nkOpenSym: getPIdent(a.sons[0])
  else: nil

const
  moduleShift = when defined(cpu32): 20 else: 24

template id*(a: PType | PSym): int =
  let x = a
  (x.itemId.module.int shl moduleShift) + x.itemId.item.int

type
  IdGenerator* = ref object # unfortunately, we really need the 'shared mutable' aspect here.
    module*: int32
    symId*: int32
    typeId*: int32
    sealed*: bool
    disambTable*: CountTable[PIdent]

const
  PackageModuleId* = -3'i32

proc idGeneratorFromModule*(m: PSym): IdGenerator =
  assert m.kind == skModule
  result = IdGenerator(module: m.itemId.module, symId: m.itemId.item, typeId: 0, disambTable: initCountTable[PIdent]())

proc idGeneratorForPackage*(nextIdWillBe: int32): IdGenerator =
  result = IdGenerator(module: PackageModuleId, symId: nextIdWillBe - 1'i32, typeId: 0, disambTable: initCountTable[PIdent]())

proc nextSymId(x: IdGenerator): ItemId {.inline.} =
  assert(not x.sealed)
  inc x.symId
  result = ItemId(module: x.module, item: x.symId)

proc nextTypeId*(x: IdGenerator): ItemId {.inline.} =
  assert(not x.sealed)
  inc x.typeId
  result = ItemId(module: x.module, item: x.typeId)

when false:
  proc nextId*(x: IdGenerator): ItemId {.inline.} =
    inc x.item
    result = x[]

when false:
  proc storeBack*(dest: var IdGenerator; src: IdGenerator) {.inline.} =
    assert dest.ItemId.module == src.ItemId.module
    if dest.ItemId.item > src.ItemId.item:
      echo dest.ItemId.item, " ", src.ItemId.item, " ", src.ItemId.module
    assert dest.ItemId.item <= src.ItemId.item
    dest = src

var ggDebug* {.deprecated.}: bool ## convenience switch for trying out things

proc isCallExpr*(n: PNode): bool =
  result = n.kind in nkCallKinds

proc discardSons*(father: PNode)

proc len*(n: PNode): int {.inline.} =
  result = n.sons.len

proc safeLen*(n: PNode): int {.inline.} =
  ## works even for leaves.
  if n.kind in {nkNone..nkNilLit}: result = 0
  else: result = n.len

proc safeArrLen*(n: PNode): int {.inline.} =
  ## works for array-like objects (strings passed as openArray in VM).
  if n.kind in {nkStrLit..nkTripleStrLit}: result = n.strVal.len
  elif n.kind in {nkNone..nkFloat128Lit}: result = 0
  else: result = n.len

proc add*(father, son: PNode) =
  assert son != nil
  father.sons.add(son)

proc addAllowNil*(father, son: PNode) {.inline.} =
  father.sons.add(son)

template `[]`*(n: PNode, i: int): PNode = n.sons[i]
template `[]=`*(n: PNode, i: int; x: PNode) = n.sons[i] = x

template `[]`*(n: PNode, i: BackwardsIndex): PNode = n[n.len - i.int]
template `[]=`*(n: PNode, i: BackwardsIndex; x: PNode) = n[n.len - i.int] = x

proc add*(father, son: PType) =
  assert son != nil
  father.sons.add(son)

proc addAllowNil*(father, son: PType) {.inline.} =
  father.sons.add(son)

template `[]`*(n: PType, i: int): PType = n.sons[i]
template `[]=`*(n: PType, i: int; x: PType) = n.sons[i] = x

template `[]`*(n: PType, i: BackwardsIndex): PType = n[n.len - i.int]
template `[]=`*(n: PType, i: BackwardsIndex; x: PType) = n[n.len - i.int] = x

proc getDeclPragma*(n: PNode): PNode =
  ## return the `nkPragma` node for declaration `n`, or `nil` if no pragma was found.
  ## Currently only supports routineDefs + {nkTypeDef}.
  case n.kind
  of routineDefs:
    if n[pragmasPos].kind != nkEmpty: result = n[pragmasPos]
    else: result = nil
  of nkTypeDef:
    #[
    type F3*{.deprecated: "x3".} = int

    TypeSection
      TypeDef
        PragmaExpr
          Postfix
            Ident "*"
            Ident "F3"
          Pragma
            ExprColonExpr
              Ident "deprecated"
              StrLit "x3"
        Empty
        Ident "int"
    ]#
    if n[0].kind == nkPragmaExpr:
      result = n[0][1]
    else:
      result = nil
  else:
    # support as needed for `nkIdentDefs` etc.
    result = nil
  if result != nil:
    assert result.kind == nkPragma, $(result.kind, n.kind)

proc extractPragma*(s: PSym): PNode =
  ## gets the pragma node of routine/type/var/let/const symbol `s`
  if s.kind in routineKinds: # bug #24167
    if s.ast[pragmasPos] != nil and s.ast[pragmasPos].kind != nkEmpty:
      result = s.ast[pragmasPos]
    else:
      result = nil
  elif s.kind in {skType, skVar, skLet, skConst}:
    if s.ast != nil and s.ast.len > 0:
      if s.ast[0].kind == nkPragmaExpr and s.ast[0].len > 1:
        # s.ast = nkTypedef / nkPragmaExpr / [nkSym, nkPragma]
        result = s.ast[0][1]
      else:
        result = nil
    else:
      result = nil
  else:
    result = nil
  assert result == nil or result.kind == nkPragma

proc skipPragmaExpr*(n: PNode): PNode =
  ## if pragma expr, give the node the pragmas are applied to,
  ## otherwise give node itself
  if n.kind == nkPragmaExpr:
    result = n[0]
  else:
    result = n

proc setInfoRecursive*(n: PNode, info: TLineInfo) =
  ## set line info recursively
  if n != nil:
    for i in 0..<n.safeLen: setInfoRecursive(n[i], info)
    n.info = info

when defined(useNodeIds):
  const nodeIdToDebug* = -1 # 2322968
  var gNodeId: int

template newNodeImpl(info2) =
  result = PNode(kind: kind, info: info2)
  when false:
    # this would add overhead, so we skip it; it results in a small amount of leaked entries
    # for old PNode that gets re-allocated at the same address as a PNode that
    # has `nfHasComment` set (and an entry in that table). Only `nfHasComment`
    # should be used to test whether a PNode has a comment; gconfig.comments
    # can contain extra entries for deleted PNode's with comments.
    gconfig.comments.del(cast[int](result))

template setIdMaybe() =
  when defined(useNodeIds):
    result.id = gNodeId
    if result.id == nodeIdToDebug:
      echo "KIND ", result.kind
      writeStackTrace()
    inc gNodeId

proc newNode*(kind: TNodeKind): PNode =
  ## new node with unknown line info, no type, and no children
  newNodeImpl(unknownLineInfo)
  setIdMaybe()

proc newNodeI*(kind: TNodeKind, info: TLineInfo): PNode =
  ## new node with line info, no type, and no children
  newNodeImpl(info)
  setIdMaybe()

proc newNodeI*(kind: TNodeKind, info: TLineInfo, children: int): PNode =
  ## new node with line info, type, and children
  newNodeImpl(info)
  if children > 0:
    newSeq(result.sons, children)
  setIdMaybe()

proc newNodeIT*(kind: TNodeKind, info: TLineInfo, typ: PType): PNode =
  ## new node with line info, type, and no children
  result = newNode(kind)
  result.info = info
  result.typ() = typ

proc newNode*(kind: TNodeKind, info: TLineInfo): PNode =
  ## new node with line info, no type, and no children
  newNodeImpl(info)
  setIdMaybe()

proc newAtom*(ident: PIdent, info: TLineInfo): PNode =
  result = newNode(nkIdent, info)
  result.ident = ident

proc newAtom*(kind: TNodeKind, intVal: BiggestInt, info: TLineInfo): PNode =
  result = newNode(kind, info)
  result.intVal = intVal

proc newAtom*(kind: TNodeKind, floatVal: BiggestFloat, info: TLineInfo): PNode =
  result = newNode(kind, info)
  result.floatVal = floatVal

proc newAtom*(kind: TNodeKind; strVal: sink string; info: TLineInfo): PNode =
  result = newNode(kind, info)
  result.strVal = strVal

proc newTree*(kind: TNodeKind; info: TLineInfo; children: varargs[PNode]): PNode =
  result = newNodeI(kind, info)
  if children.len > 0:
    result.info = children[0].info
  result.sons = @children

proc newTree*(kind: TNodeKind; children: varargs[PNode]): PNode =
  result = newNode(kind)
  if children.len > 0:
    result.info = children[0].info
  result.sons = @children

proc newTreeI*(kind: TNodeKind; info: TLineInfo; children: varargs[PNode]): PNode =
  result = newNodeI(kind, info)
  if children.len > 0:
    result.info = children[0].info
  result.sons = @children

proc newTreeIT*(kind: TNodeKind; info: TLineInfo; typ: PType; children: varargs[PNode]): PNode =
  result = newNodeIT(kind, info, typ)
  if children.len > 0:
    result.info = children[0].info
  result.sons = @children

template previouslyInferred*(t: PType): PType =
  if t.sons.len > 1: t.last else: nil

when false:
  import tables, strutils
  var x: CountTable[string]

  addQuitProc proc () {.noconv.} =
    for k, v in pairs(x):
      echo k
      echo v

proc newSym*(symKind: TSymKind, name: PIdent, idgen: IdGenerator; owner: PSym,
             info: TLineInfo; options: TOptions = {}): PSym =
  # generates a symbol and initializes the hash field too
  assert not name.isNil
  let id = nextSymId idgen
  result = PSym(name: name, kind: symKind, flags: {}, info: info, itemId: id,
                options: options, ownerField: owner, offset: defaultOffset,
                disamb: getOrDefault(idgen.disambTable, name).int32)
  idgen.disambTable.inc name
  when false:
    if id.module == 48 and id.item == 39:
      writeStackTrace()
      echo "kind ", symKind, " ", name.s
      if owner != nil: echo owner.name.s

proc astdef*(s: PSym): PNode =
  # get only the definition (initializer) portion of the ast
  if s.ast != nil and s.ast.kind in {nkIdentDefs, nkConstDef}:
    s.ast[2]
  else:
    s.ast

proc isMetaType*(t: PType): bool =
  return t.kind in tyMetaTypes or
         (t.kind == tyStatic and t.n == nil) or
         tfHasMeta in t.flags

proc isUnresolvedStatic*(t: PType): bool =
  return t.kind == tyStatic and t.n == nil

proc linkTo*(t: PType, s: PSym): PType {.discardable.} =
  t.sym = s
  s.typ = t
  result = t

proc linkTo*(s: PSym, t: PType): PSym {.discardable.} =
  t.sym = s
  s.typ = t
  result = s

template fileIdx*(c: PSym): FileIndex =
  # XXX: this should be used only on module symbols
  c.position.FileIndex

template filename*(c: PSym): string =
  # XXX: this should be used only on module symbols
  c.position.FileIndex.toFilename

proc appendToModule*(m: PSym, n: PNode) =
  ## The compiler will use this internally to add nodes that will be
  ## appended to the module after the sem pass
  if m.ast == nil:
    m.ast = newNode(nkStmtList)
    m.ast.sons = @[n]
  else:
    assert m.ast.kind == nkStmtList
    m.ast.sons.add(n)

const                         # for all kind of hash tables:
  GrowthFactor* = 2           # must be power of 2, > 0
  StartSize* = 8              # must be power of 2, > 0

proc copyStrTable*(dest: var TStrTable, src: TStrTable) =
  dest.counter = src.counter
  setLen(dest.data, src.data.len)
  for i in 0..high(src.data): dest.data[i] = src.data[i]

proc copyObjectSet*(dest: var TObjectSet, src: TObjectSet) =
  dest.counter = src.counter
  setLen(dest.data, src.data.len)
  for i in 0..high(src.data): dest.data[i] = src.data[i]

proc discardSons*(father: PNode) =
  father.sons = @[]

proc withInfo*(n: PNode, info: TLineInfo): PNode =
  n.info = info
  return n

proc newIdentNode*(ident: PIdent, info: TLineInfo): PNode =
  result = newNode(nkIdent)
  result.ident = ident
  result.info = info

proc newSymNode*(sym: PSym): PNode =
  result = newNode(nkSym)
  result.sym = sym
  result.typ() = sym.typ
  result.info = sym.info

proc newSymNode*(sym: PSym, info: TLineInfo): PNode =
  result = newNode(nkSym)
  result.sym = sym
  result.typ() = sym.typ
  result.info = info

proc newOpenSym*(n: PNode): PNode {.inline.} =
  result = newTreeI(nkOpenSym, n.info, n)

proc newIntNode*(kind: TNodeKind, intVal: BiggestInt): PNode =
  result = newNode(kind)
  result.intVal = intVal

proc newIntNode*(kind: TNodeKind, intVal: Int128): PNode =
  result = newNode(kind)
  result.intVal = castToInt64(intVal)

proc lastSon*(n: PNode): PNode {.inline.} = n.sons[^1]
template setLastSon*(n: PNode, s: PNode) = n.sons[^1] = s

template firstSon*(n: PNode): PNode = n.sons[0]
template secondSon*(n: PNode): PNode = n.sons[1]

template hasSon*(n: PNode): bool = n.len > 0
template has2Sons*(n: PNode): bool = n.len > 1

proc replaceFirstSon*(n, newson: PNode) {.inline.} =
  n.sons[0] = newson

proc replaceSon*(n: PNode; i: int; newson: PNode) {.inline.} =
  n.sons[i] = newson

proc last*(n: PType): PType {.inline.} = n.sons[^1]

proc elementType*(n: PType): PType {.inline.} = n.sons[^1]
proc skipModifier*(n: PType): PType {.inline.} = n.sons[^1]

proc indexType*(n: PType): PType {.inline.} = n.sons[0]
proc baseClass*(n: PType): PType {.inline.} = n.sons[0]

proc base*(t: PType): PType {.inline.} =
  result = t.sons[0]

proc returnType*(n: PType): PType {.inline.} = n.sons[0]
proc setReturnType*(n, r: PType) {.inline.} = n.sons[0] = r
proc setIndexType*(n, idx: PType) {.inline.} = n.sons[0] = idx

proc firstParamType*(n: PType): PType {.inline.} = n.sons[1]
proc firstGenericParam*(n: PType): PType {.inline.} = n.sons[1]

proc typeBodyImpl*(n: PType): PType {.inline.} = n.sons[^1]

proc genericHead*(n: PType): PType {.inline.} = n.sons[0]

proc skipTypes*(t: PType, kinds: TTypeKinds): PType =
  ## Used throughout the compiler code to test whether a type tree contains or
  ## doesn't contain a specific type/types - it is often the case that only the
  ## last child nodes of a type tree need to be searched. This is a really hot
  ## path within the compiler!
  result = t
  while result.kind in kinds: result = last(result)

proc newIntTypeNode*(intVal: BiggestInt, typ: PType): PNode =
  let kind = skipTypes(typ, abstractVarRange).kind
  case kind
  of tyInt:     result = newNode(nkIntLit)
  of tyInt8:    result = newNode(nkInt8Lit)
  of tyInt16:   result = newNode(nkInt16Lit)
  of tyInt32:   result = newNode(nkInt32Lit)
  of tyInt64:   result = newNode(nkInt64Lit)
  of tyChar:    result = newNode(nkCharLit)
  of tyUInt:    result = newNode(nkUIntLit)
  of tyUInt8:   result = newNode(nkUInt8Lit)
  of tyUInt16:  result = newNode(nkUInt16Lit)
  of tyUInt32:  result = newNode(nkUInt32Lit)
  of tyUInt64:  result = newNode(nkUInt64Lit)
  of tyBool, tyEnum:
    # XXX: does this really need to be the kind nkIntLit?
    result = newNode(nkIntLit)
  of tyStatic: # that's a pre-existing bug, will fix in another PR
    result = newNode(nkIntLit)
  else: raiseAssert $kind
  result.intVal = intVal
  result.typ() = typ

proc newIntTypeNode*(intVal: Int128, typ: PType): PNode =
  # XXX: introduce range check
  newIntTypeNode(castToInt64(intVal), typ)

proc newFloatNode*(kind: TNodeKind, floatVal: BiggestFloat): PNode =
  result = newNode(kind)
  result.floatVal = floatVal

proc newStrNode*(kind: TNodeKind, strVal: string): PNode =
  result = newNode(kind)
  result.strVal = strVal

proc newStrNode*(strVal: string; info: TLineInfo): PNode =
  result = newNodeI(nkStrLit, info)
  result.strVal = strVal

proc newProcNode*(kind: TNodeKind, info: TLineInfo, body: PNode,
                 params,
                 name, pattern, genericParams,
                 pragmas, exceptions: PNode): PNode =
  result = newNodeI(kind, info)
  result.sons = @[name, pattern, genericParams, params,
                  pragmas, exceptions, body]

const
  AttachedOpToStr*: array[TTypeAttachedOp, string] = [
    "=wasMoved", "=destroy", "=copy", "=dup", "=sink", "=trace", "=deepcopy"]

proc `$`*(s: PSym): string =
  if s != nil:
    result = s.name.s & "@" & $s.id
  else:
    result = "<nil>"

when false:
  iterator items*(t: PType): PType =
    for i in 0..<t.sons.len: yield t.sons[i]

  iterator pairs*(n: PType): tuple[i: int, n: PType] =
    for i in 0..<n.sons.len: yield (i, n.sons[i])

when true:
  proc len*(n: PType): int {.inline.} =
    result = n.sons.len

proc sameTupleLengths*(a, b: PType): bool {.inline.} =
  result = a.sons.len == b.sons.len

iterator tupleTypePairs*(a, b: PType): (int, PType, PType) =
  for i in 0 ..< a.sons.len:
    yield (i, a.sons[i], b.sons[i])

iterator underspecifiedPairs*(a, b: PType; start = 0; without = 0): (PType, PType) =
  # XXX Figure out with what typekinds this is called.
  for i in start ..< min(a.sons.len, b.sons.len) + without:
    yield (a.sons[i], b.sons[i])

proc signatureLen*(t: PType): int {.inline.} =
  result = t.sons.len

proc paramsLen*(t: PType): int {.inline.} =
  result = t.sons.len - 1

proc genericParamsLen*(t: PType): int {.inline.} =
  assert t.kind == tyGenericInst
  result = t.sons.len - 2 # without 'head' and 'body'

proc genericInvocationParamsLen*(t: PType): int {.inline.} =
  assert t.kind == tyGenericInvocation
  result = t.sons.len - 1 # without 'head'

proc kidsLen*(t: PType): int {.inline.} =
  result = t.sons.len

proc genericParamHasConstraints*(t: PType): bool {.inline.} = t.sons.len > 0

proc hasElementType*(t: PType): bool {.inline.} = t.sons.len > 0
proc isEmptyTupleType*(t: PType): bool {.inline.} = t.sons.len == 0
proc isSingletonTupleType*(t: PType): bool {.inline.} = t.sons.len == 1

proc genericConstraint*(t: PType): PType {.inline.} = t.sons[0]

iterator genericInstParams*(t: PType): (bool, PType) =
  for i in 1..<t.sons.len-1:
    yield (i!=1, t.sons[i])

iterator genericInstParamPairs*(a, b: PType): (int, PType, PType) =
  for i in 1..<min(a.sons.len, b.sons.len)-1:
    yield (i-1, a.sons[i], b.sons[i])

iterator genericInvocationParams*(t: PType): (bool, PType) =
  for i in 1..<t.sons.len:
    yield (i!=1, t.sons[i])

iterator genericInvocationAndBodyElements*(a, b: PType): (PType, PType) =
  for i in 1..<a.sons.len:
    yield (a.sons[i], b.sons[i-1])

iterator genericInvocationParamPairs*(a, b: PType): (bool, PType, PType) =
  for i in 1..<a.sons.len:
    if i >= b.sons.len:
      yield (false, nil, nil)
    else:
      yield (true, a.sons[i], b.sons[i])

iterator genericBodyParams*(t: PType): (int, PType) =
  for i in 0..<t.sons.len-1:
    yield (i, t.sons[i])

iterator userTypeClassInstParams*(t: PType): (bool, PType) =
  for i in 1..<t.sons.len-1:
    yield (i!=1, t.sons[i])

iterator ikids*(t: PType): (int, PType) =
  for i in 0..<t.sons.len: yield (i, t.sons[i])

const
  FirstParamAt* = 1
  FirstGenericParamAt* = 1

iterator paramTypes*(t: PType): (int, PType) =
  for i in FirstParamAt..<t.sons.len: yield (i, t.sons[i])

iterator paramTypePairs*(a, b: PType): (PType, PType) =
  for i in FirstParamAt..<a.sons.len: yield (a.sons[i], b.sons[i])

template paramTypeToNodeIndex*(x: int): int = x

iterator kids*(t: PType): PType =
  for i in 0..<t.sons.len: yield t.sons[i]

iterator signature*(t: PType): PType =
  # yields return type + parameter types
  for i in 0..<t.sons.len: yield t.sons[i]

proc newType*(kind: TTypeKind; idgen: IdGenerator; owner: PSym; son: sink PType = nil): PType =
  let id = nextTypeId idgen
  result = PType(kind: kind, ownerField: owner, size: defaultSize,
                 align: defaultAlignment, itemId: id,
                 uniqueId: id, sons: @[])
  if son != nil: result.sons.add son
  when false:
    if result.itemId.module == 55 and result.itemId.item == 2:
      echo "KNID ", kind
      writeStackTrace()

proc setSons*(dest: PType; sons: sink seq[PType]) {.inline.} = dest.sons = sons
proc setSon*(dest: PType; son: sink PType) {.inline.} = dest.sons = @[son]
proc setSonsLen*(dest: PType; len: int) {.inline.} = setLen(dest.sons, len)

proc mergeLoc(a: var TLoc, b: TLoc) =
  if a.k == low(typeof(a.k)): a.k = b.k
  if a.storage == low(typeof(a.storage)): a.storage = b.storage
  a.flags.incl b.flags
  if a.lode == nil: a.lode = b.lode
  if a.snippet == "": a.snippet = b.snippet

proc newSons*(father: PNode, length: int) =
  setLen(father.sons, length)

proc newSons*(father: PType, length: int) =
  setLen(father.sons, length)

proc truncateInferredTypeCandidates*(t: PType) {.inline.} =
  assert t.kind == tyInferred
  if t.sons.len > 1:
    setLen(t.sons, 1)

proc assignType*(dest, src: PType) =
  dest.kind = src.kind
  dest.flags = src.flags
  dest.callConv = src.callConv
  dest.n = src.n
  dest.size = src.size
  dest.align = src.align
  # this fixes 'type TLock = TSysLock':
  if src.sym != nil:
    if dest.sym != nil:
      dest.sym.flags.incl src.sym.flags-{sfUsed, sfExported}
      if dest.sym.annex == nil: dest.sym.annex = src.sym.annex
      mergeLoc(dest.sym.loc, src.sym.loc)
    else:
      dest.sym = src.sym
  newSons(dest, src.sons.len)
  for i in 0..<src.sons.len: dest[i] = src[i]

proc copyType*(t: PType, idgen: IdGenerator, owner: PSym): PType =
  result = newType(t.kind, idgen, owner)
  assignType(result, t)
  result.sym = t.sym          # backend-info should not be copied

proc exactReplica*(t: PType): PType =
  result = PType(kind: t.kind, ownerField: t.owner, size: defaultSize,
                 align: defaultAlignment, itemId: t.itemId,
                 uniqueId: t.uniqueId)
  assignType(result, t)
  result.sym = t.sym          # backend-info should not be copied

proc copySym*(s: PSym; idgen: IdGenerator): PSym =
  result = newSym(s.kind, s.name, idgen, s.owner, s.info, s.options)
  #result.ast = nil            # BUGFIX; was: s.ast which made problems
  result.typ = s.typ
  result.flags = s.flags
  result.magic = s.magic
  result.options = s.options
  result.position = s.position
  result.loc = s.loc
  result.annex = s.annex      # BUGFIX
  result.constraint = s.constraint
  if result.kind in {skVar, skLet, skField}:
    result.guard = s.guard
    result.bitsize = s.bitsize
    result.alignment = s.alignment

proc createModuleAlias*(s: PSym, idgen: IdGenerator, newIdent: PIdent, info: TLineInfo;
                        options: TOptions): PSym =
  result = newSym(s.kind, newIdent, idgen, s.owner, info, options)
  # keep ID!
  result.ast = s.ast
  #result.id = s.id # XXX figure out what to do with the ID.
  result.flags = s.flags
  result.options = s.options
  result.position = s.position
  result.loc = s.loc
  result.annex = s.annex

proc initStrTable*(): TStrTable =
  result = TStrTable(counter: 0)
  newSeq(result.data, StartSize)

proc initObjectSet*(): TObjectSet =
  result = TObjectSet(counter: 0)
  newSeq(result.data, StartSize)

proc initNodeTable*(): TNodeTable =
  result = TNodeTable(counter: 0)
  newSeq(result.data, StartSize)

proc skipTypes*(t: PType, kinds: TTypeKinds; maxIters: int): PType =
  result = t
  var i = maxIters
  while result.kind in kinds:
    result = last(result)
    dec i
    if i == 0: return nil

proc skipTypesOrNil*(t: PType, kinds: TTypeKinds): PType =
  ## same as skipTypes but handles 'nil'
  result = t
  while result != nil and result.kind in kinds:
    if result.sons.len == 0: return nil
    result = last(result)

proc isGCedMem*(t: PType): bool {.inline.} =
  result = t.kind in {tyString, tyRef, tySequence} or
           t.kind == tyProc and t.callConv == ccClosure

proc propagateToOwner*(owner, elem: PType; propagateHasAsgn = true) =
  owner.flags.incl elem.flags * {tfHasMeta, tfTriggersCompileTime}
  if tfNotNil in elem.flags:
    if owner.kind in {tyGenericInst, tyGenericBody, tyGenericInvocation}:
      owner.flags.incl tfNotNil

  if elem.isMetaType:
    owner.flags.incl tfHasMeta

  let mask = elem.flags * {tfHasAsgn, tfHasOwned}
  if mask != {} and propagateHasAsgn:
    let o2 = owner.skipTypes({tyGenericInst, tyAlias, tySink})
    if o2.kind in {tyTuple, tyObject, tyArray,
                   tySequence, tyString, tySet, tyDistinct}:
      o2.flags.incl mask
      owner.flags.incl mask

  if owner.kind notin {tyProc, tyGenericInst, tyGenericBody,
                       tyGenericInvocation, tyPtr}:
    let elemB = elem.skipTypes({tyGenericInst, tyAlias, tySink})
    if elemB.isGCedMem or tfHasGCedMem in elemB.flags:
      # for simplicity, we propagate this flag even to generics. We then
      # ensure this doesn't bite us in sempass2.
      owner.flags.incl tfHasGCedMem

proc rawAddSon*(father, son: PType; propagateHasAsgn = true) =
  father.sons.add(son)
  if not son.isNil: propagateToOwner(father, son, propagateHasAsgn)

proc addSonNilAllowed*(father, son: PNode) =
  father.sons.add(son)

proc delSon*(father: PNode, idx: int) =
  if father.len == 0: return
  for i in idx..<father.len - 1: father[i] = father[i + 1]
  father.sons.setLen(father.len - 1)

proc copyNode*(src: PNode): PNode =
  # does not copy its sons!
  if src == nil:
    return nil
  result = newNode(src.kind)
  result.info = src.info
  result.typ() = src.typ
  result.flags = src.flags * PersistentNodeFlags
  result.comment = src.comment
  when defined(useNodeIds):
    if result.id == nodeIdToDebug:
      echo "COMES FROM ", src.id
  case src.kind
  of nkCharLit..nkUInt64Lit: result.intVal = src.intVal
  of nkFloatLiterals: result.floatVal = src.floatVal
  of nkSym: result.sym = src.sym
  of nkIdent: result.ident = src.ident
  of nkStrLit..nkTripleStrLit: result.strVal = src.strVal
  else: discard
  when defined(nimsuggest):
    result.endInfo = src.endInfo

template transitionNodeKindCommon(k: TNodeKind) =
  let obj {.inject.} = n[]
  n[] = TNode(kind: k, typField: n.typ, info: obj.info, flags: obj.flags)
  # n.comment = obj.comment # shouldn't be needed, the address doesnt' change
  when defined(useNodeIds):
    n.id = obj.id

proc transitionSonsKind*(n: PNode, kind: range[nkComesFrom..nkTupleConstr]) =
  transitionNodeKindCommon(kind)
  n.sons = obj.sons

proc transitionIntKind*(n: PNode, kind: range[nkCharLit..nkUInt64Lit]) =
  transitionNodeKindCommon(kind)
  n.intVal = obj.intVal

proc transitionIntToFloatKind*(n: PNode, kind: range[nkFloatLit..nkFloat128Lit]) =
  transitionNodeKindCommon(kind)
  n.floatVal = BiggestFloat(obj.intVal)

proc transitionNoneToSym*(n: PNode) =
  transitionNodeKindCommon(nkSym)

template transitionSymKindCommon*(k: TSymKind) =
  let obj {.inject.} = s[]
  s[] = TSym(kind: k, itemId: obj.itemId, magic: obj.magic, typ: obj.typ, name: obj.name,
             info: obj.info, ownerField: obj.ownerField, flags: obj.flags, ast: obj.ast,
             options: obj.options, position: obj.position, offset: obj.offset,
             loc: obj.loc, annex: obj.annex, constraint: obj.constraint)
  when hasFFI:
    s.cname = obj.cname
  when defined(nimsuggest):
    s.allUsages = obj.allUsages

proc transitionGenericParamToType*(s: PSym) =
  transitionSymKindCommon(skType)

proc transitionRoutineSymKind*(s: PSym, kind: range[skProc..skTemplate]) =
  transitionSymKindCommon(kind)
  s.gcUnsafetyReason = obj.gcUnsafetyReason
  s.transformedBody = obj.transformedBody

proc transitionToLet*(s: PSym) =
  transitionSymKindCommon(skLet)
  s.guard = obj.guard
  s.bitsize = obj.bitsize
  s.alignment = obj.alignment

template copyNodeImpl(dst, src, processSonsStmt) =
  if src == nil: return
  dst = newNode(src.kind)
  dst.info = src.info
  when defined(nimsuggest):
    result.endInfo = src.endInfo
  dst.typ() = src.typ
  dst.flags = src.flags * PersistentNodeFlags
  dst.comment = src.comment
  when defined(useNodeIds):
    if dst.id == nodeIdToDebug:
      echo "COMES FROM ", src.id
  case src.kind
  of nkCharLit..nkUInt64Lit: dst.intVal = src.intVal
  of nkFloatLiterals: dst.floatVal = src.floatVal
  of nkSym: dst.sym = src.sym
  of nkIdent: dst.ident = src.ident
  of nkStrLit..nkTripleStrLit: dst.strVal = src.strVal
  else: processSonsStmt

proc shallowCopy*(src: PNode): PNode =
  # does not copy its sons, but provides space for them:
  copyNodeImpl(result, src):
    newSeq(result.sons, src.len)

proc copyTree*(src: PNode): PNode =
  # copy a whole syntax tree; performs deep copying
  copyNodeImpl(result, src):
    newSeq(result.sons, src.len)
    for i in 0..<src.len:
      result[i] = copyTree(src[i])

proc copyTreeWithoutNode*(src, skippedNode: PNode): PNode =
  copyNodeImpl(result, src):
    result.sons = newSeqOfCap[PNode](src.len)
    for n in src.sons:
      if n != skippedNode:
        result.sons.add copyTreeWithoutNode(n, skippedNode)

proc hasSonWith*(n: PNode, kind: TNodeKind): bool =
  for i in 0..<n.len:
    if n[i].kind == kind:
      return true
  result = false

proc hasNilSon*(n: PNode): bool =
  for i in 0..<n.safeLen:
    if n[i] == nil:
      return true
    elif hasNilSon(n[i]):
      return true
  result = false

proc containsNode*(n: PNode, kinds: TNodeKinds): bool =
  result = false
  if n == nil: return
  case n.kind
  of nkEmpty..nkNilLit: result = n.kind in kinds
  else:
    for i in 0..<n.len:
      if n.kind in kinds or containsNode(n[i], kinds): return true

proc hasSubnodeWith*(n: PNode, kind: TNodeKind): bool =
  case n.kind
  of nkEmpty..nkNilLit, nkFormalParams: result = n.kind == kind
  else:
    for i in 0..<n.len:
      if (n[i].kind == kind) or hasSubnodeWith(n[i], kind):
        return true
    result = false

proc getInt*(a: PNode): Int128 =
  case a.kind
  of nkCharLit, nkUIntLit..nkUInt64Lit:
    result = toInt128(cast[uint64](a.intVal))
  of nkInt8Lit..nkInt64Lit:
    result = toInt128(a.intVal)
  of nkIntLit:
    # XXX: enable this assert
    # assert a.typ.kind notin {tyChar, tyUint..tyUInt64}
    result = toInt128(a.intVal)
  else:
    raiseRecoverableError("cannot extract number from invalid AST node")

proc getInt64*(a: PNode): int64 {.deprecated: "use getInt".} =
  case a.kind
  of nkCharLit, nkUIntLit..nkUInt64Lit, nkIntLit..nkInt64Lit:
    result = a.intVal
  else:
    raiseRecoverableError("cannot extract number from invalid AST node")

proc getFloat*(a: PNode): BiggestFloat =
  case a.kind
  of nkFloatLiterals: result = a.floatVal
  of nkCharLit, nkUIntLit..nkUInt64Lit, nkIntLit..nkInt64Lit:
    result = BiggestFloat a.intVal
  else:
    raiseRecoverableError("cannot extract number from invalid AST node")
    #doAssert false, "getFloat"
    #internalError(a.info, "getFloat")
    #result = 0.0

proc getStr*(a: PNode): string =
  case a.kind
  of nkStrLit..nkTripleStrLit: result = a.strVal
  of nkNilLit:
    # let's hope this fixes more problems than it creates:
    result = ""
  else:
    raiseRecoverableError("cannot extract string from invalid AST node")
    #doAssert false, "getStr"
    #internalError(a.info, "getStr")
    #result = ""

proc getStrOrChar*(a: PNode): string =
  case a.kind
  of nkStrLit..nkTripleStrLit: result = a.strVal
  of nkCharLit..nkUInt64Lit: result = $chr(int(a.intVal))
  else:
    raiseRecoverableError("cannot extract string from invalid AST node")
    #doAssert false, "getStrOrChar"
    #internalError(a.info, "getStrOrChar")
    #result = ""

proc isGenericParams*(n: PNode): bool {.inline.} =
  ## used to judge whether a node is generic params.
  n != nil and n.kind == nkGenericParams

proc isGenericRoutine*(n: PNode): bool  {.inline.} =
  n != nil and n.kind in callableDefs and n[genericParamsPos].isGenericParams

proc isGenericRoutineStrict*(s: PSym): bool {.inline.} =
  ## determines if this symbol represents a generic routine
  ## the unusual name is so it doesn't collide and eventually replaces
  ## `isGenericRoutine`
  s.kind in skProcKinds and s.ast.isGenericRoutine

proc isGenericRoutine*(s: PSym): bool {.inline.} =
  ## determines if this symbol represents a generic routine or an instance of
  ## one. This should be renamed accordingly and `isGenericRoutineStrict`
  ## should take this name instead.
  ##
  ## Warning/XXX: Unfortunately, it considers a proc kind symbol flagged with
  ## sfFromGeneric as a generic routine. Instead this should likely not be the
  ## case and the concepts should be teased apart:
  ## - generic definition
  ## - generic instance
  ## - either generic definition or instance
  s.kind in skProcKinds and (sfFromGeneric in s.flags or
                             s.ast.isGenericRoutine)

proc skipGenericOwner*(s: PSym): PSym =
  ## Generic instantiations are owned by their originating generic
  ## symbol. This proc skips such owners and goes straight to the owner
  ## of the generic itself (the module or the enclosing proc).
  result = if s.kind == skModule:
            s
           elif s.kind in skProcKinds and sfFromGeneric in s.flags and s.owner.kind != skModule:
             s.owner.owner
           else:
             s.owner

proc originatingModule*(s: PSym): PSym =
  result = s
  while result.kind != skModule: result = result.owner

proc isRoutine*(s: PSym): bool {.inline.} =
  result = s.kind in skProcKinds

proc isCompileTimeProc*(s: PSym): bool {.inline.} =
  result = s.kind == skMacro or
           s.kind in {skProc, skFunc} and sfCompileTime in s.flags

proc hasPattern*(s: PSym): bool {.inline.} =
  result = isRoutine(s) and s.ast[patternPos].kind != nkEmpty

iterator items*(n: PNode): PNode =
  for i in 0..<n.safeLen: yield n[i]

iterator pairs*(n: PNode): tuple[i: int, n: PNode] =
  for i in 0..<n.safeLen: yield (i, n[i])

proc isAtom*(n: PNode): bool {.inline.} =
  result = n.kind >= nkNone and n.kind <= nkNilLit

proc isEmptyType*(t: PType): bool {.inline.} =
  ## 'void' and 'typed' types are often equivalent to 'nil' these days:
  result = t == nil or t.kind in {tyVoid, tyTyped}

proc makeStmtList*(n: PNode): PNode =
  if n.kind == nkStmtList:
    result = n
  else:
    result = newNodeI(nkStmtList, n.info)
    result.add n

proc skipStmtList*(n: PNode): PNode =
  if n.kind in {nkStmtList, nkStmtListExpr}:
    for i in 0..<n.len-1:
      if n[i].kind notin {nkEmpty, nkCommentStmt}: return n
    result = n.lastSon
  else:
    result = n

proc toVar*(typ: PType; kind: TTypeKind; idgen: IdGenerator): PType =
  ## If ``typ`` is not a tyVar then it is converted into a `var <typ>` and
  ## returned. Otherwise ``typ`` is simply returned as-is.
  result = typ
  if typ.kind != kind:
    result = newType(kind, idgen, typ.owner, typ)

proc toRef*(typ: PType; idgen: IdGenerator): PType =
  ## If ``typ`` is a tyObject then it is converted into a `ref <typ>` and
  ## returned. Otherwise ``typ`` is simply returned as-is.
  result = typ
  if typ.skipTypes({tyAlias, tyGenericInst}).kind == tyObject:
    result = newType(tyRef, idgen, typ.owner, typ)

proc toObject*(typ: PType): PType =
  ## If ``typ`` is a tyRef then its immediate son is returned (which in many
  ## cases should be a ``tyObject``).
  ## Otherwise ``typ`` is simply returned as-is.
  let t = typ.skipTypes({tyAlias, tyGenericInst})
  if t.kind == tyRef: t.elementType
  else: typ

proc toObjectFromRefPtrGeneric*(typ: PType): PType =
  #[
  See also `toObject`.
  Finds the underlying `object`, even in cases like these:
  type
    B[T] = object f0: int
    A1[T] = ref B[T]
    A2[T] = ref object f1: int
    A3 = ref object f2: int
    A4 = object f3: int
  ]#
  result = typ
  while true:
    case result.kind
    of tyGenericBody: result = result.last
    of tyRef, tyPtr, tyGenericInst, tyGenericInvocation, tyAlias: result = result[0]
      # automatic dereferencing is deep, refs #18298.
    else: break
  # result does not have to be object type

proc isImportedException*(t: PType; conf: ConfigRef): bool =
  assert t != nil

  if conf.exc != excCpp:
    return false

  let base = t.skipTypes({tyAlias, tyPtr, tyDistinct, tyGenericInst})
  result = base.sym != nil and {sfCompileToCpp, sfImportc} * base.sym.flags != {}

proc isInfixAs*(n: PNode): bool =
  return n.kind == nkInfix and n[0].kind == nkIdent and n[0].ident.id == ord(wAs)

proc skipColon*(n: PNode): PNode =
  result = n
  if n.kind == nkExprColonExpr:
    result = n[1]

proc findUnresolvedStatic*(n: PNode): PNode =
  if n.kind == nkSym and n.typ != nil and n.typ.kind == tyStatic and n.typ.n == nil:
    return n
  if n.typ != nil and n.typ.kind == tyTypeDesc:
    let t = skipTypes(n.typ, {tyTypeDesc})
    if t.kind == tyGenericParam and not t.genericParamHasConstraints:
      return n
  for son in n:
    let n = son.findUnresolvedStatic
    if n != nil: return n

  return nil

when false:
  proc containsNil*(n: PNode): bool =
    # only for debugging
    if n.isNil: return true
    for i in 0..<n.safeLen:
      if n[i].containsNil: return true


template hasDestructor*(t: PType): bool = {tfHasAsgn, tfHasOwned} * t.flags != {}

template incompleteType*(t: PType): bool =
  t.sym != nil and {sfForward, sfNoForward} * t.sym.flags == {sfForward}

template typeCompleted*(s: PSym) =
  incl s.flags, sfNoForward

template detailedInfo*(sym: PSym): string =
  sym.name.s

proc isInlineIterator*(typ: PType): bool {.inline.} =
  typ.kind == tyProc and tfIterator in typ.flags and typ.callConv != ccClosure

proc isIterator*(typ: PType): bool {.inline.} =
  typ.kind == tyProc and tfIterator in typ.flags

proc isClosureIterator*(typ: PType): bool {.inline.} =
  typ.kind == tyProc and tfIterator in typ.flags and typ.callConv == ccClosure

proc isClosure*(typ: PType): bool {.inline.} =
  typ.kind == tyProc and typ.callConv == ccClosure

proc isNimcall*(s: PSym): bool {.inline.} =
  s.typ.callConv == ccNimCall

proc isExplicitCallConv*(s: PSym): bool {.inline.} =
  tfExplicitCallConv in s.typ.flags

proc isSinkParam*(s: PSym): bool {.inline.} =
  s.kind == skParam and (s.typ.kind == tySink or tfHasOwned in s.typ.flags)

proc isSinkType*(t: PType): bool {.inline.} =
  t.kind == tySink or tfHasOwned in t.flags

proc newProcType*(info: TLineInfo; idgen: IdGenerator; owner: PSym): PType =
  result = newType(tyProc, idgen, owner)
  result.n = newNodeI(nkFormalParams, info)
  rawAddSon(result, nil) # return type
  # result.n[0] used to be `nkType`, but now it's `nkEffectList` because
  # the effects are now stored in there too ... this is a bit hacky, but as
  # usual we desperately try to save memory:
  result.n.add newNodeI(nkEffectList, info)

proc addParam*(procType: PType; param: PSym) =
  param.position = procType.sons.len-1
  procType.n.add newSymNode(param)
  rawAddSon(procType, param.typ)

const magicsThatCanRaise = {
  mNone, mSlurp, mStaticExec, mParseExprToAst, mParseStmtToAst, mEcho}

proc canRaiseConservative*(fn: PNode): bool =
  if fn.kind == nkSym and fn.sym.magic notin magicsThatCanRaise:
    result = false
  else:
    result = true

proc canRaise*(fn: PNode): bool =
  if fn.kind == nkSym and (fn.sym.magic notin magicsThatCanRaise or
      {sfImportc, sfInfixCall} * fn.sym.flags == {sfImportc} or
      sfGeneratedOp in fn.sym.flags):
    result = false
  elif fn.kind == nkSym and fn.sym.magic == mEcho:
    result = true
  else:
    # TODO check for n having sons? or just return false for now if not
    if fn.typ != nil and fn.typ.n != nil and fn.typ.n[0].kind == nkSym:
      result = false
    else:
      result = fn.typ != nil and fn.typ.n != nil and ((fn.typ.n[0].len < effectListLen) or
        (fn.typ.n[0][exceptionEffects] != nil and
        fn.typ.n[0][exceptionEffects].safeLen > 0))

proc toHumanStrImpl[T](kind: T, num: static int): string =
  result = $kind
  result = result[num..^1]
  result[0] = result[0].toLowerAscii

proc toHumanStr*(kind: TSymKind): string =
  ## strips leading `sk`
  result = toHumanStrImpl(kind, 2)

proc toHumanStr*(kind: TTypeKind): string =
  ## strips leading `tk`
  result = toHumanStrImpl(kind, 2)

proc skipHiddenAddr*(n: PNode): PNode {.inline.} =
  (if n.kind == nkHiddenAddr: n[0] else: n)

proc isNewStyleConcept*(n: PNode): bool {.inline.} =
  assert n.kind == nkTypeClassTy
  result = n[0].kind == nkEmpty

proc isOutParam*(t: PType): bool {.inline.} = tfIsOutParam in t.flags

const
  nodesToIgnoreSet* = {nkNone..pred(nkSym), succ(nkSym)..nkNilLit,
    nkTypeSection, nkProcDef, nkConverterDef,
    nkMethodDef, nkIteratorDef, nkMacroDef, nkTemplateDef, nkLambda, nkDo,
    nkFuncDef, nkConstSection, nkConstDef, nkIncludeStmt, nkImportStmt,
    nkExportStmt, nkPragma, nkCommentStmt, nkBreakState,
    nkTypeOfExpr, nkMixinStmt, nkBindStmt}

proc isTrue*(n: PNode): bool =
  n.kind == nkSym and n.sym.kind == skEnumField and n.sym.position != 0 or
    n.kind == nkIntLit and n.intVal != 0

type
  TypeMapping* = Table[ItemId, PType]
  SymMapping* = Table[ItemId, PSym]

template idTableGet*(tab: typed; key: PSym | PType): untyped = tab.getOrDefault(key.itemId)
template idTablePut*(tab: typed; key, val: PSym | PType) = tab[key.itemId] = val

template initSymMapping*(): Table[ItemId, PSym] = initTable[ItemId, PSym]()
template initTypeMapping*(): Table[ItemId, PType] = initTable[ItemId, PType]()

template resetIdTable*(tab: Table[ItemId, PSym]) = tab.clear()
template resetIdTable*(tab: Table[ItemId, PType]) = tab.clear()
