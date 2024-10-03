discard """
  cmd: "nim check --hints:off $file"
"""

# issue #17848

block:
  # generate with:
  # var a = ""
  # for i in 0..<80: a.add "k" & $i & ", "
  # echo a
  type
    TMsgKind = enum
      k0, k1, k2, k3, k4, k5, k6, k7, k8, k9, k10, k11, k12, k13, k14, k15, k16, k17, k18, k19, k20, k21, k22, k23, k24, k25, k26, k27, k28, k29, k30, k31, k32, k33, k34, k35, k36, k37, k38, k39, k40, k41, k42, k43, k44, k45, k46, k47, k48, k49, k50, k51, k52, k53, k54, k55, k56, k57, k58, k59, k60, k61, k62, k63, k64, k65, k66, k67, k68, k69, k70, k71, k72, k73, k74, k75, k76, k77, k78, k79
  type
    TNoteKind = range[k10..k79]
    Conf = ref object
      notes: set[TNoteKind]
  proc bad(conf: Conf, noteSet: set[TMsgKind]) =
    conf.notes = noteSet #[tt.Error
                 ^ type mismatch: got <set[TMsgKind]> but expected 'set[TNoteKind]']#
  var conf = Conf()
  bad(conf, {k10..k60})

block:
  type
    TMsgKind = enum k0, k1, k2, k3
    TNoteKind = range[k1..k2]
    TNoteKinds = set[TNoteKind]
  type Conf = ref object
    notes: TNoteKinds
  proc fn(conf: Conf, b: set[TMsgKind]) =
    conf.notes = b #[tt.Error
                 ^ type mismatch: got <set[TMsgKind]> but expected 'TNoteKinds = set[TNoteKind]']#
  var conf = Conf()
  conf.fn({k0..k3}) # BUG: this should give error
  echo conf.notes # {k1, k2}

block:
  #[
  compiler/bitsets.nim(43, 9) `elem >= 0`  [AssertionDefect]
  ]#
  type
    TMsgKind = enum k0, k1, k2, k3
    TNoteKind = range[k1..k2]
  var notes: set[TNoteKind]
  notes = {k0} #[tt.Error
          ^ type mismatch: got <set[TMsgKind]> but expected 'set[TNoteKind]']#
  notes = {k0..k3} #[tt.Error
          ^ type mismatch: got <set[TMsgKind]> but expected 'set[TNoteKind]']#
