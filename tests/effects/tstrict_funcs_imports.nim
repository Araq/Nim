discard """
  cmd: "nim $target $options --hints:on --experimental:strictFuncs --experimental:views --threads:on -d:ssl -d:nimCoroutines $file"
  targets: "c"
"""
{.warning[UnusedImport]: off.}

when defined(linux):
  import linenoise

when defined(nimPreviewSlimSystem):
  import std/[
    assertions,
    formatfloat,
    objectdollar,
    syncio,
    widestrs,
  ]

import
  algorithm,
  asyncdispatch,
  asyncfile,
  asyncfutures,
  asynchttpserver,
  asyncmacro,
  asyncnet,
  asyncstreams,
  atomics,
  base64,
  bitops,
  browsers,
  cgi,
  chains,
  colors,
  complex,
  cookies,
  coro,
  cpuinfo,
  cpuload,
  critbits,
  cstrutils,
  deques,
  distros,
  dynlib,
  encodings,
  endians,
  epoll,
  fenv,
  hashes,
  heapqueue,
  hotcodereloading,
  htmlgen,
  htmlparser,
  httpclient,
  httpcore,
  inotify,
  intsets,
  json,
  kqueue,
  lenientops,
  lexbase,
  lists,
  locks,
  logging,
  macrocache,
  macros,
  marshal,
  math,
  md5,
  memfiles,
  mersenne,
  mimetypes,
  nativesockets,
  net,
  nimhcr,
  # nimprof,
  nre,
  oids,
  options,
  os,
  osproc,
  parsecfg,
  parsecsv,
  parsejson,
  parseopt,
  parsesql,
  parseutils,
  parsexml,
  pathnorm,
  pegs,
  posix_utils,
  prelude,
  punycode,
  random,
  rationals,
  rdstdin,
  re,
  registry,
  reservedmem,
  rlocks,
  ropes,
  rtarrays,
  selectors,
  sequtils,
  sets,
  sharedlist,
  sharedtables,
  ssl_certs,
  ssl_config,
  stats,
  streams,
  streamwrapper,
  strformat,
  strmisc,
  strscans,
  strtabs,
  strutils,
  sugar,
  tables,
  terminal,
  threadpool,
  times,
  typeinfo,
  typetraits,
  unicode,
  unidecode,
  unittest,
  uri,
  volatile,
  winlean,
  xmlparser,
  xmltree

import experimental/[
  diff,
]

import packages/docutils/[
  highlite,
  rst,
  rstast,
  rstgen,
]

import std/[
  compilesettings,
  decls,
  editdistance,
  effecttraits,
  enumerate,
  enumutils,
  exitprocs,
  isolation,
  jsonutils,
  logic,
  monotimes,
  packedsets,
  setutils,
  sha1,
  socketstreams,
  stackframes,
  sums,
  time_t,
  varints,
  with,
  wordwrap,
  wrapnils,
]

import std/private/[
  asciitables,
  decode_helpers,
  gitutils,
  globs,
  miscdollars,
  since,
  strimpl,
  underscored_calls,
]
