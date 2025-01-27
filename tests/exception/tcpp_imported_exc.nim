discard """
matrix: "--mm:refc"
targets: "cpp"
output: '''
caught as std::exception
expected
finally1
finally2
finally2
2
expected
finally 1
finally 2
expected
cpp exception caught
'''
# doesn't work on macos 13 seemingly due to libc++ linking issue https://stackoverflow.com/a/77375947
disabled: osx
"""

type
  std_exception* {.importcpp: "std::exception", header: "<exception>".} = object
  std_runtime_error* {.importcpp: "std::runtime_error", header: "<stdexcept>".} = object
  std_string* {.importcpp: "std::string", header: "<string>".} = object

proc constructStdString(s: cstring): std_string {.importcpp: "std::string(@)", constructor, header: "<string>".}

proc constructRuntimeError(s: stdstring): std_runtime_error {.importcpp: "std::runtime_error(@)", constructor.}

proc what(ex: std_runtime_error): cstring {.importcpp: "((char *)#.what())".}

proc myexception =
  raise constructRuntimeError(constructStdString("cpp_exception"))

try:
  myexception() # raise std::runtime_error
except std_exception:
  echo "caught as std::exception"
  try:
    raise constructStdString("x")
  except std_exception:
    echo "should not happen"
  except:
    echo "expected"

doAssert(getCurrentException() == nil)

proc earlyReturn =
  try:
    try:
      myexception()
    finally:
      echo "finally1"
  except:
    return
  finally:
    echo "finally2"

earlyReturn()
doAssert(getCurrentException() == nil)


try:
  block blk1:
    try:
      raise newException(ValueError, "mmm")
    except:
      break blk1
except:
  echo "should not happen"
finally:
  echo "finally2"

doAssert(getCurrentException() == nil)

#--------------------------------------

# raise by pointer and also generic type

type
  std_vector[T] {.importcpp"std::vector", header"<vector>".} = object

proc newVector[T](len: int): ptr std_vector[T] {.importcpp: "new std::vector<'1>(@)".}
proc deleteVector[T](v: ptr std_vector[T]) {.importcpp: "delete @; @ = NIM_NIL;".}
proc len[T](v: std_vector[T]): uint {.importcpp: "size".}

var v = newVector[int](2)
try:
  try:
    try:
      raise v
    except ptr std_vector[int] as ex:
      echo len(ex[])
      raise newException(ValueError, "msg5")
    except:
      echo "should not happen"
  finally:
    deleteVector(v)
except:
  echo "expected"

doAssert(v == nil)
doAssert(getCurrentException() == nil)

#--------------------------------------

# mix of Nim and imported exceptions
try:
  try:
    try:
      raise newException(KeyError, "msg1")
    except KeyError:
      raise newException(ValueError, "msg2")
    except:
      echo "should not happen"
    finally:
      echo "finally 1"
  except:
    doAssert(getCurrentExceptionMsg() == "msg2")
    raise constructStdString("std::string")
  finally:
    echo "finally 2"
except:
  echo "expected"

doAssert(getCurrentException() == nil)

try:
  try:
    myexception()
  except std_runtime_error as ex:
    echo "cpp exception caught"
    raise newException(ValueError, "rewritten " & $ex.what())
except:
  doAssert(getCurrentExceptionMsg() == "rewritten cpp_exception")

doAssert(getCurrentException() == nil)
