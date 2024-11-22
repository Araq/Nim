#
#
#            Nim's Runtime Library
#        (c) Copyright 2024 Nim Contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# The current PCRE2 version information.

const
  PCRE2_MAJOR* = 10
  PCRE2_MINOR* = 45
  PCRE2_PRERELEASE* = true
  PCRE2_DATE* = "2024-06-09"

const
  ANCHORED* = 0x80000000'u32
  NO_UTF_CHECK* = 0x40000000'u32
  ENDANCHORED* = 0x20000000'u32

##  The following option bits can be passed only to pcre2_compile(). However,
## they may affect compilation, JIT compilation, and/or interpretive execution.
## The following tags indicate which:
##
## C   alters what is compiled by pcre2_compile()
## J   alters what is compiled by pcre2_jit_compile()
## M   is inspected during pcre2_match() execution
## D   is inspected during pcre2_dfa_match() execution
##

const
  ALLOW_EMPTY_CLASS* = 0x00000001'u32
  ALT_BSUX* = 0x00000002'u32
  AUTO_CALLOUT* = 0x00000004'u32
  CASELESS* = 0x00000008'u32
  DOLLAR_ENDONLY* = 0x00000010'u32
  DOTALL* = 0x00000020'u32
  DUPNAMES* = 0x00000040'u32
  EXTENDED* = 0x00000080'u32
  FIRSTLINE* = 0x00000100'u32
  MATCH_UNSET_BACKREF* = 0x00000200'u32
  MULTILINE* = 0x00000400'u32
  NEVER_UCP* = 0x00000800'u32
  NEVER_UTF* = 0x00001000'u32
  NO_AUTO_CAPTURE* = 0x00002000'u32
  NO_AUTO_POSSESS* = 0x00004000'u32
  NO_DOTSTAR_ANCHOR* = 0x00008000'u32
  NO_START_OPTIMIZE* = 0x00010000'u32
  UCP* = 0x00020000'u32
  UNGREEDY* = 0x00040000'u32
  UTF* = 0x00080000'u32
  NEVER_BACKSLASH_C* = 0x00100000'u32
  ALT_CIRCUMFLEX* = 0x00200000'u32
  ALT_VERBNAMES* = 0x00400000'u32
  USE_OFFSET_LIMIT* = 0x00800000'u32
  EXTENDED_MORE* = 0x01000000'u32
  LITERAL* = 0x02000000'u32
  MATCH_INVALID_UTF* = 0x0400000'u32
  ALT_EXTENDED_CLASS* = 0x080000'u32

##  An additional compile options word is available in the compile context.

const
  EXTRA_ALLOW_SURROGATE_ESCAPES* = 0x00000001'u32
  EXTRA_BAD_ESCAPE_IS_LITERAL* = 0x00000002'u32
  EXTRA_MATCH_WORD* = 0x00000004'u32
  EXTRA_MATCH_LINE* = 0x00000008'u32
  EXTRA_ESCAPED_CR_IS_LF* = 0x00000010'u32
  EXTRA_ALT_BSUX* = 0x00000020'u32
  EXTRA_ALLOW_LOOKAROUND_BSK* = 0x00000040'u32
  EXTRA_CASELESS_RESTRICT* = 0x00000080'u32
  EXTRA_ASCII_BSD* = 0x00000100'u32
  EXTRA_ASCII_BSS* = 0x00000200'u32
  EXTRA_ASCII_BSW* = 0x00000400'u32
  EXTRA_ASCII_POSIX* = 0x00000800'u32
  EXTRA_ASCII_DIGIT* = 0x00001000'u32
  EXTRA_PYTHON_OCTAL* = 0x00002000'u32
  EXTRA_NO_BS0* = 0x00004000'u32
  EXTRA_NEVER_CALLOUT* = 0x00008000'u32
  EXTRA_TURKISH_CASING* = 0x00010000'u32

##  These are for pcre2_jit_compile().

const
  JIT_COMPLETE* = 0x00000001'u32
  JIT_PARTIAL_SOFT* = 0x00000002'u32
  JIT_PARTIAL_HARD* = 0x00000004'u32
  JIT_INVALID_UTF* = 0x00000100'u32
  JIT_TEST_ALLOC* = 0x00000200'u32

##  These are for pcre2_match(), pcre2_dfa_match(), pcre2_jit_match(), and
## pcre2_substitute(). Some are allowed only for one of the functions, and in
## these cases it is noted below. Note that ANCHORED, ENDANCHORED and
## NO_UTF_CHECK can also be passed to these functions (though
## pcre2_jit_match() ignores the latter since it bypasses all sanity checks).

const
  NOTBOL* = 0x00000001'u32
  NOTEOL* = 0x00000002'u32
  NOTEMPTY* = 0x00000004'u32
  NOTEMPTY_ATSTART* = 0x00000008'u32
  PARTIAL_SOFT* = 0x00000010'u32
  PARTIAL_HARD* = 0x00000020'u32
  DFA_RESTART* = 0x00000040'u32
  DFA_SHORTEST* = 0x00000080'u32
  SUBSTITUTE_GLOBAL* = 0x00000100'u32
  SUBSTITUTE_EXTENDED* = 0x00000200'u32
  SUBSTITUTE_UNSET_EMPTY* = 0x00000400'u32
  SUBSTITUTE_UNKNOWN_UNSET* = 0x00000800'u32
  SUBSTITUTE_OVERFLOW_LENGTH* = 0x00001000'u32
  NO_JIT* = 0x00002000'u32
  COPY_MATCHED_SUBJECT* = 0x00004000'u32
  SUBSTITUTE_LITERAL* = 0x00008000'u32
  SUBSTITUTE_MATCHED* = 0x00010000'u32
  SUBSTITUTE_REPLACEMENT_ONLY* = 0x00020000'u32
  DISABLE_RECURSELOOP_CHECK* = 0x00040000'u32

##  Options for pcre2_pattern_convert().

const
  CONVERT_UTF* = 0x00000001'u32
  CONVERT_NO_UTF_CHECK* = 0x00000002'u32
  CONVERT_POSIX_BASIC* = 0x00000004'u32
  CONVERT_POSIX_EXTENDED* = 0x00000008'u32
  CONVERT_GLOB* = 0x00000010'u32
  CONVERT_GLOB_NO_WILD_SEPARATOR* = 0x00000030'u32
  CONVERT_GLOB_NO_STARSTAR* = 0x00000050'u32

##  Newline and \R settings, for use in compile contexts. The newline values
## must be kept in step with values set in config.h and both sets must all be
## greater than zero.

const
  NEWLINE_CR* = 1
  NEWLINE_LF* = 2
  NEWLINE_CRLF* = 3
  NEWLINE_ANY* = 4
  NEWLINE_ANYCRLF* = 5
  NEWLINE_NUL* = 6
  BSR_UNICODE* = 1
  BSR_ANYCRLF* = 2

##  Error codes for pcre2_compile(). Some of these are also used by
## pcre2_pattern_convert().

const
  ERROR_END_BACKSLASH* = 101
  ERROR_END_BACKSLASH_C* = 102
  ERROR_UNKNOWN_ESCAPE* = 103
  ERROR_QUANTIFIER_OUT_OF_ORDER* = 104
  ERROR_QUANTIFIER_TOO_BIG* = 105
  ERROR_MISSING_SQUARE_BRACKET* = 106
  ERROR_ESCAPE_INVALID_IN_CLASS* = 107
  ERROR_CLASS_RANGE_ORDER* = 108
  ERROR_QUANTIFIER_INVALID* = 109
  ERROR_INTERNAL_UNEXPECTED_REPEAT* = 110
  ERROR_INVALID_AFTER_PARENS_QUERY* = 111
  ERROR_POSIX_CLASS_NOT_IN_CLASS* = 112
  ERROR_POSIX_NO_SUPPORT_COLLATING* = 113
  ERROR_MISSING_CLOSING_PARENTHESIS* = 114
  ERROR_BAD_SUBPATTERN_REFERENCE* = 115
  ERROR_NULL_PATTERN* = 116
  ERROR_BAD_OPTIONS* = 117
  ERROR_MISSING_COMMENT_CLOSING* = 118
  ERROR_PARENTHESES_NEST_TOO_DEEP* = 119
  ERROR_PATTERN_TOO_LARGE* = 120
  ERROR_HEAP_FAILED* = 121
  ERROR_UNMATCHED_CLOSING_PARENTHESIS* = 122
  ERROR_INTERNAL_CODE_OVERFLOW* = 123
  ERROR_MISSING_CONDITION_CLOSING* = 124
  ERROR_LOOKBEHIND_NOT_FIXED_LENGTH* = 125
  ERROR_ZERO_RELATIVE_REFERENCE* = 126
  ERROR_TOO_MANY_CONDITION_BRANCHES* = 127
  ERROR_CONDITION_ASSERTION_EXPECTED* = 128
  ERROR_BAD_RELATIVE_REFERENCE* = 129
  ERROR_UNKNOWN_POSIX_CLASS* = 130
  ERROR_INTERNAL_STUDY_ERROR* = 131
  ERROR_UNICODE_NOT_SUPPORTED* = 132
  ERROR_PARENTHESES_STACK_CHECK* = 133
  ERROR_CODE_POINT_TOO_BIG* = 134
  ERROR_LOOKBEHIND_TOO_COMPLICATED* = 135
  ERROR_LOOKBEHIND_INVALID_BACKSLASH_C* = 136
  ERROR_UNSUPPORTED_ESCAPE_SEQUENCE* = 137
  ERROR_CALLOUT_NUMBER_TOO_BIG* = 138
  ERROR_MISSING_CALLOUT_CLOSING* = 139
  ERROR_ESCAPE_INVALID_IN_VERB* = 140
  ERROR_UNRECOGNIZED_AFTER_QUERY_P* = 141
  ERROR_MISSING_NAME_TERMINATOR* = 142
  ERROR_DUPLICATE_SUBPATTERN_NAME* = 143
  ERROR_INVALID_SUBPATTERN_NAME* = 144
  ERROR_UNICODE_PROPERTIES_UNAVAILABLE* = 145
  ERROR_MALFORMED_UNICODE_PROPERTY* = 146
  ERROR_UNKNOWN_UNICODE_PROPERTY* = 147
  ERROR_SUBPATTERN_NAME_TOO_LONG* = 148
  ERROR_TOO_MANY_NAMED_SUBPATTERNS* = 149
  ERROR_CLASS_INVALID_RANGE* = 150
  ERROR_OCTAL_BYTE_TOO_BIG* = 151
  ERROR_INTERNAL_OVERRAN_WORKSPACE* = 152
  ERROR_INTERNAL_MISSING_SUBPATTERN* = 153
  ERROR_DEFINE_TOO_MANY_BRANCHES* = 154
  ERROR_BACKSLASH_O_MISSING_BRACE* = 155
  ERROR_INTERNAL_UNKNOWN_NEWLINE* = 156
  ERROR_BACKSLASH_G_SYNTAX* = 157
  ERROR_PARENS_QUERY_R_MISSING_CLOSING* = 158

##  Error 159 is obsolete and should now never occur

const
  ERROR_VERB_ARGUMENT_NOT_ALLOWED* = 159
  ERROR_VERB_UNKNOWN* = 160
  ERROR_SUBPATTERN_NUMBER_TOO_BIG* = 161
  ERROR_SUBPATTERN_NAME_EXPECTED* = 162
  ERROR_INTERNAL_PARSED_OVERFLOW* = 163
  ERROR_INVALID_OCTAL* = 164
  ERROR_SUBPATTERN_NAMES_MISMATCH* = 165
  ERROR_MARK_MISSING_ARGUMENT* = 166
  ERROR_INVALID_HEXADECIMAL* = 167
  ERROR_BACKSLASH_C_SYNTAX* = 168
  ERROR_BACKSLASH_K_SYNTAX* = 169
  ERROR_INTERNAL_BAD_CODE_LOOKBEHINDS* = 170
  ERROR_BACKSLASH_N_IN_CLASS* = 171
  ERROR_CALLOUT_STRING_TOO_LONG* = 172
  ERROR_UNICODE_DISALLOWED_CODE_POINT* = 173
  ERROR_UTF_IS_DISABLED* = 174
  ERROR_UCP_IS_DISABLED* = 175
  ERROR_VERB_NAME_TOO_LONG* = 176
  ERROR_BACKSLASH_U_CODE_POINT_TOO_BIG* = 177
  ERROR_MISSING_OCTAL_OR_HEX_DIGITS* = 178
  ERROR_VERSION_CONDITION_SYNTAX* = 179
  ERROR_INTERNAL_BAD_CODE_AUTO_POSSESS* = 180
  ERROR_CALLOUT_NO_STRING_DELIMITER* = 181
  ERROR_CALLOUT_BAD_STRING_DELIMITER* = 182
  ERROR_BACKSLASH_C_CALLER_DISABLED* = 183
  ERROR_QUERY_BARJX_NEST_TOO_DEEP* = 184
  ERROR_BACKSLASH_C_LIBRARY_DISABLED* = 185
  ERROR_PATTERN_TOO_COMPLICATED* = 186
  ERROR_LOOKBEHIND_TOO_LONG* = 187
  ERROR_PATTERN_STRING_TOO_LONG* = 188
  ERROR_INTERNAL_BAD_CODE* = 189
  ERROR_INTERNAL_BAD_CODE_IN_SKIP* = 190
  ERROR_NO_SURROGATES_IN_UTF16* = 191
  ERROR_BAD_LITERAL_OPTIONS* = 192
  ERROR_SUPPORTED_ONLY_IN_UNICODE* = 193
  ERROR_INVALID_HYPHEN_IN_OPTIONS* = 194
  ERROR_ALPHA_ASSERTION_UNKNOWN* = 195
  ERROR_SCRIPT_RUN_NOT_AVAILABLE* = 196
  ERROR_TOO_MANY_CAPTURES* = 197
  ERROR_MISSING_OCTAL_DIGIT* = 198
  ERROR_BACKSLASH_K_IN_LOOKAROUND* = 199
  ERROR_MAX_VAR_LOOKBEHIND_EXCEEDED* = 200
  ERROR_PATTERN_COMPILED_SIZE_TOO_BIG* = 201
  ERROR_OVERSIZE_PYTHON_OCTAL* = 202
  ERROR_CALLOUT_CALLER_DISABLED* = 203
  ERROR_EXTRA_CASING_REQUIRES_UNICODE* = 204
  ERROR_TURKISH_CASING_REQUIRES_UTF* = 205
  ERROR_EXTRA_CASING_INCOMPATIBLE* = 206
  ERROR_ECLASS_NEST_TOO_DEEP* = 207
  ERROR_ECLASS_INVALID_OPERATOR* = 208
  ERROR_ECLASS_UNEXPECTED_OPERATOR* = 209
  ERROR_ECLASS_EXPECTED_OPERAND* = 210
  ERROR_ECLASS_MIXED_OPERATORS* = 211
  ERROR_ECLASS_HINT_SQUARE_BRACKET* = 212

##  "Expected" matching error codes: no match and partial match.

const
  ERROR_NOMATCH* = (-1)
  ERROR_PARTIAL* = (-2)

##  Error codes for UTF-8 validity checks

const
  ERROR_UTF8_ERR1* = (-3)
  ERROR_UTF8_ERR2* = (-4)
  ERROR_UTF8_ERR3* = (-5)
  ERROR_UTF8_ERR4* = (-6)
  ERROR_UTF8_ERR5* = (-7)
  ERROR_UTF8_ERR6* = (-8)
  ERROR_UTF8_ERR7* = (-9)
  ERROR_UTF8_ERR8* = (-10)
  ERROR_UTF8_ERR9* = (-11)
  ERROR_UTF8_ERR10* = (-12)
  ERROR_UTF8_ERR11* = (-13)
  ERROR_UTF8_ERR12* = (-14)
  ERROR_UTF8_ERR13* = (-15)
  ERROR_UTF8_ERR14* = (-16)
  ERROR_UTF8_ERR15* = (-17)
  ERROR_UTF8_ERR16* = (-18)
  ERROR_UTF8_ERR17* = (-19)
  ERROR_UTF8_ERR18* = (-20)
  ERROR_UTF8_ERR19* = (-21)
  ERROR_UTF8_ERR20* = (-22)
  ERROR_UTF8_ERR21* = (-23)

##  Error codes for UTF-16 validity checks

const
  ERROR_UTF16_ERR1* = (-24)
  ERROR_UTF16_ERR2* = (-25)
  ERROR_UTF16_ERR3* = (-26)

##  Error codes for UTF-32 validity checks

const
  ERROR_UTF32_ERR1* = (-27)
  ERROR_UTF32_ERR2* = (-28)

##  Miscellaneous error codes for pcre2[_dfa]_match(), substring extraction
## functions, context functions, and serializing functions. They are in numerical
## order. Originally they were in alphabetical order too, but now that PCRE2 is
## released, the numbers must not be changed.

const
  ERROR_BADDATA* = (-29)
  ERROR_MIXEDTABLES* = (-30) ##  Name was changed
  ERROR_BADMAGIC* = (-31)
  ERROR_BADMODE* = (-32)
  ERROR_BADOFFSET* = (-33)
  ERROR_BADOPTION* = (-34)
  ERROR_BADREPLACEMENT* = (-35)
  ERROR_BADUTFOFFSET* = (-36)
  ERROR_CALLOUT* = (-37)  ##  Never used by PCRE2 itself
  ERROR_DFA_BADRESTART* = (-38)
  ERROR_DFA_RECURSE* = (-39)
  ERROR_DFA_UCOND* = (-40)
  ERROR_DFA_UFUNC* = (-41)
  ERROR_DFA_UITEM* = (-42)
  ERROR_DFA_WSSIZE* = (-43)
  ERROR_INTERNAL* = (-44)
  ERROR_JIT_BADOPTION* = (-45)
  ERROR_JIT_STACKLIMIT* = (-46)
  ERROR_MATCHLIMIT* = (-47)
  ERROR_NOMEMORY* = (-48)
  ERROR_NOSUBSTRING* = (-49)
  ERROR_NOUNIQUESUBSTRING* = (-50)
  ERROR_NULL* = (-51)
  ERROR_RECURSELOOP* = (-52)
  ERROR_DEPTHLIMIT* = (-53)
  ERROR_RECURSIONLIMIT* = (-53) ##  Obsolete synonym
  ERROR_UNAVAILABLE* = (-54)
  ERROR_UNSET* = (-55)
  ERROR_BADOFFSETLIMIT* = (-56)
  ERROR_BADREPESCAPE* = (-57)
  ERROR_REPMISSINGBRACE* = (-58)
  ERROR_BADSUBSTITUTION* = (-59)
  ERROR_BADSUBSPATTERN* = (-60)
  ERROR_TOOMANYREPLACE* = (-61)
  ERROR_BADSERIALIZEDDATA* = (-62)
  ERROR_HEAPLIMIT* = (-63)
  ERROR_CONVERT_SYNTAX* = (-64)
  ERROR_INTERNAL_DUPMATCH* = (-65)
  ERROR_DFA_UINVALID_UTF* = (-66)
  ERROR_INVALIDOFFSET* = (-67)
  ERROR_JIT_UNSUPPORTED* = (-68)

##  Request types for pcre2_pattern_info()

const
  INFO_ALLOPTIONS* = 0
  INFO_ARGOPTIONS* = 1
  INFO_BACKREFMAX* = 2
  INFO_BSR* = 3
  INFO_CAPTURECOUNT* = 4
  INFO_FIRSTCODEUNIT* = 5
  INFO_FIRSTCODETYPE* = 6
  INFO_FIRSTBITMAP* = 7
  INFO_HASCRORLF* = 8
  INFO_JCHANGED* = 9
  INFO_JITSIZE* = 10
  INFO_LASTCODEUNIT* = 11
  INFO_LASTCODETYPE* = 12
  INFO_MATCHEMPTY* = 13
  INFO_MATCHLIMIT* = 14
  INFO_MAXLOOKBEHIND* = 15
  INFO_MINLENGTH* = 16
  INFO_NAMECOUNT* = 17
  INFO_NAMEENTRYSIZE* = 18
  INFO_NAMETABLE* = 19
  INFO_NEWLINE* = 20
  INFO_DEPTHLIMIT* = 21
  INFO_RECURSIONLIMIT* = 21
  INFO_SIZE* = 22
  INFO_HASBACKSLASHC* = 23
  INFO_FRAMESIZE* = 24
  INFO_HEAPLIMIT* = 25
  INFO_EXTRAOPTIONS* = 26

##  Request types for pcre2_config().

const
  CONFIG_BSR* = 0
  CONFIG_JIT* = 1
  CONFIG_JITTARGET* = 2
  CONFIG_LINKSIZE* = 3
  CONFIG_MATCHLIMIT* = 4
  CONFIG_NEWLINE* = 5
  CONFIG_PARENSLIMIT* = 6
  CONFIG_DEPTHLIMIT* = 7
  CONFIG_RECURSIONLIMIT* = 7
  CONFIG_STACKRECURSE* = 8
  CONFIG_UNICODE* = 9
  CONFIG_UNICODE_VERSION* = 10
  CONFIG_VERSION* = 11
  CONFIG_HEAPLIMIT* = 12
  CONFIG_NEVER_BACKSLASH_C* = 13
  CONFIG_COMPILED_WIDTHS* = 14
  CONFIG_TABLES_LENGTH* = 15

##  Optimization directives for pcre2_set_optimize().
## For binary compatibility, only add to this list; do not renumber.

const
  OPTIMIZATION_NONE* = 0
  OPTIMIZATION_FULL* = 1
  AUTO_POSSESS* = 64
  AUTO_POSSESS_OFF* = 65
  DOTSTAR_ANCHOR* = 66
  DOTSTAR_ANCHOR_OFF* = 67
  START_OPTIMIZE* = 68
  START_OPTIMIZE_OFF* = 69

##  Types used in pcre2_set_substitute_case_callout().

const
  SUBSTITUTE_CASE_LOWER* = 0
  SUBSTITUTE_CASE_UPPER* = 1
  SUBSTITUTE_CASE_TITLE* = 2


const
  ZERO_TERMINATED* = not 0.csize_t
  UNSET* = not 0.csize_t

# Types
type
  Pcre* = object
  Pcre16* = object
  Pcre32* = object
  JitStack* = object
  JitStack16* = object
  JitStack32* = object
  GeneralContext* = object
  MatchData* = object

when defined(nimHasStyleChecks):
  {.push styleChecks: off.}

# The structure for passing out data via the pcre_callout_function. We use a
# structure so that new fields can be added on the end in future versions,
# without changing the API of the function, thereby allowing old clients to
# work without modification.
type
  CalloutBlock* = object
    version*         : cint       ## Identifies version of block
    # ------------------------ Version 0 -------------------------------
    callout_number*  : cint       ## Number compiled into pattern
    offset_vector*   : ptr cint   ## The offset vector
    subject*         : cstring    ## The subject being matched
    subject_length*  : cint       ## The length of the subject
    start_match*     : cint       ## Offset to start of this match attempt
    current_position*: cint       ## Where we currently are in the subject
    capture_top*     : cint       ## Max current capture
    capture_last*    : cint       ## Most recently closed capture
    callout_data*    : pointer    ## Data passed in with the call
    # ------------------- Added for Version 1 --------------------------
    pattern_position*: cint       ## Offset to next item in the pattern
    next_item_length*: cint       ## Length of next item in the pattern
    # ------------------- Added for Version 2 --------------------------
    mark*            : pointer    ## Pointer to current mark or NULL
    # ------------------------------------------------------------------

when defined(nimHasStyleChecks):
  {.pop.}

# User defined callback which provides a stack just before the match starts.
type
  JitCallback* = proc (a: pointer): ptr JitStack {.cdecl.}


when not defined(usePcreHeader):
  when hostOS == "windows":
    const pcreDll = "libpcre2-8-0.dll"
  elif hostOS == "macosx":
    const pcreDll = "libpcre2-8.0.dylib"
  else:
    const pcreDll = "libpcre2-8.so.0"
  {.push dynlib: pcreDll.}
else:
  {.push header: "<pcre2.h>".}

{.push cdecl, importc: "pcre2_$1_8".}

# Exported PCRE functions

proc compile*(pattern: cstring,
              options: csize_t,
              flags: uint32,
              errorCode: ptr cint,
              offset: ptr csize_t,
              tableptr: pointer): ptr Pcre

proc config*(what: uint32,
             where: pointer): cint

proc dfa_match*(code: ptr Pcre,
               subject: cstring,
               length: csize_t,
               startoffset: csize_t,
               options: uint32,
               ovector: ptr MatchData,
               ovecsize: pointer, # TODO: pcre2_match_context
               workspace: ptr cint,
               wscount: csize_t): cint

proc match*(code: ptr Pcre,
           subject: cstring,
           length: csize_t,
           startoffset: csize_t,
           options: uint32,
           ovector: ptr MatchData,
           ovecsize: pointer # TODO: pcre2_match_context
           ): cint

proc match_data_create*(size: uint32, ctx: ptr GeneralContext): ptr MatchData

proc match_data_create_from_pattern*(
  code: ptr Pcre,
  ctx: ptr GeneralContext
): ptr MatchData

proc match_data_free*(data: ptr MatchData)

proc get_ovector_pointer*(ovector: ptr MatchData): ptr csize_t

proc get_ovector_count*(ovector: ptr MatchData): uint32

proc jit_match*(code: ptr Pcre,
               subject: cstring,
               length: csize_t,
               startoffset: csize_t,
               options: uint32,
               ovector: ptr MatchData,
               ovecsize: pointer # TODO: pcre2_match_context
               ): cint

proc code_free*(code: ptr Pcre)

proc pattern_info*(code: ptr Pcre,
               what: uint32,
               where: pointer): cint

# JIT compiler related functions.

proc jit_compile*(code: ptr Pcre, options: uint32): cint


{.pop.}
{.pop.}

