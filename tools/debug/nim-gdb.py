import gdb
import re
import sys
import traceback

# some feedback that the nim runtime support is loading, isn't a bad
# thing at all.
gdb.write("Loading Nim Runtime support.\n", gdb.STDERR)

# When error occure they occur regularly. This 'caches' known errors
# and prevents them from being reprinted over and over again.
errorSet = set()
def printErrorOnce(id, message):
  global errorSet
  if id not in errorSet:
    errorSet.add(id)
    gdb.write("printErrorOnce: " + message, gdb.STDERR)

def debugPrint(x):
  gdb.write(str(x) + "\n", gdb.STDERR)

NIM_STRING_TYPES = ["NimStringDesc", "NimStringV2"]

################################################################################
#####  Type pretty printers
################################################################################

type_hash_regex = re.compile("^([A-Za-z0-9]*)_([A-Za-z0-9]*)_+([A-Za-z0-9]*)$")

def getNimName(typ):
  if m := type_hash_regex.match(typ):
    return m.group(2)
  return f"unknown <{typ}>"

def getNimRti(type_name):
  """ Return a ``gdb.Value`` object for the Nim Runtime Information of ``type_name``. """

  # Get static const TNimType variable. This should be available for
  # every non trivial Nim type.
  m = type_hash_regex.match(type_name)
  if m:
    lookups = [
      "NTI" + m.group(2).lower() + "__" + m.group(3) + "_",
      "NTI" + "__" + m.group(3) + "_",
      "NTI" + m.group(2).replace("colon", "58").lower() + "__" + m.group(3) + "_"
      ]
    for l in lookups:
      try:
        return gdb.parse_and_eval(l)
      except:
        pass
  None

def getNameFromNimRti(rti):
  """ Return name (or None) given a Nim RTI ``gdb.Value`` """
  try:
    # sometimes there isn't a name field -- example enums
    return rti['name'].string(encoding="utf-8", errors="ignore")
  except:
    return None

class NimTypeRecognizer:
  # this type map maps from types that are generated in the C files to
  # how they are called in nim. To not mix up the name ``int`` from
  # system.nim with the name ``int`` that could still appear in
  # generated code, ``NI`` is mapped to ``system.int`` and not just
  # ``int``.

  type_map_static = {
    'NI': 'system.int',  'NI8': 'int8', 'NI16': 'int16',  'NI32': 'int32',
    'NI64': 'int64',
    
    'NU': 'uint', 'NU8': 'uint8','NU16': 'uint16', 'NU32': 'uint32',
    'NU64': 'uint64',
    
    'NF': 'float', 'NF32': 'float32', 'NF64': 'float64',
    
    'NIM_BOOL': 'bool',

    'NIM_CHAR': 'char', 'NCSTRING': 'cstring', 'NimStringDesc': 'string', 'NimStringV2': 'string'
  }

  # object_type_pattern = re.compile("^(\w*):ObjectType$")

  def recognize(self, type_obj):
    # skip things we can't handle like functions
    if type_obj.code in [gdb.TYPE_CODE_FUNC, gdb.TYPE_CODE_VOID]:
      return None

    tname = None
    if type_obj.tag is not None:
      tname = type_obj.tag
    elif type_obj.name is not None:
      tname = type_obj.name

    # handle pointer types
    if not tname:
      target_type = type_obj
      if type_obj.code in [gdb.TYPE_CODE_PTR]:
        target_type = type_obj.target()

      if target_type.name:
        # visualize 'string' as non pointer type (unpack pointer type).
        if target_type.name == "NimStringDesc":
          tname = target_type.name # could also just return 'string'
        else:
          rti = getNimRti(target_type.name)
          if rti:
            return getNameFromNimRti(rti)

    if tname:
      result = self.type_map_static.get(tname, None)
      if result:
        return result
      elif tname.startswith("tyEnum_"):
        return getNimName(tname)
      elif tname.startswith("tyTuple__"):
        # We make the name be the field types (Just like in Nim)
        fields = ", ".join([self.recognize(field.type) for field in type_obj.fields()])
        return f"({fields})"

      rti = getNimRti(tname)
      if rti:
        return getNameFromNimRti(rti)

    return None

class NimTypePrinter:
  """Nim type printer. One printer for all Nim types."""

  # enabling and disabling of type printers can be done with the
  # following gdb commands:
  #
  #   enable  type-printer NimTypePrinter
  #   disable type-printer NimTypePrinter
  # relevant docs: https://sourceware.org/gdb/onlinedocs/gdb/Type-Printing-API.html

  name = "NimTypePrinter"

  def __init__(self):
    self.enabled = True

  def instantiate(self):
    return NimTypeRecognizer()

################################################################################
#####  GDB Function, equivalent of Nim's $ operator
################################################################################

class DollarPrintFunction (gdb.Function):
  "Nim's equivalent of $ operator as a gdb function, available in expressions `print $dollar(myvalue)"

  dollar_functions = re.findall(
    r'(?:NimStringDesc \*|NimStringV2)\s?(dollar__[A-z0-9_]+?)\(([^,)]*)\);',
    gdb.execute("info functions dollar__", True, True)
  )

  def __init__ (self):
    super (DollarPrintFunction, self).__init__("dollar")


  @staticmethod
  def invoke_static(arg, ignore_errors = False):
    if arg.type.code == gdb.TYPE_CODE_PTR and arg.type.target().name in NIM_STRING_TYPES:
      return arg
    argTypeName = str(arg.type)
    for func, arg_typ in DollarPrintFunction.dollar_functions:
      # this way of overload resolution cannot deal with type aliases,
      # therefore it won't find all overloads.
      if arg_typ == argTypeName:
        func_value = gdb.lookup_global_symbol(func, gdb.SYMBOL_FUNCTION_DOMAIN).value()
        return func_value(arg)

      elif arg_typ == argTypeName + " *":
        func_value = gdb.lookup_global_symbol(func, gdb.SYMBOL_FUNCTION_DOMAIN).value()
        return func_value(arg.address)

    if not ignore_errors:
      debugPrint(f"No suitable Nim $ operator found for type: {getNimName(argTypeName)}\n")
    return None

  def invoke(self, arg):
    return self.invoke_static(arg)

DollarPrintFunction()


################################################################################
#####  GDB Function, Nim string comparison
################################################################################

class NimStringEqFunction (gdb.Function):
  """Compare Nim strings for example in conditionals for breakpoints."""

  def __init__ (self):
    super (NimStringEqFunction, self).__init__("nimstreq")

  @staticmethod
  def invoke_static(arg1,arg2):
    if arg1.type.code == gdb.TYPE_CODE_PTR and arg1.type.target().name in NIM_STRING_TYPES:
      str1 = NimStringPrinter(arg1).to_string()
    else:
      str1 = arg1.string()
    if arg2.type.code == gdb.TYPE_CODE_PTR and arg2.type.target().name in NIM_STRING_TYPES:
      str2 = NimStringPrinter(arg1).to_string()
    else:
      str2 = arg2.string()

    return str1 == str2

  def invoke(self, arg1, arg2):
    return self.invoke_static(arg1, arg2)

NimStringEqFunction()


################################################################################
#####  GDB Command, equivalent of Nim's $ operator
################################################################################

class DollarPrintCmd (gdb.Command):
  """Dollar print command for Nim, `$ expr` will invoke Nim's $ operator and print the result."""

  def __init__ (self):
    super (DollarPrintCmd, self).__init__ ("$", gdb.COMMAND_DATA, gdb.COMPLETE_EXPRESSION)

  def invoke(self, arg, from_tty):
    param = gdb.parse_and_eval(arg)
    strValue = DollarPrintFunction.invoke_static(param)
    if strValue:
      gdb.write(
        str(NimStringPrinter(strValue)) + "\n",
        gdb.STDOUT
      )

    # could not find a suitable dollar overload. This here is the
    # fallback to get sensible output of basic types anyway.

    elif param.type.code == gdb.TYPE_CODE_ARRAY and param.type.target().name == "char":
      gdb.write(param.string("utf-8", "ignore") + "\n", gdb.STDOUT)
    elif param.type.code == gdb.TYPE_CODE_INT:
      gdb.write(str(int(param)) + "\n", gdb.STDOUT)
    elif param.type.name == "NIM_BOOL":
      if int(param) != 0:
        gdb.write("true\n", gdb.STDOUT)
      else:
        gdb.write("false\n", gdb.STDOUT)

DollarPrintCmd()


################################################################################
#####  GDB Commands to invoke common nim tools.
################################################################################


import subprocess, os


class KochCmd (gdb.Command):
  """Command that invokes ``koch'', the build tool for the compiler."""

  def __init__ (self):
    super (KochCmd, self).__init__ ("koch",
                                    gdb.COMMAND_USER, gdb.COMPLETE_FILENAME)
    self.binary = os.path.join(
      os.path.dirname(os.path.dirname(__file__)), "koch")

  def invoke(self, argument, from_tty):
    subprocess.run([self.binary] + gdb.string_to_argv(argument))

KochCmd()


class NimCmd (gdb.Command):
  """Command that invokes ``nim'', the nim compiler."""

  def __init__ (self):
    super (NimCmd, self).__init__ ("nim",
                                   gdb.COMMAND_USER, gdb.COMPLETE_FILENAME)
    self.binary = os.path.join(
      os.path.dirname(os.path.dirname(__file__)), "bin/nim")

  def invoke(self, argument, from_tty):
    subprocess.run([self.binary] + gdb.string_to_argv(argument))

NimCmd()


class NimbleCmd (gdb.Command):
  """Command that invokes ``nimble'', the nim package manager and build tool."""

  def __init__ (self):
    super (NimbleCmd, self).__init__ ("nimble",
                                      gdb.COMMAND_USER, gdb.COMPLETE_FILENAME)
    self.binary = os.path.join(
      os.path.dirname(os.path.dirname(__file__)), "bin/nimble")

  def invoke(self, argument, from_tty):
    subprocess.run([self.binary] + gdb.string_to_argv(argument))

NimbleCmd()

################################################################################
#####  Value pretty printers
################################################################################

class NimBoolPrinter:

  pattern = re.compile(r'^NIM_BOOL$')

  def __init__(self, val):
    self.val = val

  def to_string(self):
    if self.val == 0:
      return "false"
    else:
      return "true"

################################################################################

def strFromLazy(strVal):
  if isinstance(strVal, str):
    return strVal
  else:
    return strVal.value().string("utf-8")

class NimStringPrinter:
  pattern = re.compile(r'^(NimStringDesc \*|NimStringV2)$')

  def __init__(self, val):
    self.val = val

  def display_hint(self):
    return 'string'

  def to_string(self):
    if self.val:
      if self.val.type.name == "NimStringV2":
        l = int(self.val["len"])
        data = self.val["p"]["data"]
      else:
        l = int(self.val['Sup']['len'])
        data = self.val["data"]
      return data.lazy_string(encoding="utf-8", length=l)
    else:
      return ""

  def __str__(self):
    return strFromLazy(self.to_string())

class NimRopePrinter:
  pattern = re.compile(r'^tyObject_RopeObj__([A-Za-z0-9]*) \*$')

  def __init__(self, val):
    self.val = val

  def display_hint(self):
    return 'string'

  def to_string(self):
    if self.val:
      left  = NimRopePrinter(self.val["left"]).to_string()
      data  = NimStringPrinter(self.val["data"]).to_string()
      right = NimRopePrinter(self.val["right"]).to_string()
      return left + data + right
    else:
      return ""


################################################################################

def reprEnum(e, typ):
  # Casts the value to the enum type and then calls the enum printer
  e = int(e)
  val = gdb.Value(e).cast(typ)
  return strFromLazy(NimEnumPrinter(val).to_string())

def enumNti(typeNimName, idString):
  typeInfoName = "NTI" + typeNimName.lower() + "__" + idString + "_"
  nti = gdb.lookup_global_symbol(typeInfoName)
  if nti is None:
    typeInfoName = "NTI" + "__" + idString + "_"
    nti = gdb.lookup_global_symbol(typeInfoName)
  return (typeInfoName, nti)

class NimEnumPrinter:
  pattern = re.compile(r'^tyEnum_([A-Za-z0-9]+)__([A-Za-z0-9]*)$')
  enumReprProc = gdb.lookup_global_symbol("reprEnum", gdb.SYMBOL_FUNCTION_DOMAIN)

  def __init__(self, val):
    self.val = val
    typeName = self.val.type.name
    match = self.pattern.match(typeName)
    self.typeNimName  = match.group(1)
    typeInfoName, self.nti = enumNti(self.typeNimName, match.group(2))

  def to_string(self):
    if NimEnumPrinter.enumReprProc and self.nti:
      # Use the old runtimes enumRepr function.
      # We call the Nim proc itself so that the implementation is correct
      f = gdb.newest_frame()
      # We need to strip the quotes so it looks like an enum instead of a string
      reprProc = NimEnumPrinter.enumReprProc.value()
      return str(reprProc(self.val, self.nti.value(f).address)).strip('"')
    elif dollarResult := DollarPrintFunction.invoke_static(self.val):
      # New runtime doesn't use enumRepr so we instead try and call the
      # dollar function for it
      return str(NimStringPrinter(dollarResult))
    else:
      return self.typeNimName + "(" + str(int(self.val)) + ")"

################################################################################

class NimSetPrinter:
  ## the set printer is limited to sets that fit in an integer.  Other
  ## sets are compiled to `NU8 *` (ptr uint8) and are invisible to
  ## gdb (currently).
  pattern = re.compile(r'^tySet_tyEnum_([A-Za-z0-9]+)__([A-Za-z0-9]*)$')

  def __init__(self, val):
    self.val = val
    typeName = self.val.type.name
    match = self.pattern.match(typeName)
    self.typeNimName = match.group(1)

  def to_string(self):
    # Remove the tySet from the type name
    typ = gdb.lookup_type(self.val.type.name[6:])
    enumStrings = []
    val = int(self.val)
    i   = 0
    while val > 0:
      if (val & 1) == 1:
        enumStrings.append(reprEnum(i, typ))
      val = val >> 1
      i += 1

    return '{' + ', '.join(enumStrings) + '}'

################################################################################

class NimHashSetPrinter:
  pattern = re.compile(r'^tyObject_(HashSet)__([A-Za-z0-9]*)$')

  def __init__(self, val):
    self.val = val

  def display_hint(self):
    return 'array'

  def to_string(self):
    counter  = 0
    capacity = 0
    if self.val:
      counter  = int(self.val['counter'])
      if self.val['data']:
        capacity = int(self.val['data']['Sup']['len'])

    return 'HashSet({0}, {1})'.format(counter, capacity)

  def children(self):
    if self.val:
      data = NimSeqPrinter(self.val['data'])
      for idxStr, entry in data.children():
        if int(entry['Field0']) > 0:
          yield ("data." + idxStr + ".Field1", str(entry['Field1']))

################################################################################

class NimSeq:
  # Wrapper around sequences.
  # This handles the differences between old and new runtime

  def __init__(self, val):
    self.val = val
    # new runtime has sequences on stack, old has them on heap
    self.new = val.type.code != gdb.TYPE_CODE_PTR
    if self.new:
      # Some seqs are just the content and to save repeating ourselves we do
      # handle them here. Only thing that needs to check this is the len/data getters
      self.isContent = val.type.name.endswith("Content")

  def __bool__(self):
    if self.new:
      return self.val is not None
    else:
      return bool(self.val)

  def __len__(self):
    if not self:
      return 0
    if self.new:
      if self.isContent:
        return int(self.val["cap"])
      else:
        return int(self.val["len"])
    else:
      return self.val["Sup"]["len"]

  @property
  def data(self):
    if self.new:
      if self.isContent:
        return self.val["data"]
      elif self.val["p"]:
        return self.val["p"]["data"]
    else:
      return self.val["data"]

  @property
  def cap(self):
    if not self:
      return 0
    if self.new:
      if self.isContent:
        return int(self.val["cap"])
      elif self.val["p"]:
        return int(self.val["p"]["cap"])
      else:
        return 0
    return int(self.val['Sup']['reserved'])

class NimSeqPrinter:
  pattern = re.compile(r'^tySequence_\w*\s?\*?$')

  def __init__(self, val):
    self.val = NimSeq(val)


  def display_hint(self):
    return 'array'

  def to_string(self):
    return f'seq({len(self.val)}, {self.val.cap})'

  def children(self):
    if self.val:
      val = self.val
      length = len(val)

      if length <= 0:
        return

      data = val.data

      inaccessible = False
      for i in range(length):
        if inaccessible:
          return
        try:
          str(data[i])
          yield "data[{0}]".format(i), data[i]
        except RuntimeError:
          inaccessible = True
          yield "data[{0}]".format(i), "inaccessible"
      
################################################################################

class NimArrayPrinter:
  pattern = re.compile(r'^tyArray_\w*$')

  def __init__(self, val):
    self.val = val

  def display_hint(self):
    return 'array'

  def to_string(self):
    return 'array'

  def children(self):
    length = self.val.type.sizeof // self.val[0].type.sizeof
    align = len(str(length-1))
    for i in range(length):
      yield ("[{0:>{1}}]".format(i, align), self.val[i])

################################################################################

class NimStringTablePrinter:
  pattern = re.compile(r'^tyObject_(StringTableObj)__([A-Za-z0-9]*)(:? \*)?$')

  def __init__(self, val):
    self.val = val

  def display_hint(self):
    return 'map'

  def to_string(self):
    counter  = 0
    capacity = 0
    if self.val:
      counter  = int(self.val['counter'])
      if self.val['data']:
        capacity = int(self.val['data']['Sup']['len'])

    return 'StringTableObj({0}, {1})'.format(counter, capacity)

  def children(self):
    if self.val:
      data = NimSeqPrinter(self.val['data'].referenced_value())
      for idxStr, entry in data.children():
        if int(entry['Field0']) != 0:
          yield (idxStr + ".Field0", entry['Field0'])
          yield (idxStr + ".Field1", entry['Field1'])

################################################################

class NimTablePrinter:
  pattern = re.compile(r'^tyObject_(Table)__([A-Za-z0-9]*)(:? \*)?$')

  def __init__(self, val):
    self.val = val

  def display_hint(self):
    return 'map'

  def to_string(self):
    counter  = 0
    capacity = 0
    if self.val:
      counter  = int(self.val['counter'])
      if self.val['data']:
        capacity = NimSeq(self.val["data"]).cap

    return 'Table({0}, {1})'.format(counter, capacity)

  def children(self):
    if self.val:
      data = NimSeqPrinter(self.val['data'])
      for idxStr, entry in data.children():
        if int(entry['Field0']) != 0:
          yield (idxStr + '.Field1', entry['Field1'])
          yield (idxStr + '.Field2', entry['Field2'])

################################################################################

class NimTuplePrinter:
  pattern = re.compile(r"^tyTuple__([A-Za-z0-9]*)")

  def __init__(self, val):
    self.val = val

  def to_string(self):
    # We don't have field names so just print out the tuple as if it was anonymous
    tupleValues = [str(self.val[field.name]) for field in self.val.type.fields()]
    return f"({', '.join(tupleValues)})"

################################################################################

class NimFrameFilter:
  def __init__(self):
    self.name = "nim-frame-filter"
    self.enabled = True
    self.priority = 100
    self.hidden =  {"NimMainInner","NimMain", "main"}

  def filter(self, iterator):
    for framedecorator in iterator:
      if framedecorator.function() not in self.hidden:
        yield framedecorator

################################################################################

def makematcher(klass):
  def matcher(val):
    typeName = str(val.type)
    try:
      if hasattr(klass, 'pattern') and hasattr(klass, '__name__'):
        # print(typeName + " <> " + klass.__name__)
        if klass.pattern.match(typeName):
          return klass(val)
    except Exception as e:
      print(klass)
      printErrorOnce(typeName, "No matcher for type '" + typeName + "': " + str(e) + "\n")
  return matcher

def register_nim_pretty_printers_for_object(objfile):
  nimMainSym = gdb.lookup_global_symbol("NimMain", gdb.SYMBOL_FUNCTION_DOMAIN)
  if nimMainSym and nimMainSym.symtab.objfile == objfile:
    print("set Nim pretty printers for ", objfile.filename)

    gdb.types.register_type_printer(objfile, NimTypePrinter())
    objfile.pretty_printers = [makematcher(var) for var in list(globals().values()) if hasattr(var, 'pattern')]

# Register pretty printers for all objfiles that are already loaded.
for old_objfile in gdb.objfiles():
  register_nim_pretty_printers_for_object(old_objfile)

# Register an event handler to register nim pretty printers for all future objfiles.
def new_object_handler(event):
  register_nim_pretty_printers_for_object(event.new_objfile)

gdb.events.new_objfile.connect(new_object_handler)

gdb.frame_filters = {"nim-frame-filter": NimFrameFilter()}
