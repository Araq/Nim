# v1.0.2 - 2019-10-23


## Bugfixes

* fixes the --verbosity:2 regression
* Fixed "Fail to compile a file twice under Windows (v1.0 bug)." [#12242](https://github.com/nim-lang/Nim/issues/12242)
* fix nimpretty removing space before pragma
* JS: gensym is stricter for 'this'
* Fixed "VM Assertion Error with newruntime" [#12294](https://github.com/nim-lang/Nim/issues/12294)
* Fixed "Assertion error when running `nim check` on compiler/nim.nim" [#12281](https://github.com/nim-lang/Nim/issues/12281)
* Fixed "Compiler crash with empty array and generic instantiation with int as parameter" [#12264](https://github.com/nim-lang/Nim/issues/12264)
* Fixed "Regression in JS backend codegen "Error: request to generate code for .compileTime proc"" [#12240](https://github.com/nim-lang/Nim/issues/12240)
* Fix how `relativePath` handles case sensitivity
* Fixed "SIGSEGV in compiler when using generic types and seqs" [#12336](https://github.com/nim-lang/Nim/issues/12336)
* Fixed "[1.0.0] weird interaction between `import os` and casting integer to char on macosx trigger bad codegen" [#12291](https://github.com/nim-lang/Nim/issues/12291)
* VM: no special casing for big endian machines
* Fixed "`internal error: environment misses` with a simple template inside one of Jester macros" [#12323](https://github.com/nim-lang/Nim/issues/12323)
* nimsuggest: fix tcp socket leak
* nimsuggest: fix tcp socket leak for epc backend
* Fixed "`writeFile` and `write(f, str)` skip null bytes on Windows" [#12315](https://github.com/nim-lang/Nim/issues/12315)
* Fixed "Crash in intsets symmetric_difference" [#12366](https://github.com/nim-lang/Nim/issues/12366)
* Fixed "[regression] VM crash when dealing with var param of a proc result" [#12244](https://github.com/nim-lang/Nim/issues/12244)
* fixes a koch regression that made 'koch boot --listcmd' not work anymore
* Fixed "[regression] inconsistent signed int `mod` operator between runtime, compiletime, and semfold" [#12332](https://github.com/nim-lang/Nim/issues/12332)
* Fixed "Boehm disables interior pointer checking" [#12286](https://github.com/nim-lang/Nim/issues/12286)
* Fixes semCustomPragma when nkSym
* Fixed yield in nkCheckedFieldExpr
* Fixed "`randomize()` from `random` not working on JS" [#12418](https://github.com/nim-lang/Nim/issues/12418)
* Fixed "Compiler crash with invalid object variant" [#12379](https://github.com/nim-lang/Nim/issues/12379)
* fix type's case in random.nim
* Fixed "Update docs with a better way to signal unimplemented methods" [#10804](https://github.com/nim-lang/Nim/issues/10804)
* Fixed "Nim language manual, push pragma is not explained well" [#10824](https://github.com/nim-lang/Nim/issues/10824)
* Fixed "[regression] Importing more than one module with same name from different packages produce bad codegen" [#12420](https://github.com/nim-lang/Nim/issues/12420)
* Namespace unittest enums to avoid name conflicts
* Fixed "VM checks unsigned integers for overflow." [#12310](https://github.com/nim-lang/Nim/issues/12310)
* Fixed "line directive is not generated for first line of function definition" [#12426](https://github.com/nim-lang/Nim/issues/12426)



## Documentation improvements

* threadpool: fix link in docs (#12258)
* Fix spellings (#12277)
* fix #12278, don't expose internal PCRE documentation
* Fixed "Documentation of quitprocs is wrong" [#12279](https://github.com/nim-lang/Nim/issues/12279)
* Fix typo in docs
* Fix reference to parseSpec proc in readme
* [doc/tut1] removed discard discussion in comments
* Documentation improvements around the db interface 
* Easier build instructions for windows - just run `build_all.bat`.
* fix a few dead links and a missing sentence in documentation
* Macro docs additions
* Updated the code example in the os module to use better grammar.
* Mention "lambdas" and `=>` in the manual
* Better documentation on Garbage Collector
