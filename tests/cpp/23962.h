#include <iostream>

struct Foo {

  Foo(int inX): x(inX) {
    std::cout << "Ctor Foo(" << x << ")\n";
  }
  ~Foo() {
    std::cout << "Destory Foo(" << x << ")\n";
  }

  void print() {
    std::cout << "Foo.x = " << x << '\n';
  }

  int x;
};