# issue #17779

{.experimental: "dotOperators".}

type
    Flag = enum
        A

    Flags = set[Flag]

template `.=`*(flags: Flags, key: Flag, val: bool) =
    if val: flags.incl key else: flags.excl key

var flags: Flags

flags.A = 123 #[tt.Error
        ^ undeclared field: 'A=' for type tmismatch.Flags [type declared in tmismatch.nim(9, 5)]]#
