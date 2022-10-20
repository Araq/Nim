
discard """
  cmd: "nim check --hints:off --warnings:off $file"
  action: "reject"
  nimout: '''
tconstclosure.nim(44, 24) Error: const closure proc with an environment cannot be used at runtime: makeMyClosure(myRef)






'''
"""





type
  CallbackFunc* = proc (arg: pointer) {.gcsafe, raises: [Defect].}

  AsyncCallback* = object
    function*: CallbackFunc
    udata*: pointer

proc sentinelCallbackImpl(arg: pointer) {.gcsafe, raises: [Defect].} =
  raiseAssert "Sentinel callback MUST not be scheduled"

const
  SentinelCallback = AsyncCallback(function: sentinelCallbackImpl,
                                   udata: nil)

const a = proc() {.closure.} = echo "Hello"
a()

proc makeMyClosure(r: ref int): proc() =
    result = proc() =
      inc r[]
      echo r[]

var myRef {.compileTime.} = new int # This makes a reference in VM since it needs to be accessible at CT, but we can make a closure to capture it.

const c = makeMyClosure(myRef)
let d = c

d()