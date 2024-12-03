# tests v3 outline

type
  Foo* = ref object of RootObj
    bar*: string
  FooEnum = enum value1, value2
  FooPrivate = ref object of RootObj
    barPrivate: string

macro m(arg: untyped): untyped = discard
template t(arg: untyped): untyped = discard
proc p(): void = discard
iterator i(): int = discard
converter c(s: string): int = discard
method m(f: Foo): void = discard
func f(): void = discard

let a = 1
var b = 2
const con = 2

proc outer(): void =
  proc inner() = discard

proc procWithLocal(): void =
  let local = 10

discard """
$nimsuggest --v3 --tester $file
>outline $file
outline	skType	tv3_outline.Foo	Foo	$file	4	2	""	100	5	16
outline	skType	tv3_outline.FooEnum	FooEnum	$file	6	2	""	100	6	31
outline	skEnumField	tv3_outline.FooEnum.value1	FooEnum	$file	6	17	""	100	6	23
outline	skEnumField	tv3_outline.FooEnum.value2	FooEnum	$file	6	25	""	100	6	31
outline	skType	tv3_outline.FooPrivate	FooPrivate	$file	7	2	""	100	8	22
outline	skMacro	tv3_outline.m	macro (arg: untyped): untyped{.noSideEffect, gcsafe, raises: <inferred> [].}	$file	10	6	""	100	10	40
outline	skTemplate	tv3_outline.t	template (arg: untyped): untyped	$file	11	9	""	100	11	43
outline	skProc	tv3_outline.p	proc (){.noSideEffect, gcsafe, raises: <inferred> [].}	$file	12	5	""	100	12	24
outline	skConverter	tv3_outline.c	converter (s: string): int{.noSideEffect, gcsafe, raises: <inferred> [].}	$file	14	10	""	100	14	37
outline	skFunc	tv3_outline.f	proc (){.noSideEffect, gcsafe, raises: <inferred> [].}	$file	16	5	""	100	16	24
outline	skConst	tv3_outline.con	int literal(2)	$file	20	6	""	100	20	13
outline	skProc	tv3_outline.outer	proc (){.noSideEffect, gcsafe, raises: <inferred> [].}	$file	22	5	""	100	23	24
outline	skProc	tv3_outline.outer.inner	proc (){.noSideEffect, gcsafe, raises: <inferred> [].}	$file	23	7	""	100	23	24
outline	skProc	tv3_outline.procWithLocal	proc (){.noSideEffect, gcsafe, raises: <inferred> [].}	$file	25	5	""	100	26	16
"""
