## tests for -d:checkAbi used by addAbiCheck via NIM_STATIC_ASSERT

{.emit:"""/*TYPESECTION*/
struct Foo1{
  int a;
};
struct Foo2{
  int a;
};
enum Foo3{k1, k2};
typedef enum Foo3 Foo3b;
typedef enum Foo4{k3, k4} Foo4;

typedef int Foo5[3];

typedef struct Foo6{
  int a1;
  bool a2;
  double a3;
  struct Foo6* a4;
} Foo6;
""".}

template ensureCgen(T: typedesc) =
  ## ensures cgen
  var a {.volatile.}: T

block:
  type Foo1Alias{.importc: "struct Foo1", nodecl, size: sizeof(cint).} = object
    a: cint
  ensureCgen Foo1Alias

block:
  type Foo3Alias{.importc: "enum Foo3", size: sizeof(cint).} = enum
    k1, k2
  ensureCgen Foo3Alias

block:
  type Foo3bAlias{.importc: "Foo3b", size: sizeof(cint).} = enum
    k1, k2
  ensureCgen Foo3bAlias

block:
  type Foo3b{.importc, size: sizeof(cint).} = enum
    k1, k2
  ensureCgen Foo3b
  static:
    doAssert Foo3b.sizeof == cint.sizeof

block:
  type Foo4{.importc, size: sizeof(cint).} = enum
    k3, k4
  # adding entries should not yield duplicate ABI checks, as enforced by
  # `typeABICache`.
  # Currently the test doesn't check for this but you can inspect the cgen'd file
  ensureCgen Foo4
  ensureCgen Foo4
  ensureCgen Foo4

block:
  type Foo5{.importc.} = array[3, cint]
  ensureCgen Foo5

block:
  type Foo5{.importc.} = array[3, cint]
  ensureCgen Foo5

block: # CT sizeof
  type Foo6GT = object # grountruth
    a1: cint
    a2: bool
    a3: cfloat
    a4: ptr Foo6GT

  type Foo6{.importc, completeStruct.} = object
    a1: cint
    a2: bool
    a3: cfloat
    a4: ptr Foo6

  static: doAssert compiles(static(Foo6.sizeof))
  static: doAssert Foo6.sizeof == Foo6GT.sizeof
  static: doAssert (Foo6, int, array[2, Foo6]).sizeof ==
    (Foo6GT, int, array[2, Foo6GT]).sizeof

block:
  type GoodImportcType {.importc: "signed char", nodecl.} = char
    # "good" in sense the sizeof will match
  ensureCgen GoodImportcType

block:
  type Foo6{.importc.} = object
    a1: cint
  doAssert compiles(Foo6.sizeof)
  static: doAssert not compiles(static(Foo6.sizeof))

when defined caseBad:
  # Each case below should give a static cgen assert fail message

  block:
    type BadImportcType {.importc: "unsigned char", nodecl.} = uint64
      # "sizeof" check will fail
    ensureCgen BadImportcType

  block:
    type Foo2AliasBad{.importc: "struct Foo2", size: 1.} = object
      a: cint
    ensureCgen Foo2AliasBad

  block:
    type Foo5{.importc.} = array[4, cint]
    ensureCgen Foo5

  block:
    type Foo5{.importc.} = array[3, bool]
    ensureCgen Foo5

  block:
    type Foo6{.importc:"struct Foo6", completeStruct.} = object
      a1: cint
      # a2: bool # missing this should trigger assert fail
      a3: cfloat
      a4: ptr Foo6
    ensureCgen Foo6

  when false:
    block:
      # pre-existing BUG: this should give a CT error in semcheck because `size`
      # disagrees with `array[3, cint]`
      type Foo5{.importc, size: 1.} = array[3, cint]
      ensureCgen Foo5
