#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This file implements the new evaluation engine for Nim code.
## An instruction is 1-3 int32s in memory, it is a register based VM.

import semmacrosanity
import
  std/[strutils, tables, parseutils],
  msgs, vmdef, vmgen, nimsets, types,
  parser, vmdeps, idents, trees, renderer, options, transf,
  gorgeimpl, lineinfos, btrees, macrocacheimpl,
  modulegraphs, sighashes, int128, vmprofiler

when defined(nimPreviewSlimSystem):
  import std/formatfloat
import ast except getstr
from semfold import leValueConv, ordinalValToString
from evaltempl import evalTemplate
from magicsys import getSysType

const
  traceCode = defined(nimVMDebug)

when hasFFI:
  import evalffi


proc stackTraceAux(c: PCtx; x: PStackFrame; pc: int; recursionLimit=100) =
  if x != nil:
    if recursionLimit == 0:
      var calls = 0
      var x = x
      while x != nil:
        inc calls
        x = x.next
      msgWriteln(c.config, $calls & " calls omitted\n", {msgNoUnitSep})
      return
    stackTraceAux(c, x.next, x.comesFrom, recursionLimit-1)
    var info = c.debug[pc]
    # we now use a format similar to the one in lib/system/excpt.nim
    var s = ""
    # todo: factor with quotedFilename
    if optExcessiveStackTrace in c.config.globalOptions:
      s = toFullPath(c.config, info)
    else:
      s = toFilename(c.config, info)
    var line = toLinenumber(info)
    var col = toColumn(info)
    if line > 0:
      s.add('(')
      s.add($line)
      s.add(", ")
      s.add($(col + ColOffset))
      s.add(')')
    if x.prc != nil:
      for k in 1..max(1, 25-s.len): s.add(' ')
      s.add(x.prc.name.s)
    msgWriteln(c.config, s, {msgNoUnitSep})

proc stackTraceImpl(c: PCtx, tos: PStackFrame, pc: int,
  msg: string, lineInfo: TLineInfo, infoOrigin: InstantiationInfo) {.noinline.} =
  # noinline to avoid code bloat
  msgWriteln(c.config, "stack trace: (most recent call last)", {msgNoUnitSep})
  stackTraceAux(c, tos, pc)
  let action = if c.mode == emRepl: doRaise else: doNothing
    # XXX test if we want 'globalError' for every mode
  let lineInfo = if lineInfo == TLineInfo.default: c.debug[pc] else: lineInfo
  liMessage(c.config, lineInfo, errGenerated, msg, action, infoOrigin)

when not defined(nimHasCallsitePragma):
  {.pragma: callsite.}

template stackTrace(c: PCtx, tos: PStackFrame, pc: int,
                    msg: string, lineInfo: TLineInfo = TLineInfo.default) {.callsite.} =
  stackTraceImpl(c, tos, pc, msg, lineInfo, instantiationInfo(-2, fullPaths = true))
  return

proc bailOut(c: PCtx; tos: PStackFrame) =
  stackTrace(c, tos, c.exceptionInstr, "unhandled exception: " &
             c.currentExceptionA[3].skipColon.strVal &
             " [" & c.currentExceptionA[2].skipColon.strVal & "]")

when not defined(nimComputedGoto):
  {.pragma: computedGoto.}

proc ensureKind(n: var TFullReg, k: TRegisterKind) {.inline.} =
  if n.kind != k:
    n = TFullReg(kind: k)

template ensureKind(k: untyped) {.dirty.} =
  ensureKind(regs[ra], k)

template decodeB(k: untyped) {.dirty.} =
  let rb = instr.regB
  ensureKind(k)

template decodeBC(k: untyped) {.dirty.} =
  let rb = instr.regB
  let rc = instr.regC
  ensureKind(k)

template declBC() {.dirty.} =
  let rb = instr.regB
  let rc = instr.regC

template decodeBImm(k: untyped) {.dirty.} =
  let rb = instr.regB
  let imm = instr.regC - byteExcess
  ensureKind(k)

template decodeBx(k: untyped) {.dirty.} =
  let rbx = instr.regBx - wordExcess
  ensureKind(k)

template move(a, b: untyped) {.dirty.} =
  when defined(gcArc) or defined(gcOrc) or defined(gcAtomicArc):
    a = move b
  else:
    system.shallowCopy(a, b)
    # XXX fix minor 'shallowCopy' overloading bug in compiler

proc derefPtrToReg(address: BiggestInt, typ: PType, r: var TFullReg, isAssign: bool): bool =
  # nim bug: `isAssign: static bool` doesn't work, giving odd compiler error
  template fun(field, typ, rkind) =
    if isAssign:
      cast[ptr typ](address)[] = typ(r.field)
    else:
      r.ensureKind(rkind)
      let val = cast[ptr typ](address)[]
      when typ is SomeInteger | char:
        r.field = BiggestInt(val)
      else:
        r.field = val
    return true

  ## see also typeinfo.getBiggestInt
  case typ.kind
  of tyChar: fun(intVal, char, rkInt)
  of tyInt: fun(intVal, int, rkInt)
  of tyInt8: fun(intVal, int8, rkInt)
  of tyInt16: fun(intVal, int16, rkInt)
  of tyInt32: fun(intVal, int32, rkInt)
  of tyInt64: fun(intVal, int64, rkInt)
  of tyUInt: fun(intVal, uint, rkInt)
  of tyUInt8: fun(intVal, uint8, rkInt)
  of tyUInt16: fun(intVal, uint16, rkInt)
  of tyUInt32: fun(intVal, uint32, rkInt)
  of tyUInt64: fun(intVal, uint64, rkInt) # note: differs from typeinfo.getBiggestInt
  of tyFloat: fun(floatVal, float, rkFloat)
  of tyFloat32: fun(floatVal, float32, rkFloat)
  of tyFloat64: fun(floatVal, float64, rkFloat)
  else: return false

proc createStrKeepNode(x: var TFullReg; keepNode=true) =
  if x.node.isNil or not keepNode:
    x.node = newNode(nkStrLit)
  elif x.node.kind == nkNilLit and keepNode:
    when defined(useNodeIds):
      let id = x.node.id
    x.node[] = TNode(kind: nkStrLit)
    when defined(useNodeIds):
      x.node.id = id
  elif x.node.kind notin {nkStrLit..nkTripleStrLit} or
      nfAllConst in x.node.flags:
    # XXX this is hacky; tests/txmlgen triggers it:
    x.node = newNode(nkStrLit)
    # It not only hackey, it is also wrong for tgentemplate. The primary
    # cause of bugs like these is that the VM does not properly distinguish
    # between variable definitions (var foo = e) and variable updates (foo = e).

include vmhooks

template createStr(x) =
  x.node = newNode(nkStrLit)

template createSet(x) =
  x.node = newNode(nkCurly)

proc moveConst(x: var TFullReg, y: TFullReg) =
  x.ensureKind(y.kind)
  case x.kind
  of rkNone: discard
  of rkInt: x.intVal = y.intVal
  of rkFloat: x.floatVal = y.floatVal
  of rkNode: x.node = y.node
  of rkRegisterAddr: x.regAddr = y.regAddr
  of rkNodeAddr: x.nodeAddr = y.nodeAddr

# this seems to be the best way to model the reference semantics
# of system.NimNode:
template asgnRef(x, y: untyped) = moveConst(x, y)

proc copyValue(src: PNode): PNode =
  if src == nil or nfIsRef in src.flags:
    return src
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
  of nkFloatLit..nkFloat128Lit: result.floatVal = src.floatVal
  of nkSym: result.sym = src.sym
  of nkIdent: result.ident = src.ident
  of nkStrLit..nkTripleStrLit: result.strVal = src.strVal
  else:
    newSeq(result.sons, src.len)
    for i in 0..<src.len:
      result[i] = copyValue(src[i])

proc asgnComplex(x: var TFullReg, y: TFullReg) =
  x.ensureKind(y.kind)
  case x.kind
  of rkNone: discard
  of rkInt: x.intVal = y.intVal
  of rkFloat: x.floatVal = y.floatVal
  of rkNode: x.node = copyValue(y.node)
  of rkRegisterAddr: x.regAddr = y.regAddr
  of rkNodeAddr: x.nodeAddr = y.nodeAddr

proc fastAsgnComplex(x: var TFullReg, y: TFullReg) =
  x.ensureKind(y.kind)
  case x.kind
  of rkNone: discard
  of rkInt: x.intVal = y.intVal
  of rkFloat: x.floatVal = y.floatVal
  of rkNode: x.node = y.node
  of rkRegisterAddr: x.regAddr = y.regAddr
  of rkNodeAddr: x.nodeAddr = y.nodeAddr

proc writeField(n: var PNode, x: TFullReg) =
  case x.kind
  of rkNone: discard
  of rkInt:
    if n.kind == nkNilLit:
      n[] = TNode(kind: nkIntLit) # ideally, `nkPtrLit`
    n.intVal = x.intVal
  of rkFloat: n.floatVal = x.floatVal
  of rkNode: n = copyValue(x.node)
  of rkRegisterAddr: writeField(n, x.regAddr[])
  of rkNodeAddr: n = x.nodeAddr[]

proc putIntoReg(dest: var TFullReg; n: PNode) =
  case n.kind
  of nkStrLit..nkTripleStrLit:
    dest = TFullReg(kind: rkNode, node: newStrNode(nkStrLit, n.strVal))
  of nkIntLit: # use `nkPtrLit` once this is added
    if dest.kind == rkNode: dest.node = n
    elif n.typ != nil and n.typ.kind in PtrLikeKinds:
      dest = TFullReg(kind: rkNode, node: n)
    else:
      dest = TFullReg(kind: rkInt, intVal: n.intVal)
  of {nkCharLit..nkUInt64Lit} - {nkIntLit}:
    dest = TFullReg(kind: rkInt, intVal: n.intVal)
  of nkFloatLit..nkFloat128Lit:
    dest = TFullReg(kind: rkFloat, floatVal: n.floatVal)
  else:
    dest = TFullReg(kind: rkNode, node: n)

proc regToNode(x: TFullReg): PNode =
  case x.kind
  of rkNone: result = newNode(nkEmpty)
  of rkInt: result = newNode(nkIntLit); result.intVal = x.intVal
  of rkFloat: result = newNode(nkFloatLit); result.floatVal = x.floatVal
  of rkNode: result = x.node
  of rkRegisterAddr: result = regToNode(x.regAddr[])
  of rkNodeAddr: result = x.nodeAddr[]

template getstr(a: untyped): untyped =
  (if a.kind == rkNode: a.node.strVal else: $chr(int(a.intVal)))

proc pushSafePoint(f: PStackFrame; pc: int) =
  f.safePoints.add(pc)

proc popSafePoint(f: PStackFrame) =
  discard f.safePoints.pop()

type
  ExceptionGoto = enum
    ExceptionGotoHandler,
    ExceptionGotoFinally,
    ExceptionGotoUnhandled

proc findExceptionHandler(c: PCtx, f: PStackFrame, exc: PNode):
    tuple[why: ExceptionGoto, where: int] =
  let raisedType = exc.typ.skipTypes(abstractPtrs)

  while f.safePoints.len > 0:
    var pc = f.safePoints.pop()

    var matched = false
    var pcEndExcept = pc

    # Scan the chain of exceptions starting at pc.
    # The structure is the following:
    # pc - opcExcept, <end of this block>
    #      - opcExcept, <pattern1>
    #      - opcExcept, <pattern2>
    #        ...
    #      - opcExcept, <patternN>
    #      - Exception handler body
    #    - ... more opcExcept blocks may follow
    #    - ... an optional opcFinally block may follow
    #
    # Note that the exception handler body already contains a jump to the
    # finally block or, if that's not present, to the point where the execution
    # should continue.
    # Also note that opcFinally blocks are the last in the chain.
    while c.code[pc].opcode == opcExcept:
      # Where this Except block ends
      pcEndExcept = pc + c.code[pc].regBx - wordExcess
      inc pc

      # A series of opcExcept follows for each exception type matched
      while c.code[pc].opcode == opcExcept:
        let excIndex = c.code[pc].regBx - wordExcess
        let exceptType =
          if excIndex > 0: c.types[excIndex].skipTypes(abstractPtrs)
          else: nil

        # echo typeToString(exceptType), " ", typeToString(raisedType)

        # Determine if the exception type matches the pattern
        if exceptType.isNil or inheritanceDiff(raisedType, exceptType) <= 0:
          matched = true
          break

        inc pc

      # Skip any further ``except`` pattern and find the first instruction of
      # the handler body
      while c.code[pc].opcode == opcExcept:
        inc pc

      if matched:
        break

      # If no handler in this chain is able to catch this exception we check if
      # the "parent" chains are able to. If this chain ends with a `finally`
      # block we must execute it before continuing.
      pc = pcEndExcept

    # Where the handler body starts
    let pcBody = pc

    if matched:
      return (ExceptionGotoHandler, pcBody)
    elif c.code[pc].opcode == opcFinally:
      # The +1 here is here because we don't want to execute it since we've
      # already pop'd this statepoint from the stack.
      return (ExceptionGotoFinally, pc + 1)

  return (ExceptionGotoUnhandled, 0)

proc cleanUpOnReturn(c: PCtx; f: PStackFrame): int =
  # Walk up the chain of safepoints and return the PC of the first `finally`
  # block we find or -1 if no such block is found.
  # Note that the safepoint is removed once the function returns!
  result = -1

  # Traverse the stack starting from the end in order to execute the blocks in
  # the intended order
  for i in 1..f.safePoints.len:
    var pc = f.safePoints[^i]
    # Skip the `except` blocks
    while c.code[pc].opcode == opcExcept:
      pc += c.code[pc].regBx - wordExcess
    if c.code[pc].opcode == opcFinally:
      discard f.safePoints.pop
      return pc + 1

proc opConv(c: PCtx; dest: var TFullReg, src: TFullReg, desttyp, srctyp: PType): bool =
  result = false
  if desttyp.kind == tyString:
    dest.ensureKind(rkNode)
    dest.node = newNode(nkStrLit)
    let styp = srctyp.skipTypes(abstractRange)
    case styp.kind
    of tyEnum:
      let n = styp.n
      let x = src.intVal.int
      if x <% n.len and (let f = n[x].sym; f.position == x):
        dest.node.strVal = if f.ast.isNil: f.name.s else: f.ast.strVal
      else:
        for i in 0..<n.len:
          if n[i].kind != nkSym: internalError(c.config, "opConv for enum")
          let f = n[i].sym
          if f.position == x:
            dest.node.strVal = if f.ast.isNil: f.name.s else: f.ast.strVal
            return
        dest.node.strVal = styp.sym.name.s & " " & $x
    of tyInt..tyInt64:
      dest.node.strVal = $src.intVal
    of tyUInt..tyUInt64:
      dest.node.strVal = $uint64(src.intVal)
    of tyBool:
      dest.node.strVal = if src.intVal == 0: "false" else: "true"
    of tyFloat..tyFloat128:
      dest.node.strVal = $src.floatVal
    of tyString:
      dest.node.strVal = src.node.strVal
    of tyCstring:
      if src.node.kind == nkBracket:
        # Array of chars
        var strVal = ""
        for son in src.node.sons:
          let c = char(son.intVal)
          if c == '\0': break
          strVal.add(c)
        dest.node.strVal = strVal
      else:
        dest.node.strVal = src.node.strVal
    of tyChar:
      dest.node.strVal = $chr(src.intVal)
    else:
      internalError(c.config, "cannot convert to string " & desttyp.typeToString)
  else:
    let desttyp = skipTypes(desttyp, abstractVarRange)
    case desttyp.kind
    of tyInt..tyInt64:
      dest.ensureKind(rkInt)
      case skipTypes(srctyp, abstractRange).kind
      of tyFloat..tyFloat64:
        dest.intVal = int(src.floatVal)
      else:
        dest.intVal = src.intVal
      if toInt128(dest.intVal) < firstOrd(c.config, desttyp) or toInt128(dest.intVal) > lastOrd(c.config, desttyp):
        return true
    of tyUInt..tyUInt64:
      dest.ensureKind(rkInt)
      let styp = srctyp.skipTypes(abstractRange) # skip distinct types(dest type could do this too if needed)
      case styp.kind
      of tyFloat..tyFloat64:
        dest.intVal = int(src.floatVal)
      else:
        let destSize = getSize(c.config, desttyp)
        let destDist = (sizeof(dest.intVal) - destSize) * 8
        var value = cast[BiggestUInt](src.intVal)
        when false:
          # this would make uint64(-5'i8) evaluate to 251
          # but at runtime, uint64(-5'i8) is 18446744073709551611
          # so don't do it
          let srcSize = getSize(c.config, styp)
          let srcDist = (sizeof(src.intVal) - srcSize) * 8
          value = (value shl srcDist) shr srcDist
        value = (value shl destDist) shr destDist
        dest.intVal = cast[BiggestInt](value)
    of tyBool:
      dest.ensureKind(rkInt)
      dest.intVal =
        case skipTypes(srctyp, abstractRange).kind
          of tyFloat..tyFloat64: int(src.floatVal != 0.0)
          else: int(src.intVal != 0)
    of tyFloat..tyFloat64:
      dest.ensureKind(rkFloat)
      let srcKind = skipTypes(srctyp, abstractRange).kind
      case srcKind
      of tyInt..tyInt64, tyUInt..tyUInt64, tyEnum, tyBool, tyChar:
        dest.floatVal = toBiggestFloat(src.intVal)
      elif src.kind == rkInt:
        dest.floatVal = toBiggestFloat(src.intVal)
      else:
        dest.floatVal = src.floatVal
    of tyObject:
      if srctyp.skipTypes(abstractVarRange).kind != tyObject:
        internalError(c.config, "invalid object-to-object conversion")
      # A object-to-object conversion is essentially a no-op
      moveConst(dest, src)
    else:
      asgnComplex(dest, src)

proc compile(c: PCtx, s: PSym): int =
  result = vmgen.genProc(c, s)
  when debugEchoCode: c.echoCode result
  #c.echoCode

template handleJmpBack() {.dirty.} =
  if c.loopIterations <= 0:
    if allowInfiniteLoops in c.features:
      c.loopIterations = c.config.maxLoopIterationsVM
    else:
      msgWriteln(c.config, "stack trace: (most recent call last)", {msgNoUnitSep})
      stackTraceAux(c, tos, pc)
      globalError(c.config, c.debug[pc], errTooManyIterations % $c.config.maxLoopIterationsVM)
  dec(c.loopIterations)

proc recSetFlagIsRef(arg: PNode) =
  if arg.kind notin {nkStrLit..nkTripleStrLit}:
    arg.flags.incl(nfIsRef)
  for i in 0..<arg.safeLen:
    arg[i].recSetFlagIsRef

proc setLenSeq(c: PCtx; node: PNode; newLen: int; info: TLineInfo) =
  let typ = node.typ.skipTypes(abstractInst+{tyRange}-{tyTypeDesc})
  let oldLen = node.len
  setLen(node.sons, newLen)
  if oldLen < newLen:
    for i in oldLen..<newLen:
      node[i] = getNullValue(c, typ.elementType, info, c.config)

const
  errNilAccess = "attempt to access a nil address"
  errOverOrUnderflow = "over- or underflow"
  errConstantDivisionByZero = "division by zero"
  errIllegalConvFromXtoY = "illegal conversion from '$1' to '$2'"
  errTooManyIterations = "interpretation requires too many iterations; " &
    "if you are sure this is not a bug in your code, compile with `--maxLoopIterationsVM:number` (current value: $1)"
  errCallDepthExceeded = "maximum call depth for the VM exceeded; " &
    "if you are sure this is not a bug in your code, compile with `--maxCallDepthVM:number` (current value: $1)"
  errFieldXNotFound = "node lacks field: "


template maybeHandlePtr(node2: PNode, reg: TFullReg, isAssign2: bool): bool =
  let node = node2 # prevent double evaluation
  if node.kind == nkNilLit:
    stackTrace(c, tos, pc, errNilAccess)
  let typ = node.typ
  if nfIsPtr in node.flags or (typ != nil and typ.kind == tyPtr):
    assert node.kind == nkIntLit, $(node.kind)
    assert typ != nil
    let typ2 = if typ.kind == tyPtr: typ.elementType else: typ
    if not derefPtrToReg(node.intVal, typ2, reg, isAssign = isAssign2):
      # tyObject not supported in this context
      stackTrace(c, tos, pc, "deref unsupported ptr type: " & $(typeToString(typ), typ.kind))
    true
  else:
    false

template takeAddress(reg, source) =
  reg.nodeAddr = addr source
  GC_ref source

proc takeCharAddress(c: PCtx, src: PNode, index: BiggestInt, pc: int): TFullReg =
  let typ = newType(tyPtr, c.idgen, c.module.owner)
  typ.add getSysType(c.graph, c.debug[pc], tyChar)
  var node = newNodeIT(nkIntLit, c.debug[pc], typ) # xxx nkPtrLit
  node.intVal = cast[int](src.strVal[index].addr)
  node.flags.incl nfIsPtr
  TFullReg(kind: rkNode, node: node)


proc rawExecute(c: PCtx, start: int, tos: PStackFrame): TFullReg =
  result = TFullReg(kind: rkNone)
  var pc = start
  var tos = tos
  # Used to keep track of where the execution is resumed.
  var savedPC = -1
  var savedFrame: PStackFrame = nil
  when defined(gcArc) or defined(gcOrc) or defined(gcAtomicArc):
    template updateRegsAlias = discard
    template regs: untyped = tos.slots
  else:
    template updateRegsAlias =
      move(regs, tos.slots)
    var regs: seq[TFullReg] # alias to tos.slots for performance
    updateRegsAlias
  #echo "NEW RUN ------------------------"
  while true:
    #{.computedGoto.}
    let instr = c.code[pc]
    let ra = instr.regA

    when traceCode:
      template regDescr(name, r): string =
        let kind = if r < regs.len: $regs[r].kind else: ""
        let ret = name & ": " & $r & " " & $kind
        alignLeft(ret, 15)
      echo "PC:$pc $opcode $ra $rb $rc" % [
        "pc", $pc, "opcode", alignLeft($c.code[pc].opcode, 15),
        "ra", regDescr("ra", ra), "rb", regDescr("rb", instr.regB),
        "rc", regDescr("rc", instr.regC)]
    if c.config.isVmTrace:
      # unlike nimVMDebug, this doesn't require re-compiling nim and is controlled by user code
      let info = c.debug[pc]
      # other useful variables: c.loopIterations
      echo "$# [$#] $#" % [c.config$info, $instr.opcode, c.config.sourceLine(info)]
    c.profiler.enter(c, tos)
    case instr.opcode
    of opcEof: return regs[ra]
    of opcRet:
      let newPc = c.cleanUpOnReturn(tos)
      # Perform any cleanup action before returning
      if newPc < 0:
        inc(c.callDepth)
        pc = tos.comesFrom
        let retVal = regs[0]
        tos = tos.next
        if tos.isNil:
          return retVal

        updateRegsAlias
        assert c.code[pc].opcode in {opcIndCall, opcIndCallAsgn}
        if c.code[pc].opcode == opcIndCallAsgn:
          regs[c.code[pc].regA] = retVal
      else:
        savedPC = pc
        savedFrame = tos
        # The -1 is needed because at the end of the loop we increment `pc`
        pc = newPc - 1
    of opcYldYoid: assert false
    of opcYldVal: assert false
    of opcAsgnInt:
      decodeB(rkInt)
      if regs[rb].kind == rkInt:
        regs[ra].intVal = regs[rb].intVal
      else:
        stackTrace(c, tos, pc, "opcAsgnInt: got " & $regs[rb].kind)
    of opcAsgnFloat:
      decodeB(rkFloat)
      regs[ra].floatVal = regs[rb].floatVal
    of opcCastFloatToInt32:
      let rb = instr.regB
      ensureKind(rkInt)
      regs[ra].intVal = cast[int32](float32(regs[rb].floatVal))
    of opcCastFloatToInt64:
      let rb = instr.regB
      ensureKind(rkInt)
      regs[ra].intVal = cast[int64](regs[rb].floatVal)
    of opcCastIntToFloat32:
      let rb = instr.regB
      ensureKind(rkFloat)
      regs[ra].floatVal = cast[float32](regs[rb].intVal)
    of opcCastIntToFloat64:
      let rb = instr.regB
      ensureKind(rkFloat)
      regs[ra].floatVal = cast[float64](regs[rb].intVal)

    of opcCastPtrToInt: # RENAME opcCastPtrOrRefToInt
      decodeBImm(rkInt)
      case imm
      of 1: # PtrLikeKinds
        case regs[rb].kind
        of rkNode:
          regs[ra].intVal = cast[int](regs[rb].node.intVal)
        of rkNodeAddr:
          regs[ra].intVal = cast[int](regs[rb].nodeAddr)
        of rkRegisterAddr:
          regs[ra].intVal = cast[int](regs[rb].regAddr)
        of rkInt:
          regs[ra].intVal = regs[rb].intVal
        else:
          stackTrace(c, tos, pc, "opcCastPtrToInt: got " & $regs[rb].kind)
      of 2: # tyRef
        regs[ra].intVal = cast[int](regs[rb].node)
      else: assert false, $imm
    of opcCastIntToPtr:
      let rb = instr.regB
      let typ = regs[ra].node.typ
      let node2 = newNodeIT(nkIntLit, c.debug[pc], typ)
      case regs[rb].kind
      of rkInt: node2.intVal = regs[rb].intVal
      of rkNode:
        if regs[rb].node.typ.kind notin PtrLikeKinds:
          stackTrace(c, tos, pc, "opcCastIntToPtr: regs[rb].node.typ: " & $regs[rb].node.typ.kind)
        node2.intVal = regs[rb].node.intVal
      else: stackTrace(c, tos, pc, "opcCastIntToPtr: regs[rb].kind: " & $regs[rb].kind)
      regs[ra].node = node2
    of opcAsgnComplex:
      asgnComplex(regs[ra], regs[instr.regB])
    of opcFastAsgnComplex:
      fastAsgnComplex(regs[ra], regs[instr.regB])
    of opcAsgnRef:
      asgnRef(regs[ra], regs[instr.regB])
    of opcNodeToReg:
      let ra = instr.regA
      let rb = instr.regB
      # opcLdDeref might already have loaded it into a register. XXX Let's hope
      # this is still correct this way:
      if regs[rb].kind != rkNode:
        regs[ra] = regs[rb]
      else:
        assert regs[rb].kind == rkNode
        let nb = regs[rb].node
        if nb == nil:
          stackTrace(c, tos, pc, errNilAccess)
        else:
          case nb.kind
          of nkCharLit..nkUInt64Lit:
            ensureKind(rkInt)
            regs[ra].intVal = nb.intVal
          of nkFloatLit..nkFloat64Lit:
            ensureKind(rkFloat)
            regs[ra].floatVal = nb.floatVal
          else:
            ensureKind(rkNode)
            regs[ra].node = nb
    of opcSlice:
      # A bodge, but this takes in `toOpenArray(rb, rc, rc)` and emits
      # nkTupleConstr(x, y, z) into the `regs[ra]`. These can later be used for calculating the slice we have taken.
      decodeBC(rkNode)
      let
        collection = regs[ra].node
        leftInd = regs[rb].intVal
        rightInd = regs[rc].intVal

      proc rangeCheck(left, right: BiggestInt, safeLen: BiggestInt) =
        if left < 0:
          stackTrace(c, tos, pc, formatErrorIndexBound(left, safeLen))

        if right > safeLen:
          stackTrace(c, tos, pc, formatErrorIndexBound(right, safeLen))

      case collection.kind
      of nkTupleConstr: # slice of a slice
        let safeLen = collection[2].intVal - collection[1].intVal
        rangeCheck(leftInd, rightInd, safeLen)
        let
          leftInd = leftInd + collection[1].intVal # Slice is from the start of the old
          rightInd = rightInd + collection[1].intVal

        regs[ra].node = newTree(
          nkTupleConstr,
          collection[0],
          newIntNode(nkIntLit, BiggestInt leftInd),
          newIntNode(nkIntLit, BiggestInt rightInd)
        )

      else:
        let safeLen = safeArrLen(collection) - 1
        rangeCheck(leftInd, rightInd, safeLen)
        regs[ra].node = newTree(
          nkTupleConstr,
          collection,
          newIntNode(nkIntLit, BiggestInt leftInd),
          newIntNode(nkIntLit, BiggestInt rightInd)
        )


    of opcLdArr:
      # a = b[c]
      decodeBC(rkNode)
      if regs[rc].intVal > high(int):
        stackTrace(c, tos, pc, formatErrorIndexBound(regs[rc].intVal, high(int)))
      let idx = regs[rc].intVal.int
      let src = regs[rb].node
      case src.kind
      of nkTupleConstr: # refer to `of opcSlice`
        let
          left = src[1].intVal
          right = src[2].intVal
          realIndex = left + idx
        if idx in 0..(right - left):
          case src[0].kind
          of nkStrKinds:
            regs[ra].node =  newIntNode(nkCharLit, ord src[0].strVal[int realIndex])
          of nkBracket:
            regs[ra].node = src[0][int realIndex]
          else:
            stackTrace(c, tos, pc, "opcLdArr internal error")
        else:
          stackTrace(c, tos, pc, formatErrorIndexBound(idx, int right))

      of nkStrLit..nkTripleStrLit:
        if idx <% src.strVal.len:
          regs[ra].node = newNodeI(nkCharLit, c.debug[pc])
          regs[ra].node.intVal = src.strVal[idx].ord
        else:
          stackTrace(c, tos, pc, formatErrorIndexBound(idx, src.strVal.len-1))
      elif src.kind notin {nkEmpty..nkFloat128Lit} and idx <% src.len:
        regs[ra].node = src[idx]
      else:
        stackTrace(c, tos, pc, formatErrorIndexBound(idx, src.safeLen-1))
    of opcLdArrAddr:
      # a = addr(b[c])
      decodeBC(rkNodeAddr)
      if regs[rc].intVal > high(int):
        stackTrace(c, tos, pc, formatErrorIndexBound(regs[rc].intVal, high(int)))
      let idx = regs[rc].intVal.int
      let src = if regs[rb].kind == rkNode: regs[rb].node else: regs[rb].nodeAddr[]
      case src.kind
      of nkTupleConstr:
        let
          left = src[1].intVal
          right = src[2].intVal
          realIndex = left + idx
        if idx in 0..(right - left): # Refer to `opcSlice`
          case src[0].kind
          of nkStrKinds:
            regs[ra] = takeCharAddress(c, src[0], realIndex, pc)
          of nkBracket:
            takeAddress regs[ra], src.sons[0].sons[realIndex]
          else:
            stackTrace(c, tos, pc, "opcLdArrAddr internal error")
        else:
          stackTrace(c, tos, pc, formatErrorIndexBound(idx, int right))
      else:
        if src.kind notin {nkEmpty..nkTripleStrLit} and idx <% src.len:
          takeAddress regs[ra], src.sons[idx]
        elif src.kind in nkStrKinds and idx <% src.strVal.len:
          regs[ra] = takeCharAddress(c, src, idx, pc)
        else:
          stackTrace(c, tos, pc, formatErrorIndexBound(idx, src.safeLen-1))
    of opcLdStrIdx:
      decodeBC(rkInt)
      let idx = regs[rc].intVal.int
      let s {.cursor.} = regs[rb].node.strVal
      if idx <% s.len:
        regs[ra].intVal = s[idx].ord
      else:
        stackTrace(c, tos, pc, formatErrorIndexBound(idx, s.len-1))
    of opcLdStrIdxAddr:
      # a = addr(b[c]); similar to opcLdArrAddr
      decodeBC(rkNode)
      if regs[rc].intVal > high(int):
        stackTrace(c, tos, pc, formatErrorIndexBound(regs[rc].intVal, high(int)))
      let idx = regs[rc].intVal.int
      let s = regs[rb].node.strVal.addr # or `byaddr`
      if idx <% s[].len:
        regs[ra] = takeCharAddress(c, regs[rb].node, idx, pc)
      else:
        stackTrace(c, tos, pc, formatErrorIndexBound(idx, s[].len-1))
    of opcWrArr:
      # a[b] = c
      decodeBC(rkNode)
      let idx = regs[rb].intVal.int
      assert regs[ra].kind == rkNode
      let arr = regs[ra].node
      case arr.kind
      of nkTupleConstr: # refer to `opcSlice`
        let
          src = arr[0]
          left = arr[1].intVal
          right = arr[2].intVal
          realIndex = left + idx
        if idx in 0..(right - left):
          case src.kind
          of nkStrKinds:
            src.strVal[int(realIndex)] = char(regs[rc].intVal)
          of nkBracket:
            if regs[rc].kind == rkInt:
              src[int(realIndex)] = newIntNode(nkIntLit, regs[rc].intVal)
            else:
              assert regs[rc].kind == rkNode
              src[int(realIndex)] = regs[rc].node
          else:
            stackTrace(c, tos, pc, "opcWrArr internal error")
        else:
          stackTrace(c, tos, pc, formatErrorIndexBound(idx, int right))
      of {nkStrLit..nkTripleStrLit}:
        if idx <% arr.strVal.len:
          arr.strVal[idx] = chr(regs[rc].intVal)
        else:
          stackTrace(c, tos, pc, formatErrorIndexBound(idx, arr.strVal.len-1))
      elif idx <% arr.len:
        writeField(arr[idx], regs[rc])
      else:
        stackTrace(c, tos, pc, formatErrorIndexBound(idx, arr.safeLen-1))
    of opcLdObj:
      # a = b.c
      decodeBC(rkNode)
      if rb >= regs.len or regs[rb].kind == rkNone or 
        (regs[rb].kind == rkNode and regs[rb].node == nil) or
        (regs[rb].kind == rkNodeAddr and regs[rb].nodeAddr[] == nil): 
        stackTrace(c, tos, pc, errNilAccess)
      else:
        let src = if regs[rb].kind == rkNode: regs[rb].node else: regs[rb].nodeAddr[]
        case src.kind
        of nkEmpty..nkNilLit:
          # for nkPtrLit, this could be supported in the future, use something like:
          # derefPtrToReg(src.intVal + offsetof(src.typ, rc), typ_field, regs[ra], isAssign = false)
          # where we compute the offset in bytes for field rc
          stackTrace(c, tos, pc, errNilAccess & " " & $("kind", src.kind, "typ", typeToString(src.typ), "rc", rc))
        of nkObjConstr:
          let n = src[rc + 1].skipColon
          regs[ra].node = n
        of nkTupleConstr:
          let n = if src.typ != nil and tfTriggersCompileTime in src.typ.flags:
              src[rc]
            else:
              src[rc].skipColon
          regs[ra].node = n
        else:
          let n = src[rc]
          regs[ra].node = n
    of opcLdObjAddr:
      # a = addr(b.c)
      decodeBC(rkNodeAddr)
      let src = if regs[rb].kind == rkNode: regs[rb].node else: regs[rb].nodeAddr[]
      case src.kind
      of nkEmpty..nkNilLit:
        stackTrace(c, tos, pc, errNilAccess)
      of nkObjConstr:
        let n = src.sons[rc + 1]
        if n.kind == nkExprColonExpr:
          takeAddress regs[ra], n.sons[1]
        else:
          takeAddress regs[ra], src.sons[rc + 1]
      else:
        takeAddress regs[ra], src.sons[rc]
    of opcWrObj:
      # a.b = c
      decodeBC(rkNode)
      assert regs[ra].node != nil
      let shiftedRb = rb + ord(regs[ra].node.kind == nkObjConstr)
      let dest = regs[ra].node
      if dest.kind == nkNilLit:
        stackTrace(c, tos, pc, errNilAccess)
      elif dest[shiftedRb].kind == nkExprColonExpr:
        writeField(dest[shiftedRb][1], regs[rc])
        dest[shiftedRb][1].flags.incl nfSkipFieldChecking
      else:
        writeField(dest[shiftedRb], regs[rc])
        dest[shiftedRb].flags.incl nfSkipFieldChecking
    of opcWrStrIdx:
      decodeBC(rkNode)
      let idx = regs[rb].intVal.int
      if idx <% regs[ra].node.strVal.len:
        regs[ra].node.strVal[idx] = chr(regs[rc].intVal)
      else:
        stackTrace(c, tos, pc, formatErrorIndexBound(idx, regs[ra].node.strVal.len-1))
    of opcAddrReg:
      decodeB(rkRegisterAddr)
      regs[ra].regAddr = addr(regs[rb])
    of opcAddrNode:
      decodeB(rkNodeAddr)
      case regs[rb].kind
      of rkNode:
        takeAddress regs[ra], regs[rb].node
      of rkNodeAddr: # bug #14339
        regs[ra].nodeAddr = regs[rb].nodeAddr
      else:
        stackTrace(c, tos, pc, "limited VM support for 'addr', got kind: " & $regs[rb].kind)
    of opcLdDeref:
      # a = b[]
      let ra = instr.regA
      let rb = instr.regB
      case regs[rb].kind
      of rkNodeAddr:
        ensureKind(rkNode)
        regs[ra].node = regs[rb].nodeAddr[]
      of rkRegisterAddr:
        ensureKind(regs[rb].regAddr.kind)
        regs[ra] = regs[rb].regAddr[]
      of rkNode:
        if regs[rb].node.kind == nkRefTy:
          regs[ra].node = regs[rb].node[0]
        elif not maybeHandlePtr(regs[rb].node, regs[ra], false):
          ## e.g.: typ.kind = tyObject
          ensureKind(rkNode)
          regs[ra].node = regs[rb].node
      else:
        stackTrace(c, tos, pc, errNilAccess & " kind: " & $regs[rb].kind)
    of opcWrDeref:
      # a[] = c; b unused
      let ra = instr.regA
      let rc = instr.regC
      case regs[ra].kind
      of rkNodeAddr:
        let n = regs[rc].regToNode
        # `var object` parameters are sent as rkNodeAddr. When they are mutated
        # vmgen generates opcWrDeref, which means that we must dereference
        # twice.
        # TODO: This should likely be handled differently in vmgen.
        let nAddr = regs[ra].nodeAddr
        if nAddr[] == nil: stackTrace(c, tos, pc, "opcWrDeref internal error") # refs bug #16613
        if (nfIsRef notin nAddr[].flags and nfIsRef notin n.flags): nAddr[][] = n[]
        else: nAddr[] = n
      of rkRegisterAddr: regs[ra].regAddr[] = regs[rc]
      of rkNode:
         # xxx: also check for nkRefTy as in opcLdDeref?
        if not maybeHandlePtr(regs[ra].node, regs[rc], true):
          regs[ra].node[] = regs[rc].regToNode[]
          regs[ra].node.flags.incl nfIsRef
      else: stackTrace(c, tos, pc, errNilAccess)
    of opcAddInt:
      decodeBC(rkInt)
      let
        bVal = regs[rb].intVal
        cVal = regs[rc].intVal
        sum = bVal +% cVal
      if (sum xor bVal) >= 0 or (sum xor cVal) >= 0:
        regs[ra].intVal = sum
      else:
        stackTrace(c, tos, pc, errOverOrUnderflow)
    of opcAddImmInt:
      decodeBImm(rkInt)
      #message(c.config, c.debug[pc], warnUser, "came here")
      #debug regs[rb].node
      let
        bVal = regs[rb].intVal
        cVal = imm
        sum = bVal +% cVal
      if (sum xor bVal) >= 0 or (sum xor cVal) >= 0:
        regs[ra].intVal = sum
      else:
        stackTrace(c, tos, pc, errOverOrUnderflow)
    of opcSubInt:
      decodeBC(rkInt)
      let
        bVal = regs[rb].intVal
        cVal = regs[rc].intVal
        diff = bVal -% cVal
      if (diff xor bVal) >= 0 or (diff xor not cVal) >= 0:
        regs[ra].intVal = diff
      else:
        stackTrace(c, tos, pc, errOverOrUnderflow)
    of opcSubImmInt:
      decodeBImm(rkInt)
      let
        bVal = regs[rb].intVal
        cVal = imm
        diff = bVal -% cVal
      if (diff xor bVal) >= 0 or (diff xor not cVal) >= 0:
        regs[ra].intVal = diff
      else:
        stackTrace(c, tos, pc, errOverOrUnderflow)
    of opcLenSeq:
      decodeBImm(rkInt)
      #assert regs[rb].kind == nkBracket
      let
        high = (imm and 1) # discard flags
        node = regs[rb].node
      if (imm and nimNodeFlag) != 0:
        # used by mNLen (NimNode.len)
        regs[ra].intVal = regs[rb].node.safeLen - high
      else:
        case node.kind
        of nkTupleConstr: # refer to `of opcSlice`
          regs[ra].intVal = node[2].intVal - node[1].intVal + 1 - high
        else:
          # safeArrLen also return string node len
          # used when string is passed as openArray in VM
          regs[ra].intVal = node.safeArrLen - high

    of opcLenStr:
      decodeBImm(rkInt)
      assert regs[rb].kind == rkNode
      regs[ra].intVal = regs[rb].node.strVal.len - imm
    of opcLenCstring:
      decodeBImm(rkInt)
      assert regs[rb].kind == rkNode
      if regs[rb].node.kind == nkNilLit:
        regs[ra].intVal = -imm
      else:
        regs[ra].intVal = regs[rb].node.strVal.cstring.len - imm
    of opcIncl:
      decodeB(rkNode)
      let b = regs[rb].regToNode
      if not inSet(regs[ra].node, b):
        regs[ra].node.add copyTree(b)
    of opcInclRange:
      decodeBC(rkNode)
      var r = newNode(nkRange)
      r.add regs[rb].regToNode
      r.add regs[rc].regToNode
      regs[ra].node.add r.copyTree
    of opcExcl:
      decodeB(rkNode)
      var b = newNodeIT(nkCurly, regs[ra].node.info, regs[ra].node.typ)
      b.add regs[rb].regToNode
      var r = diffSets(c.config, regs[ra].node, b)
      discardSons(regs[ra].node)
      for i in 0..<r.len: regs[ra].node.add r[i]
    of opcCard:
      decodeB(rkInt)
      regs[ra].intVal = nimsets.cardSet(c.config, regs[rb].node)
    of opcMulInt:
      decodeBC(rkInt)
      let
        bVal = regs[rb].intVal
        cVal = regs[rc].intVal
        product = bVal *% cVal
        floatProd = toBiggestFloat(bVal) * toBiggestFloat(cVal)
        resAsFloat = toBiggestFloat(product)
      if resAsFloat == floatProd:
        regs[ra].intVal = product
      elif 32.0 * abs(resAsFloat - floatProd) <= abs(floatProd):
        regs[ra].intVal = product
      else:
        stackTrace(c, tos, pc, errOverOrUnderflow)
    of opcDivInt:
      decodeBC(rkInt)
      if regs[rc].intVal == 0: stackTrace(c, tos, pc, errConstantDivisionByZero)
      else: regs[ra].intVal = regs[rb].intVal div regs[rc].intVal
    of opcModInt:
      decodeBC(rkInt)
      if regs[rc].intVal == 0: stackTrace(c, tos, pc, errConstantDivisionByZero)
      else: regs[ra].intVal = regs[rb].intVal mod regs[rc].intVal
    of opcAddFloat:
      decodeBC(rkFloat)
      regs[ra].floatVal = regs[rb].floatVal + regs[rc].floatVal
    of opcSubFloat:
      decodeBC(rkFloat)
      regs[ra].floatVal = regs[rb].floatVal - regs[rc].floatVal
    of opcMulFloat:
      decodeBC(rkFloat)
      regs[ra].floatVal = regs[rb].floatVal * regs[rc].floatVal
    of opcDivFloat:
      decodeBC(rkFloat)
      regs[ra].floatVal = regs[rb].floatVal / regs[rc].floatVal
    of opcShrInt:
      decodeBC(rkInt)
      let b = cast[uint64](regs[rb].intVal)
      let c = cast[uint64](regs[rc].intVal)
      let a = cast[int64](b shr c)
      regs[ra].intVal = a
    of opcShlInt:
      decodeBC(rkInt)
      regs[ra].intVal = regs[rb].intVal shl regs[rc].intVal
    of opcAshrInt:
      decodeBC(rkInt)
      regs[ra].intVal = ashr(regs[rb].intVal, regs[rc].intVal)
    of opcBitandInt:
      decodeBC(rkInt)
      regs[ra].intVal = regs[rb].intVal and regs[rc].intVal
    of opcBitorInt:
      decodeBC(rkInt)
      regs[ra].intVal = regs[rb].intVal or regs[rc].intVal
    of opcBitxorInt:
      decodeBC(rkInt)
      regs[ra].intVal = regs[rb].intVal xor regs[rc].intVal
    of opcAddu:
      decodeBC(rkInt)
      regs[ra].intVal = regs[rb].intVal +% regs[rc].intVal
    of opcSubu:
      decodeBC(rkInt)
      regs[ra].intVal = regs[rb].intVal -% regs[rc].intVal
    of opcMulu:
      decodeBC(rkInt)
      regs[ra].intVal = regs[rb].intVal *% regs[rc].intVal
    of opcDivu:
      decodeBC(rkInt)
      regs[ra].intVal = regs[rb].intVal /% regs[rc].intVal
    of opcModu:
      decodeBC(rkInt)
      regs[ra].intVal = regs[rb].intVal %% regs[rc].intVal
    of opcEqInt:
      decodeBC(rkInt)
      regs[ra].intVal = ord(regs[rb].intVal == regs[rc].intVal)
    of opcLeInt:
      decodeBC(rkInt)
      regs[ra].intVal = ord(regs[rb].intVal <= regs[rc].intVal)
    of opcLtInt:
      decodeBC(rkInt)
      regs[ra].intVal = ord(regs[rb].intVal < regs[rc].intVal)
    of opcEqFloat:
      decodeBC(rkInt)
      regs[ra].intVal = ord(regs[rb].floatVal == regs[rc].floatVal)
    of opcLeFloat:
      decodeBC(rkInt)
      regs[ra].intVal = ord(regs[rb].floatVal <= regs[rc].floatVal)
    of opcLtFloat:
      decodeBC(rkInt)
      regs[ra].intVal = ord(regs[rb].floatVal < regs[rc].floatVal)
    of opcLeu:
      decodeBC(rkInt)
      regs[ra].intVal = ord(regs[rb].intVal <=% regs[rc].intVal)
    of opcLtu:
      decodeBC(rkInt)
      regs[ra].intVal = ord(regs[rb].intVal <% regs[rc].intVal)
    of opcEqRef:
      var ret = false
      decodeBC(rkInt)
      template getTyp(n): untyped =
        n.typ.skipTypes(abstractInst)
      template skipRegisterAddr(n: TFullReg): TFullReg =
        var tmp = n
        while tmp.kind == rkRegisterAddr:
          tmp = tmp.regAddr[]
        tmp

      proc ptrEquality(n1: ptr PNode, n2: PNode): bool =
        ## true if n2.intVal represents a ptr equal to n1
        let p1 = cast[int](n1)
        case n2.kind
        of nkNilLit: return p1 == 0
        of nkIntLit: # TODO: nkPtrLit
          # for example, n1.kind == nkFloatLit (ptr float)
          # the problem is that n1.typ == nil so we can't compare n1.typ and n2.typ
          # this is the best we can do (pending making sure we assign a valid n1.typ to nodeAddr's)
          let t2 = n2.getTyp
          return t2.kind in PtrLikeKinds and n2.intVal == p1
        else: return false

      let rbReg = skipRegisterAddr(regs[rb])
      let rcReg = skipRegisterAddr(regs[rc])

      if rbReg.kind == rkNodeAddr:
        if rcReg.kind == rkNodeAddr:
          ret = rbReg.nodeAddr == rcReg.nodeAddr
        else:
          ret = ptrEquality(rbReg.nodeAddr, rcReg.node)
      elif rcReg.kind == rkNodeAddr:
        ret = ptrEquality(rcReg.nodeAddr, rbReg.node)
      else:
        let nb = rbReg.node
        let nc = rcReg.node
        if nb.kind != nc.kind: discard
        elif (nb == nc) or (nb.kind == nkNilLit): ret = true # intentional
        elif nb.kind in {nkSym, nkTupleConstr, nkClosure} and nb.typ != nil and nb.typ.kind == tyProc and sameConstant(nb, nc):
          ret = true
          # this also takes care of procvar's, represented as nkTupleConstr, e.g. (nil, nil)
        elif nb.kind == nkIntLit and nc.kind == nkIntLit and nb.intVal == nc.intVal: # TODO: nkPtrLit
          let tb = nb.getTyp
          let tc = nc.getTyp
          ret = tb.kind in PtrLikeKinds and tc.kind == tb.kind
      regs[ra].intVal = ord(ret)
    of opcEqNimNode:
      decodeBC(rkInt)
      regs[ra].intVal =
        ord(exprStructuralEquivalent(regs[rb].node, regs[rc].node,
                                     strictSymEquality=true))
    of opcSameNodeType:
      decodeBC(rkInt)
      regs[ra].intVal = ord(regs[rb].node.typ.sameTypeOrNil(regs[rc].node.typ, {ExactTypeDescValues, ExactGenericParams}))
      # The types should exactly match which is why we pass `{ExactTypeDescValues..ExactGcSafety}`.
    of opcXor:
      decodeBC(rkInt)
      regs[ra].intVal = ord(regs[rb].intVal != regs[rc].intVal)
    of opcNot:
      decodeB(rkInt)
      assert regs[rb].kind == rkInt
      regs[ra].intVal = 1 - regs[rb].intVal
    of opcUnaryMinusInt:
      decodeB(rkInt)
      assert regs[rb].kind == rkInt
      let val = regs[rb].intVal
      if val != int64.low:
        regs[ra].intVal = -val
      else:
        stackTrace(c, tos, pc, errOverOrUnderflow)
    of opcUnaryMinusFloat:
      decodeB(rkFloat)
      assert regs[rb].kind == rkFloat
      regs[ra].floatVal = -regs[rb].floatVal
    of opcBitnotInt:
      decodeB(rkInt)
      assert regs[rb].kind == rkInt
      regs[ra].intVal = not regs[rb].intVal
    of opcEqStr:
      decodeBC(rkInt)
      regs[ra].intVal = ord(regs[rb].node.strVal == regs[rc].node.strVal)
    of opcEqCString:
      decodeBC(rkInt)
      let bNil = regs[rb].node.kind == nkNilLit
      let cNil = regs[rc].node.kind == nkNilLit
      regs[ra].intVal = ord((bNil and cNil) or
        (not bNil and not cNil and regs[rb].node.strVal == regs[rc].node.strVal))
    of opcLeStr:
      decodeBC(rkInt)
      regs[ra].intVal = ord(regs[rb].node.strVal <= regs[rc].node.strVal)
    of opcLtStr:
      decodeBC(rkInt)
      regs[ra].intVal = ord(regs[rb].node.strVal < regs[rc].node.strVal)
    of opcLeSet:
      decodeBC(rkInt)
      regs[ra].intVal = ord(containsSets(c.config, regs[rb].node, regs[rc].node))
    of opcEqSet:
      decodeBC(rkInt)
      regs[ra].intVal = ord(equalSets(c.config, regs[rb].node, regs[rc].node))
    of opcLtSet:
      decodeBC(rkInt)
      let a = regs[rb].node
      let b = regs[rc].node
      regs[ra].intVal = ord(containsSets(c.config, a, b) and not equalSets(c.config, a, b))
    of opcMulSet:
      decodeBC(rkNode)
      createSet(regs[ra])
      move(regs[ra].node.sons,
            nimsets.intersectSets(c.config, regs[rb].node, regs[rc].node).sons)
    of opcPlusSet:
      decodeBC(rkNode)
      createSet(regs[ra])
      move(regs[ra].node.sons,
           nimsets.unionSets(c.config, regs[rb].node, regs[rc].node).sons)
    of opcMinusSet:
      decodeBC(rkNode)
      createSet(regs[ra])
      move(regs[ra].node.sons,
           nimsets.diffSets(c.config, regs[rb].node, regs[rc].node).sons)
    of opcXorSet:
      decodeBC(rkNode)
      createSet(regs[ra])
      move(regs[ra].node.sons,
           nimsets.symdiffSets(c.config, regs[rb].node, regs[rc].node).sons)
    of opcConcatStr:
      decodeBC(rkNode)
      createStr regs[ra]
      regs[ra].node.strVal = getstr(regs[rb])
      for i in rb+1..rb+rc-1:
        regs[ra].node.strVal.add getstr(regs[i])
    of opcAddStrCh:
      decodeB(rkNode)
      regs[ra].node.strVal.add(regs[rb].intVal.chr)
    of opcAddStrStr:
      decodeB(rkNode)
      regs[ra].node.strVal.add(regs[rb].node.strVal)
    of opcAddSeqElem:
      decodeB(rkNode)
      if regs[ra].node.kind == nkBracket:
        regs[ra].node.add(copyValue(regs[rb].regToNode))
      else:
        stackTrace(c, tos, pc, errNilAccess)
    of opcGetImpl:
      decodeB(rkNode)
      var a = regs[rb].node
      if a.kind == nkVarTy: a = a[0]
      if a.kind == nkSym:
        regs[ra].node = if a.sym.ast.isNil: newNode(nkNilLit)
                        else: copyTree(a.sym.ast)
        regs[ra].node.flags.incl nfIsRef
      else:
        stackTrace(c, tos, pc, "node is not a symbol")
    of opcGetImplTransf:
      decodeB(rkNode)
      let a = regs[rb].node
      if a.kind == nkSym:
        regs[ra].node =
          if a.sym.ast.isNil:
            newNode(nkNilLit)
          else:
            let ast = a.sym.ast.shallowCopy
            for i in 0..<a.sym.ast.len:
              ast[i] = a.sym.ast[i]
            ast[bodyPos] = transformBody(c.graph, c.idgen, a.sym, {useCache, force})
            ast.copyTree()
    of opcSymOwner:
      decodeB(rkNode)
      let a = regs[rb].node
      if a.kind == nkSym:
        regs[ra].node = if a.sym.owner.isNil: newNode(nkNilLit)
                        else: newSymNode(a.sym.skipGenericOwner)
        regs[ra].node.flags.incl nfIsRef
      else:
        stackTrace(c, tos, pc, "node is not a symbol")
    of opcSymIsInstantiationOf:
      decodeBC(rkInt)
      let a = regs[rb].node
      let b = regs[rc].node
      if a.kind == nkSym and a.sym.kind in skProcKinds and
         b.kind == nkSym and b.sym.kind in skProcKinds:
        regs[ra].intVal =
          if sfFromGeneric in a.sym.flags and a.sym.instantiatedFrom == b.sym: 1
          else: 0
      else:
        stackTrace(c, tos, pc, "node is not a proc symbol")
    of opcEcho:
      let rb = instr.regB
      template fn(s) = msgWriteln(c.config, s, {msgStdout, msgNoUnitSep})
      if rb == 1: fn(regs[ra].node.strVal)
      else:
        var outp = ""
        for i in ra..ra+rb-1:
          #if regs[i].kind != rkNode: debug regs[i]
          outp.add(regs[i].node.strVal)
        fn(outp)
    of opcContainsSet:
      decodeBC(rkInt)
      regs[ra].intVal = ord(inSet(regs[rb].node, regs[rc].regToNode))
    of opcParseFloat:
      decodeBC(rkInt)
      var rcAddr = addr(regs[rc])
      if rcAddr.kind == rkRegisterAddr: rcAddr = rcAddr.regAddr
      elif regs[rc].kind != rkFloat:
        regs[rc] = TFullReg(kind: rkFloat)

      let coll = regs[rb].node

      case coll.kind
      of nkTupleConstr:
        let
          data = coll[0]
          left = coll[1].intVal
          right = coll[2].intVal
        case data.kind
        of nkStrKinds:
          regs[ra].intVal = parseBiggestFloat(data.strVal.toOpenArray(int left, int right), rcAddr.floatVal)
        of nkBracket:
          var s = newStringOfCap(right - left + 1)
          for i in left..right:
            s.add char data[int i].intVal
          regs[ra].intVal = parseBiggestFloat(s, rcAddr.floatVal)
        else:
          internalError(c.config, c.debug[pc], "opcParseFloat: Incorrectly created openarray")
      else:
        regs[ra].intVal = parseBiggestFloat(regs[rb].node.strVal, rcAddr.floatVal)

    of opcRangeChck:
      let rb = instr.regB
      let rc = instr.regC
      if not (leValueConv(regs[rb].regToNode, regs[ra].regToNode) and
              leValueConv(regs[ra].regToNode, regs[rc].regToNode)):
        stackTrace(c, tos, pc,
          errIllegalConvFromXtoY % [
             $regs[ra].regToNode, "[" & $regs[rb].regToNode & ".." & $regs[rc].regToNode & "]"])
    of opcIndCall, opcIndCallAsgn:
      # dest = call regStart, n; where regStart = fn, arg1, ...
      let rb = instr.regB
      let rc = instr.regC
      let bb = regs[rb].node
      if bb.kind == nkNilLit:
        stackTrace(c, tos, pc, "attempt to call nil closure")
      let isClosure = bb.kind == nkTupleConstr
      if isClosure and bb[0].kind == nkNilLit:
        stackTrace(c, tos, pc, "attempt to call nil closure")
      let prc = if not isClosure: bb.sym else: bb[0].sym
      if prc.offset < -1:
        # it's a callback:
        c.callbacks[-prc.offset-2](
          VmArgs(ra: ra, rb: rb, rc: rc, slots: cast[ptr UncheckedArray[TFullReg]](addr regs[0]),
                 currentException: c.currentExceptionA,
                 currentLineInfo: c.debug[pc])
                 )
      elif importcCond(c, prc):
        if compiletimeFFI notin c.config.features:
          globalError(c.config, c.debug[pc], "VM not allowed to do FFI, see `compiletimeFFI`")
        # we pass 'tos.slots' instead of 'regs' so that the compiler can keep
        # 'regs' in a register:
        when hasFFI:
          if prc.position - 1 < 0:
            globalError(c.config, c.debug[pc],
              "VM call invalid: prc.position: " & $prc.position)
          let prcValue = c.globals[prc.position-1]
          if prcValue.kind == nkEmpty:
            globalError(c.config, c.debug[pc], "cannot run " & prc.name.s)
          var slots2: TNodeSeq = newSeq[PNode](tos.slots.len)
          for i in 0..<tos.slots.len:
            slots2[i] = regToNode(tos.slots[i])
          let newValue = callForeignFunction(c.config, prcValue, prc.typ, slots2,
                                             rb+1, rc-1, c.debug[pc])
          if newValue.kind != nkEmpty:
            assert instr.opcode == opcIndCallAsgn
            putIntoReg(regs[ra], newValue)
        else:
          globalError(c.config, c.debug[pc], "VM not built with FFI support")
      elif prc.kind != skTemplate:
        let newPc = compile(c, prc)
        # tricky: a recursion is also a jump back, so we use the same
        # logic as for loops:
        if newPc < pc: handleJmpBack()
        #echo "new pc ", newPc, " calling: ", prc.name.s
        var newFrame = PStackFrame(prc: prc, comesFrom: pc, next: tos)
        newSeq(newFrame.slots, prc.offset+ord(isClosure))
        if not isEmptyType(prc.typ.returnType):
          putIntoReg(newFrame.slots[0], getNullValue(c, prc.typ.returnType, prc.info, c.config))
        for i in 1..rc-1:
          newFrame.slots[i] = regs[rb+i]
        if isClosure:
          newFrame.slots[rc] = TFullReg(kind: rkNode, node: regs[rb].node[1])
        if c.callDepth <= 0:
          if allowInfiniteRecursion in c.features:
            c.callDepth = c.config.maxCallDepthVM
          else:
            msgWriteln(c.config, "stack trace: (most recent call last)", {msgNoUnitSep})
            stackTraceAux(c, tos, pc)
            globalError(c.config, c.debug[pc], errCallDepthExceeded % $c.config.maxCallDepthVM)
        dec(c.callDepth)
        tos = newFrame
        updateRegsAlias
        # -1 for the following 'inc pc'
        pc = newPc-1
      else:
        # for 'getAst' support we need to support template expansion here:
        let genSymOwner = if tos.next != nil and tos.next.prc != nil:
                            tos.next.prc
                          else:
                            c.module
        var macroCall = newNodeI(nkCall, c.debug[pc])
        macroCall.add(newSymNode(prc))
        for i in 1..rc-1:
          let node = regs[rb+i].regToNode
          node.info = c.debug[pc]
          if prc.typ[i].kind notin {tyTyped, tyUntyped}:
            node.annotateType(prc.typ[i], c.config)

          macroCall.add(node)
        var a = evalTemplate(macroCall, prc, genSymOwner, c.config, c.cache, c.templInstCounter, c.idgen)
        if a.kind == nkStmtList and a.len == 1: a = a[0]
        a.recSetFlagIsRef
        ensureKind(rkNode)
        regs[ra].node = a
    of opcTJmp:
      # jump Bx if A != 0
      let rbx = instr.regBx - wordExcess - 1 # -1 for the following 'inc pc'
      if regs[ra].intVal != 0:
        inc pc, rbx
    of opcFJmp:
      # jump Bx if A == 0
      let rbx = instr.regBx - wordExcess - 1 # -1 for the following 'inc pc'
      if regs[ra].intVal == 0:
        inc pc, rbx
    of opcJmp:
      # jump Bx
      let rbx = instr.regBx - wordExcess - 1 # -1 for the following 'inc pc'
      inc pc, rbx
    of opcJmpBack:
      let rbx = instr.regBx - wordExcess - 1 # -1 for the following 'inc pc'
      inc pc, rbx
      handleJmpBack()
    of opcBranch:
      # we know the next instruction is a 'fjmp':
      let branch = c.constants[instr.regBx-wordExcess]
      var cond = false
      for j in 0..<branch.len - 1:
        if overlap(regs[ra].regToNode, branch[j]):
          cond = true
          break
      assert c.code[pc+1].opcode == opcFJmp
      inc pc
      # we skip this instruction so that the final 'inc(pc)' skips
      # the following jump
      if not cond:
        let instr2 = c.code[pc]
        let rbx = instr2.regBx - wordExcess - 1 # -1 for the following 'inc pc'
        inc pc, rbx
    of opcTry:
      let rbx = instr.regBx - wordExcess
      tos.pushSafePoint(pc + rbx)
      assert c.code[pc+rbx].opcode in {opcExcept, opcFinally}
    of opcExcept:
      # This opcode is never executed, it only holds information for the
      # exception handling routines.
      raiseAssert "unreachable"
    of opcFinally:
      # Pop the last safepoint introduced by a opcTry. This opcode is only
      # executed _iff_ no exception was raised in the body of the `try`
      # statement hence the need to pop the safepoint here.
      doAssert(savedPC < 0)
      tos.popSafePoint()
    of opcFinallyEnd:
      # The control flow may not resume at the next instruction since we may be
      # raising an exception or performing a cleanup.
      if savedPC >= 0:
        pc = savedPC - 1
        savedPC = -1
        if tos != savedFrame:
          tos = savedFrame
          updateRegsAlias
    of opcRaise:
      let raised =
        # Empty `raise` statement - reraise current exception
        if regs[ra].kind == rkNone:
          c.currentExceptionA
        else:
          regs[ra].node
      c.currentExceptionA = raised
      # Set the `name` field of the exception
      var exceptionNameNode = newStrNode(nkStrLit, c.currentExceptionA.typ.sym.name.s)
      if c.currentExceptionA[2].kind == nkExprColonExpr:
        exceptionNameNode.typ() = c.currentExceptionA[2][1].typ
        c.currentExceptionA[2][1] = exceptionNameNode
      else:
        exceptionNameNode.typ() = c.currentExceptionA[2].typ
        c.currentExceptionA[2] = exceptionNameNode
      c.exceptionInstr = pc

      var frame = tos
      var jumpTo = findExceptionHandler(c, frame, raised)
      while jumpTo.why == ExceptionGotoUnhandled and not frame.next.isNil:
        frame = frame.next
        jumpTo = findExceptionHandler(c, frame, raised)

      case jumpTo.why
      of ExceptionGotoHandler:
        # Jump to the handler, do nothing when the `finally` block ends.
        savedPC = -1
        pc = jumpTo.where - 1
        if tos != frame:
          tos = frame
          updateRegsAlias
      of ExceptionGotoFinally:
        # Jump to the `finally` block first then re-jump here to continue the
        # traversal of the exception chain
        savedPC = pc
        savedFrame = tos
        pc = jumpTo.where - 1
        if tos != frame:
          tos = frame
          updateRegsAlias
      of ExceptionGotoUnhandled:
        # Nobody handled this exception, error out.
        bailOut(c, tos)
    of opcNew:
      ensureKind(rkNode)
      let typ = c.types[instr.regBx - wordExcess]
      regs[ra].node = getNullValue(c, typ, c.debug[pc], c.config)
      regs[ra].node.flags.incl nfIsRef
    of opcNewSeq:
      let typ = c.types[instr.regBx - wordExcess]
      inc pc
      ensureKind(rkNode)
      let instr2 = c.code[pc]
      let count = regs[instr2.regA].intVal.int
      regs[ra].node = newNodeI(nkBracket, c.debug[pc])
      regs[ra].node.typ() = typ
      newSeq(regs[ra].node.sons, count)
      for i in 0..<count:
        regs[ra].node[i] = getNullValue(c, typ.elementType, c.debug[pc], c.config)
    of opcNewStr:
      decodeB(rkNode)
      regs[ra].node = newNodeI(nkStrLit, c.debug[pc])
      regs[ra].node.strVal = newString(regs[rb].intVal.int)
    of opcLdImmInt:
      # dest = immediate value
      decodeBx(rkInt)
      regs[ra].intVal = rbx
    of opcLdNull:
      ensureKind(rkNode)
      let typ = c.types[instr.regBx - wordExcess]
      regs[ra].node = getNullValue(c, typ, c.debug[pc], c.config)
      # opcLdNull really is the gist of the VM's problems: should it load
      # a fresh null to  regs[ra].node  or to regs[ra].node[]? This really
      # depends on whether regs[ra] represents the variable itself or whether
      # it holds the indirection! Due to the way registers are re-used we cannot
      # say for sure here! --> The codegen has to deal with it
      # via 'genAsgnPatch'.
    of opcLdNullReg:
      let typ = c.types[instr.regBx - wordExcess]
      if typ.skipTypes(abstractInst+{tyRange}-{tyTypeDesc}).kind in {
          tyFloat..tyFloat128}:
        ensureKind(rkFloat)
        regs[ra].floatVal = 0.0
      else:
        ensureKind(rkInt)
        regs[ra].intVal = 0
    of opcLdConst:
      let rb = instr.regBx - wordExcess
      let cnst = c.constants[rb]
      if fitsRegister(cnst.typ):
        reset(regs[ra])
        putIntoReg(regs[ra], cnst)
      else:
        ensureKind(rkNode)
        regs[ra].node = cnst
    of opcAsgnConst:
      let rb = instr.regBx - wordExcess
      let cnst = c.constants[rb]
      if fitsRegister(cnst.typ):
        putIntoReg(regs[ra], cnst)
      else:
        ensureKind(rkNode)
        regs[ra].node = cnst.copyTree
    of opcLdGlobal:
      let rb = instr.regBx - wordExcess - 1
      ensureKind(rkNode)
      regs[ra].node = c.globals[rb]
    of opcLdGlobalDerefFFI:
      let rb = instr.regBx - wordExcess - 1
      let node = c.globals[rb]
      let typ = node.typ
      doAssert node.kind == nkIntLit, $(node.kind)
      if typ.kind == tyPtr:
        ensureKind(rkNode)
        # use nkPtrLit once this is added
        let node2 = newNodeIT(nkIntLit, c.debug[pc], typ)
        node2.intVal = cast[ptr int](node.intVal)[]
        node2.flags.incl nfIsPtr
        regs[ra].node = node2
      elif not derefPtrToReg(node.intVal, typ, regs[ra], isAssign = false):
        stackTrace(c, tos, pc, "opcLdDeref unsupported type: " & $(typeToString(typ), typ.elementType.kind))
    of opcLdGlobalAddrDerefFFI:
      let rb = instr.regBx - wordExcess - 1
      let node = c.globals[rb]
      let typ = node.typ
      var node2 = newNodeIT(nkIntLit, node.info, typ)
      node2.intVal = node.intVal
      node2.flags.incl nfIsPtr
      ensureKind(rkNode)
      regs[ra].node = node2
    of opcLdGlobalAddr:
      let rb = instr.regBx - wordExcess - 1
      ensureKind(rkNodeAddr)
      regs[ra].nodeAddr = addr(c.globals[rb])
    of opcRepr:
      decodeB(rkNode)
      createStr regs[ra]
      regs[ra].node.strVal = renderTree(regs[rb].regToNode, {renderNoComments, renderDocComments, renderNonExportedFields})
    of opcQuit:
      if c.mode in {emRepl, emStaticExpr, emStaticStmt}:
        message(c.config, c.debug[pc], hintQuitCalled)
        msgQuit(int8(toInt(getOrdValue(regs[ra].regToNode, onError = toInt128(1)))))
      else:
        return TFullReg(kind: rkNone)
    of opcInvalidField:
      let msg = regs[ra].node.strVal
      let disc = regs[instr.regB].regToNode
      let msg2 = formatFieldDefect(msg, $disc)
      stackTrace(c, tos, pc, msg2)
    of opcSetLenStr:
      decodeB(rkNode)
      #createStrKeepNode regs[ra]
      regs[ra].node.strVal.setLen(regs[rb].intVal.int)
    of opcOf:
      decodeBC(rkInt)
      let typ = c.types[regs[rc].intVal.int]
      regs[ra].intVal = ord(inheritanceDiff(regs[rb].node.typ, typ) <= 0)
    of opcIs:
      decodeBC(rkInt)
      let t1 = regs[rb].node.typ.skipTypes({tyTypeDesc})
      let t2 = c.types[regs[rc].intVal.int]
      # XXX: This should use the standard isOpImpl
      let match = if t2.kind == tyUserTypeClass: true
                  else: sameType(t1, t2)
      regs[ra].intVal = ord(match)
    of opcSetLenSeq:
      decodeB(rkNode)
      let newLen = regs[rb].intVal.int
      if regs[ra].node.isNil: stackTrace(c, tos, pc, errNilAccess)
      else: c.setLenSeq(regs[ra].node, newLen, c.debug[pc])
    of opcNarrowS:
      decodeB(rkInt)
      let min = -(1.BiggestInt shl (rb-1))
      let max = (1.BiggestInt shl (rb-1))-1
      if regs[ra].intVal < min or regs[ra].intVal > max:
        stackTrace(c, tos, pc, "unhandled exception: value out of range")
    of opcNarrowU:
      decodeB(rkInt)
      regs[ra].intVal = regs[ra].intVal and ((1'i64 shl rb)-1)
    of opcSignExtend:
      # like opcNarrowS, but no out of range possible
      decodeB(rkInt)
      let imm = 64 - rb
      regs[ra].intVal = ashr(regs[ra].intVal shl imm, imm)
    of opcIsNil:
      decodeB(rkInt)
      let node = regs[rb].node
      regs[ra].intVal = ord(
        # Note that `nfIsRef` + `nkNilLit` represents an allocated
        # reference with the value `nil`, so `isNil` should be false!
        (node.kind == nkNilLit and nfIsRef notin node.flags) or
        (not node.typ.isNil and node.typ.kind == tyProc and
          node.typ.callConv == ccClosure and node.safeLen > 0 and
          node[0].kind == nkNilLit and node[1].kind == nkNilLit))
    of opcNBindSym:
      # cannot use this simple check
      # if dynamicBindSym notin c.config.features:

      # bindSym with static input
      decodeBx(rkNode)
      regs[ra].node = copyTree(c.constants[rbx])
      regs[ra].node.flags.incl nfIsRef
    of opcNDynBindSym:
      # experimental bindSym
      let
        rb = instr.regB
        rc = instr.regC
        idx = int(regs[rb+rc-1].intVal)
        callback = c.callbacks[idx]
        args = VmArgs(ra: ra, rb: rb, rc: rc, slots: cast[ptr UncheckedArray[TFullReg]](addr regs[0]),
                currentException: c.currentExceptionA,
                currentLineInfo: c.debug[pc])
      callback(args)
      regs[ra].node.flags.incl nfIsRef
    of opcNChild:
      decodeBC(rkNode)
      let idx = regs[rc].intVal.int
      let src = regs[rb].node
      if src.kind in {nkEmpty..nkNilLit}:
        stackTrace(c, tos, pc, "cannot get child of node kind: n" & $src.kind)
      elif idx >=% src.len:
        stackTrace(c, tos, pc, formatErrorIndexBound(idx, src.len-1))
      else:
        regs[ra].node = src[idx]
    of opcNSetChild:
      decodeBC(rkNode)
      let idx = regs[rb].intVal.int
      var dest = regs[ra].node
      if nfSem in dest.flags and allowSemcheckedAstModification notin c.config.legacyFeatures:
        stackTrace(c, tos, pc, "typechecked nodes may not be modified")
      elif dest.kind in {nkEmpty..nkNilLit}:
        stackTrace(c, tos, pc, "cannot set child of node kind: n" & $dest.kind)
      elif idx >=% dest.len:
        stackTrace(c, tos, pc, formatErrorIndexBound(idx, dest.len-1))
      else:
        dest[idx] = regs[rc].node
    of opcNAdd:
      decodeBC(rkNode)
      var u = regs[rb].node
      if nfSem in u.flags and allowSemcheckedAstModification notin c.config.legacyFeatures:
        stackTrace(c, tos, pc, "typechecked nodes may not be modified")
      elif u.kind in {nkEmpty..nkNilLit}:
        stackTrace(c, tos, pc, "cannot add to node kind: n" & $u.kind)
      else:
        u.add(regs[rc].node)
      regs[ra].node = u
    of opcNAddMultiple:
      decodeBC(rkNode)
      let x = regs[rc].node
      var u = regs[rb].node
      if nfSem in u.flags and allowSemcheckedAstModification notin c.config.legacyFeatures:
        stackTrace(c, tos, pc, "typechecked nodes may not be modified")
      elif u.kind in {nkEmpty..nkNilLit}:
        stackTrace(c, tos, pc, "cannot add to node kind: n" & $u.kind)
      else:
        for i in 0..<x.len: u.add(x[i])
      regs[ra].node = u
    of opcNKind:
      decodeB(rkInt)
      regs[ra].intVal = ord(regs[rb].node.kind)
      c.comesFromHeuristic = regs[rb].node.info
    of opcNSymKind:
      decodeB(rkInt)
      let a = regs[rb].node
      if a.kind == nkSym:
        regs[ra].intVal = ord(a.sym.kind)
      else:
        stackTrace(c, tos, pc, "node is not a symbol")
      c.comesFromHeuristic = regs[rb].node.info
    of opcNIntVal:
      decodeB(rkInt)
      let a = regs[rb].node
      if a.kind in {nkCharLit..nkUInt64Lit}:
        regs[ra].intVal = a.intVal
      elif a.kind == nkSym and a.sym.kind == skEnumField:
        regs[ra].intVal = a.sym.position
      else:
        stackTrace(c, tos, pc, errFieldXNotFound & "intVal")
    of opcNFloatVal:
      decodeB(rkFloat)
      let a = regs[rb].node
      case a.kind
      of nkFloatLit..nkFloat64Lit: regs[ra].floatVal = a.floatVal
      else: stackTrace(c, tos, pc, errFieldXNotFound & "floatVal")
    of opcNSymbol:
      decodeB(rkNode)
      let a = regs[rb].node
      if a.kind == nkSym:
        regs[ra].node = copyNode(a)
      else:
        stackTrace(c, tos, pc, errFieldXNotFound & "symbol")
    of opcNIdent:
      decodeB(rkNode)
      let a = regs[rb].node
      if a.kind == nkIdent:
        regs[ra].node = copyNode(a)
      else:
        stackTrace(c, tos, pc, errFieldXNotFound & "ident")
    of opcNodeId:
      decodeB(rkInt)
      when defined(useNodeIds):
        regs[ra].intVal = regs[rb].node.id
      else:
        regs[ra].intVal = -1
    of opcNGetType:
      let rb = instr.regB
      let rc = instr.regC
      case rc
      of 0:
        # getType opcode:
        ensureKind(rkNode)
        if regs[rb].kind == rkNode and regs[rb].node.typ != nil:
          regs[ra].node = opMapTypeToAst(c.cache, regs[rb].node.typ, c.debug[pc], c.idgen)
        elif regs[rb].kind == rkNode and regs[rb].node.kind == nkSym and regs[rb].node.sym.typ != nil:
          regs[ra].node = opMapTypeToAst(c.cache, regs[rb].node.sym.typ, c.debug[pc], c.idgen)
        else:
          stackTrace(c, tos, pc, "node has no type")
      of 1:
        # typeKind opcode:
        ensureKind(rkInt)
        if regs[rb].kind == rkNode and regs[rb].node.typ != nil:
          regs[ra].intVal = ord(regs[rb].node.typ.kind)
        elif regs[rb].kind == rkNode and regs[rb].node.kind == nkSym and regs[rb].node.sym.typ != nil:
          regs[ra].intVal = ord(regs[rb].node.sym.typ.kind)
        #else:
        #  stackTrace(c, tos, pc, "node has no type")
      of 2:
        # getTypeInst opcode:
        ensureKind(rkNode)
        if regs[rb].kind == rkNode and regs[rb].node.typ != nil:
          regs[ra].node = opMapTypeInstToAst(c.cache, regs[rb].node.typ, c.debug[pc], c.idgen)
        elif regs[rb].kind == rkNode and regs[rb].node.kind == nkSym and regs[rb].node.sym.typ != nil:
          regs[ra].node = opMapTypeInstToAst(c.cache, regs[rb].node.sym.typ, c.debug[pc], c.idgen)
        else:
          stackTrace(c, tos, pc, "node has no type")
      else:
        # getTypeImpl opcode:
        ensureKind(rkNode)
        if regs[rb].kind == rkNode and regs[rb].node.typ != nil:
          regs[ra].node = opMapTypeImplToAst(c.cache, regs[rb].node.typ, c.debug[pc], c.idgen)
        elif regs[rb].kind == rkNode and regs[rb].node.kind == nkSym and regs[rb].node.sym.typ != nil:
          regs[ra].node = opMapTypeImplToAst(c.cache, regs[rb].node.sym.typ, c.debug[pc], c.idgen)
        else:
          stackTrace(c, tos, pc, "node has no type")
    of opcNGetSize:
      decodeBImm(rkInt)
      let n = regs[rb].node
      case imm
      of 0: # size
        if n.typ == nil:
          stackTrace(c, tos, pc, "node has no type")
        else:
          regs[ra].intVal = getSize(c.config, n.typ)
      of 1: # align
        if n.typ == nil:
          stackTrace(c, tos, pc, "node has no type")
        else:
          regs[ra].intVal = getAlign(c.config, n.typ)
      else: # offset
        if n.kind != nkSym:
          stackTrace(c, tos, pc, "node is not a symbol")
        elif n.sym.kind != skField:
          stackTrace(c, tos, pc, "symbol is not a field (nskField)")
        else:
          regs[ra].intVal = n.sym.offset
    of opcNStrVal:
      decodeB(rkNode)
      createStr regs[ra]
      let a = regs[rb].node
      case a.kind
      of nkStrLit..nkTripleStrLit:
        regs[ra].node.strVal = a.strVal
      of nkCommentStmt:
        regs[ra].node.strVal = a.comment
      of nkIdent:
        regs[ra].node.strVal = a.ident.s
      of nkSym:
        regs[ra].node.strVal = a.sym.name.s
      else:
        stackTrace(c, tos, pc, errFieldXNotFound & "strVal")
    of opcNSigHash:
      decodeB(rkNode)
      createStr regs[ra]
      if regs[rb].node.kind != nkSym:
        stackTrace(c, tos, pc, "node is not a symbol")
      else:
        regs[ra].node.strVal = $sigHash(regs[rb].node.sym, c.config)
    of opcSlurp:
      decodeB(rkNode)
      createStr regs[ra]
      regs[ra].node.strVal = opSlurp(regs[rb].node.strVal, c.debug[pc],
                                     c.module, c.config)
    of opcGorge:
      decodeBC(rkNode)
      inc pc
      let rd = c.code[pc].regA
      createStr regs[ra]
      if defined(nimsuggest) or c.config.cmd == cmdCheck:
        discard "don't run staticExec for 'nim suggest'"
        regs[ra].node.strVal = ""
      else:
        when defined(nimcore):
          regs[ra].node.strVal = opGorge(regs[rb].node.strVal,
                                        regs[rc].node.strVal, regs[rd].node.strVal,
                                        c.debug[pc], c.config)[0]
        else:
          regs[ra].node.strVal = ""
          globalError(c.config, c.debug[pc], "VM is not built with 'gorge' support")
    of opcNError, opcNWarning, opcNHint:
      decodeB(rkNode)
      let a = regs[ra].node
      let b = regs[rb].node
      let info = if b.kind == nkNilLit: c.debug[pc] else: b.info
      if instr.opcode == opcNError:
        stackTrace(c, tos, pc, a.strVal, info)
      elif instr.opcode == opcNWarning:
        message(c.config, info, warnUser, a.strVal)
      elif instr.opcode == opcNHint:
        message(c.config, info, hintUser, a.strVal)
    of opcParseExprToAst:
      decodeBC(rkNode)
      var error: string = ""
      let ast = parseString(regs[rb].node.strVal, c.cache, c.config,
                            regs[rc].node.strVal, 0,
                            proc (conf: ConfigRef; info: TLineInfo; msg: TMsgKind; arg: string) =
                              if error.len == 0 and msg <= errMax:
                                error = formatMsg(conf, info, msg, arg))

      regs[ra].node = newNode(nkEmpty)
      if error.len > 0:
        c.errorFlag = error
      elif ast.len != 1:
        c.errorFlag = formatMsg(c.config, c.debug[pc], errGenerated,
          "expected expression, but got multiple statements")
      else:
        regs[ra].node = ast[0]
    of opcParseStmtToAst:
      decodeBC(rkNode)
      var error: string = ""
      let ast = parseString(regs[rb].node.strVal, c.cache, c.config,
                            regs[rc].node.strVal, 0,
                            proc (conf: ConfigRef; info: TLineInfo; msg: TMsgKind; arg: string) =
                              if error.len == 0 and msg <= errMax:
                                error = formatMsg(conf, info, msg, arg))
      if error.len > 0:
        c.errorFlag = error
        regs[ra].node = newNode(nkEmpty)
      else:
        regs[ra].node = ast
    of opcQueryErrorFlag:
      createStr regs[ra]
      regs[ra].node.strVal = c.errorFlag
      c.errorFlag.setLen 0
    of opcCallSite:
      ensureKind(rkNode)
      if c.callsite != nil: regs[ra].node = c.callsite
      else: stackTrace(c, tos, pc, errFieldXNotFound & "callsite")
    of opcNGetLineInfo:
      decodeBImm(rkNode)
      let n = regs[rb].node
      case imm
      of 0: # getFile
        regs[ra].node = newStrNode(nkStrLit, toFullPath(c.config, n.info))
      of 1: # getLine
        regs[ra].node = newIntNode(nkIntLit, n.info.line.int)
      of 2: # getColumn
        regs[ra].node = newIntNode(nkIntLit, n.info.col.int)
      else:
        internalAssert c.config, false
      regs[ra].node.info = n.info
      regs[ra].node.typ() = n.typ
    of opcNCopyLineInfo:
      decodeB(rkNode)
      regs[ra].node.info = regs[rb].node.info
    of opcNSetLineInfoLine:
      decodeB(rkNode)
      regs[ra].node.info.line = regs[rb].intVal.uint16
    of opcNSetLineInfoColumn:
      decodeB(rkNode)
      regs[ra].node.info.col = regs[rb].intVal.int16
    of opcNSetLineInfoFile:
      decodeB(rkNode)
      regs[ra].node.info.fileIndex =
        fileInfoIdx(c.config, RelativeFile regs[rb].node.strVal)
    of opcEqIdent:
      decodeBC(rkInt)
      # aliases for shorter and easier to understand code below
      var aNode = regs[rb].node
      var bNode = regs[rc].node
      # Skipping both, `nkPostfix` and `nkAccQuoted` for both
      # arguments.  `nkPostfix` exists only to tag exported symbols
      # and therefor it can be safely skipped. Nim has no postfix
      # operator. `nkAccQuoted` is used to quote an identifier that
      # wouldn't be allowed to use in an unquoted context.
      if aNode.kind == nkPostfix:
        aNode = aNode[1]
      if aNode.kind == nkAccQuoted:
        aNode = aNode[0]
      if bNode.kind == nkPostfix:
        bNode = bNode[1]
      if bNode.kind == nkAccQuoted:
        bNode = bNode[0]
      # These vars are of type `cstring` to prevent unnecessary string copy.
      var aStrVal: cstring = nil
      var bStrVal: cstring = nil
      # extract strVal from argument ``a``
      case aNode.kind
      of nkStrLit..nkTripleStrLit:
        aStrVal = aNode.strVal.cstring
      of nkIdent:
        aStrVal = aNode.ident.s.cstring
      of nkSym:
        aStrVal = aNode.sym.name.s.cstring
      of nkOpenSymChoice, nkClosedSymChoice:
        aStrVal = aNode[0].sym.name.s.cstring
      else:
        discard
      # extract strVal from argument ``b``
      case bNode.kind
      of nkStrLit..nkTripleStrLit:
        bStrVal = bNode.strVal.cstring
      of nkIdent:
        bStrVal = bNode.ident.s.cstring
      of nkSym:
        bStrVal = bNode.sym.name.s.cstring
      of nkOpenSymChoice, nkClosedSymChoice:
        bStrVal = bNode[0].sym.name.s.cstring
      else:
        discard
      regs[ra].intVal =
        if aStrVal != nil and bStrVal != nil:
          ord(idents.cmpIgnoreStyle(aStrVal, bStrVal, high(int)) == 0)
        else:
          0

    of opcStrToIdent:
      decodeB(rkNode)
      if regs[rb].node.kind notin {nkStrLit..nkTripleStrLit}:
        stackTrace(c, tos, pc, errFieldXNotFound & "strVal")
      else:
        regs[ra].node = newNodeI(nkIdent, c.debug[pc])
        regs[ra].node.ident = getIdent(c.cache, regs[rb].node.strVal)
        regs[ra].node.flags.incl nfIsRef
    of opcSetType:
      let typ = c.types[instr.regBx - wordExcess]
      if regs[ra].kind != rkNode:
        let temp = regToNode(regs[ra])
        ensureKind(rkNode)
        regs[ra].node = temp
        regs[ra].node.info = c.debug[pc]
      regs[ra].node.typ() = typ
    of opcConv:
      let rb = instr.regB
      inc pc
      let desttyp = c.types[c.code[pc].regBx - wordExcess]
      inc pc
      let srctyp = c.types[c.code[pc].regBx - wordExcess]

      if opConv(c, regs[ra], regs[rb], desttyp, srctyp):
        stackTrace(c, tos, pc,
          errIllegalConvFromXtoY % [
          typeToString(srctyp), typeToString(desttyp)])
    of opcCast:
      let rb = instr.regB
      inc pc
      let desttyp = c.types[c.code[pc].regBx - wordExcess]
      inc pc
      let srctyp = c.types[c.code[pc].regBx - wordExcess]

      when hasFFI:
        let dest = fficast(c.config, regs[rb].node, desttyp)
        # todo: check whether this is correct
        # asgnRef(regs[ra], dest)
        putIntoReg(regs[ra], dest)
      else:
        globalError(c.config, c.debug[pc], "cannot evaluate cast")
    of opcNSetIntVal:
      decodeB(rkNode)
      var dest = regs[ra].node
      if dest.kind in {nkCharLit..nkUInt64Lit} and
         regs[rb].kind in {rkInt}:
        dest.intVal = regs[rb].intVal
      elif dest.kind == nkSym and dest.sym.kind == skEnumField:
        stackTrace(c, tos, pc, "`intVal` cannot be changed for an enum symbol.")
      else:
        stackTrace(c, tos, pc, errFieldXNotFound & "intVal")
    of opcNSetFloatVal:
      decodeB(rkNode)
      var dest = regs[ra].node
      if dest.kind in {nkFloatLit..nkFloat64Lit} and
         regs[rb].kind in {rkFloat}:
        dest.floatVal = regs[rb].floatVal
      else:
        stackTrace(c, tos, pc, errFieldXNotFound & "floatVal")
    of opcNSetSymbol:
      decodeB(rkNode)
      var dest = regs[ra].node
      if dest.kind == nkSym and regs[rb].node.kind == nkSym:
        dest.sym = regs[rb].node.sym
      else:
        stackTrace(c, tos, pc, errFieldXNotFound & "symbol")
    of opcNSetIdent:
      decodeB(rkNode)
      var dest = regs[ra].node
      if dest.kind == nkIdent and regs[rb].node.kind == nkIdent:
        dest.ident = regs[rb].node.ident
      else:
        stackTrace(c, tos, pc, errFieldXNotFound & "ident")
    of opcNSetStrVal:
      decodeB(rkNode)
      var dest = regs[ra].node
      if dest.kind in {nkStrLit..nkTripleStrLit} and
         regs[rb].kind in {rkNode}:
        dest.strVal = regs[rb].node.strVal
      elif dest.kind == nkCommentStmt and regs[rb].kind in {rkNode}:
        dest.comment = regs[rb].node.strVal
      else:
        stackTrace(c, tos, pc, errFieldXNotFound & "strVal")
    of opcNNewNimNode:
      decodeBC(rkNode)
      var k = regs[rb].intVal
      if k < 0 or k > ord(high(TNodeKind)):
        internalError(c.config, c.debug[pc],
          "request to create a NimNode of invalid kind")
      let cc = regs[rc].node

      let x = newNodeI(TNodeKind(int(k)),
        if cc.kind != nkNilLit:
          cc.info
        elif c.comesFromHeuristic.line != 0'u16:
          c.comesFromHeuristic
        elif c.callsite != nil and c.callsite.safeLen > 1:
          c.callsite[1].info
        else:
          c.debug[pc])
      x.flags.incl nfIsRef
      # prevent crashes in the compiler resulting from wrong macros:
      if x.kind == nkIdent: x.ident = c.cache.emptyIdent
      regs[ra].node = x
    of opcNCopyNimNode:
      decodeB(rkNode)
      regs[ra].node = copyNode(regs[rb].node)
    of opcNCopyNimTree:
      decodeB(rkNode)
      regs[ra].node = copyTree(regs[rb].node)
    of opcNDel:
      decodeBC(rkNode)
      let bb = regs[rb].intVal.int
      for i in 0..<regs[rc].intVal.int:
        delSon(regs[ra].node, bb)
    of opcGenSym:
      decodeBC(rkNode)
      let k = regs[rb].intVal
      let name = if regs[rc].node.strVal.len == 0: ":tmp"
                 else: regs[rc].node.strVal
      if k < 0 or k > ord(high(TSymKind)):
        internalError(c.config, c.debug[pc], "request to create symbol of invalid kind")
      var sym = newSym(k.TSymKind, getIdent(c.cache, name), c.idgen, c.module.owner, c.debug[pc])
      incl(sym.flags, sfGenSym)
      regs[ra].node = newSymNode(sym)
      regs[ra].node.flags.incl nfIsRef
    of opcNccValue:
      decodeB(rkInt)
      let destKey {.cursor.} = regs[rb].node.strVal
      regs[ra].intVal = getOrDefault(c.graph.cacheCounters, destKey)
    of opcNccInc:
      let g = c.graph
      declBC()
      let destKey {.cursor.} = regs[rb].node.strVal
      let by = regs[rc].intVal
      let v = getOrDefault(g.cacheCounters, destKey)
      g.cacheCounters[destKey] = v+by
      recordInc(c, c.debug[pc], destKey, by)
    of opcNcsAdd:
      let g = c.graph
      declBC()
      let destKey {.cursor.} = regs[rb].node.strVal
      let val = regs[rc].node
      if not contains(g.cacheSeqs, destKey):
        g.cacheSeqs[destKey] = newTree(nkStmtList, val)
      else:
        g.cacheSeqs[destKey].add val
      recordAdd(c, c.debug[pc], destKey, val)
    of opcNcsIncl:
      let g = c.graph
      declBC()
      let destKey {.cursor.} = regs[rb].node.strVal
      let val = regs[rc].node
      if not contains(g.cacheSeqs, destKey):
        g.cacheSeqs[destKey] = newTree(nkStmtList, val)
      else:
        block search:
          for existing in g.cacheSeqs[destKey]:
            if exprStructuralEquivalent(existing, val, strictSymEquality=true):
              break search
          g.cacheSeqs[destKey].add val
      recordIncl(c, c.debug[pc], destKey, val)
    of opcNcsLen:
      let g = c.graph
      decodeB(rkInt)
      let destKey {.cursor.} = regs[rb].node.strVal
      regs[ra].intVal =
        if contains(g.cacheSeqs, destKey): g.cacheSeqs[destKey].len else: 0
    of opcNcsAt:
      let g = c.graph
      decodeBC(rkNode)
      let idx = regs[rc].intVal
      let destKey {.cursor.} = regs[rb].node.strVal
      if contains(g.cacheSeqs, destKey) and idx <% g.cacheSeqs[destKey].len:
        regs[ra].node = g.cacheSeqs[destKey][idx.int]
      else:
        stackTrace(c, tos, pc, formatErrorIndexBound(idx, g.cacheSeqs[destKey].len-1))
    of opcNctPut:
      let g = c.graph
      let destKey {.cursor.} = regs[ra].node.strVal
      let key {.cursor.} = regs[instr.regB].node.strVal
      let val = regs[instr.regC].node
      if not contains(g.cacheTables, destKey):
        g.cacheTables[destKey] = initBTree[string, PNode]()
      if not contains(g.cacheTables[destKey], key):
        g.cacheTables[destKey].add(key, val)
        recordPut(c, c.debug[pc], destKey, key, val)
      else:
        stackTrace(c, tos, pc, "key already exists: " & key)
    of opcNctLen:
      let g = c.graph
      decodeB(rkInt)
      let destKey {.cursor.} = regs[rb].node.strVal
      regs[ra].intVal =
        if contains(g.cacheTables, destKey): g.cacheTables[destKey].len else: 0
    of opcNctGet:
      let g = c.graph
      decodeBC(rkNode)
      let destKey {.cursor.} = regs[rb].node.strVal
      let key {.cursor.} = regs[rc].node.strVal
      if contains(g.cacheTables, destKey):
        if contains(g.cacheTables[destKey], key):
          regs[ra].node = getOrDefault(g.cacheTables[destKey], key)
        else:
          stackTrace(c, tos, pc, "key does not exist: " & key)
      else:
        stackTrace(c, tos, pc, "key does not exist: " & destKey)
    of opcNctHasNext:
      let g = c.graph
      decodeBC(rkInt)
      let destKey {.cursor.} = regs[rb].node.strVal
      regs[ra].intVal =
        if g.cacheTables.contains(destKey):
          ord(btrees.hasNext(g.cacheTables[destKey], regs[rc].intVal.int))
        else:
          0
    of opcNctNext:
      let g = c.graph
      decodeBC(rkNode)
      let destKey {.cursor.} = regs[rb].node.strVal
      let index = regs[rc].intVal
      if contains(g.cacheTables, destKey):
        let (k, v, nextIndex) = btrees.next(g.cacheTables[destKey], index.int)
        regs[ra].node = newTree(nkTupleConstr, newStrNode(k, c.debug[pc]), v,
                                newIntNode(nkIntLit, nextIndex))
      else:
        stackTrace(c, tos, pc, "key does not exist: " & destKey)

    of opcTypeTrait:
      # XXX only supports 'name' for now; we can use regC to encode the
      # type trait operation
      decodeB(rkNode)
      var typ = regs[rb].node.typ
      internalAssert c.config, typ != nil
      while typ.kind == tyTypeDesc and typ.hasElementType: typ = typ.skipModifier
      createStr regs[ra]
      regs[ra].node.strVal = typ.typeToString(preferExported)

    c.profiler.leave(c)

    inc pc

proc execute(c: PCtx, start: int): PNode =
  var tos = PStackFrame(prc: nil, comesFrom: 0, next: nil)
  newSeq(tos.slots, c.prc.regInfo.len)
  result = rawExecute(c, start, tos).regToNode

proc execProc*(c: PCtx; sym: PSym; args: openArray[PNode]): PNode =
  c.loopIterations = c.config.maxLoopIterationsVM
  c.callDepth = c.config.maxCallDepthVM
  if sym.kind in routineKinds:
    if sym.typ.paramsLen != args.len:
      result = nil
      localError(c.config, sym.info,
        "NimScript: expected $# arguments, but got $#" % [
        $(sym.typ.paramsLen), $args.len])
    else:
      let start = genProc(c, sym)

      var tos = PStackFrame(prc: sym, comesFrom: 0, next: nil)
      let maxSlots = sym.offset
      newSeq(tos.slots, maxSlots)

      # setup parameters:
      if not isEmptyType(sym.typ.returnType) or sym.kind == skMacro:
        putIntoReg(tos.slots[0], getNullValue(c, sym.typ.returnType, sym.info, c.config))
      # XXX We could perform some type checking here.
      for i in 0..<sym.typ.paramsLen:
        putIntoReg(tos.slots[i+1], args[i])

      result = rawExecute(c, start, tos).regToNode
  else:
    result = nil
    localError(c.config, sym.info,
      "NimScript: attempt to call non-routine: " & sym.name.s)

proc errorNode(idgen: IdGenerator; owner: PSym, n: PNode): PNode =
  result = newNodeI(nkEmpty, n.info)
  result.typ() = newType(tyError, idgen, owner)
  result.typ.flags.incl tfCheckedForDestructor

proc evalStmt*(c: PCtx, n: PNode) =
  let n = transformExpr(c.graph, c.idgen, c.module, n)
  let start = genStmt(c, n)
  if c.cannotEval:
    c.cannotEval = false
    return
  # execute new instructions; this redundant opcEof check saves us lots
  # of allocations in 'execute':
  if c.code[start].opcode != opcEof:
    discard execute(c, start)

proc evalExpr*(c: PCtx, n: PNode): PNode =
  # deadcode
  # `nim --eval:"expr"` might've used it at some point for idetools; could
  # be revived for nimsuggest
  let n = transformExpr(c.graph, c.idgen, c.module, n)
  c.cannotEval = false
  let start = genExpr(c, n)
  if c.cannotEval:
    return errorNode(c.idgen, c.module, n)
  assert c.code[start].opcode != opcEof
  result = execute(c, start)

proc getGlobalValue*(c: PCtx; s: PSym): PNode =
  internalAssert c.config, s.kind in {skLet, skVar} and sfGlobal in s.flags
  result = c.globals[s.position-1]

proc setGlobalValue*(c: PCtx; s: PSym, val: PNode) =
  ## Does not do type checking so ensure the `val` matches the `s.typ`
  internalAssert c.config, s.kind in {skLet, skVar} and sfGlobal in s.flags
  c.globals[s.position-1] = val

include vmops

proc setupGlobalCtx*(module: PSym; graph: ModuleGraph; idgen: IdGenerator) =
  if graph.vm.isNil:
    graph.vm = newCtx(module, graph.cache, graph, idgen)
    registerAdditionalOps(PCtx graph.vm)
  else:
    refresh(PCtx graph.vm, module, idgen)

proc setupEvalGen*(graph: ModuleGraph; module: PSym; idgen: IdGenerator): PPassContext =
  #var c = newEvalContext(module, emRepl)
  #c.features = {allowCast, allowInfiniteLoops}
  #pushStackFrame(c, newStackFrame())

  # XXX produce a new 'globals' environment here:
  setupGlobalCtx(module, graph, idgen)
  result = PCtx graph.vm

proc interpreterCode*(c: PPassContext, n: PNode): PNode =
  let c = PCtx(c)
  # don't eval errornous code:
  if c.oldErrorCount == c.config.errorCounter:
    evalStmt(c, n)
    result = newNodeI(nkEmpty, n.info)
  else:
    result = n
  c.oldErrorCount = c.config.errorCounter

proc evalConstExprAux(module: PSym; idgen: IdGenerator;
                      g: ModuleGraph; prc: PSym, n: PNode,
                      mode: TEvalMode): PNode =
  when defined(nimsuggest):
    if g.config.expandDone():
      return n
  #if g.config.errorCounter > 0: return n
  let n = transformExpr(g, idgen, module, n)
  setupGlobalCtx(module, g, idgen)
  var c = PCtx g.vm
  let oldMode = c.mode
  c.mode = mode
  c.cannotEval = false
  let start = genExpr(c, n, requiresValue = mode!=emStaticStmt)
  if c.cannotEval:
    return errorNode(idgen, prc, n)
  if c.code[start].opcode == opcEof: return newNodeI(nkEmpty, n.info)
  assert c.code[start].opcode != opcEof
  when debugEchoCode: c.echoCode start
  var tos = PStackFrame(prc: prc, comesFrom: 0, next: nil)
  newSeq(tos.slots, c.prc.regInfo.len)
  #for i in 0..<c.prc.regInfo.len: tos.slots[i] = newNode(nkEmpty)
  result = rawExecute(c, start, tos).regToNode
  if result.info.col < 0: result.info = n.info
  c.mode = oldMode

proc evalConstExpr*(module: PSym; idgen: IdGenerator; g: ModuleGraph; e: PNode): PNode =
  result = evalConstExprAux(module, idgen, g, nil, e, emConst)

proc evalStaticExpr*(module: PSym; idgen: IdGenerator; g: ModuleGraph; e: PNode, prc: PSym): PNode =
  result = evalConstExprAux(module, idgen, g, prc, e, emStaticExpr)

proc evalStaticStmt*(module: PSym; idgen: IdGenerator; g: ModuleGraph; e: PNode, prc: PSym) =
  discard evalConstExprAux(module, idgen, g, prc, e, emStaticStmt)

proc setupCompileTimeVar*(module: PSym; idgen: IdGenerator; g: ModuleGraph; n: PNode) =
  discard evalConstExprAux(module, idgen, g, nil, n, emStaticStmt)

proc prepareVMValue(arg: PNode): PNode =
  ## strip nkExprColonExpr from tuple values recursively. That is how
  ## they are expected to be stored in the VM.

  # Early abort without copy. No transformation takes place.
  if arg.kind in nkLiterals:
    return arg

  if arg.kind == nkExprColonExpr and arg[0].typ != nil and
     arg[0].typ.sym != nil and arg[0].typ.sym.magic == mPNimrodNode:
    # Poor mans way of protecting static NimNodes
    # XXX: Maybe we need a nkNimNode?
    return arg

  result = copyNode(arg)
  if arg.kind == nkTupleConstr:
    for child in arg:
      if child.kind == nkExprColonExpr:
        result.add prepareVMValue(child[1])
      else:
        result.add prepareVMValue(child)
  else:
    for child in arg:
      result.add prepareVMValue(child)

proc setupMacroParam(x: PNode, typ: PType): TFullReg =
  case typ.kind
  of tyStatic:
    result = TFullReg(kind: rkNone)
    putIntoReg(result, prepareVMValue(x))
  else:
    var n = x
    if n.kind in {nkHiddenSubConv, nkHiddenStdConv}: n = n[1]
    n.flags.incl nfIsRef
    n.typ() = x.typ
    result = TFullReg(kind: rkNode, node: n)

iterator genericParamsInMacroCall*(macroSym: PSym, call: PNode): (PSym, PNode) =
  let gp = macroSym.ast[genericParamsPos]
  for i in 0..<gp.len:
    let genericParam = gp[i].sym
    let posInCall = macroSym.typ.signatureLen + i
    if posInCall < call.len:
      yield (genericParam, call[posInCall])

# to prevent endless recursion in macro instantiation
const evalMacroLimit = 1000

proc evalMacroCall*(module: PSym; idgen: IdGenerator; g: ModuleGraph; templInstCounter: ref int;
                    n, nOrig: PNode, sym: PSym): PNode =
  #if g.config.errorCounter > 0: return errorNode(idgen, module, n)

  # XXX globalError() is ugly here, but I don't know a better solution for now
  inc(g.config.evalMacroCounter)
  if g.config.evalMacroCounter > evalMacroLimit:
    globalError(g.config, n.info, "macro instantiation too nested")

  # immediate macros can bypass any type and arity checking so we check the
  # arity here too:
  let sl = sym.typ.signatureLen
  if sl > n.safeLen and sl > 1:
    globalError(g.config, n.info, "in call '$#' got $#, but expected $# argument(s)" % [
        n.renderTree, $(n.safeLen-1), $(sym.typ.paramsLen)])

  setupGlobalCtx(module, g, idgen)
  var c = PCtx g.vm
  let oldMode = c.mode
  c.mode = emStaticStmt
  c.comesFromHeuristic.line = 0'u16
  c.callsite = nOrig
  c.templInstCounter = templInstCounter
  c.cannotEval = false
  let start = genProc(c, sym)
  if c.cannotEval:
    return errorNode(idgen, module, n)

  var tos = PStackFrame(prc: sym, comesFrom: 0, next: nil)
  let maxSlots = sym.offset
  newSeq(tos.slots, maxSlots)
  # setup arguments:
  var L = n.safeLen
  if L == 0: L = 1
  # This is wrong for tests/reject/tind1.nim where the passed 'else' part
  # doesn't end up in the parameter:
  #InternalAssert tos.slots.len >= L

  # return value:
  tos.slots[0] = TFullReg(kind: rkNode, node: newNodeI(nkEmpty, n.info))

  # setup parameters:
  for i, param in paramTypes(sym.typ):
    tos.slots[i-FirstParamAt+1] = setupMacroParam(n[i-FirstParamAt+1], param)

  let gp = sym.ast[genericParamsPos]
  for i in 0..<gp.len:
    let idx = sym.typ.signatureLen + i
    if idx < n.len:
      tos.slots[idx] = setupMacroParam(n[idx], gp[i].sym.typ)
    else:
      dec(g.config.evalMacroCounter)
      c.callsite = nil
      localError(c.config, n.info, "expected " & $gp.len &
                 " generic parameter(s)")
  # temporary storage:
  #for i in L..<maxSlots: tos.slots[i] = newNode(nkEmpty)
  result = rawExecute(c, start, tos).regToNode
  if result.info.line < 0: result.info = n.info
  if cyclicTree(result): globalError(c.config, n.info, "macro produced a cyclic tree")
  dec(g.config.evalMacroCounter)
  c.callsite = nil
  c.mode = oldMode
