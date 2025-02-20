# issue #15097

import macros

macro foo: untyped = 
  result = newStmtList()
  let tmp = genSym(nskProc, "tmp") #[tt.Error
                  ^ illformed AST: symbol of kind skProc has no implementation]#
  result.add quote do:
    let bar = `tmp`()
    
foo()
