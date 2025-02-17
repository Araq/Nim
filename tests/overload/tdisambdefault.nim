block:
  # don't consider inserted default values in overload disambiguation
  # https://github.com/status-im/nimbus-eth1/pull/2684#issuecomment-2392895327
  type Foo = ref object
  template foo(a: static[string], b: varargs[untyped]): string = "right"
  template foo(a: string, b: Foo = nil): string = "wrong"
  doAssert foo("abc") == "right"

block:
  # also consider unfilled varargs
  type Foo = ref object
  template foo(a: static[string], b: Foo = nil): string = "right"
  template foo(a: string, b: varargs[untyped]): string = "wrong"
  doAssert foo("abc") == "right"
