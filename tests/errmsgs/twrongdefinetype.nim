# issue #24539

type Foo = object
const foo {.define.} = Foo() #[tt.Error
      ^ unsupported type for constant 'foo' with .define pragma: Foo]#
echo repr(foo)
