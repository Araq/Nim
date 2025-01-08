discard """
  targets: "cpp"
"""

{.emit: """

namespace System {
  struct Input {};
}

struct SystemManager {
  template <class T>
  static T* getSubsystem() { return new T; }
};

""".}

type Input {.importcpp: "System::Input", nodecl.} = object
proc getSubsystem*[T](): ptr T {.
  importcpp: "SystemManager::getSubsystem<'*0>()", nodecl.}

let input: ptr Input = getSubsystem[Input]()


# bugs #4910, #6892 
proc modify(x: var int) = 
  x = 123

proc foo() =
  var ts: array[2, int]
  for t in mitems(ts):
    discard

  for t in mitems(ts):
     modify(t)

  for i, t in mpairs(ts):
    modify(t)

