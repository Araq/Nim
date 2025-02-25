#
#
#           The Nim Compiler
#        (c) Copyright 2017 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Computes hash values for routine (proc, method etc) signatures.

import ast, ropes, modulegraphs, options, msgs, pathutils
from std/hashes import Hash
import std/tables
import types
import ../dist/checksums/src/checksums/md5


when defined(nimPreviewSlimSystem):
  import std/assertions


proc `&=`(c: var MD5Context, s: string) = md5Update(c, s, s.len)
proc `&=`(c: var MD5Context, ch: char) =
  # XXX suspicious code here; relies on ch being zero terminated?
  md5Update(c, cast[cstring](unsafeAddr ch), 1)

proc `&=`(c: var MD5Context, i: BiggestInt) =
  md5Update(c, cast[cstring](unsafeAddr i), sizeof(i))
proc `&=`(c: var MD5Context, f: BiggestFloat) =
  md5Update(c, cast[cstring](unsafeAddr f), sizeof(f))
proc `&=`(c: var MD5Context, s: SigHash) =
  md5Update(c, cast[cstring](unsafeAddr s), sizeof(s))
template lowlevel(v) =
  md5Update(c, cast[cstring](unsafeAddr(v)), sizeof(v))


type
  ConsiderFlag* = enum
    CoProc
    CoType
    CoOwnerSig
    CoIgnoreRange
    CoConsiderOwned
    CoDistinct
    CoHashTypeInsideNode

proc hashType(c: var MD5Context, t: PType; flags: set[ConsiderFlag]; conf: ConfigRef)
proc hashSym(c: var MD5Context, s: PSym) =
  if sfAnon in s.flags or s.kind == skGenericParam:
    c &= ":anon"
  else:
    var it = s
    while it != nil:
      c &= it.name.s
      c &= "."
      it = it.owner
    c &= "#"
    c &= s.disamb

proc hashTypeSym(c: var MD5Context, s: PSym; conf: ConfigRef) =
  if sfAnon in s.flags or s.kind == skGenericParam:
    c &= ":anon"
  else:
    var it = s
    c &= customPath(conf.toFullPath(s.info))
    while it != nil:
      if sfFromGeneric in it.flags and it.kind in routineKinds and
          it.typ != nil:
        hashType c, it.typ, {CoProc}, conf
      c &= it.name.s
      c &= "."
      it = it.owner
    c &= "#"
    c &= s.disamb

proc hashTree(c: var MD5Context, n: PNode; flags: set[ConsiderFlag]; conf: ConfigRef) =
  if n == nil:
    c &= "\255"
    return
  let k = n.kind
  c &= char(k)
  # we really must not hash line information. 'n.typ' is debatable but
  # shouldn't be necessary for now and avoids potential infinite recursions.
  case n.kind
  of nkEmpty, nkNilLit, nkType: discard
  of nkIdent:
    c &= n.ident.s
  of nkSym:
    hashSym(c, n.sym)
    if CoHashTypeInsideNode in flags and n.sym.typ != nil:
      hashType(c, n.sym.typ, flags, conf)
  of nkCharLit..nkUInt64Lit:
    let v = n.intVal
    lowlevel v
  of nkFloatLit..nkFloat64Lit:
    let v = n.floatVal
    lowlevel v
  of nkStrLit..nkTripleStrLit:
    c &= n.strVal
  else:
    for i in 0..<n.len: hashTree(c, n[i], flags, conf)

proc hashType(c: var MD5Context, t: PType; flags: set[ConsiderFlag]; conf: ConfigRef) =
  if t == nil:
    c &= "\254"
    return

  case t.kind
  of tyGenericInvocation:
    for a in t.kids:
      c.hashType a, flags, conf
  of tyDistinct:
    if CoDistinct in flags:
      if t.sym != nil: c.hashSym(t.sym)
      if t.sym == nil or tfFromGeneric in t.flags:
        c.hashType t.elementType, flags, conf
    elif CoType in flags or t.sym == nil:
      c.hashType t.elementType, flags, conf
    else:
      c.hashSym(t.sym)
  of tyGenericInst:
    if sfInfixCall in t.base.sym.flags:
      # This is an imported C++ generic type.
      # We cannot trust the `lastSon` to hold a properly populated and unique
      # value for each instantiation, so we hash the generic parameters here:
      let normalizedType = t.skipGenericAlias
      c.hashType normalizedType.genericHead, flags, conf
      for _, a in normalizedType.genericInstParams:
        c.hashType a, flags, conf
    else:
      c.hashType t.skipModifier, flags, conf
  of tyAlias, tySink, tyUserTypeClasses, tyInferred:
    c.hashType t.skipModifier, flags, conf
  of tyOwned:
    if CoConsiderOwned in flags:
      c &= char(t.kind)
    c.hashType t.skipModifier, flags, conf
  of tyBool, tyChar, tyInt..tyUInt64:
    # no canonicalization for integral types, so that e.g. ``pid_t`` is
    # produced instead of ``NI``:
    c &= char(t.kind)
    if t.sym != nil and {sfImportc, sfExportc} * t.sym.flags != {}:
      c.hashSym(t.sym)
  of tyObject, tyEnum:
    if t.typeInst != nil:
      # prevent against infinite recursions here, see bug #8883:
      let inst = t.typeInst
      t.typeInst = nil
      assert inst.kind == tyGenericInst
      c.hashType inst.genericHead, flags, conf
      for _, a in inst.genericInstParams:
        c.hashType a, flags, conf
      t.typeInst = inst
      return
    c &= char(t.kind)
    # Every cyclic type in Nim need to be constructed via some 't.sym', so this
    # is actually safe without an infinite recursion check:
    if t.sym != nil:
      if {sfCompilerProc} * t.sym.flags != {}:
        doAssert t.sym.loc.snippet != ""
        # The user has set a specific name for this type
        c &= t.sym.loc.snippet
      elif CoOwnerSig in flags:
        c.hashTypeSym(t.sym, conf)
      else:
        c.hashSym(t.sym)

      var symWithFlags: PSym = nil
      template hasFlag(sym): bool =
        let ret = {sfAnon, sfGenSym} * sym.flags != {}
        if ret: symWithFlags = sym
        ret
      if hasFlag(t.sym) or (t.kind == tyObject and t.owner.kind == skType and t.owner.typ.kind == tyRef and hasFlag(t.owner)):
        # for `PFoo:ObjectType`, arising from `type PFoo = ref object`
        # Generated object names can be identical, so we need to
        # disambiguate furthermore by hashing the field types and names.
        if t.n.len > 0:
          let oldFlags = symWithFlags.flags
          # Hack to prevent endless recursion
          # xxx instead, use a hash table to indicate we've already visited a type, which
          # would also be more efficient.
          symWithFlags.flags.excl {sfAnon, sfGenSym}
          hashTree(c, t.n, flags + {CoHashTypeInsideNode}, conf)
          symWithFlags.flags = oldFlags
        else:
          # The object has no fields: we _must_ add something here in order to
          # make the hash different from the one we produce by hashing only the
          # type name.
          c &= ".empty"
    else:
      c &= t.id
    if t.hasElementType and t.baseClass != nil:
      hashType c, t.baseClass, flags, conf
  of tyRef, tyPtr, tyVar:
    c &= char(t.kind)
    if t.hasElementType:
      c.hashType t.elementType, flags, conf
    if tfVarIsPtr in t.flags: c &= ".varisptr"
  of tyGenericBody:
    c &= char(t.kind)
    if t.hasElementType:
      c.hashType t.typeBodyImpl, flags, conf
  of tyFromExpr:
    c &= char(t.kind)
    c.hashTree(t.n, {}, conf)
  of tyTuple:
    c &= char(t.kind)
    if t.n != nil and CoType notin flags:
      for i in 0..<t.n.len:
        assert(t.n[i].kind == nkSym)
        c &= t.n[i].sym.name.s
        c &= ':'
        c.hashType(t.n[i].sym.typ, flags+{CoIgnoreRange}, conf)
        c &= ','
    else:
      for a in t.kids: c.hashType a, flags+{CoIgnoreRange}, conf
  of tyRange:
    if CoIgnoreRange notin flags:
      c &= char(t.kind)
      c.hashTree(t.n, {}, conf)
    c.hashType(t.elementType, flags, conf)
  of tyStatic:
    c &= char(t.kind)
    c.hashTree(t.n, {}, conf)
    c.hashType(t.skipModifier, flags, conf)
  of tyProc:
    c &= char(t.kind)
    c &= (if tfIterator in t.flags: "iterator " else: "proc ")
    if CoProc in flags and t.n != nil:
      let params = t.n
      for i in 1..<params.len:
        let param = params[i].sym
        c &= param.name.s
        c &= ':'
        c.hashType(param.typ, flags, conf)
        c &= ','
      c.hashType(t.returnType, flags, conf)
    else:
      for a in t.signature: c.hashType(a, flags, conf)
    c &= char(t.callConv)
    # purity of functions doesn't have to affect the mangling (which is in fact
    # problematic for HCR - someone could have cached a pointer to another
    # function which changes its purity and suddenly the cached pointer is danglign)
    # IMHO anything that doesn't affect the overload resolution shouldn't be part of the mangling...
    # if CoType notin flags:
    #   if tfNoSideEffect in t.flags: c &= ".noSideEffect"
    #   if tfThread in t.flags: c &= ".thread"
    if tfVarargs in t.flags: c &= ".varargs"
  of tyArray:
    c &= char(t.kind)
    c.hashType(t.indexType, flags-{CoIgnoreRange}, conf)
    c.hashType(t.elementType, flags-{CoIgnoreRange}, conf)
  else:
    c &= char(t.kind)
    for a in t.kids: c.hashType(a, flags, conf)
  if tfNotNil in t.flags and CoType notin flags: c &= "not nil"

when defined(debugSigHashes):
  import db_sqlite

  let db = open(connection="sighashes.db", user="araq", password="",
                database="sighashes")
  db.exec(sql"DROP TABLE IF EXISTS sighashes")
  db.exec sql"""CREATE TABLE sighashes(
    id integer primary key,
    hash varchar(5000) not null,
    type varchar(5000) not null,
    unique (hash, type))"""
  #  select hash, type from sighashes where hash in
  # (select hash from sighashes group by hash having count(*) > 1) order by hash;

proc hashType*(t: PType; conf: ConfigRef; flags: set[ConsiderFlag] = {CoType}): SigHash =
  result = default(SigHash)
  var c: MD5Context = default(MD5Context)
  md5Init c
  hashType c, t, flags+{CoOwnerSig}, conf
  md5Final c, result.MD5Digest
  when defined(debugSigHashes):
    db.exec(sql"INSERT OR IGNORE INTO sighashes(type, hash) VALUES (?, ?)",
            typeToString(t), $result)

proc hashProc(s: PSym; conf: ConfigRef): SigHash =
  result = default(SigHash)
  var c: MD5Context = default(MD5Context)
  md5Init c
  hashType c, s.typ, {CoProc}, conf

  var m = s
  while m.kind != skModule: m = m.owner
  let p = m.owner
  assert p.kind == skPackage
  c &= p.name.s
  c &= "."
  c &= m.name.s
  if sfDispatcher in s.flags:
    c &= ".dispatcher"
  # so that createThread[void]() (aka generic specialization) gets a unique
  # hash, we also hash the line information. This is pretty bad, but the best
  # solution for now:
  #c &= s.info.line
  md5Final c, result.MD5Digest

proc hashNonProc*(s: PSym): SigHash =
  result = default(SigHash)
  var c: MD5Context = default(MD5Context)
  md5Init c
  hashSym(c, s)
  var it = s
  while it != nil:
    c &= it.name.s
    c &= "."
    it = it.owner
  # for bug #5135 we also take the position into account, but only
  # for parameters, because who knows what else position dependency
  # might cause:
  if s.kind == skParam:
    c &= s.position
  md5Final c, result.MD5Digest

proc hashOwner*(s: PSym): SigHash =
  result = default(SigHash)
  var c: MD5Context = default(MD5Context)
  md5Init c
  var m = s
  while m.kind != skModule: m = m.owner
  let p = m.owner
  assert p.kind == skPackage
  c &= p.name.s
  c &= "."
  c &= m.name.s

  md5Final c, result.MD5Digest

proc sigHash*(s: PSym; conf: ConfigRef): SigHash =
  if s.kind in routineKinds and s.typ != nil:
    result = hashProc(s, conf)
  else:
    result = hashNonProc(s)

proc symBodyDigest*(graph: ModuleGraph, sym: PSym): SigHash

proc hashBodyTree(graph: ModuleGraph, c: var MD5Context, n: PNode)

proc hashVarSymBody(graph: ModuleGraph, c: var MD5Context, s: PSym) =
  assert: s.kind in {skParam, skResult, skVar, skLet, skConst, skForVar}
  if sfGlobal notin s.flags:
    c &= char(s.kind)
    c &= s.name.s
  else:
    c &= hashNonProc(s)
    # this one works for let and const but not for var. True variables can change value
    # later on. it is user resposibility to hash his global state if required
    if s.ast != nil and s.ast.kind in {nkIdentDefs, nkConstDef}:
      hashBodyTree(graph, c, s.ast[^1])
    else:
      hashBodyTree(graph, c, s.ast)

proc hashBodyTree(graph: ModuleGraph, c: var MD5Context, n: PNode) =
  # hash Nim tree recursing into simply
  if n == nil:
    c &= "nil"
    return
  c &= char(n.kind)
  case n.kind
  of nkEmpty, nkNilLit, nkType: discard
  of nkIdent:
    c &= n.ident.s
  of nkSym:
    if n.sym.kind in skProcKinds:
      c &= symBodyDigest(graph, n.sym)
    elif n.sym.kind in {skParam, skResult, skVar, skLet, skConst, skForVar}:
      hashVarSymBody(graph, c, n.sym)
    else:
      c &= hashNonProc(n.sym)
  of nkProcDef, nkFuncDef, nkTemplateDef, nkMacroDef:
    discard # we track usage of proc symbols not their definition
  of nkCharLit..nkUInt64Lit:
    c &= n.intVal
  of nkFloatLit..nkFloat64Lit:
    c &= n.floatVal
  of nkStrLit..nkTripleStrLit:
    c &= n.strVal
  else:
    for i in 0..<n.len:
      hashBodyTree(graph, c, n[i])

proc symBodyDigest*(graph: ModuleGraph, sym: PSym): SigHash =
  ## compute unique digest of the proc/func/method symbols
  ## recursing into invoked symbols as well
  assert(sym.kind in skProcKinds, $sym.kind)
  result = default(SigHash)
  graph.symBodyHashes.withValue(sym.id, value):
    return value[]

  var c: MD5Context = default(MD5Context)
  md5Init(c)
  c.hashType(sym.typ, {CoProc}, graph.config)
  c &= char(sym.kind)
  c.md5Final(result.MD5Digest)
  graph.symBodyHashes[sym.id] = result # protect from recursion in the body

  if sym.ast != nil:
    md5Init(c)
    c.md5Update(cast[cstring](result.addr), sizeof(result))
    hashBodyTree(graph, c, getBody(graph, sym))
    c.md5Final(result.MD5Digest)
    graph.symBodyHashes[sym.id] = result

proc idOrSig*(s: PSym, currentModule: string,
              sigCollisions: var CountTable[SigHash]; conf: ConfigRef): Rope =
  if s.kind in routineKinds and s.typ != nil:
    # signatures for exported routines are reliable enough to
    # produce a unique name and this means produced C++ is more stable regarding
    # Nim changes:
    let sig = hashProc(s, conf)
    result = rope($sig)
    #let m = if s.typ.callConv != ccInline: findPendingModule(m, s) else: m
    let counter = sigCollisions.getOrDefault(sig)
    #if sigs == "_jckmNePK3i2MFnWwZlp6Lg" and s.name.s == "contains":
    #  echo "counter ", counter, " ", s.id
    if counter != 0:
      result.add "_" & rope(counter+1)
    # this minor hack is necessary to make tests/collections/thashes compile.
    # The inlined hash function's original module is ambiguous so we end up
    # generating duplicate names otherwise:
    if s.typ.callConv == ccInline:
      result.add rope(currentModule)
    sigCollisions.inc(sig)
  else:
    let sig = hashNonProc(s)
    result = rope($sig)
    let counter = sigCollisions.getOrDefault(sig)
    if counter != 0:
      result.add "_" & rope(counter+1)
    sigCollisions.inc(sig)

