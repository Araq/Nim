discard """
  cmd: "nim check --hints:off $file"
"""

block:
  template foo =
    when false:
      let x = 123
    else:
      template x: untyped {.inject.} = 456
    echo x #[tt.Error
         ^ undeclared identifier: 'x`gensym0'; if declared in a template, this identifier may be inconsistently marked inject or gensym]#
  foo()

block:
  template foo(y: static bool) =
    block:
      when y:
        let x {.gensym.} = 123
      else:
        let x {.inject.} = 456
      echo x #[tt.Error
           ^ undeclared identifier: 'x']#
  foo(false)
  foo(true)
