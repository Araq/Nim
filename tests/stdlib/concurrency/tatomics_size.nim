discard """
  # test C with -d:nimUseCppAtomics as well to check nothing breaks
  matrix: "--mm:refc; --mm:orc; --mm:refc -d:nimUseCppAtomics; --mm:orc -d:nimUseCppAtomics"
  targets: "c cpp"
"""
import std/atomics
import std/assertions

block testSize: # issue 12726
  type
    Node = ptr object
      # works
      next: Atomic[pointer]
      f:AtomicFlag
    MyChannel = object
      # type not defined completely
      back: Atomic[ptr int]
      f: AtomicFlag
  static:
    doAssert sizeof(Node) == sizeof(pointer)
    doAssert sizeof(MyChannel) == sizeof(pointer) * 2
