import ast except elementType
import idents, lineinfos, astalgo
import vmdef
import std/times

template elementType*(T: typedesc): typedesc =
  typeof(block:
    var a: T
    for ai in a: ai)

proc fromLit*(a: PNode, T: typedesc): auto =
  ## generic PNode => type
  ## see also reverse operation `toLit`
  when T is set:
    result = default(T)
    type Ti = elementType(T)
    for ai in a:
      result.incl Ti(ai.intVal)
  else:
    static: raiseAssert "not yet supported: " & $T # add as needed

proc toLit*[T](a: T): PNode =
  ## generic type => PNode
  ## see also reverse operation `fromLit`
  when T is string: newStrNode(nkStrLit, a)
  elif T is Ordinal: newIntNode(nkIntLit, a.ord)
  elif T is (proc): newNode(nkNilLit)
  elif T is ref:
    if a == nil: newNode(nkNilLit)
    else: toLit(a[])
  elif T is tuple:
    result = newTree(nkTupleConstr)
    for ai in fields(a): result.add toLit(ai)
  elif T is seq:
    result = newNode(nkBracket)
    for ai in a:
      result.add toLit(ai)
  elif T is object:
    result = newTree(nkObjConstr)
    result.add(newNode(nkEmpty))
    for k, ai in fieldPairs(a):
      let reti = newNode(nkExprColonExpr)
      reti.add k.toLit
      reti.add ai.toLit
      result.add reti
  else:
    static: raiseAssert "not yet supported: " & $T # add as needed

proc toTimeLit*(a: Time, c: PCtx, obj: PNode, info: TLineInfo): PNode =
  # probably refactor it into `toLit` in the future
  result = newTree(nkObjConstr)
  result.add(newNode(nkEmpty)) # can be changed to a symbol according to PType
  for k, ai in fieldPairs(a):
    let reti = newNode(nkExprColonExpr)
    reti.add newSymNode(lookupInRecord(obj, getIdent(c.cache, k)), info)
    reti.add ai.toLit
    result.add reti
