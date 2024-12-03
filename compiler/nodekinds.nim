#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## NodeKind enum.

type
  TNodeKind* = enum # order is extremely important, because ranges are used
                    # to check whether a node belongs to a certain class
    nkNone,               # unknown node kind: indicates an error
                          # Expressions:
                          # Atoms:
    nkEmpty,              # the node is empty
    nkIdent,              # node is an identifier
    nkSym,                # node is a symbol
    nkType,               # node is used for its typ field

    nkCharLit,            # a character literal ''
    nkIntLit,             # an integer literal
    nkInt8Lit,
    nkInt16Lit,
    nkInt32Lit,
    nkInt64Lit,
    nkUIntLit,            # an unsigned integer literal
    nkUInt8Lit,
    nkUInt16Lit,
    nkUInt32Lit,
    nkUInt64Lit,
    nkFloatLit,           # a floating point literal
    nkFloat32Lit,
    nkFloat64Lit,
    nkFloat128Lit,
    nkStrLit,             # a string literal ""
    nkRStrLit,            # a raw string literal r""
    nkTripleStrLit,       # a triple string literal """
    nkNilLit,             # the nil literal
                          # end of atoms
    nkComesFrom,          # "comes from" template/macro information for
                          # better stack trace generation
    nkDotCall,            # used to temporarily flag a nkCall node;
                          # this is used
                          # for transforming ``s.len`` to ``len(s)``

    nkCommand,            # a call like ``p 2, 4`` without parenthesis
    nkCall,               # a call like p(x, y) or an operation like +(a, b)
    nkCallStrLit,         # a call with a string literal
                          # x"abc" has two sons: nkIdent, nkRStrLit
                          # x"""abc""" has two sons: nkIdent, nkTripleStrLit
    nkInfix,              # a call like (a + b)
    nkPrefix,             # a call like !a
    nkPostfix,            # something like a! (also used for visibility)
    nkHiddenCallConv,     # an implicit type conversion via a type converter

    nkExprEqExpr,         # a named parameter with equals: ''expr = expr''
    nkExprColonExpr,      # a named parameter with colon: ''expr: expr''
    nkIdentDefs,          # a definition like `a, b: typeDesc = expr`
                          # either typeDesc or expr may be nil; used in
                          # formal parameters, var statements, etc.
    nkVarTuple,           # a ``var (a, b) = expr`` construct
    nkPar,                # syntactic (); may be a tuple constructor
    nkObjConstr,          # object constructor: T(a: 1, b: 2)
    nkCurly,              # syntactic {}
    nkCurlyExpr,          # an expression like a{i}
    nkBracket,            # syntactic []
    nkBracketExpr,        # an expression like a[i..j, k]
    nkPragmaExpr,         # an expression like a{.pragmas.}
    nkRange,              # an expression like i..j
    nkDotExpr,            # a.b
    nkCheckedFieldExpr,   # a.b, but b is a field that needs to be checked
    nkDerefExpr,          # a^
    nkIfExpr,             # if as an expression
    nkElifExpr,
    nkElseExpr,
    nkLambda,             # lambda expression
    nkDo,                 # lambda block appering as trailing proc param
    nkAccQuoted,          # `a` as a node

    nkTableConstr,        # a table constructor {expr: expr}
    nkBind,               # ``bind expr`` node
    nkClosedSymChoice,    # symbol choice node; a list of nkSyms (closed)
    nkOpenSymChoice,      # symbol choice node; a list of nkSyms (open)
    nkHiddenStdConv,      # an implicit standard type conversion
    nkHiddenSubConv,      # an implicit type conversion from a subtype
                          # to a supertype
    nkConv,               # a type conversion
    nkCast,               # a type cast
    nkStaticExpr,         # a static expr
    nkAddr,               # a addr expression
    nkHiddenAddr,         # implicit address operator
    nkHiddenDeref,        # implicit ^ operator
    nkObjDownConv,        # down conversion between object types
    nkObjUpConv,          # up conversion between object types
    nkChckRangeF,         # range check for floats
    nkChckRange64,        # range check for 64 bit ints
    nkChckRange,          # range check for ints
    nkStringToCString,    # string to cstring
    nkCStringToString,    # cstring to string
                          # end of expressions

    nkAsgn,               # a = b
    nkFastAsgn,           # internal node for a fast ``a = b``
                          # (no string copy)
    nkGenericParams,      # generic parameters
    nkFormalParams,       # formal parameters
    nkOfInherit,          # inherited from symbol

    nkImportAs,           # a 'as' b in an import statement
    nkProcDef,            # a proc
    nkMethodDef,          # a method
    nkConverterDef,       # a converter
    nkMacroDef,           # a macro
    nkTemplateDef,        # a template
    nkIteratorDef,        # an iterator

    nkOfBranch,           # used inside case statements
                          # for (cond, action)-pairs
    nkElifBranch,         # used in if statements
    nkExceptBranch,       # an except section
    nkElse,               # an else part
    nkAsmStmt,            # an assembler block
    nkPragma,             # a pragma statement
    nkPragmaBlock,        # a pragma with a block
    nkIfStmt,             # an if statement
    nkWhenStmt,           # a when expression or statement
    nkForStmt,            # a for statement
    nkParForStmt,         # a parallel for statement
    nkWhileStmt,          # a while statement
    nkCaseStmt,           # a case statement
    nkTypeSection,        # a type section (consists of type definitions)
    nkVarSection,         # a var section
    nkLetSection,         # a let section
    nkConstSection,       # a const section
    nkConstDef,           # a const definition
    nkTypeDef,            # a type definition
    nkYieldStmt,          # the yield statement as a tree
    nkDefer,              # the 'defer' statement
    nkTryStmt,            # a try statement
    nkFinally,            # a finally section
    nkRaiseStmt,          # a raise statement
    nkReturnStmt,         # a return statement
    nkBreakStmt,          # a break statement
    nkContinueStmt,       # a continue statement
    nkBlockStmt,          # a block statement
    nkStaticStmt,         # a static statement
    nkDiscardStmt,        # a discard statement
    nkStmtList,           # a list of statements
    nkImportStmt,         # an import statement
    nkImportExceptStmt,   # an import x except a statement
    nkExportStmt,         # an export statement
    nkExportExceptStmt,   # an 'export except' statement
    nkFromStmt,           # a from * import statement
    nkIncludeStmt,        # an include statement
    nkBindStmt,           # a bind statement
    nkMixinStmt,          # a mixin statement
    nkUsingStmt,          # an using statement
    nkCommentStmt,        # a comment statement
    nkStmtListExpr,       # a statement list followed by an expr; this is used
                          # to allow powerful multi-line templates
    nkBlockExpr,          # a statement block ending in an expr; this is used
                          # to allow powerful multi-line templates that open a
                          # temporary scope
    nkStmtListType,       # a statement list ending in a type; for macros
    nkBlockType,          # a statement block ending in a type; for macros
                          # types as syntactic trees:

    nkWith,               # distinct with `foo`
    nkWithout,            # distinct without `foo`

    nkTypeOfExpr,         # type(1+2)
    nkObjectTy,           # object body
    nkTupleTy,            # tuple body
    nkTupleClassTy,       # tuple type class
    nkTypeClassTy,        # user-defined type class
    nkStaticTy,           # ``static[T]``
    nkRecList,            # list of object parts
    nkRecCase,            # case section of object
    nkRecWhen,            # when section of object
    nkRefTy,              # ``ref T``
    nkPtrTy,              # ``ptr T``
    nkVarTy,              # ``var T``
    nkConstTy,            # ``const T``
    nkOutTy,              # ``out T``
    nkDistinctTy,         # distinct type
    nkProcTy,             # proc type
    nkIteratorTy,         # iterator type
    nkSinkAsgn,           # '=sink(x, y)'
    nkEnumTy,             # enum body
    nkEnumFieldDef,       # `ident = expr` in an enumeration
    nkArgList,            # argument list
    nkPattern,            # a special pattern; used for matching
    nkHiddenTryStmt,      # a hidden try statement
    nkClosure,            # (prc, env)-pair (internally used for code gen)
    nkGotoState,          # used for the state machine (for iterators)
    nkState,              # give a label to a code section (for iterators)
    nkBreakState,         # special break statement for easier code generation
    nkFuncDef,            # a func
    nkTupleConstr         # a tuple constructor
    nkError               # erroneous AST node
    nkModuleRef           # for .rod file support: A (moduleId, itemId) pair
    nkReplayAction        # for .rod file support: A replay action
    nkNilRodNode          # for .rod file support: a 'nil' PNode
    nkOpenSym             # container for captured sym that can be overriden by local symbols

const
  nkCallKinds* = {nkCall, nkInfix, nkPrefix, nkPostfix,
                  nkCommand, nkCallStrLit, nkHiddenCallConv}
