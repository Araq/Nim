discard """
  cmd: "nim check --warningAsError:UnreachableCode $file"
  action: "reject"
  nimout: '''
tunreachable.nim(26, 3) Error: unreachable code after 'return' statement or '{.noReturn.}' proc [UnreachableCode]
tunreachable.nim(33, 3) Error: unreachable code after 'return' statement or '{.noReturn.}' proc [UnreachableCode]
tunreachable.nim(42, 3) Error: unreachable code after 'return' statement or '{.noReturn.}' proc [UnreachableCode]
tunreachable.nim(65, 5) Error: unreachable code after 'return' statement or '{.noReturn.}' proc [UnreachableCode]
tunreachable.nim(77, 5) Error: unreachable code after 'return' statement or '{.noReturn.}' proc [UnreachableCode]
'''
"""
  
# bug #9839
template myquit1():untyped=
  ## foo
  quit(1)
template myquit2():untyped=
  echo 123
  myquit1()

proc main1()=

  # BUG: uncommenting this doesn't give `Error: unreachable statement`
  myquit2()

  echo "after"

main1()

proc main2() =
  myquit1()

  echo "after"

main2()

proc main3() =
  if true:
    return
  else:
    return
  echo "after"

main3()


block:
  # Cases like strings are not checked for exhaustiveness unless they have an else
  proc main4(x: string) =
    case x
    of "a":
      return
    # reachable
    echo "after"

  main4("a")

  proc main5(x: string) =
    case x
    of "a":
      return
    else:
      return
    # unreachable
    echo "after"

  main5("a")

block:
  # In this case no else is needed because it's exhaustive
  proc exhaustive(x: bool) =
    case x
    of true:
      return
    of false:
      return
    echo "after"

  exhaustive(true)
