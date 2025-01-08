# issue #24186

macro mymacro(typ: typedesc; def) =
  def

macro mymacro2(typ: typedesc; typ2: typedesc; def) =
  def

template mytemplate(typ: typedesc) =   # works
  proc myproc() {.mymacro: typ .} =
    discard

template mytemplate2(typ: typedesc) =   # Error: undeclared identifier: 'typ'
  proc myproc2() {.mymacro(typ) .} =
    discard
  
template mytemplate3(typ: typedesc, typ2: typedesc) =  # Error: undeclared identifier: 'typ'
  proc myproc3() {.mymacro2(typ, typ2) .} =
    discard
  
template mytemplate4() =  # works
  proc myproc4() {.mymacro2(string, int) .} =
    discard

mytemplate(string)
mytemplate2(string)
mytemplate3(string, int)
mytemplate4()
