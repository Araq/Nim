import ./mambtype1
export mambtype1
template K*(kind: static int): auto = typedesc[mambtype1.K]
template B*(kind: static int): auto = typedesc[mambtype1.K]
