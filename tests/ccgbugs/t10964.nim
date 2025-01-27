func test*(input: var openArray[int32], start: int = 0, fin: int = input.len - 1) =
    discard

var someSeq = @[1'i32]

test(someSeq)
# bug with gcc 14