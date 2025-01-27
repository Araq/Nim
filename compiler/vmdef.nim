#
#
#           The Nim Compiler
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module contains the type definitions for the new evaluation engine.
## An instruction is 1-3 int32s in memory, it is a register based VM.

import std/[tables, strutils]

import ast, idents, options, modulegraphs, lineinfos

type TInstrType* = uint64

const
  regOBits = 8 # Opcode
  regABits = 16
  regBBits = 16
  regCBits = 16
  regBxBits = 24

  byteExcess* = 128 # we use excess-K for immediates

# Calculate register shifts, masks and ranges

const
  regOShift* = 0.TInstrType
  regAShift* = (regOShift + regOBits)
  regBShift* = (regAShift + regABits)
  regCShift* = (regBShift + regBBits)
  regBxShift* = (regAShift + regABits)

  regOMask*  = ((1.TInstrType shl regOBits) - 1)
  regAMask*  = ((1.TInstrType shl regABits) - 1)
  regBMask*  = ((1.TInstrType shl regBBits) - 1)
  regCMask*  = ((1.TInstrType shl regCBits) - 1)
  regBxMask* = ((1.TInstrType shl regBxBits) - 1)

  wordExcess* = 1 shl (regBxBits-1)
  regBxMin* = -wordExcess+1
  regBxMax* =  wordExcess-1

type
  TRegister* = range[0..regAMask.int]
  TDest* = range[-1..regAMask.int]
  TInstr* = distinct TInstrType

  TOpcode* = enum
    opcEof,         # end of code
    opcRet,         # return
    opcYldYoid,     # yield with no value
    opcYldVal,      # yield with a value

    opcAsgnInt,
    opcAsgnFloat,
    opcAsgnRef,
    opcAsgnComplex,
    opcCastIntToFloat32,    # int and float must be of the same byte size
    opcCastIntToFloat64,    # int and float must be of the same byte size
    opcCastFloatToInt32,    # int and float must be of the same byte size
    opcCastFloatToInt64,    # int and float must be of the same byte size
    opcCastPtrToInt,
    opcCastIntToPtr,
    opcFastAsgnComplex,
    opcNodeToReg,

    opcLdArr,  # a = b[c]
    opcLdArrAddr, # a = addr(b[c])
    opcWrArr,  # a[b] = c
    opcLdObj,  # a = b.c
    opcLdObjAddr, # a = addr(b.c)
    opcWrObj,  # a.b = c
    opcAddrReg,
    opcAddrNode,
    opcLdDeref,
    opcWrDeref,
    opcWrStrIdx,
    opcLdStrIdx, # a = b[c]
    opcLdStrIdxAddr,  # a = addr(b[c])
    opcSlice, # toOpenArray(collection, left, right)

    opcAddInt,
    opcAddImmInt,
    opcSubInt,
    opcSubImmInt,
    opcLenSeq,
    opcLenStr,
    opcLenCstring,

    opcIncl, opcInclRange, opcExcl, opcCard, opcMulInt, opcDivInt, opcModInt,
    opcAddFloat, opcSubFloat, opcMulFloat, opcDivFloat,
    opcShrInt, opcShlInt, opcAshrInt,
    opcBitandInt, opcBitorInt, opcBitxorInt, opcAddu, opcSubu, opcMulu,
    opcDivu, opcModu, opcEqInt, opcLeInt, opcLtInt, opcEqFloat,
    opcLeFloat, opcLtFloat, opcLeu, opcLtu,
    opcEqRef, opcEqNimNode, opcSameNodeType,
    opcXor, opcNot, opcUnaryMinusInt, opcUnaryMinusFloat, opcBitnotInt,
    opcEqStr, opcEqCString, opcLeStr, opcLtStr, opcEqSet, opcLeSet, opcLtSet,
    opcMulSet, opcPlusSet, opcMinusSet, opcXorSet, opcConcatStr,
    opcContainsSet, opcRepr, opcSetLenStr, opcSetLenSeq,
    opcIsNil, opcOf, opcIs,
    opcParseFloat, opcConv, opcCast,
    opcQuit, opcInvalidField,
    opcNarrowS, opcNarrowU,
    opcSignExtend,

    opcAddStrCh,
    opcAddStrStr,
    opcAddSeqElem,
    opcRangeChck,

    opcNAdd,
    opcNAddMultiple,
    opcNKind,
    opcNSymKind,
    opcNIntVal,
    opcNFloatVal,
    opcNSymbol,
    opcNIdent,
    opcNGetType,
    opcNStrVal,
    opcNSigHash,
    opcNGetSize,

    opcNSetIntVal,
    opcNSetFloatVal, opcNSetSymbol, opcNSetIdent, opcNSetStrVal,
    opcNNewNimNode, opcNCopyNimNode, opcNCopyNimTree, opcNDel, opcGenSym,

    opcNccValue, opcNccInc, opcNcsAdd, opcNcsIncl, opcNcsLen, opcNcsAt,
    opcNctPut, opcNctLen, opcNctGet, opcNctHasNext, opcNctNext, opcNodeId,

    opcSlurp,
    opcGorge,
    opcParseExprToAst,
    opcParseStmtToAst,
    opcQueryErrorFlag,
    opcNError,
    opcNWarning,
    opcNHint,
    opcNGetLineInfo, opcNCopyLineInfo, opcNSetLineInfoLine,
    opcNSetLineInfoColumn, opcNSetLineInfoFile
    opcEqIdent,
    opcStrToIdent,
    opcGetImpl,
    opcGetImplTransf

    opcEcho,
    opcIndCall, # dest = call regStart, n; where regStart = fn, arg1, ...
    opcIndCallAsgn, # dest = call regStart, n; where regStart = fn, arg1, ...

    opcRaise,
    opcNChild,
    opcNSetChild,
    opcCallSite,
    opcNewStr,

    opcTJmp,  # jump Bx if A != 0
    opcFJmp,  # jump Bx if A == 0
    opcJmp,   # jump Bx
    opcJmpBack, # jump Bx; resulting from a while loop
    opcBranch,  # branch for 'case'
    opcTry,
    opcExcept,
    opcFinally,
    opcFinallyEnd,
    opcNew,
    opcNewSeq,
    opcLdNull,    # dest = nullvalue(types[Bx])
    opcLdNullReg,
    opcLdConst,   # dest = constants[Bx]
    opcAsgnConst, # dest = copy(constants[Bx])
    opcLdGlobal,  # dest = globals[Bx]
    opcLdGlobalAddr, # dest = addr(globals[Bx])
    opcLdGlobalDerefFFI, # dest = globals[Bx][]
    opcLdGlobalAddrDerefFFI, # globals[Bx][] = ...

    opcLdImmInt,  # dest = immediate value
    opcNBindSym, opcNDynBindSym,
    opcSetType,   # dest.typ = types[Bx]
    opcTypeTrait,
    opcSymOwner,
    opcSymIsInstantiationOf

  TBlock* = object
    label*: PSym
    fixups*: seq[TPosition]

  TEvalMode* = enum           ## reason for evaluation
    emRepl,                   ## evaluate because in REPL mode
    emConst,                  ## evaluate for 'const' according to spec
    emOptimize,               ## evaluate for optimization purposes (same as
                              ## emConst?)
    emStaticExpr,             ## evaluate for enforced compile time eval
                              ## ('static' context)
    emStaticStmt              ## 'static' as an expression

  TSandboxFlag* = enum        ## what the evaluation engine should allow
    allowCast,                ## allow unsafe language feature: 'cast'
    allowInfiniteLoops        ## allow endless loops
    allowInfiniteRecursion    ## allow infinite recursion
  TSandboxFlags* = set[TSandboxFlag]

  TSlotKind* = enum   # We try to re-use slots in a smart way to
                      # minimize allocations; however the VM supports arbitrary
                      # temporary slot usage. This is required for the parameter
                      # passing implementation.
    slotEmpty,        # slot is unused
    slotFixedVar,     # slot is used for a fixed var/result (requires copy then)
    slotFixedLet,     # slot is used for a fixed param/let
    slotTempUnknown,  # slot but type unknown (argument of proc call)
    slotTempInt,      # some temporary int
    slotTempFloat,    # some temporary float
    slotTempStr,      # some temporary string
    slotTempComplex,  # some complex temporary (s.node field is used)
    slotTempPerm      # slot is temporary but permanent (hack)

  TRegisterKind* = enum
    rkNone, rkNode, rkInt, rkFloat, rkRegisterAddr, rkNodeAddr
  TFullReg* = object  # with a custom mark proc, we could use the same
                      # data representation as LuaJit (tagged NaNs).
    case kind*: TRegisterKind
    of rkNone: nil
    of rkInt: intVal*: BiggestInt
    of rkFloat: floatVal*: BiggestFloat
    of rkNode: node*: PNode
    of rkRegisterAddr: regAddr*: ptr TFullReg
    of rkNodeAddr: nodeAddr*: ptr PNode

  PProc* = ref object
    blocks*: seq[TBlock]    # blocks; temp data structure
    sym*: PSym
    regInfo*: seq[tuple[inUse: bool, kind: TSlotKind]]

  VmArgs* = object
    ra*, rb*, rc*: Natural
    slots*: ptr UncheckedArray[TFullReg]
    currentException*: PNode
    currentLineInfo*: TLineInfo
  VmCallback* = proc (args: VmArgs) {.closure.}

  PCtx* = ref TCtx
  TCtx* = object of TPassContext # code gen context
    code*: seq[TInstr]
    debug*: seq[TLineInfo]  # line info for every instruction; kept separate
                            # to not slow down interpretation
    globals*: PNode         #
    constants*: PNode       # constant data
    types*: seq[PType]      # some instructions reference types (e.g. 'except')
    currentExceptionA*, currentExceptionB*: PNode
    exceptionInstr*: int # index of instruction that raised the exception
    prc*: PProc
    module*: PSym
    callsite*: PNode
    mode*: TEvalMode
    features*: TSandboxFlags
    traceActive*: bool
    loopIterations*, callDepth*: int
    comesFromHeuristic*: TLineInfo # Heuristic for better macro stack traces
    callbacks*: seq[VmCallback]
    callbackIndex*: Table[string, int]
    errorFlag*: string
    cache*: IdentCache
    config*: ConfigRef
    graph*: ModuleGraph
    oldErrorCount*: int
    profiler*: Profiler
    templInstCounter*: ref int # gives every template instantiation a unique ID, needed here for getAst
    vmstateDiff*: seq[(PSym, PNode)] # we remember the "diff" to global state here (feature for IC)
    procToCodePos*: Table[int, int]
    cannotEval*: bool

  PStackFrame* = ref TStackFrame
  TStackFrame* {.acyclic.} = object
    prc*: PSym                 # current prc; proc that is evaluated
    slots*: seq[TFullReg]      # parameters passed to the proc + locals;
                              # parameters come first
    next*: PStackFrame         # for stacking
    comesFrom*: int
    safePoints*: seq[int]      # used for exception handling
                              # XXX 'break' should perform cleanup actions
                              # What does the C backend do for it?
  Profiler* = object
    tEnter*: float
    tos*: PStackFrame

  TPosition* = distinct int

  PEvalContext* = PCtx

proc newCtx*(module: PSym; cache: IdentCache; g: ModuleGraph; idgen: IdGenerator): PCtx =
  PCtx(code: @[], debug: @[],
    globals: newNode(nkStmtListExpr), constants: newNode(nkStmtList), types: @[],
    prc: PProc(blocks: @[]), module: module, loopIterations: g.config.maxLoopIterationsVM,
    callDepth: g.config.maxCallDepthVM,
    comesFromHeuristic: unknownLineInfo, callbacks: @[], callbackIndex: initTable[string, int](), errorFlag: "",
    cache: cache, config: g.config, graph: g, idgen: idgen)

proc refresh*(c: PCtx, module: PSym; idgen: IdGenerator) =
  c.module = module
  c.prc = PProc(blocks: @[])
  c.loopIterations = c.config.maxLoopIterationsVM
  c.callDepth = c.config.maxCallDepthVM
  c.idgen = idgen

proc reverseName(s: string): string =
  result = newStringOfCap(s.len)
  let y = s.split('.')
  for i in 1..y.len:
    result.add y[^i]
    if i != y.len:
      result.add '.'

proc registerCallback*(c: PCtx; name: string; callback: VmCallback): int {.discardable.} =
  result = c.callbacks.len
  c.callbacks.add(callback)
  c.callbackIndex[reverseName(name)] = result

const
  firstABxInstr* = opcTJmp
  largeInstrs* = { # instructions which use 2 int32s instead of 1:
    opcConv, opcCast, opcNewSeq, opcOf
    }
  slotSomeTemp* = slotTempUnknown
  relativeJumps* = {opcTJmp, opcFJmp, opcJmp, opcJmpBack}

# flag is used to signal opcSeqLen if node is NimNode.
const nimNodeFlag* = 16

template opcode*(x: TInstr): TOpcode = TOpcode(x.TInstrType shr regOShift and regOMask)
template regA*(x: TInstr): TRegister = TRegister(x.TInstrType shr regAShift and regAMask)
template regB*(x: TInstr): TRegister = TRegister(x.TInstrType shr regBShift and regBMask)
template regC*(x: TInstr): TRegister = TRegister(x.TInstrType shr regCShift and regCMask)
template regBx*(x: TInstr): int = (x.TInstrType shr regBxShift and regBxMask).int

template jmpDiff*(x: TInstr): int = regBx(x) - wordExcess
