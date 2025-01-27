proc foo(x: int) =
  if x < 0:
    echo "done"
  else:
    foo(x + 1) #[tt.Error
       ^ maximum call depth for the VM exceeded; if you are sure this is not a bug in your code, compile with `--maxCallDepthVM:number` (current value: 2000)]#

static:
  foo(1)
