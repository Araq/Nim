proc foo(x: int) =
  if x < 0:
    echo "done"
  else:
    foo(x + 1) #[tt.Error
       ^ maximum call depth exceeded (2000)]#

static:
  foo(1)
