discard """
cmd:"nim cpp $file"
errormsg: "type mismatch: got <proc (self: SomeObject){.member, gcsafe.}>"
line: 17
"""
type SomeObject = object
    value: int

proc printValue(self: SomeObject) {.virtual.} =
    echo "The value is ", self.value

proc callAProc(p: proc(self: SomeObject){.noconv.}) =
    let someObj = SomeObject(value: 4)
    echo "calling param proc"
    p(someObj)

callAProc(printValue)