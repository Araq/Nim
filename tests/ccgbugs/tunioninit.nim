# issue #20653

type
  EmptySeq* {.bycopy.} = object

  ChoiceWithEmptySeq_d* {.bycopy.} = object
    a*: bool

  INNER_C_UNION* {.bycopy, union.} = object
    a*: char
    b*: EmptySeq
    c*: byte
    d*: ChoiceWithEmptySeq_d

  ChoiceWithEmptySeq_selection* = enum
    ChoiceWithEmptySeq_NONE, 
    ChoiceWithEmptySeq_a_PRESENT,
    ChoiceWithEmptySeq_b_PRESENT,  
    ChoiceWithEmptySeq_c_PRESENT,
    ChoiceWithEmptySeq_d_PRESENT

  ChoiceWithEmptySeq* {.bycopy.} = object
    kind*: ChoiceWithEmptySeq_selection
    u*: INNER_C_UNION

  Og_Context* {.bycopy.} = object
    state*: int
    init_done*: bool
    ch*: ChoiceWithEmptySeq
    em*: EmptySeq

var context* : Og_Context = Og_Context(init_done: false)
