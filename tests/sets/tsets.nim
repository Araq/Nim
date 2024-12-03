discard """
  targets: "c cpp"
"""

# Test builtin sets

# xxx these tests are not very good, this should be revisited.

when defined nimTestsTsetsGenerate:
  # to generate enums for this test
  var ret: string
  for i in 0..<276:
    ret.add "k" & $i & ", "
  echo ret

proc testSets(s: var set[char]) =
  s = {'A', 'B', 'C', 'E'..'G'} + {'Z'} + s

# test sets if the first element is different from 0:
block:
  type
    TAZ = range['a'..'z']
    TAZset = set[TAZ]
    FakeTokType = enum
      k0, k1, k2, k3, k4, k5, k6, k7, k8, k9, k10, k11, k12, k13, k14, k15, k16, k17, k18, k19, k20, k21, k22, k23, k24, k25, k26, k27, k28, k29, k30, k31, k32, k33, k34, k35, k36, k37, k38, k39, k40, k41, k42, k43, k44, k45, k46, k47, k48, k49, k50, k51, k52, k53, k54, k55, k56, k57, k58, k59, k60, k61, k62, k63, k64, k65, k66, k67, k68, k69, k70, k71, k72, k73, k74, k75, k76, k77, k78, k79, k80, k81, k82, k83, k84, k85, k86, k87, k88, k89, k90, k91, k92, k93, k94, k95, k96, k97, k98, k99, k100, k101, k102, k103, k104, k105, k106, k107, k108, k109, k110, k111, k112, k113, k114, k115, k116, k117, k118, k119, k120, k121, k122, k123, k124, k125, k126, k127, k128, k129, k130, k131, k132, k133, k134, k135, k136, k137, k138, k139, k140, k141, k142, k143, k144, k145, k146, k147, k148, k149, k150, k151, k152, k153, k154, k155, k156, k157, k158, k159, k160, k161, k162, k163, k164, k165, k166, k167, k168, k169, k170, k171, k172, k173, k174, k175, k176, k177, k178, k179, k180, k181, k182, k183, k184, k185, k186, k187, k188, k189, k190, k191, k192, k193, k194, k195, k196, k197, k198, k199, k200, k201, k202, k203, k204, k205, k206, k207, k208, k209, k210, k211, k212, k213, k214, k215, k216, k217, k218, k219, k220, k221, k222, k223, k224, k225, k226, k227, k228, k229, k230, k231, k232, k233, k234, k235, k236, k237, k238, k239, k240, k241, k242, k243, k244, k245, k246, k247, k248, k249
    FakeTokTypeRange = range[k2..k101]
    FakeTokTypes = set[FakeTokTypeRange]
    Foo = object
      field: set[Bar] #Bug: 6259
    Bar = enum
      bar1, bar2, bar3

  const toktypes: FakeTokTypes = {FakeTokTypeRange(k2)..pred(k64), k72..k74}

  var
    s: set[char]
    a: TAZset
  s = {'0'..'9'}
  testSets(s)
  doAssert 'F' in s
  a = {} #{'a'..'z'}
  for x in low(TAZ) .. high(TAZ):
    incl(a, x)
    doAssert x in a

  for x in low(FakeTokTypeRange) .. high(FakeTokTypeRange):
    if x in tokTypes:
      discard

type
  FakeMsgKind* = enum
    k0, k1, k2, k3, k4, k5, k6, k7, k8, k9, k10, k11, k12, k13, k14, k15, k16, k17, k18, k19, k20, k21, k22, k23, k24, k25, k26, k27, k28, k29, k30, k31, k32, k33, k34, k35, k36, k37, k38, k39, k40, k41, k42, k43, k44, k45, k46, k47, k48, k49, k50, k51, k52, k53, k54, k55, k56, k57, k58, k59, k60, k61, k62, k63, k64, k65, k66, k67, k68, k69, k70, k71, k72, k73, k74, k75, k76, k77, k78, k79, k80, k81, k82, k83, k84, k85, k86, k87, k88, k89, k90, k91, k92, k93, k94, k95, k96, k97, k98, k99, k100, k101, k102, k103, k104, k105, k106, k107, k108, k109, k110, k111, k112, k113, k114, k115, k116, k117, k118, k119, k120, k121, k122, k123, k124, k125, k126, k127, k128, k129, k130, k131, k132, k133, k134, k135, k136, k137, k138, k139, k140, k141, k142, k143, k144, k145, k146, k147, k148, k149, k150, k151, k152, k153, k154, k155, k156, k157, k158, k159, k160, k161, k162, k163, k164, k165, k166, k167, k168, k169, k170, k171, k172, k173, k174, k175, k176, k177, k178, k179, k180, k181, k182, k183, k184, k185, k186, k187, k188, k189, k190, k191, k192, k193, k194, k195, k196, k197, k198, k199, k200, k201, k202, k203, k204, k205, k206, k207, k208, k209, k210, k211, k212, k213, k214, k215, k216, k217, k218, k219, k220, k221, k222, k223, k224, k225, k226, k227, k228, k229, k230, k231, k232, k233, k234, k235, k236, k237, k238, k239, k240, k241, k242, k243, k244, k245, k246, k247, k248, k249, k250, k251, k252, k253, k254, k255, k256, k257, k258, k259, k260, k261, k262, k263, k264, k265, k266, k267, k268, k269, k270, k271, k272, k273, k274, k275,

doAssert pred(k260) == k259

type
  FakeMsgKind2 = range[k230..high(FakeMsgKind)]
  FakeMsgKind3 = set[FakeMsgKind2]

var gNotes: FakeMsgKind3 = {low(FakeMsgKind2)..high(FakeMsgKind2)} - {k233, k235}

doAssert k233 notin gNotes

# 7555
doAssert {-1.int8, -2, -2}.card == 2
doAssert {1, 2, 2, 3..5, 4..6}.card == 6

# merely test the alias
doAssert {-1.int8, -2, -2}.len == 2
doAssert {1, 2, 2, 3..5, 4..6}.len == 6

type Foo = enum
  Foo1 = 0
  Foo2 = 1
  Foo3 = 3

let x = { Foo1, Foo2 }
# bug #8425

block:
  # bug #2880
  type
    FakeMsgKind = enum
      k0, k1, k2, k3, k4, k5, k6, k7, k8, k9, k10, k11, k12, k13, k14, k15, k16, k17, k18, k19, k20, k21, k22, k23, k24, k25, k26, k27, k28, k29, k30, k31, k32, k33, k34, k35, k36, k37, k38, k39, k40, k41, k42, k43, k44, k45, k46, k47, k48, k49, k50, k51, k52, k53, k54, k55, k56, k57, k58, k59, k60, k61, k62, k63, k64, k65, k66, k67, k68, k69, k70, k71, k72, k73, k74, k75, k76, k77, k78, k79, k80, k81, k82, k83, k84, k85, k86, k87, k88, k89, k90, k91, k92, k93, k94, k95, k96, k97, k98, k99, k100

  type
    FakeMsgKind2 = range[FakeMsgKind.k50..high(FakeMsgKind)]
    FakeMsgKind2s = set[FakeMsgKind2]

  const
    a1: array[0..0, FakeMsgKind2s] = [{low(FakeMsgKind2)..high(FakeMsgKind2)} - {FakeMsgKind.k99}]
    a2 = a1[0]

  var
    s1: FakeMsgKind2s = a1[0]
    s2: FakeMsgKind2s = a2

  doAssert k99 notin s1
  doAssert k99 notin s2

block: # bug #23422
  block:
    var a: set[uint8] = {1'u8}

    proc printLen(x: set[uint8]): int =
      doAssert x.len == card(x)
      result = card(x)

    proc printLenVar(x: var set[uint8]): int =
      doAssert x.len == card(x)
      result = card(x)

    doAssert a.len == 1
    doAssert printLen(a) == 1
    doAssert printLenVar(a) == card(a)

  block:
    type Fruit = enum
      Apple, Banana, Melon

    var a: set[Fruit] = {Apple}

    proc printLen(x: set[Fruit]): int =
      doAssert x.len == card(x)
      result = card(x)

    proc printLenVar(x: var set[Fruit]): int =
      doAssert x.len == card(x)
      result = card(x)

    doAssert a.len == 1
    doAssert printLen(a) == 1
    doAssert printLenVar(a) == card(a)
