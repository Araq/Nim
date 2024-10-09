##[
## note 1
`useHead` should ideally be used as the default but lots of packages (e.g. `chronos`)
don't have release tags (or have really old ones compared to HEAD), making it
impossible to test them reliably here.

packages listed here should ideally have regularly updated release tags, so that:
* we're testing recent versions of the package
* the version that's tested is stable enough even if HEAD may occasionally break

## note 2: D20210308T165435:here
nimble packages should be testable as follows:
git clone $url $dir && cd $dir
NIMBLE_DIR=$TMP_NIMBLE_DIR XDG_CONFIG_HOME= nimble install --depsOnly -y
NIMBLE_DIR=$TMP_NIMBLE_DIR XDG_CONFIG_HOME= nimble test

if this fails (e.g. nimcrypto), it could be because a package lacks a `tests/nim.cfg` with `--path:..`,
so the above commands would've worked by accident with `nimble install` but not with `nimble install --depsOnly`.
When this is the case, a workaround is to test this package here by adding `--path:$srcDir` on the test `cmd`.
]##

type NimblePackage* = object
  name*, cmd*, url*: string
  useHead*: bool
  allowFailure*: bool
    ## When true, we still run the test but the test is allowed to fail.
    ## This is useful for packages that currently fail but that we still want to
    ## run in CI, e.g. so that we can monitor when they start working again and
    ## are reminded about those failures without making CI fail for unrelated PRs.

var packages*: seq[NimblePackage]

proc pkg(name: string; cmd = "nimble test"; url = "", useHead = true, allowFailure = false) =
  packages.add NimblePackage(name: name, cmd: cmd, url: url, useHead: useHead, allowFailure: allowFailure)

pkg "alea"
pkg "argparse"
pkg "arraymancer", "nim c tests/tests_cpu.nim"
pkg "ast_pattern_matching", "nim c -r tests/test1.nim"
pkg "asyncftpclient", "nimble compileExample"
pkg "asyncthreadpool", "nimble test --mm:refc"
pkg "awk"
pkg "bigints"
pkg "binaryheap", "nim c -r binaryheap.nim"
pkg "BipBuffer"
pkg "blscurve", allowFailure = true
pkg "bncurve"
pkg "brainfuck", "nim c -d:release -r tests/compile.nim"
pkg "bump", "nim c --mm:arc --path:. -r tests/tbump.nim", "https://github.com/disruptek/bump", allowFailure = true
pkg "c2nim", "nim c testsuite/tester.nim"
pkg "cascade"
pkg "cello", url = "https://github.com/nim-lang/cello", useHead = true
pkg "checksums"
pkg "chroma"
pkg "chronicles", "nim c -o:chr -r chronicles.nim"
pkg "chronos", "nim c -r -d:release tests/testall"
pkg "cligen", "nim c --path:. -r cligen.nim"
pkg "combparser", "nimble test --mm:orc"
pkg "compactdict"
pkg "comprehension", "nimble test", "https://github.com/alehander92/comprehension"
pkg "constantine", "nimble make_lib"
pkg "cowstrings"
pkg "criterion", allowFailure = true # needs testing binary
pkg "datamancer", url = "https://github.com/nim-lang/Datamancer"
pkg "dashing", "nim c tests/functional.nim"
pkg "delaunay"
pkg "dnsclient", allowFailure = true # super fragile
pkg "docopt"
pkg "dotenv"
# when defined(linux): pkg "drchaos"
pkg "easygl", "nim c -o:egl -r src/easygl.nim", "https://github.com/jackmott/easygl"
pkg "elvis"
pkg "faststreams"
pkg "fidget"
pkg "fragments", "nim c -r fragments/dsl.nim", allowFailure = true # pending https://github.com/nim-lang/packages/issues/2115 
pkg "fusion"
pkg "gara"
pkg "glob"
pkg "ggplotnim", "nim c -d:noCairo -r tests/tests.nim"
pkg "gittyup", "nimble test", "https://github.com/disruptek/gittyup", allowFailure = true
pkg "gnuplot", "nim c gnuplot.nim"
# pkg "gram", "nim c -r --mm:arc --define:danger tests/test.nim", "https://github.com/disruptek/gram"
  # pending https://github.com/nim-lang/Nim/issues/16509
pkg "hts", "nim c -o:htss src/hts.nim"
pkg "httpauth"
pkg "httputils"
pkg "illwill", "nimble examples"
pkg "inim"
pkg "itertools", "nim doc src/itertools.nim"
pkg "iterutils"
pkg "json_rpc"
pkg "json_serialization"
pkg "jstin"
pkg "karax", "nim c -r tests/tester.nim"
pkg "kdtree", "nimble test -d:nimLegacyRandomInitRand", "https://github.com/jblindsay/kdtree"
pkg "loopfusion"
pkg "lockfreequeues"
pkg "macroutils"
pkg "manu"
pkg "markdown"
pkg "measuremancer", "nimble testDeps; nimble -y test"
pkg "memo"
pkg "msgpack4nim", "nim c -r tests/test_spec.nim"
pkg "nake", "nim c nakefile.nim"
pkg "neo", "nim c -d:blas=openblas --mm:refc tests/all.nim"
pkg "nesm", "nimble tests", "https://github.com/nim-lang/NESM", useHead = true, allowFailure = true
  # inactive, tests not adapted to #23096
pkg "netty"
pkg "nico", allowFailure = true
pkg "nicy", "nim c -r src/nicy.nim"
when defined(osx):
  # gives "could not load: libgtk-3.0.dylib" on macos 13
  # just test compiling instead of running
  pkg "nigui", "nim c -o:niguii src/nigui.nim"
else:
  pkg "nigui", "nim c -o:niguii -r src/nigui.nim"
pkg "nimcrypto", "nim r --path:. tests/testall.nim" # `--path:.` workaround needed, see D20210308T165435
pkg "NimData", "nim c -o:nimdataa src/nimdata.nim"
pkg "nimes", "nim c src/nimes.nim"
pkg "nimfp", "nim c -o:nfp -r src/fp.nim"
pkg "nimgame2", "nim c --mm:refc nimgame2/nimgame.nim"
pkg "nimgen", "nim c -o:nimgenn -r src/nimgen/runcfg.nim"
pkg "nimib"
pkg "nimlsp"
pkg "nimly", "nim c -r tests/test_readme_example.nim"
pkg "nimongo", "nimble test_ci", allowFailure = true
pkg "nimph", "nimble test", "https://github.com/disruptek/nimph", allowFailure = true
pkg "nimPNG", useHead = true
pkg "nimpy", "nim c -r tests/nimfrompy.nim"
pkg "nimquery"
pkg "nimsl"
pkg "nimsvg"
pkg "nimterop", "nimble minitest", url = "https://github.com/nim-lang/nimterop"
pkg "nimwc", "nim c nimwc.nim"
pkg "nimx", "nim c test/main.nim", allowFailure = true
pkg "nitter", "nim c src/nitter.nim", "https://github.com/zedeus/nitter"
pkg "norm", "testament r tests/common/tmodel.nim"
pkg "normalize"
pkg "npeg", "nimble testarc"
pkg "numericalnim", "nimble nimCI"
pkg "optionsutils"
pkg "ormin", "nim c -o:orminn ormin.nim"
pkg "parsetoml"
pkg "patty"
pkg "pixie"
pkg "plotly", "nim c examples/all.nim"
pkg "pnm"
pkg "polypbren"
pkg "presto"
pkg "prologue", "nimble tcompile"
# remove fork after https://github.com/PMunch/combparser/pull/7 is merged:
pkg "protobuf", "nimble uninstall -i -y combparser; nimble install -y https://github.com/metagn/combparser@#HEAD; nimble install --depsOnly -y; nim c -o:protobuff -r src/protobuf.nim"
pkg "rbtree"
pkg "react", "nimble example"
pkg "regex", "nim c src/regex"
pkg "results", "nim c -r results.nim"
pkg "RollingHash", "nim c -r tests/test_cyclichash.nim"
pkg "rosencrantz", "nim c -o:rsncntz -r rosencrantz.nim"
pkg "sdl1", "nim c -r src/sdl.nim"
pkg "sdl2_nim", "nim c -r sdl2/sdl.nim"
pkg "serialization"
pkg "sigv4", "nim c --mm:arc -r sigv4.nim", "https://github.com/disruptek/sigv4"
pkg "sim"
pkg "smtp", "nimble compileExample"
pkg "snip", "nimble test", "https://github.com/genotrance/snip"
pkg "ssostrings"
pkg "stew"
pkg "stint", "nim c stint.nim"
pkg "strslice"
pkg "strunicode", "nim c -r --mm:refc src/strunicode.nim"
pkg "supersnappy"
pkg "synthesis"
pkg "taskpools"
pkg "telebot", "nim c -o:tbot -r src/telebot.nim"
pkg "tempdir"
pkg "templates"
pkg "tensordsl", "nim c -r --mm:refc tests/tests.nim", "https://krux02@bitbucket.org/krux02/tensordslnim.git"
pkg "terminaltables", "nim c src/terminaltables.nim"
pkg "termstyle", "nim c -r termstyle.nim"
pkg "testutils"
pkg "timeit"
pkg "timezones"
pkg "tiny_sqlite"
pkg "unicodedb", "nim c -d:release -r tests/tests.nim"
pkg "unicodeplus", "nim c -d:release -r tests/tests.nim"
pkg "union", "nim c -r tests/treadme.nim", url = "https://github.com/alaviss/union"
pkg "unittest2"
pkg "unpack"
pkg "weave", "nimble install -y cligen@#HEAD; nimble test_gc_arc", useHead = true
pkg "websock"
pkg "websocket", "nim c websocket.nim"
# pkg "winim", allowFailure = true
pkg "with"
pkg "ws", allowFailure = true
pkg "yaml"
pkg "zero_functional", "nim c -r test.nim"
pkg "zippy"
pkg "zxcvbn"
