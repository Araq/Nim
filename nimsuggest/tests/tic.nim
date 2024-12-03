import std/[appdirs, assertions, cmdline, compilesettings, decls, 
  dirs, editdistance, effecttraits, enumerate, enumutils, envvars, 
  exitprocs, files, formatfloat, genasts, importutils, 
  isolation, jsonutils, logic, monotimes, objectdollar, 
  oserrors, outparams, packedsets, paths, private, setutils, sha1, 
  socketstreams, stackframes, staticos, strbasics, symlinks, syncio, 
  sysatomics, sysrand, tasks, tempfiles, time_t, typedthreads, varints, 
  vmutils, widestrs, with, wordwrap, wrapnils]

proc test(a: string, b:string) = discard
proc test(a: int) = discard

test(#[!]#

discard """
$nimsuggest --v3 --ic:off --tester $file 
>con $1
con;;skProc;;tic.test;;proc (a: string, b: string);;$file;;10;;5;;"";;100
con;;skProc;;tic.test;;proc (a: int);;$file;;11;;5;;"";;100
"""