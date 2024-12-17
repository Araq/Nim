# bug #23790

discard compiles($default(seq[seq[ref int]]))
discard compiles($default(seq[seq[ref uint]]))
discard compiles($default(seq[seq[ref int8]]))
discard compiles($default(seq[seq[ref uint8]]))
discard compiles($default(seq[seq[ref int16]]))
discard compiles($default(seq[seq[ref uint16]]))
discard compiles($default(seq[seq[ref int32]]))
discard compiles($default(seq[seq[ref uint32]]))
discard compiles($default(seq[seq[ref int64]]))
discard compiles($default(seq[seq[ref uint64]]))
proc s(_: int | string) = discard
s(0)
