discard """
  errormsg: "type mismatch: got <(Child, int)> but expected '(Parent, int)'"
  line: 17
"""

# issue #18125 solved with correct type relation

type
  Parent = ref object of RootObj

  Child = ref object of Parent
    c: char

func foo(c: char): (Parent, int) =
  # Works if you use (Parent(Child(c: c)), 0)
  let x = (Child(c: c), 0)
  x

let x = foo('x')[0]
doAssert Child(x).c == 'x'
