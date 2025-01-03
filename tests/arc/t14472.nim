discard """
  valgrind: true
  cmd: "nim cpp --gc:arc -d:useMalloc --deepcopy:on $file"
"""

type
  ImportMaterial* = object
    # Adding a field here makes the problem go away.

  Mesh* = object
    vertices: seq[float32]
    material: ImportMaterial

  ImportedScene* = object
    meshes*: seq[Mesh]

proc bork() : ImportedScene =
  result = ImportedScene()
  var mats: seq[ImportMaterial] = @[]

  setLen(mats, 1)
  add(result.meshes, Mesh(material: mats[0]))

var s = bork()


#------------------------------------------------------------------------
# issue #15543

import tables

type
  cdbl {.importc: "double".} = object

  MyObject = ref object of RootObj
    y: Table[string, cdbl]
        

proc test =
  var x = new(MyObject)

test()


