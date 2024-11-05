/*

            Nim's Runtime Library
        (c) Copyright 2015 Andreas Rumpf

    See the file "copying.txt", included in this
    distribution, for details about the copyright.
*/

/* compiler symbols:
__BORLANDC__
_MSC_VER
__GNUC__
__TINYC__
__clang__
__AVR__
__arm__
__EMSCRIPTEN__
*/


#ifndef NIMBASE_H
#define NIMBASE_H

/*------------ declaring a custom attribute to support using LLVM's Address Sanitizer ------------ */

/*
   This definition exists to provide support for using the LLVM ASAN (Address SANitizer) tooling with Nim. This
   should only be used to mark implementations of the GC system that raise false flags with the ASAN tooling, or
   for functions that are hot and need to be disabled for performance reasons. Based on the official ASAN
   documentation, both the clang and gcc compilers are supported. In addition to that, a check is performed to
   verify that the necessary attribute is supported by the compiler.

   To flag a proc as ignored, append the following code pragma to the proc declaration:
      {.codegenDecl: "CLANG_NO_SANITIZE_ADDRESS $# $#$#".}

   For further information, please refer to the official documentation:
     https://github.com/google/sanitizers/wiki/AddressSanitizer
 */
#define CLANG_NO_SANITIZE_ADDRESS
#if defined(__clang__)
#  if __has_attribute(no_sanitize_address)
#    undef CLANG_NO_SANITIZE_ADDRESS
#    define CLANG_NO_SANITIZE_ADDRESS __attribute__((no_sanitize_address))
#  endif
#endif


/* ------------ ignore typical warnings in Nim-generated files ------------- */
#if defined(__GNUC__) || defined(__clang__)
#  pragma GCC diagnostic ignored "-Wpragmas"
#  pragma GCC diagnostic ignored "-Wwritable-strings"
#  pragma GCC diagnostic ignored "-Winvalid-noreturn"
#  pragma GCC diagnostic ignored "-Wformat"
#  pragma GCC diagnostic ignored "-Wlogical-not-parentheses"
#  pragma GCC diagnostic ignored "-Wlogical-op-parentheses"
#  pragma GCC diagnostic ignored "-Wshadow"
#  pragma GCC diagnostic ignored "-Wunused-function"
#  pragma GCC diagnostic ignored "-Wunused-variable"
#  pragma GCC diagnostic ignored "-Winvalid-offsetof"
#  pragma GCC diagnostic ignored "-Wtautological-compare"
#  pragma GCC diagnostic ignored "-Wswitch-bool"
#  pragma GCC diagnostic ignored "-Wmacro-redefined"
#  pragma GCC diagnostic ignored "-Wincompatible-pointer-types-discards-qualifiers"
#  pragma GCC diagnostic ignored "-Wpointer-bool-conversion"
#  pragma GCC diagnostic ignored "-Wconstant-conversion"
#endif

#if defined(_MSC_VER)
#  pragma warning(disable: 4005 4100 4101 4189 4191 4200 4244 4293 4296 4309)
#  pragma warning(disable: 4310 4365 4456 4477 4514 4574 4611 4668 4702 4706)
#  pragma warning(disable: 4710 4711 4774 4800 4809 4820 4996 4090 4297)
#endif
/* ------------------------------------------------------------------------- */

#if defined(__GNUC__) && !defined(__ZEPHYR__)
/* Zephyr does some magic in it's headers that override the GCC stdlib. This breaks that. */
#  define _GNU_SOURCE 1
#endif

#if defined(__TINYC__)
/*#  define __GNUC__ 3
#  define GCC_MAJOR 4
#  define __GNUC_MINOR__ 4
#  define __GNUC_PATCHLEVEL__ 5 */
#  define __DECLSPEC_SUPPORTED 1
#endif

/* calling convention mess ----------------------------------------------- */
#if defined(__GNUC__) || defined(__TINYC__)
  /* these should support C99's inline */
#  define N_INLINE(rettype, name) inline rettype name
#elif defined(__BORLANDC__) || defined(_MSC_VER)
/* Borland's compiler is really STRANGE here; note that the __fastcall
   keyword cannot be before the return type, but __inline cannot be after
   the return type, so we do not handle this mess in the code generator
   but rather here. */
#  define N_INLINE(rettype, name) __inline rettype name
#else /* others are less picky: */
#  define N_INLINE(rettype, name) rettype __inline name
#endif

#define N_INLINE_PTR(rettype, name) rettype (*name)

#if defined(__cplusplus)
#  define NIM_CONST /* C++ is picky with const modifiers */
#else
#  define NIM_CONST  const
#endif

/*
  NIM_THREADVAR declaration based on
  https://stackoverflow.com/questions/18298280/how-to-declare-a-variable-as-thread-local-portably
*/
#if defined _WIN32
#  if defined _MSC_VER || defined __BORLANDC__
#    define NIM_THREADVAR __declspec(thread)
#  else
#    define NIM_THREADVAR __thread
#  endif
#elif defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112 && !defined __STDC_NO_THREADS__
#  define NIM_THREADVAR _Thread_local
#elif defined _WIN32 && ( \
       defined _MSC_VER || \
       defined __ICL || \
       defined __BORLANDC__ )
#  define NIM_THREADVAR __declspec(thread)
#elif defined(__TINYC__) || defined(__GENODE__)
#  define NIM_THREADVAR
/* note that ICC (linux) and Clang are covered by __GNUC__ */
#elif defined __GNUC__ || \
       defined __SUNPRO_C || \
       defined __xlC__
#  define NIM_THREADVAR __thread
#else
#  error "Cannot define NIM_THREADVAR"
#endif

#if defined(__cplusplus)
  #define NIM_THREAD_LOCAL thread_local
#endif

/* --------------- how int64 constants should be declared: ----------- */
#if defined(__GNUC__) || defined(_MSC_VER)
#  define IL64(x) x##LL
#else /* works only without LL */
#  define IL64(x) ((NI64)x)
#endif

/* ---------------- casting without correct aliasing rules ----------- */

#if defined(__GNUC__)
#  define NIM_CAST(type, ptr) (((union{type __x__;}*)(ptr))->__x__)
#else
#  define NIM_CAST(type, ptr) ((type)(ptr))
#endif


/* ------------------------------------------------------------------- */
#ifdef  __cplusplus
#  define NIM_EXTERNC extern "C"
#else
#  define NIM_EXTERNC
#endif

#if defined(WIN32) || defined(_WIN32) /* only Windows has this mess... */
#  define N_LIB_PRIVATE
#  define N_CDECL(rettype, name) rettype __cdecl name
#  define N_STDCALL(rettype, name) rettype __stdcall name
#  define N_SYSCALL(rettype, name) rettype __syscall name
#  define N_FASTCALL(rettype, name) rettype __fastcall name
#  define N_THISCALL(rettype, name) rettype __thiscall name
#  define N_SAFECALL(rettype, name) rettype __stdcall name
/* function pointers with calling convention: */
#  define N_CDECL_PTR(rettype, name) rettype (__cdecl *name)
#  define N_STDCALL_PTR(rettype, name) rettype (__stdcall *name)
#  define N_SYSCALL_PTR(rettype, name) rettype (__syscall *name)
#  define N_FASTCALL_PTR(rettype, name) rettype (__fastcall *name)
#  define N_THISCALL_PTR(rettype, name) rettype (__thiscall *name)
#  define N_SAFECALL_PTR(rettype, name) rettype (__stdcall *name)

#  ifdef __EMSCRIPTEN__
#    define N_LIB_EXPORT  NIM_EXTERNC __declspec(dllexport) __attribute__((used))
#    define N_LIB_EXPORT_VAR  __declspec(dllexport) __attribute__((used))
#  else
#    define N_LIB_EXPORT  NIM_EXTERNC __declspec(dllexport)
#    define N_LIB_EXPORT_VAR  __declspec(dllexport)
#  endif
#  define N_LIB_IMPORT  extern __declspec(dllimport)
#else
#  define N_LIB_PRIVATE __attribute__((visibility("hidden")))
#  if defined(__GNUC__)
#    define N_CDECL(rettype, name) rettype name
#    define N_STDCALL(rettype, name) rettype name
#    define N_SYSCALL(rettype, name) rettype name
#    define N_FASTCALL(rettype, name) __attribute__((fastcall)) rettype name
#    define N_SAFECALL(rettype, name) rettype name
/*   function pointers with calling convention: */
#    define N_CDECL_PTR(rettype, name) rettype (*name)
#    define N_STDCALL_PTR(rettype, name) rettype (*name)
#    define N_SYSCALL_PTR(rettype, name) rettype (*name)
#    define N_FASTCALL_PTR(rettype, name) __attribute__((fastcall)) rettype (*name)
#    define N_SAFECALL_PTR(rettype, name) rettype (*name)
#  else
#    define N_CDECL(rettype, name) rettype name
#    define N_STDCALL(rettype, name) rettype name
#    define N_SYSCALL(rettype, name) rettype name
#    define N_FASTCALL(rettype, name) rettype name
#    define N_SAFECALL(rettype, name) rettype name
/*   function pointers with calling convention: */
#    define N_CDECL_PTR(rettype, name) rettype (*name)
#    define N_STDCALL_PTR(rettype, name) rettype (*name)
#    define N_SYSCALL_PTR(rettype, name) rettype (*name)
#    define N_FASTCALL_PTR(rettype, name) rettype (*name)
#    define N_SAFECALL_PTR(rettype, name) rettype (*name)
#  endif
#  ifdef __EMSCRIPTEN__
#    define N_LIB_EXPORT NIM_EXTERNC __attribute__((visibility("default"), used))
#    define N_LIB_EXPORT_VAR  __attribute__((visibility("default"), used))
#  else
#    define N_LIB_EXPORT NIM_EXTERNC __attribute__((visibility("default")))
#    define N_LIB_EXPORT_VAR  __attribute__((visibility("default")))
#  endif
#  define N_LIB_IMPORT  extern
#endif

#define N_NOCONV(rettype, name) rettype name
/* specify no calling convention */
#define N_NOCONV_PTR(rettype, name) rettype (*name)

#if defined(__GNUC__) || defined(__ICC__)
#  define N_NOINLINE(rettype, name) rettype __attribute__((__noinline__)) name
#elif defined(_MSC_VER)
#  define N_NOINLINE(rettype, name) __declspec(noinline) rettype name
#else
#  define N_NOINLINE(rettype, name) rettype name
#endif

#define N_NOINLINE_PTR(rettype, name) rettype (*name)

#if defined(__BORLANDC__) || defined(_MSC_VER) || defined(WIN32) || defined(_WIN32)
/* these compilers have a fastcall so use it: */
#  ifdef __TINYC__
#    define N_NIMCALL(rettype, name) rettype __attribute((__fastcall)) name
#    define N_NIMCALL_PTR(rettype, name) rettype (__attribute((__fastcall)) *name)
#    define N_RAW_NIMCALL __attribute((__fastcall))
#  else
#    define N_NIMCALL(rettype, name) rettype __fastcall name
#    define N_NIMCALL_PTR(rettype, name) rettype (__fastcall *name)
#    define N_RAW_NIMCALL __fastcall
#  endif
#else
#  define N_NIMCALL(rettype, name) rettype name /* no modifier */
#  define N_NIMCALL_PTR(rettype, name) rettype (*name)
#  define N_RAW_NIMCALL
#endif

#define N_CLOSURE(rettype, name) N_NIMCALL(rettype, name)
#define N_CLOSURE_PTR(rettype, name) N_NIMCALL_PTR(rettype, name)

/* ----------------------------------------------------------------------- */

#define COMMA ,

#include <limits.h>
#include <stddef.h>

// define NIM_STATIC_ASSERT
// example use case: CT sizeof for importc types verification
// where we have {.completeStruct.} (or lack of {.incompleteStruct.})
#if (defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L)
#define NIM_STATIC_ASSERT(x, msg) _Static_assert((x), msg)
#elif defined(__cplusplus)
#define NIM_STATIC_ASSERT(x, msg) static_assert((x), msg)
#else
#define _NIM_STATIC_ASSERT_FINAL(x, append_name) typedef int NIM_STATIC_ASSERT_AUX ## append_name[(x) ? 1 : -1];
#define _NIM_STATIC_ASSERT_STAGE_3(x, line)      _NIM_STATIC_ASSERT_FINAL(x, _AT_LINE_##line)
#define _NIM_STATIC_ASSERT_STAGE_2(x, line)      _NIM_STATIC_ASSERT_STAGE_3(x, line)
#define NIM_STATIC_ASSERT(x, msg)                _NIM_STATIC_ASSERT_STAGE_2(x,__LINE__)
// On failure, your C compiler will say something like:
//   "error: 'NIM_STATIC_ASSERT_AUX_AT_LINE_XXX' declared as an array with a negative size"
// Adding the line number helps to avoid redefinitions which are not allowed in
// old GCC versions, however the order of evaluation for __LINE__ is a little tricky,
// hence all the helper macros. See https://stackoverflow.com/a/3385694 for more info.
#endif

/* C99 compiler? */
#if (defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 199901))
#  define HAVE_STDINT_H
#endif

/* Known compiler with stdint.h that doesn't fit the general pattern? */
#if defined(__AVR__) || (defined(__cplusplus) && (__cplusplus < 201103))
#  define HAVE_STDINT_H
#endif

#if (!defined(HAVE_STDINT_H) && defined(__cplusplus) && (__cplusplus >= 201103))
#  define HAVE_CSTDINT
#endif


/* wrap all Nim typedefs into namespace Nim */
#ifdef USE_NIM_NAMESPACE
#ifdef HAVE_CSTDINT
#include <cstdint>
#else
#include <stdint.h>
#endif
namespace USE_NIM_NAMESPACE {
#endif

// preexisting check, seems paranoid, maybe remove
#if defined(NIM_TRUE) || defined(NIM_FALSE) || defined(NIM_BOOL)
#error "nim reserved preprocessor macros clash"
#endif

/* bool types (C++ has it): */
#ifdef __cplusplus
#define NIM_BOOL bool
#elif (defined(__STDC_VERSION__) && __STDC_VERSION__ >= 199901)
// see #13798: to avoid conflicts for code emitting `#include <stdbool.h>`
#define NIM_BOOL _Bool
#else
typedef unsigned char NIM_BOOL; // best effort
#endif

NIM_STATIC_ASSERT(sizeof(NIM_BOOL) == 1, ""); // check whether really needed
NIM_STATIC_ASSERT(CHAR_BIT == 8, "");
  // fail fast for (rare) environments where this doesn't hold, as some implicit
  // assumptions would need revisiting (e.g. `uint8` or https://github.com/nim-lang/Nim/pull/18505)

#define NIM_TRUE true
#define NIM_FALSE false

#ifdef __cplusplus
#  if __cplusplus >= 201103L
#    /* nullptr is more type safe (less implicit conversions than 0) */
#    define NIM_NIL nullptr
#  else
#    // both `((void*)0)` and `NULL` would cause codegen to emit
#    // error: assigning to 'Foo *' from incompatible type 'void *'
#    // but codegen could be fixed if need. See also potential caveat regarding
#    // NULL.
#    // However, `0` causes other issues, see #13798
#    define NIM_NIL 0
#  endif
#else
#  include <stdbool.h>
#  define NIM_NIL ((void*)0) /* C's NULL is fucked up in some C compilers, so
                              the generated code does not rely on it anymore */
#endif

#if defined(__BORLANDC__) || defined(_MSC_VER)
typedef signed char NI8;
typedef signed short int NI16;
typedef signed int NI32;
typedef __int64 NI64;
/* XXX: Float128? */
typedef unsigned char NU8;
typedef unsigned short int NU16;
typedef unsigned int NU32;
typedef unsigned __int64 NU64;
#elif defined(HAVE_STDINT_H)
#ifndef USE_NIM_NAMESPACE
#  include <stdint.h>
#endif
typedef int8_t NI8;
typedef int16_t NI16;
typedef int32_t NI32;
typedef int64_t NI64;
typedef uint8_t NU8;
typedef uint16_t NU16;
typedef uint32_t NU32;
typedef uint64_t NU64;
#elif defined(HAVE_CSTDINT)
#ifndef USE_NIM_NAMESPACE
#  include <cstdint>
#endif
typedef std::int8_t NI8;
typedef std::int16_t NI16;
typedef std::int32_t NI32;
typedef std::int64_t NI64;
typedef std::uint8_t NU8;
typedef std::uint16_t NU16;
typedef std::uint32_t NU32;
typedef std::uint64_t NU64;
#else
/* Unknown compiler/version, do our best */
#ifdef __INT8_TYPE__
typedef __INT8_TYPE__ NI8;
#else
typedef signed char NI8;
#endif
#ifdef __INT16_TYPE__
typedef __INT16_TYPE__ NI16;
#else
typedef signed short int NI16;
#endif
#ifdef __INT32_TYPE__
typedef __INT32_TYPE__ NI32;
#else
typedef signed int NI32;
#endif
#ifdef __INT64_TYPE__
typedef __INT64_TYPE__ NI64;
#else
typedef long long int NI64;
#endif
/* XXX: Float128? */
#ifdef __UINT8_TYPE__
typedef __UINT8_TYPE__ NU8;
#else
typedef unsigned char NU8;
#endif
#ifdef __UINT16_TYPE__
typedef __UINT16_TYPE__ NU16;
#else
typedef unsigned short int NU16;
#endif
#ifdef __UINT32_TYPE__
typedef __UINT32_TYPE__ NU32;
#else
typedef unsigned int NU32;
#endif
#ifdef __UINT64_TYPE__
typedef __UINT64_TYPE__ NU64;
#else
typedef unsigned long long int NU64;
#endif
#endif

#ifdef NIM_INTBITS
#  if NIM_INTBITS == 64
typedef NI64 NI;
typedef NU64 NU;
#  elif NIM_INTBITS == 32
typedef NI32 NI;
typedef NU32 NU;
#  elif NIM_INTBITS == 16
typedef NI16 NI;
typedef NU16 NU;
#  elif NIM_INTBITS == 8
typedef NI8 NI;
typedef NU8 NU;
#  else
#    error "invalid bit width for int"
#  endif
#endif

// for now there isn't an easy way for C code to reach the program result
// when hot code reloading is ON - users will have to:
// load the nimhcr.dll, get the hcrGetGlobal proc from there and use it
#ifndef NIM_HOT_CODE_RELOADING
extern NI nim_program_result;
#endif

typedef float NF32;
typedef double NF64;
typedef double NF;

typedef char NIM_CHAR;
typedef char* NCSTRING;

#ifdef NIM_BIG_ENDIAN
#  define NIM_IMAN 1
#else
#  define NIM_IMAN 0
#endif

#define NIM_STRLIT_FLAG ((NU)(1) << ((NIM_INTBITS) - 2)) /* This has to be the same as system.strlitFlag! */

/* declared size of a sequence/variable length array: */
#if defined(__cplusplus) && defined(__clang__)
#  define SEQ_DECL_SIZE 1
#elif defined(__GNUC__) || defined(_MSC_VER) || defined(__TINYC__) || \
        (defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 199901)) // C99
#  define SEQ_DECL_SIZE /* empty is correct! */
#else
#  define SEQ_DECL_SIZE 1000000
#endif

#define ALLOC_0(size)  calloc(1, size)
#define DL_ALLOC_0(size) dlcalloc(1, size)

#define paramCount() cmdCount

// NAN definition copied from math.h included in the Windows SDK version 10.0.14393.0
#ifndef NAN
#  ifndef _HUGE_ENUF
#    define _HUGE_ENUF  1e+300  // _HUGE_ENUF*_HUGE_ENUF must overflow
#  endif
#  define NAN_INFINITY ((float)(_HUGE_ENUF * _HUGE_ENUF))
#  define NAN ((float)(NAN_INFINITY * 0.0F))
#endif

#ifndef INF
#  ifdef INFINITY
#    define INF INFINITY
#  elif defined(HUGE_VAL)
#    define INF  HUGE_VAL
#  elif defined(_MSC_VER)
#    include <float.h>
#    define INF (DBL_MAX+DBL_MAX)
#  else
#    define INF (1.0 / 0.0)
#  endif
#endif

typedef struct TFrame_ TFrame;
struct TFrame_ {
  TFrame* prev;
  NCSTRING procname;
  NI line;
  NCSTRING filename;
  NI16 len;
  NI16 calldepth;
  NI frameMsgLen;
};

#define NIM_POSIX_INIT  __attribute__((constructor))

#ifdef __GNUC__
#  define NIM_LIKELY(x) __builtin_expect(x, 1)
#  define NIM_UNLIKELY(x) __builtin_expect(x, 0)
/* We need the following for the posix wrapper. In particular it will give us
   POSIX_SPAWN_USEVFORK: */
#  ifndef _GNU_SOURCE
#    define _GNU_SOURCE
#  endif
#else
#  define NIM_LIKELY(x) (x)
#  define NIM_UNLIKELY(x) (x)
#endif

#if 0 // defined(__GNUC__) || defined(__clang__)
// not needed anymore because the stack marking cares about
// interior pointers now
static inline void GCGuard (void *ptr) { asm volatile ("" :: "X" (ptr)); }
#  define GC_GUARD __attribute__ ((cleanup(GCGuard)))
#else
#  define GC_GUARD
#endif

// Test to see if Nim and the C compiler agree on the size of a pointer.
NIM_STATIC_ASSERT(sizeof(NI) == sizeof(void*) && NIM_INTBITS == sizeof(NI)*8, "Pointer size mismatch between Nim and C/C++ backend. You probably need to setup the backend compiler for target CPU.");

#ifdef USE_NIM_NAMESPACE
}
#endif

#if defined(_MSC_VER)
#  define NIM_ALIGN(x)  __declspec(align(x))
#  define NIM_ALIGNOF(x) __alignof(x)
#else
#  define NIM_ALIGN(x)  __attribute__((aligned(x)))
#  define NIM_ALIGNOF(x) __alignof__(x)
#endif

/* ---------------- platform specific includes ----------------------- */

/* VxWorks related includes */
#if defined(__VXWORKS__)
#  include <sys/types.h>
#  include <types/vxWind.h>
#  include <tool/gnu/toolMacros.h>
#elif defined(__FreeBSD__)
#  include <sys/types.h>
#endif

/* these exist to make the codegen logic simpler */
#define nimModInt(a, b, res) (((*res) = (a) % (b)), 0)
#define nimModInt64(a, b, res) (((*res) = (a) % (b)), 0)

#if (!defined(_MSC_VER) || defined(__clang__)) && !defined(NIM_EmulateOverflowChecks)
  /* these exist because we cannot have .compilerProcs that are importc'ed
    by a different name */

  #define nimAddInt64(a, b, res) __builtin_saddll_overflow(a, b, (long long int*)res)
  #define nimSubInt64(a, b, res) __builtin_ssubll_overflow(a, b, (long long int*)res)
  #define nimMulInt64(a, b, res) __builtin_smulll_overflow(a, b, (long long int*)res)

  #if NIM_INTBITS == 32
    #if defined(__arm__) && defined(__GNUC__)
      /* arm-none-eabi-gcc targets defines int32_t as long int */
      #define nimAddInt(a, b, res) __builtin_saddl_overflow(a, b, res)
      #define nimSubInt(a, b, res) __builtin_ssubl_overflow(a, b, res)
      #define nimMulInt(a, b, res) __builtin_smull_overflow(a, b, res)
    #else
      #define nimAddInt(a, b, res) __builtin_sadd_overflow(a, b, res)
      #define nimSubInt(a, b, res) __builtin_ssub_overflow(a, b, res)
      #define nimMulInt(a, b, res) __builtin_smul_overflow(a, b, res)
    #endif
  #else
    /* map it to the 'long long' variant */
    #define nimAddInt(a, b, res) __builtin_saddll_overflow(a, b, (long long int*)res)
    #define nimSubInt(a, b, res) __builtin_ssubll_overflow(a, b, (long long int*)res)
    #define nimMulInt(a, b, res) __builtin_smulll_overflow(a, b, (long long int*)res)
  #endif
#endif

#define NIM_NOALIAS __restrict
/* __restrict is said to work for all the C(++) compilers out there that we support */

#endif /* NIMBASE_H */
