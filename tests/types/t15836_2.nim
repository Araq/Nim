import std/sugar

type Tensor[T] = object
  x: T

proc numerical_gradient*[T](input: T, f: (proc(x: T): T), h = T(1e-5)): T {.inline.} =
  result = default(T)

proc numerical_gradient*[T](input: Tensor[T], f: (proc(x: Tensor[T]): T), h = T(1e-5)): Tensor[T] {.noinit.} =
  result = default(Tensor[T])

proc conv2d*[T](input: Tensor[T]): Tensor[T] {.inline.} =
  result = default(Tensor[T])

proc sum*[T](arg: Tensor[T]): T = default(T)

proc sum*[T](arg: Tensor[T], axis: int): Tensor[T] {.noinit.} = default(Tensor[T])

let dinput = Tensor[int](x: 1)
let target_grad_input = dinput.numerical_gradient(
    x => conv2d(x).sum())
