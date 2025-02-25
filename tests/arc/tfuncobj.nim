discard """
  outputsub: '''f1
f2
f3'''
  cmd: "nim c --gc:orc $file"
  valgrind: true
"""

type
  FuncObj = object
    fn: proc (env: pointer) {.cdecl.}
    env: pointer

proc `=destroy`(x: var FuncObj) =
  GC_unref(cast[RootRef](x.env))

proc `=copy`(x: var FuncObj, y: FuncObj) {.error.}

# bug #18433

proc main =
  var fs: seq[FuncObj] = @[]

  proc wrap(p: proc()) =
    proc closeOver() = p()
    let env = rawEnv closeOver
    GC_ref(cast[RootRef](env))
    fs.add(FuncObj(fn: cast[proc(env: pointer){.cdecl.}](rawProc closeOver), env: env))

  wrap(proc() {.closure.} = echo "f1")
  wrap(proc() {.closure.} = echo "f2")
  wrap(proc() {.closure.} = echo "f3")

  for a in fs:
    a.fn(a.env)

main()

