discard """
    targets: "c cpp"
"""

# bug #23796

{.emit: """
#ifdef __cplusplus
extern "C" {
#endif

void fooArr(float data[3]) {}
void fooIntArr(int id, float data[3]) {}

#ifdef __cplusplus
}
#endif
""".}

proc fooArr(data: var array[3, cfloat]) {.importc.}
proc fooIntArr(id: cint, data: var array[3, cfloat]) {.importc, nodecl.}

var arr = [cfloat 1, 2, 3]
fooArr(arr)
fooIntArr(1, arr)
