when defined(nimNoQuit):
  proc rawQuit(errorcode: int = QuitSuccess) = discard "ignoring quit"

elif defined(genode):
  import genode/env

  var systemEnv {.exportc: runtimeEnvSym.}: GenodeEnvPtr

  type GenodeEnv = GenodeEnvPtr
    ## Opaque type representing Genode environment.

  proc rawQuit(env: GenodeEnv; errorcode: int) {.magic: "Exit", noreturn,
    importcpp: "#->parent().exit(@); Genode::sleep_forever()", header: "<base/sleep.h>".}

  proc rawQuit(errorcode: int = QuitSuccess) {.inline, noreturn.} =
    systemEnv.rawQuit(errorcode)


elif defined(js) and defined(nodejs) and not defined(nimscript):
  proc rawQuit(errorcode: int = QuitSuccess) {.magic: "Exit",
    importc: "process.exit", noreturn.}

else:
  proc rawQuit(errorcode: cint) {.
    magic: "Exit", importc: "exit", header: "<stdlib.h>", noreturn.}
