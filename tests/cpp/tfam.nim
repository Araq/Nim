discard """
  targets: "cpp"
"""
type 
  Test {.importcpp, header: "fam.h".} = object

let test = newSeq[Test]()