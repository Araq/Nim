discard """
  output: '''Section: common
  Param: Floats1
Section: local
  Param: Str
  Param: Bool
  Param: Floats2
destroy Foo
destroy Foo
'''
  cmd: '''nim c --gc:arc $file'''
"""

# bug #15325

import tables
import strutils

const defaultSection = "***"

type
    Config* = ref object
        table: OrderedTableRef[string, OrderedTable[string, string]]

# ----------------------------------------------------------------------------------------------------------------------
proc newConfig*(): Config =
    result       = new(Config)
    result.table = newOrderedTable[string, OrderedTable[string, string]]()

# ----------------------------------------------------------------------------------------------------------------------
proc add*(self: Config, param, value, section: string) {.nosinks.} =
    let s = if section == "": defaultSection else: section

    if not self.table.contains(s):
        self.table[s] = initOrderedTable[string, string]()

    self.table[s][param] = value

# ----------------------------------------------------------------------------------------------------------------------
proc sections*(self: Config): seq[string] =
    result = @[]
    for i in self.table.keys:
        let s = if i == defaultSection: "" else: i
        result.add(s)

# ----------------------------------------------------------------------------------------------------------------------
proc params*(self: Config, section: string): seq[string] =
    result = @[]
    let s = if section == "": defaultSection else: section

    if self.table.contains(s):
        for i in self.table[s].keys:
            result.add(i)

# ----------------------------------------------------------------------------------------------------------------------
proc extract*(str, start, finish: string): string =
    let startPos = str.find(start)

    if startPos < 0:
        return ""

    let endPos = str.find(finish, startPos)

    if endPos < 0:
        return ""

    return str[startPos + start.len() ..< endPos]

# ----------------------------------------------------------------------------------------------------------------------
proc loadString*(self: Config, text: string): tuple[valid: bool, errorInLine: int] {.discardable.} =
    self.table.clear()

    var data = ""

    data = text

    var
        actualSection = ""
        lineCount     = 0

    for i in splitLines(data):
        lineCount += 1

        var line = strip(i)

        if line.len() == 0:
            continue

        if line[0] == '#' or line[0] == ';':
            continue

        if line[0] == '[':
            let section = strip(extract(line, "[", "]"))

            if section.len() != 0:
                actualSection = section
            else:
                self.table.clear()
                return (false, lineCount)
        else:
            let equal = find(line, '=')

            if equal <= 0:
                self.table.clear()
                return (false, lineCount)
            else:
                let
                    param = strip(line[0 .. equal - 1])
                    value = strip(line[equal + 1 .. ^1])

                if param.len() == 0:
                    self.table.clear()
                    return (false, lineCount)
                else:
                    self.add(param, value, actualSection)

    return (true, 0)

# ----------------------------------------------------------------------------------------------------------------------
when isMainModule:
    var cfg = newConfig()

    cfg.loadString("[common]\nFloats1 = 1,2,3\n[local]\nStr = \"String...\"\nBool = true\nFloats2 = 4, 5, 6\n")

    for s in cfg.sections():
        echo "Section: " & s

        for p in cfg.params(s):
            echo "  Param: " & p

# bug #16437

type
  Foo = object
  FooRef = ref Foo

  Bar = ref object
    f: FooRef

proc `=destroy`(o: var Foo) =
  echo "destroy Foo"

proc testMe(x: Bar) =
  var c = (if x != nil: x.f else: nil)
  assert c != nil

proc main =
  var b = Bar(f: FooRef())
  testMe(b)

main()

proc testMe2(x: Bar) =
  var c: FooRef
  c = (if x != nil: x.f else: nil)
  assert c != nil

proc main2 =
  var b = Bar(f: FooRef())
  testMe2(b)

main2()

