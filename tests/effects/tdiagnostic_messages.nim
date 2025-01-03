discard """
  nimoutFull: true
  action: "reject"
  cmd: "nim r --hint:Conf:off --warnings:off $file"
  nimout: '''
tdiagnostic_messages.nim(36, 6) Error: 'a' can have side effects
> tdiagnostic_messages.nim(37, 30) Hint: 'a' calls `.sideEffect` 'callWithSideEffects'
>> tdiagnostic_messages.nim(29, 6) Hint: 'callWithSideEffects' called by 'a'
>>> tdiagnostic_messages.nim(31, 34) Hint: 'callWithSideEffects' calls `.sideEffect` 'indirectCallViaVarParam'
>>>> tdiagnostic_messages.nim(25, 6) Hint: 'indirectCallViaVarParam' called by 'callWithSideEffects'
>>>>> tdiagnostic_messages.nim(26, 7) Hint: 'indirectCallViaVarParam' calls routine via hidden pointer indirection
>>> tdiagnostic_messages.nim(32, 33) Hint: 'callWithSideEffects' calls `.sideEffect` 'indirectCallViaPointer'
>>>> tdiagnostic_messages.nim(27, 6) Hint: 'indirectCallViaPointer' called by 'callWithSideEffects'
>>>>> tdiagnostic_messages.nim(28, 32) Hint: 'indirectCallViaPointer' calls routine via pointer indirection
>>> tdiagnostic_messages.nim(33, 3) Hint: 'callWithSideEffects' calls `.sideEffect` 'myEcho'
>>>> tdiagnostic_messages.nim(24, 6) Hint: 'myEcho' called by 'callWithSideEffects'
>>> tdiagnostic_messages.nim(34, 3) Hint: 'callWithSideEffects' accesses global state 'globalVar'
>>>> tdiagnostic_messages.nim(23, 5) Hint: 'globalVar' accessed by 'callWithSideEffects'

'''
"""

var globalVar = 0
proc myEcho(a: string) {.sideEffect.} = discard
proc indirectCallViaVarParam(call: var proc(): int {.nimcall.}): int =
  call()
proc indirectCallViaPointer(call: pointer): int =
  cast[ptr proc(): int](call)[]()
proc callWithSideEffects(): int =
  var p = proc (): int {.nimcall.} = 0
  discard indirectCallViaVarParam(p)
  discard indirectCallViaPointer(addr p)
  myEcho ""
  globalVar

func a: int =
  discard callWithSideEffects()
