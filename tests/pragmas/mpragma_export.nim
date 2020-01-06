template myfoo2* = {.exportc.}
template myfoo3* = {.exportc: "myfoo3_in_c", discardable.}
template myfoo4* = {.discardable, myfoo2.}
template myfoo5 = {. .}

when false:
  # would require pragma export via https://github.com/nim-lang/Nim/pull/13030
  {.pragma: myfoo0, exportc: "myfoo0_in_c".}
  export myfoo0
elif false:
  # can't use non exported template pragma inside exported template pragma
  template myfoo0 = {.exportc: "myfoo0_in_c".}
else:
  # works
  template myfoo0* = {.exportc: "myfoo0_in_c".}

template myfoo6* = {.myfoo0, discardable.}

template myfooHijacked* = {.discardable.}
template myfoo7* = {.myfooHijacked.}

export myfoo5
