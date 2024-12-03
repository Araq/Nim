# issue #18125 solved with type inference

type
  Parent = ref object of RootObj

  Child = ref object of Parent
    c: char

func foo(c: char): (Parent, int) =
  # Works if you use (Parent(Child(c: c)), 0)
  (Child(c: c), 0)

let x = foo('x')[0]
doAssert Child(x).c == 'x'
