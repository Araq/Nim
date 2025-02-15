var
  nimThreadDestructionHandlers* {.rtlThreadVar.}: seq[proc () {.closure, gcsafe, raises: [].}]
when not defined(boehmgc) and not hasSharedHeap and not defined(gogc) and not defined(gcRegions):
  proc deallocOsPages() {.rtl, raises: [].}
proc threadTrouble() {.raises: [], gcsafe.}
# create for the main thread. Note: do not insert this data into the list
# of all threads; it's not to be stopped etc.
when not defined(useNimRtl):
  #when not defined(createNimRtl): initStackBottom()
  when declared(initGC):
    initGC()
    when not emulatedThreadVars:
      type ThreadType {.pure.} = enum
        None = 0,
        NimThread = 1,
        ForeignThread = 2
      var
        threadType {.rtlThreadVar.}: ThreadType

      threadType = ThreadType.NimThread

when defined(gcDestructors):
  proc deallocThreadStorage(p: pointer) = c_free(p)
else:
  template deallocThreadStorage(p: pointer) = deallocShared(p)

template afterThreadRuns() =
  for i in countdown(nimThreadDestructionHandlers.len-1, 0):
    nimThreadDestructionHandlers[i]()

proc onThreadDestruction*(handler: proc () {.closure, gcsafe, raises: [].}) =
  ## Registers a *thread local* handler that is called at the thread's
  ## destruction.
  ##
  ## A thread is destructed when the `.thread` proc returns
  ## normally or when it raises an exception. Note that unhandled exceptions
  ## in a thread nevertheless cause the whole process to die.
  nimThreadDestructionHandlers.add handler

when defined(boehmgc):
  type GCStackBaseProc = proc(sb: pointer, t: pointer) {.noconv.}
  proc boehmGC_call_with_stack_base(sbp: GCStackBaseProc, p: pointer)
    {.importc: "GC_call_with_stack_base", boehmGC.}
  proc boehmGC_register_my_thread(sb: pointer)
    {.importc: "GC_register_my_thread", boehmGC.}
  proc boehmGC_unregister_my_thread()
    {.importc: "GC_unregister_my_thread", boehmGC.}

  proc threadProcWrapDispatch[TArg](sb: pointer, thrd: pointer) {.noconv, raises: [].} =
    boehmGC_register_my_thread(sb)
    try:
      let thrd = cast[ptr Thread[TArg]](thrd)
      when TArg is void:
        thrd.dataFn()
      else:
        thrd.dataFn(thrd.data)
    except:
      threadTrouble()
    finally:
      afterThreadRuns()
    boehmGC_unregister_my_thread()
else:
  proc threadProcWrapDispatch[TArg](thrd: ptr Thread[TArg]) {.raises: [].} =
    try:
      when TArg is void:
        thrd.dataFn()
      else:
        when defined(nimV2):
          thrd.dataFn(thrd.data)
        else:
          var x: TArg = default(TArg)
          deepCopy(x, thrd.data)
          thrd.dataFn(x)
    except:
      threadTrouble()
    finally:
      afterThreadRuns()
      when hasAllocStack:
        deallocThreadStorage(thrd.rawStack)

proc threadProcWrapStackFrame[TArg](thrd: ptr Thread[TArg]) {.raises: [].} =
  when defined(boehmgc):
    boehmGC_call_with_stack_base(threadProcWrapDispatch[TArg], thrd)
  elif not defined(nogc) and not defined(gogc) and not defined(gcRegions) and not usesDestructors:
    var p {.volatile.}: pointer
    # init the GC for refc/markandsweep
    nimGC_setStackBottom(addr(p))
    when declared(initGC):
      initGC()
    when declared(threadType):
      threadType = ThreadType.NimThread
    threadProcWrapDispatch[TArg](thrd)
    when declared(deallocOsPages): deallocOsPages()
  else:
    threadProcWrapDispatch(thrd)

template nimThreadProcWrapperBody*(closure: untyped): untyped =
  var thrd = cast[ptr Thread[TArg]](closure)
  var core = thrd.core
  when declared(globalsSlot): threadVarSetValue(globalsSlot, thrd.core)
  threadProcWrapStackFrame(thrd)
  # Since an unhandled exception terminates the whole process (!), there is
  # no need for a ``try finally`` here, nor would it be correct: The current
  # exception is tried to be re-raised by the code-gen after the ``finally``!
  # However this is doomed to fail, because we already unmapped every heap
  # page!

  # mark as not running anymore:
  thrd.core = nil
  thrd.dataFn = nil
  deallocThreadStorage(cast[pointer](core))
