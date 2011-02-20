/* Generated by Nimrod Compiler v0.8.11 */
/*   (c) 2011 Andreas Rumpf */

typedef long int NI;
typedef unsigned long int NU;
#include "nimbase.h"

typedef struct TY191208 TY191208;
typedef struct TY191206 TY191206;
typedef struct NimStringDesc NimStringDesc;
typedef struct TGenericSeq TGenericSeq;
typedef struct TY55548 TY55548;
typedef struct TNimType TNimType;
typedef struct TNimNode TNimNode;
typedef struct TY10802 TY10802;
typedef struct TY10818 TY10818;
typedef struct TY11196 TY11196;
typedef struct TY10814 TY10814;
typedef struct TY10810 TY10810;
typedef struct TY11194 TY11194;
typedef struct TY43019 TY43019;
typedef struct TY43013 TY43013;
typedef struct TY38661 TY38661;
typedef struct TY55526 TY55526;
typedef struct TY93031 TY93031;
typedef struct TY54005 TY54005;
typedef struct TNimObject TNimObject;
typedef struct TY55552 TY55552;
typedef struct TY54011 TY54011;
typedef struct TY47538 TY47538;
typedef struct TY55530 TY55530;
typedef struct TY55528 TY55528;
typedef struct TY55540 TY55540;
typedef struct TY52008 TY52008;
typedef struct TY55544 TY55544;
typedef struct TY75204 TY75204;
typedef struct TY105006 TY105006;
typedef struct TY105002 TY105002;
typedef struct TY77267 TY77267;
typedef struct TY76015 TY76015;
typedef struct TY77281 TY77281;
typedef struct TY77263 TY77263;
typedef struct TY55520 TY55520;
typedef struct TY39221 TY39221;
typedef struct TY93029 TY93029;
typedef struct TY60215 TY60215;
typedef struct TY60213 TY60213;
typedef struct TY60211 TY60211;
typedef struct TY55564 TY55564;
typedef struct TY55562 TY55562;
typedef struct TY55560 TY55560;
typedef struct TY55550 TY55550;
struct TGenericSeq {
NI len;
NI space;
};
typedef NIM_CHAR TY239[100000001];
struct NimStringDesc {
  TGenericSeq Sup;
TY239 data;
};
struct TY191206 {
NimStringDesc* Filename;
TY55548* Module;
};
struct TNimType {
NI size;
NU8 kind;
NU8 flags;
TNimType* base;
TNimNode* node;
void* finalizer;
};
struct TNimNode {
NU8 kind;
NI offset;
TNimType* typ;
NCSTRING name;
NI len;
TNimNode** sons;
};
struct TY10802 {
NI Refcount;
TNimType* Typ;
};
struct TY10818 {
NI Len;
NI Cap;
TY10802** D;
};
struct TY10814 {
NI Counter;
NI Max;
TY10810* Head;
TY10810** Data;
};
struct TY11194 {
NI Stackscans;
NI Cyclecollections;
NI Maxthreshold;
NI Maxstacksize;
NI Maxstackcells;
NI Cycletablesize;
};
struct TY11196 {
TY10818 Zct;
TY10818 Decstack;
TY10814 Cycleroots;
TY10818 Tempstack;
TY11194 Stat;
};
struct TY43019 {
TNimType* m_type;
TY43013* Head;
TY43013* Tail;
NI Counter;
};
struct TY38661 {
NimStringDesc* Dir;
NimStringDesc* Name;
NimStringDesc* Ext;
};
typedef N_NIMCALL_PTR(TY55526*, TY105045) (NimStringDesc* Filename_105046);
typedef N_NIMCALL_PTR(TY55548*, TY105041) (NimStringDesc* Filename_105042);
struct TNimObject {
TNimType* m_type;
};
struct TY54005 {
  TNimObject Sup;
NI Id;
};
struct TY47538 {
NI16 Line;
NI16 Col;
int Fileindex;
};
struct TY55530 {
TNimType* m_type;
NI Counter;
TY55528* Data;
};
struct TY55540 {
NU8 K;
NU8 S;
NU8 Flags;
TY55552* T;
TY52008* R;
NI A;
};
struct TY55548 {
  TY54005 Sup;
NU8 Kind;
NU8 Magic;
TY55552* Typ;
TY54011* Name;
TY47538 Info;
TY55548* Owner;
NU32 Flags;
TY55530 Tab;
TY55526* Ast;
NU32 Options;
NI Position;
NI Offset;
TY55540 Loc;
TY55544* Annex;
};
struct TY54011 {
  TY54005 Sup;
NimStringDesc* S;
TY54011* Next;
NI H;
};
typedef N_NIMCALL_PTR(TY105002*, TY105007) (TY55548* Module_105008, NimStringDesc* Filename_105009);
typedef N_NIMCALL_PTR(TY105002*, TY105012) (TY55548* Module_105013, NimStringDesc* Filename_105014, TY93031* Rd_105015);
typedef N_NIMCALL_PTR(TY55526*, TY105018) (TY105002* P_105019, TY55526* N_105020);
typedef N_NIMCALL_PTR(TY55526*, TY105023) (TY105002* P_105024, TY55526* Toplevelstmt_105025);
struct TY105006 {
TY105007 Open;
TY105012 Opencached;
TY105018 Close;
TY105023 Process;
};
struct TY76015 {
  TNimObject Sup;
NI Bufpos;
NCSTRING Buf;
NI Buflen;
TY75204* Stream;
NI Linenumber;
NI Sentinel;
NI Linestart;
};
struct TY77267 {
  TY76015 Sup;
NimStringDesc* Filename;
TY77281* Indentstack;
NI Dedent;
NI Indentahead;
};
struct TY77263 {
TNimType* m_type;
NU8 Toktype;
NI Indent;
TY54011* Ident;
NI64 Inumber;
NF64 Fnumber;
NU8 Base;
NimStringDesc* Literal;
TY77263* Next;
};
typedef NI TY8814[16];
struct TY10810 {
TY10810* Next;
NI Key;
TY8814 Bits;
};
struct TY43013 {
  TNimObject Sup;
TY43013* Prev;
TY43013* Next;
};
struct TY55526 {
TY55552* Typ;
NimStringDesc* Comment;
TY47538 Info;
NU8 Flags;
NU8 Kind;
union {
struct {NI64 Intval;
} S1;
struct {NF64 Floatval;
} S2;
struct {NimStringDesc* Strval;
} S3;
struct {TY55548* Sym;
} S4;
struct {TY54011* Ident;
} S5;
struct {TY55520* Sons;
} S6;
} KindU;
};
struct TY60211 {
NI Key;
NI Val;
};
struct TY60215 {
NI Counter;
TY60213* Data;
};
struct TY93029 {
NI Lastidxkey;
NI Lastidxval;
TY60215 Tab;
TY52008* R;
NI Offset;
};
struct TY55560 {
TY54005* Key;
TNimObject* Val;
};
struct TY55564 {
NI Counter;
TY55562* Data;
};
struct TY93031 {
  TNimObject Sup;
NI Pos;
NimStringDesc* S;
NU32 Options;
NU8 Reason;
TY39221* Moddeps;
TY39221* Files;
NI Dataidx;
NI Convertersidx;
NI Initidx;
NI Interfidx;
NI Compilerprocsidx;
NI Cgenidx;
NimStringDesc* Filename;
TY93029 Index;
TY93029 Imports;
NI Readerindex;
NI Line;
NI Moduleid;
TY55564 Syms;
};
struct TY55552 {
  TY54005 Sup;
NU8 Kind;
TY55550* Sons;
TY55526* N;
NU8 Flags;
NU8 Callconv;
TY55548* Owner;
TY55548* Sym;
NI64 Size;
NI Align;
NI Containerid;
TY55540 Loc;
};
struct TY52008 {
  TNimObject Sup;
TY52008* Left;
TY52008* Right;
NI Length;
NimStringDesc* Data;
};
struct TY55544 {
  TY43013 Sup;
NU8 Kind;
NIM_BOOL Generated;
TY52008* Name;
TY55526* Path;
};
struct TY75204 {
  TNimObject Sup;
NU8 Kind;
FILE* F;
NimStringDesc* S;
NI Rd;
NI Wr;
NI Lineoffset;
};
struct TY105002 {
  TNimObject Sup;
};
struct TY191208 {
  TGenericSeq Sup;
  TY191206 data[SEQ_DECL_SIZE];
};
struct TY55528 {
  TGenericSeq Sup;
  TY55548* data[SEQ_DECL_SIZE];
};
struct TY77281 {
  TGenericSeq Sup;
  NI data[SEQ_DECL_SIZE];
};
struct TY55520 {
  TGenericSeq Sup;
  TY55526* data[SEQ_DECL_SIZE];
};
struct TY39221 {
  TGenericSeq Sup;
  NimStringDesc* data[SEQ_DECL_SIZE];
};
struct TY60213 {
  TGenericSeq Sup;
  TY60211 data[SEQ_DECL_SIZE];
};
struct TY55562 {
  TGenericSeq Sup;
  TY55560 data[SEQ_DECL_SIZE];
};
struct TY55550 {
  TGenericSeq Sup;
  TY55552* data[SEQ_DECL_SIZE];
};
N_NIMCALL(void*, newSeq)(TNimType* Typ_14404, NI Len_14405);
static N_INLINE(void, asgnRefNoCycle)(void** Dest_13218, void* Src_13219);
static N_INLINE(TY10802*, Usrtocell_11612)(void* Usr_11614);
static N_INLINE(NI, Atomicinc_3221)(NI* Memloc_3224, NI X_3225);
static N_INLINE(NI, Atomicdec_3226)(NI* Memloc_3229, NI X_3230);
static N_INLINE(void, Rtladdzct_12601)(TY10802* C_12603);
N_NOINLINE(void, Addzct_11601)(TY10818* S_11604, TY10802* C_11605);
N_NIMCALL(void, Appendstr_43061)(TY43019* List_43064, NimStringDesc* Data_43065);
N_NIMCALL(void, Prependstr_43071)(TY43019* List_43074, NimStringDesc* Data_43075);
N_NIMCALL(void, nossplitFile)(NimStringDesc* Path_38660, TY38661* Result);
static N_INLINE(void, Setid_55696)(NI Id_55698);
N_NIMCALL(TY55526*, Parsefile_92031)(NimStringDesc* Filename_92033);
N_NIMCALL(TY55548*, Importmodule_191325)(NimStringDesc* Filename_191327);
N_NIMCALL(TY55548*, Getmodule_191256)(NimStringDesc* Filename_191258);
N_NIMCALL(NIM_BOOL, nossameFile)(NimStringDesc* Path1_38850, NimStringDesc* Path2_38851);
N_NIMCALL(TY55548*, Compilemodule_191320)(NimStringDesc* Filename_191322, NIM_BOOL Ismainfile_191323, NIM_BOOL Issystemfile_191324);
N_NIMCALL(NimStringDesc*, nosaddFileExt)(NimStringDesc* Filename_38830, NimStringDesc* Ext_38831);
N_NIMCALL(TY55548*, Newmodule_191287)(NimStringDesc* Filename_191289);
N_NIMCALL(void*, newObj)(TNimType* Typ_13910, NI Size_13911);
N_NIMCALL(void, objectInit)(void* Dest_19676, TNimType* Typ_19677);
N_NIMCALL(TY54011*, Getident_54016)(NimStringDesc* Identifier_54018);
N_NIMCALL(NIM_BOOL, Isnimrodidentifier_77357)(NimStringDesc* S_77359);
N_NIMCALL(void, Rawmessage_48045)(NU8 Msg_48047, NimStringDesc* Arg_48048);
static N_INLINE(void, asgnRef)(void** Dest_13214, void* Src_13215);
static N_INLINE(void, Incref_13202)(TY10802* C_13204);
static N_INLINE(NIM_BOOL, Canbecycleroot_11616)(TY10802* C_11618);
static N_INLINE(void, Rtladdcycleroot_12252)(TY10802* C_12254);
N_NOINLINE(void, Incl_11080)(TY10814* S_11083, TY10802* Cell_11084);
static N_INLINE(void, Decref_13001)(TY10802* C_13003);
N_NIMCALL(TY47538, Newlineinfo_47712)(NimStringDesc* Filename_47714, NI Line_47715, NI Col_47716);
N_NIMCALL(void, Initstrtable_55747)(TY55530* X_55750);
N_NIMCALL(void, Registermodule_191229)(NimStringDesc* Filename_191231, TY55548* Module_191232);
N_NIMCALL(TGenericSeq*, setLengthSeq)(TGenericSeq* Seq_19003, NI Elemsize_19004, NI Newlen_19005);
N_NIMCALL(NimStringDesc*, copyString)(NimStringDesc* Src_18712);
N_NIMCALL(void, Strtableadd_60061)(TY55530* T_60064, TY55548* N_60065);
N_NIMCALL(TY93031*, Handlesymbolfile_93060)(TY55548* Module_93062, NimStringDesc* Filename_93063);
N_NIMCALL(void, Internalerror_48163)(NimStringDesc* Errmsg_48165);
static N_INLINE(NI, Getid_55694)(void);
N_NIMCALL(void, Processmodule_105035)(TY55548* Module_105037, NimStringDesc* Filename_105038, TY75204* Stream_105039, TY93031* Rd_105040);
N_NIMCALL(void, Localerror_48144)(TY47538 Info_48146, NU8 Msg_48147, NimStringDesc* Arg_48148);
N_NIMCALL(NU8, Whichkeyword_72482)(NimStringDesc* Id_72484);
N_NIMCALL(void, Wantfile_191707)(NimStringDesc* Filename_191709);
N_NIMCALL(void, Fatal_48134)(TY47538 Info_48136, NU8 Msg_48137, NimStringDesc* Arg_48138);
N_NIMCALL(void, Commandcompiletoc_191416)(NimStringDesc* Filename_191418);
N_NIMCALL(void, Semanticpasses_191408)(void);
N_NIMCALL(void, Registerpass_105028)(TY105006* P_105030);
N_NIMCALL(TY105006, Verbosepass_186033)(void);
N_NIMCALL(TY105006, Sempass_126001)(void);
N_NIMCALL(TY105006, Transfpass_188005)(void);
N_NIMCALL(TY105006, Cgenpass_161201)(void);
N_NIMCALL(TY105006, Rodwritepass_111001)(void);
N_NIMCALL(void, Compileproject_191405)(NimStringDesc* Filename_191407);
N_NIMCALL(NimStringDesc*, nosJoinPath)(NimStringDesc* Head_38403, NimStringDesc* Tail_38404);
N_NIMCALL(void, Callccompiler_70806)(NimStringDesc* Projectfile_70808);
N_NIMCALL(NimStringDesc*, nosChangeFileExt)(NimStringDesc* Filename_38820, NimStringDesc* Ext_38821);
N_NIMCALL(void, Commandcompiletoecmascript_191601)(NimStringDesc* Filename_191603);
N_NIMCALL(void, Settarget_51582)(NU8 O_51584, NU8 C_51585);
N_NIMCALL(void, Initdefines_64049)(void);
N_NIMCALL(TY105006, Ecmasgenpass_178004)(void);
N_NIMCALL(void, Commandpretty_191643)(NimStringDesc* Filename_191645);
N_NIMCALL(void, Rendermodule_85035)(TY55526* N_85037, NimStringDesc* Filename_85038, NU8 Renderflags_85041);
N_NIMCALL(NimStringDesc*, Getoutfile_46145)(NimStringDesc* Filename_46147, NimStringDesc* Ext_46148);
N_NIMCALL(void, Loadspecialconfig_80007)(NimStringDesc* Configfilename_80009);
N_NIMCALL(void, Commanddoc_156001)(NimStringDesc* Filename_156003);
N_NIMCALL(void, Commandrst2html_156004)(NimStringDesc* Filename_156006);
N_NIMCALL(void, Commandrst2tex_156007)(NimStringDesc* Filename_156009);
N_NIMCALL(void, Commandgendepend_191410)(NimStringDesc* Filename_191412);
N_NIMCALL(TY105006, Gendependpass_187004)(void);
N_NIMCALL(TY105006, Cleanuppass_186161)(void);
N_NIMCALL(void, Generatedot_187006)(NimStringDesc* Project_187008);
N_NIMCALL(void, Execexternalprogram_70570)(NimStringDesc* Cmd_70572);
static N_INLINE(void, appendString)(NimStringDesc* Dest_18799, NimStringDesc* Src_18800);
static N_INLINE(void, appendChar)(NimStringDesc* Dest_18816, NIM_CHAR C_18817);
N_NIMCALL(NimStringDesc*, rawNewString)(NI Space_18689);
N_NIMCALL(void, Listsymbols_64062)(void);
N_NIMCALL(void, Commandcheck_191413)(NimStringDesc* Filename_191415);
N_NIMCALL(void, Commandscan_191658)(NimStringDesc* Filename_191660);
N_NIMCALL(TY75204*, Llstreamopen_75224)(NimStringDesc* Filename_75226, NU8 Mode_75227);
N_NIMCALL(void, Openlexer_77298)(TY77267* Lex_77301, NimStringDesc* Filename_77302, TY75204* Inputstream_77303);
N_NIMCALL(void, Rawgettok_77304)(TY77267* L_77307, TY77263* Tok_77309);
N_NIMCALL(void, Printtok_77320)(TY77263* Tok_77322);
N_NIMCALL(void, Closelexer_77316)(TY77267* Lex_77319);
N_NIMCALL(void, Messageout_47775)(NimStringDesc* S_47777);
N_NIMCALL(void, Commandinteractive_191616)(void);
N_NIMCALL(TY105006, Evalpass_115046)(void);
N_NIMCALL(TY75204*, Llstreamopenstdin_75230)(void);
N_NIMCALL(void, Commandsuggest_191704)(NimStringDesc* Filename_191706);
STRING_LITERAL(TMP195864, "nim", 3);
STRING_LITERAL(TMP195917, "handleSymbolFile should have set the module\'s ID", 48);
STRING_LITERAL(TMP195919, "command line", 12);
STRING_LITERAL(TMP195920, "", 0);
STRING_LITERAL(TMP196860, "system", 6);
STRING_LITERAL(TMP196878, ".cpp", 4);
STRING_LITERAL(TMP196879, ".m", 2);
STRING_LITERAL(TMP197082, "pretty.nim", 10);
STRING_LITERAL(TMP197083, "nimdoc.cfg", 10);
STRING_LITERAL(TMP197486, "nimdoc.tex.cfg", 14);
STRING_LITERAL(TMP197494, "dot -Tpng -o", 12);
STRING_LITERAL(TMP197495, "png", 3);
STRING_LITERAL(TMP197496, "dot", 3);
STRING_LITERAL(TMP197498, "Beware: Indentation tokens depend on the parser\'s state!", 56);
STRING_LITERAL(TMP197499, "stdin", 5);
TY191208* Compmods_191227;
extern TNimType* NTI191208; /* TFileModuleMap */
extern TY11196 Gch_11214;
extern TY43019 Searchpaths_46081;
extern NimStringDesc* Libpath_46112;
extern NI Gid_55693;
extern TY105045 Gincludefile_105048;
extern TY105041 Gimportmodule_105044;
extern TNimType* NTI55524; /* PSym */
extern TNimType* NTI55548; /* TSym */
extern NU8 Gcmd_46084;
extern NimStringDesc* Cext_70342;
extern NU32 Gglobaloptions_46079;
extern NI Gerrormax_47568;
extern TNimType* NTI77267; /* TLexer */
extern TNimType* NTI77261; /* PToken */
extern TNimType* NTI77263; /* TToken */
static N_INLINE(TY10802*, Usrtocell_11612)(void* Usr_11614) {
TY10802* Result_11615;
Result_11615 = 0;
Result_11615 = ((TY10802*) ((NI32)((NU32)(((NI) (Usr_11614))) - (NU32)(((NI) (((NI)sizeof(TY10802))))))));
return Result_11615;
}
static N_INLINE(NI, Atomicinc_3221)(NI* Memloc_3224, NI X_3225) {
NI Result_7807;
Result_7807 = 0;
(*Memloc_3224) += X_3225;
Result_7807 = (*Memloc_3224);
return Result_7807;
}
static N_INLINE(NI, Atomicdec_3226)(NI* Memloc_3229, NI X_3230) {
NI Result_8006;
Result_8006 = 0;
(*Memloc_3229) -= X_3230;
Result_8006 = (*Memloc_3229);
return Result_8006;
}
static N_INLINE(void, Rtladdzct_12601)(TY10802* C_12603) {
Addzct_11601(&Gch_11214.Zct, C_12603);
}
static N_INLINE(void, asgnRefNoCycle)(void** Dest_13218, void* Src_13219) {
TY10802* C_13220;
NI LOC4;
TY10802* C_13222;
NI LOC9;
if (!!((Src_13219 == NIM_NIL))) goto LA2;
C_13220 = 0;
C_13220 = Usrtocell_11612(Src_13219);
LOC4 = Atomicinc_3221(&(*C_13220).Refcount, 8);
LA2: ;
if (!!(((*Dest_13218) == NIM_NIL))) goto LA6;
C_13222 = 0;
C_13222 = Usrtocell_11612((*Dest_13218));
LOC9 = Atomicdec_3226(&(*C_13222).Refcount, 8);
if (!((NU32)(LOC9) < (NU32)(8))) goto LA10;
Rtladdzct_12601(C_13222);
LA10: ;
LA6: ;
(*Dest_13218) = Src_13219;
}
static N_INLINE(void, Setid_55696)(NI Id_55698) {
Gid_55693 = ((Gid_55693 >= (NI32)(Id_55698 + 1)) ? Gid_55693 : (NI32)(Id_55698 + 1));
}
N_NIMCALL(TY55548*, Getmodule_191256)(NimStringDesc* Filename_191258) {
TY55548* Result_191259;
NI I_191283;
NI HEX3Atmp_191284;
NI Res_191286;
NIM_BOOL LOC3;
Result_191259 = 0;
I_191283 = 0;
HEX3Atmp_191284 = 0;
HEX3Atmp_191284 = (Compmods_191227->Sup.len-1);
Res_191286 = 0;
Res_191286 = 0;
while (1) {
if (!(Res_191286 <= HEX3Atmp_191284)) goto LA1;
I_191283 = Res_191286;
LOC3 = nossameFile(Compmods_191227->data[I_191283].Filename, Filename_191258);
if (!LOC3) goto LA4;
Result_191259 = Compmods_191227->data[I_191283].Module;
goto BeforeRet;
LA4: ;
Res_191286 += 1;
} LA1: ;
BeforeRet: ;
return Result_191259;
}
static N_INLINE(NIM_BOOL, Canbecycleroot_11616)(TY10802* C_11618) {
NIM_BOOL Result_11619;
Result_11619 = 0;
Result_11619 = !((((*(*C_11618).Typ).flags &(1<<((((NU8) 1))&7)))!=0));
return Result_11619;
}
static N_INLINE(void, Rtladdcycleroot_12252)(TY10802* C_12254) {
Incl_11080(&Gch_11214.Cycleroots, C_12254);
}
static N_INLINE(void, Incref_13202)(TY10802* C_13204) {
NI LOC1;
NIM_BOOL LOC3;
LOC1 = Atomicinc_3221(&(*C_13204).Refcount, 8);
LOC3 = Canbecycleroot_11616(C_13204);
if (!LOC3) goto LA4;
Rtladdcycleroot_12252(C_13204);
LA4: ;
}
static N_INLINE(void, Decref_13001)(TY10802* C_13003) {
NI LOC2;
NIM_BOOL LOC5;
LOC2 = Atomicdec_3226(&(*C_13003).Refcount, 8);
if (!((NU32)(LOC2) < (NU32)(8))) goto LA3;
Rtladdzct_12601(C_13003);
goto LA1;
LA3: ;
LOC5 = Canbecycleroot_11616(C_13003);
if (!LOC5) goto LA6;
Rtladdcycleroot_12252(C_13003);
goto LA1;
LA6: ;
LA1: ;
}
static N_INLINE(void, asgnRef)(void** Dest_13214, void* Src_13215) {
TY10802* LOC4;
TY10802* LOC8;
if (!!((Src_13215 == NIM_NIL))) goto LA2;
LOC4 = Usrtocell_11612(Src_13215);
Incref_13202(LOC4);
LA2: ;
if (!!(((*Dest_13214) == NIM_NIL))) goto LA6;
LOC8 = Usrtocell_11612((*Dest_13214));
Decref_13001(LOC8);
LA6: ;
(*Dest_13214) = Src_13215;
}
N_NIMCALL(void, Registermodule_191229)(NimStringDesc* Filename_191231, TY55548* Module_191232) {
NI Length_191243;
Length_191243 = 0;
Length_191243 = Compmods_191227->Sup.len;
Compmods_191227 = (TY191208*) setLengthSeq(&(Compmods_191227)->Sup, sizeof(TY191206), (NI32)(Length_191243 + 1));
asgnRefNoCycle((void**) &Compmods_191227->data[Length_191243].Filename, copyString(Filename_191231));
asgnRef((void**) &Compmods_191227->data[Length_191243].Module, Module_191232);
}
N_NIMCALL(TY55548*, Newmodule_191287)(NimStringDesc* Filename_191289) {
TY55548* Result_191290;
TY38661 LOC1;
NIM_BOOL LOC3;
Result_191290 = 0;
Result_191290 = (TY55548*) newObj(NTI55524, sizeof(TY55548));
objectInit(Result_191290, NTI55548);
(*Result_191290).Sup.Id = -1;
(*Result_191290).Kind = ((NU8) 6);
memset((void*)&LOC1, 0, sizeof(LOC1));
nossplitFile(Filename_191289, &LOC1);
asgnRefNoCycle((void**) &(*Result_191290).Name, Getident_54016(LOC1.Name));
LOC3 = Isnimrodidentifier_77357((*(*Result_191290).Name).S);
if (!!(LOC3)) goto LA4;
Rawmessage_48045(((NU8) 19), (*(*Result_191290).Name).S);
LA4: ;
asgnRef((void**) &(*Result_191290).Owner, Result_191290);
(*Result_191290).Info = Newlineinfo_47712(Filename_191289, 1, 1);
(*Result_191290).Flags |=(1<<((NI32)(((NU8) 0))%(sizeof(NI32)*8)));
Initstrtable_55747(&(*Result_191290).Tab);
Registermodule_191229(Filename_191289, Result_191290);
Strtableadd_60061(&(*Result_191290).Tab, Result_191290);
return Result_191290;
}
static N_INLINE(NI, Getid_55694)(void) {
NI Result_55943;
Result_55943 = 0;
Result_55943 = Gid_55693;
Gid_55693 += 1;
return Result_55943;
}
N_NIMCALL(TY55548*, Compilemodule_191320)(NimStringDesc* Filename_191322, NIM_BOOL Ismainfile_191323, NIM_BOOL Issystemfile_191324) {
TY55548* Result_191356;
TY93031* Rd_191357;
NimStringDesc* F_191358;
NIM_BOOL LOC8;
Result_191356 = 0;
Rd_191357 = 0;
Rd_191357 = NIM_NIL;
F_191358 = 0;
F_191358 = nosaddFileExt(Filename_191322, ((NimStringDesc*) &TMP195864));
Result_191356 = Newmodule_191287(Filename_191322);
if (!Ismainfile_191323) goto LA2;
(*Result_191356).Flags |=(1<<((NI32)(((NU8) 15))%(sizeof(NI32)*8)));
LA2: ;
if (!Issystemfile_191324) goto LA5;
(*Result_191356).Flags |=(1<<((NI32)(((NU8) 16))%(sizeof(NI32)*8)));
LA5: ;
LOC8 = (Gcmd_46084 == ((NU8) 1));
if (LOC8) goto LA9;
LOC8 = (Gcmd_46084 == ((NU8) 2));
LA9: ;
if (!LOC8) goto LA10;
Rd_191357 = Handlesymbolfile_93060(Result_191356, F_191358);
if (!((*Result_191356).Sup.Id < 0)) goto LA13;
Internalerror_48163(((NimStringDesc*) &TMP195917));
LA13: ;
goto LA7;
LA10: ;
(*Result_191356).Sup.Id = Getid_55694();
LA7: ;
Processmodule_105035(Result_191356, F_191358, NIM_NIL, Rd_191357);
return Result_191356;
}
N_NIMCALL(TY55548*, Importmodule_191325)(NimStringDesc* Filename_191327) {
TY55548* Result_191328;
Result_191328 = 0;
Result_191328 = Getmodule_191256(Filename_191327);
if (!(Result_191328 == NIM_NIL)) goto LA2;
Result_191328 = Compilemodule_191320(Filename_191327, NIM_FALSE, NIM_FALSE);
goto LA1;
LA2: ;
if (!(((*Result_191328).Flags &(1<<((((NU8) 16))&31)))!=0)) goto LA4;
Localerror_48144((*Result_191328).Info, ((NU8) 37), (*(*Result_191328).Name).S);
goto LA1;
LA4: ;
LA1: ;
return Result_191328;
}
N_NIMCALL(void, Wantfile_191707)(NimStringDesc* Filename_191709) {
TY47538 LOC4;
if (!((Filename_191709) && (Filename_191709)->Sup.len == 0)) goto LA2;
LOC4 = Newlineinfo_47712(((NimStringDesc*) &TMP195919), 1, 1);
Fatal_48134(LOC4, ((NU8) 182), ((NimStringDesc*) &TMP195920));
LA2: ;
}
N_NIMCALL(void, Semanticpasses_191408)(void) {
TY105006 LOC1;
TY105006 LOC2;
TY105006 LOC3;
LOC1 = Verbosepass_186033();
Registerpass_105028(&LOC1);
LOC2 = Sempass_126001();
Registerpass_105028(&LOC2);
LOC3 = Transfpass_188005();
Registerpass_105028(&LOC3);
}
N_NIMCALL(void, Compileproject_191405)(NimStringDesc* Filename_191407) {
NimStringDesc* LOC1;
NimStringDesc* LOC2;
TY55548* LOC3;
NimStringDesc* LOC4;
TY55548* LOC5;
LOC1 = 0;
LOC1 = nosaddFileExt(((NimStringDesc*) &TMP196860), ((NimStringDesc*) &TMP195864));
LOC2 = 0;
LOC2 = nosJoinPath(Libpath_46112, LOC1);
LOC3 = 0;
LOC3 = Compilemodule_191320(LOC2, NIM_FALSE, NIM_TRUE);
LOC4 = 0;
LOC4 = nosaddFileExt(Filename_191407, ((NimStringDesc*) &TMP195864));
LOC5 = 0;
LOC5 = Compilemodule_191320(LOC4, NIM_TRUE, NIM_FALSE);
}
N_NIMCALL(void, Commandcompiletoc_191416)(NimStringDesc* Filename_191418) {
TY105006 LOC1;
TY105006 LOC2;
NimStringDesc* LOC6;
Semanticpasses_191408();
LOC1 = Cgenpass_161201();
Registerpass_105028(&LOC1);
LOC2 = Rodwritepass_111001();
Registerpass_105028(&LOC2);
Compileproject_191405(Filename_191418);
if (!!((Gcmd_46084 == ((NU8) 18)))) goto LA4;
LOC6 = 0;
LOC6 = nosChangeFileExt(Filename_191418, ((NimStringDesc*) &TMP195920));
Callccompiler_70806(LOC6);
LA4: ;
}
N_NIMCALL(void, Commandcompiletoecmascript_191601)(NimStringDesc* Filename_191603) {
TY105006 LOC1;
Gglobaloptions_46079 |=(1<<((NI32)(((NU8) 8))%(sizeof(NI32)*8)));
Settarget_51582(((NU8) 20), ((NU8) 12));
Initdefines_64049();
Semanticpasses_191408();
LOC1 = Ecmasgenpass_178004();
Registerpass_105028(&LOC1);
Compileproject_191405(Filename_191603);
}
N_NIMCALL(void, Commandpretty_191643)(NimStringDesc* Filename_191645) {
TY55526* Module_191646;
NimStringDesc* LOC1;
NimStringDesc* LOC5;
Module_191646 = 0;
LOC1 = 0;
LOC1 = nosaddFileExt(Filename_191645, ((NimStringDesc*) &TMP195864));
Module_191646 = Parsefile_92031(LOC1);
if (!!((Module_191646 == NIM_NIL))) goto LA3;
LOC5 = 0;
LOC5 = Getoutfile_46145(Filename_191645, ((NimStringDesc*) &TMP197082));
Rendermodule_85035(Module_191646, LOC5, 0);
LA3: ;
}
static N_INLINE(void, appendString)(NimStringDesc* Dest_18799, NimStringDesc* Src_18800) {
memcpy(((NCSTRING) (&(*Dest_18799).data[((*Dest_18799).Sup.len)-0])), ((NCSTRING) ((*Src_18800).data)), ((int) ((NI32)((NI32)((*Src_18800).Sup.len + 1) * 1))));
(*Dest_18799).Sup.len += (*Src_18800).Sup.len;
}
static N_INLINE(void, appendChar)(NimStringDesc* Dest_18816, NIM_CHAR C_18817) {
(*Dest_18816).data[((*Dest_18816).Sup.len)-0] = C_18817;
(*Dest_18816).data[((NI32)((*Dest_18816).Sup.len + 1))-0] = 0;
(*Dest_18816).Sup.len += 1;
}
N_NIMCALL(void, Commandgendepend_191410)(NimStringDesc* Filename_191412) {
TY105006 LOC1;
TY105006 LOC2;
NimStringDesc* LOC3;
NimStringDesc* LOC4;
NimStringDesc* LOC5;
Semanticpasses_191408();
LOC1 = Gendependpass_187004();
Registerpass_105028(&LOC1);
LOC2 = Cleanuppass_186161();
Registerpass_105028(&LOC2);
Compileproject_191405(Filename_191412);
Generatedot_187006(Filename_191412);
LOC3 = 0;
LOC4 = 0;
LOC4 = nosChangeFileExt(Filename_191412, ((NimStringDesc*) &TMP197495));
LOC5 = 0;
LOC5 = nosChangeFileExt(Filename_191412, ((NimStringDesc*) &TMP197496));
LOC3 = rawNewString(LOC4->Sup.len + LOC5->Sup.len + 13);
appendString(LOC3, ((NimStringDesc*) &TMP197494));
appendString(LOC3, LOC4);
appendChar(LOC3, 32);
appendString(LOC3, LOC5);
Execexternalprogram_70570(LOC3);
}
N_NIMCALL(void, Commandcheck_191413)(NimStringDesc* Filename_191415) {
Gerrormax_47568 = 2147483647;
Semanticpasses_191408();
Compileproject_191405(Filename_191415);
}
N_NIMCALL(void, Commandscan_191658)(NimStringDesc* Filename_191660) {
NimStringDesc* F_191661;
TY75204* Stream_191662;
TY77267 L_191674;
TY77263* Tok_191675;
F_191661 = 0;
F_191661 = nosaddFileExt(Filename_191660, ((NimStringDesc*) &TMP195864));
Stream_191662 = 0;
Stream_191662 = Llstreamopen_75224(F_191661, ((NU8) 0));
if (!!((Stream_191662 == NIM_NIL))) goto LA2;
memset((void*)&L_191674, 0, sizeof(L_191674));
L_191674.Sup.Sup.m_type = NTI77267;
Tok_191675 = 0;
Tok_191675 = (TY77263*) newObj(NTI77261, sizeof(TY77263));
(*Tok_191675).m_type = NTI77263;
Openlexer_77298(&L_191674, F_191661, Stream_191662);
while (1) {
Rawgettok_77304(&L_191674, Tok_191675);
Printtok_77320(Tok_191675);
if (!((*Tok_191675).Toktype == ((NU8) 1))) goto LA6;
goto LA4;
LA6: ;
} LA4: ;
Closelexer_77316(&L_191674);
goto LA1;
LA2: ;
Rawmessage_48045(((NU8) 2), F_191661);
LA1: ;
}
N_NIMCALL(void, Commandinteractive_191616)(void) {
TY105006 LOC1;
TY105006 LOC2;
TY105006 LOC3;
TY105006 LOC4;
NimStringDesc* LOC5;
NimStringDesc* LOC6;
TY55548* LOC7;
TY55548* M_191630;
TY75204* LOC8;
Gerrormax_47568 = 2147483647;
Gglobaloptions_46079 |=(1<<((NI32)(((NU8) 8))%(sizeof(NI32)*8)));
Settarget_51582(((NU8) 21), ((NU8) 13));
Initdefines_64049();
LOC1 = Verbosepass_186033();
Registerpass_105028(&LOC1);
LOC2 = Sempass_126001();
Registerpass_105028(&LOC2);
LOC3 = Transfpass_188005();
Registerpass_105028(&LOC3);
LOC4 = Evalpass_115046();
Registerpass_105028(&LOC4);
LOC5 = 0;
LOC5 = nosaddFileExt(((NimStringDesc*) &TMP196860), ((NimStringDesc*) &TMP195864));
LOC6 = 0;
LOC6 = nosJoinPath(Libpath_46112, LOC5);
LOC7 = 0;
LOC7 = Compilemodule_191320(LOC6, NIM_FALSE, NIM_TRUE);
M_191630 = 0;
M_191630 = Newmodule_191287(((NimStringDesc*) &TMP197499));
(*M_191630).Sup.Id = Getid_55694();
(*M_191630).Flags |=(1<<((NI32)(((NU8) 15))%(sizeof(NI32)*8)));
LOC8 = 0;
LOC8 = Llstreamopenstdin_75230();
Processmodule_105035(M_191630, ((NimStringDesc*) &TMP197499), LOC8, NIM_NIL);
}
N_NIMCALL(void, Commandsuggest_191704)(NimStringDesc* Filename_191706) {
Gerrormax_47568 = 2147483647;
Semanticpasses_191408();
Compileproject_191405(Filename_191706);
}
N_NIMCALL(void, Maincommand_191201)(NimStringDesc* Cmd_191203, NimStringDesc* Filename_191204) {
TY38661 LOC4;
NU8 LOC5;
NimStringDesc* LOC6;
TY55526* LOC7;
Appendstr_43061(&Searchpaths_46081, Libpath_46112);
if (!!(((Filename_191204) && (Filename_191204)->Sup.len == 0))) goto LA2;
memset((void*)&LOC4, 0, sizeof(LOC4));
nossplitFile(Filename_191204, &LOC4);
Prependstr_43071(&Searchpaths_46081, LOC4.Dir);
LA2: ;
Setid_55696(100);
Gincludefile_105048 = Parsefile_92031;
Gimportmodule_105044 = Importmodule_191325;
LOC5 = Whichkeyword_72482(Cmd_191203);
switch (LOC5) {
case ((NU8) 107):
case ((NU8) 200):
case ((NU8) 176):
case ((NU8) 192):
Gcmd_46084 = ((NU8) 1);
Wantfile_191707(Filename_191204);
Commandcompiletoc_191416(Filename_191204);
break;
case ((NU8) 201):
asgnRefNoCycle((void**) &Cext_70342, copyString(((NimStringDesc*) &TMP196878)));
Gcmd_46084 = ((NU8) 2);
Wantfile_191707(Filename_191204);
Commandcompiletoc_191416(Filename_191204);
break;
case ((NU8) 204):
case ((NU8) 213):
asgnRefNoCycle((void**) &Cext_70342, copyString(((NimStringDesc*) &TMP196879)));
Gcmd_46084 = ((NU8) 3);
Wantfile_191707(Filename_191204);
Commandcompiletoc_191416(Filename_191204);
break;
case ((NU8) 179):
Gcmd_46084 = ((NU8) 18);
Wantfile_191707(Filename_191204);
Rawmessage_48045(((NU8) 176), Cmd_191203);
break;
case ((NU8) 202):
case ((NU8) 212):
Gcmd_46084 = ((NU8) 4);
Wantfile_191707(Filename_191204);
Commandcompiletoecmascript_191601(Filename_191204);
break;
case ((NU8) 203):
Gcmd_46084 = ((NU8) 5);
Wantfile_191707(Filename_191204);
Rawmessage_48045(((NU8) 176), Cmd_191203);
break;
case ((NU8) 205):
Gcmd_46084 = ((NU8) 7);
Wantfile_191707(Filename_191204);
Commandpretty_191643(Filename_191204);
break;
case ((NU8) 206):
Gcmd_46084 = ((NU8) 8);
Loadspecialconfig_80007(((NimStringDesc*) &TMP197083));
Wantfile_191707(Filename_191204);
Commanddoc_156001(Filename_191204);
break;
case ((NU8) 214):
Gcmd_46084 = ((NU8) 15);
Loadspecialconfig_80007(((NimStringDesc*) &TMP197083));
Wantfile_191707(Filename_191204);
Commandrst2html_156004(Filename_191204);
break;
case ((NU8) 215):
Gcmd_46084 = ((NU8) 16);
Loadspecialconfig_80007(((NimStringDesc*) &TMP197486));
Wantfile_191707(Filename_191204);
Commandrst2tex_156007(Filename_191204);
break;
case ((NU8) 207):
Gcmd_46084 = ((NU8) 9);
Wantfile_191707(Filename_191204);
Commandgendepend_191410(Filename_191204);
break;
case ((NU8) 208):
Gcmd_46084 = ((NU8) 10);
Listsymbols_64062();
break;
case ((NU8) 209):
Gcmd_46084 = ((NU8) 11);
Wantfile_191707(Filename_191204);
Commandcheck_191413(Filename_191204);
break;
case ((NU8) 210):
Gcmd_46084 = ((NU8) 12);
Wantfile_191707(Filename_191204);
LOC6 = 0;
LOC6 = nosaddFileExt(Filename_191204, ((NimStringDesc*) &TMP195864));
LOC7 = 0;
LOC7 = Parsefile_92031(LOC6);
break;
case ((NU8) 211):
Gcmd_46084 = ((NU8) 13);
Wantfile_191707(Filename_191204);
Commandscan_191658(Filename_191204);
Messageout_47775(((NimStringDesc*) &TMP197498));
break;
case ((NU8) 216):
Gcmd_46084 = ((NU8) 17);
Commandinteractive_191616();
break;
case ((NU8) 225):
Gcmd_46084 = ((NU8) 14);
Wantfile_191707(Filename_191204);
Commandsuggest_191704(Filename_191204);
break;
default:
Rawmessage_48045(((NU8) 176), Cmd_191203);
break;
}
}
N_NOINLINE(void, mainInit)(void) {
asgnRefNoCycle((void**) &Compmods_191227, (TY191208*) newSeq(NTI191208, 0));
}

