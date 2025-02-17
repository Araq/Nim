discard """
  errormsg: "The param passed to createThread must not be a ref type."
  cmd: "nim $target --hints:on --threads:on $options $file"
"""

type RefType = ref object

var
  global: string = "test string"

proc fn(rt: RefType) {.thread.} = discard

var t: Thread[RefType]
createThread[RefType](t, fn, new(RefType))
joinThread(t)
echo "ok!"