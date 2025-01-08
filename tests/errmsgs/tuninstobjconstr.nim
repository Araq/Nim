# issue #24372

type
  Foo[T] = object
    x: string
    
proc initFoo(): Foo[string] =
  Foo(x: "hello") #[tt.Error
     ^ cannot instantiate: 'Foo[T]'; the object's generic parameters cannot be inferred and must be explicitly given]#

discard initFoo()
