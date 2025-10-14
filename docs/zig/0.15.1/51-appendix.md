<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: Appendix -->
[Back to index](README.md)  |  Full reference: zig-0.15.1.md

## [Appendix](zig-0.15.1.md#toc-Appendix) <a href="zig-0.15.1.md#Appendix" class="hdr">§</a>

### [Containers](zig-0.15.1.md#toc-Containers) <a href="zig-0.15.1.md#Containers" class="hdr">§</a>

A *container* in Zig is any syntactical construct that acts as a namespace to hold [variable](zig-0.15.1.md#Container-Level-Variables) and [function](zig-0.15.1.md#Functions) declarations.
Containers are also type definitions which can be instantiated.
[Structs](zig-0.15.1.md#struct), [enums](zig-0.15.1.md#enum), [unions](zig-0.15.1.md#union), [opaques](zig-0.15.1.md#opaque), and even Zig source files themselves are containers.

Although containers (except Zig source files) use curly braces to surround their definition, they should not be confused with [blocks](zig-0.15.1.md#Blocks) or functions.
Containers do not contain statements.

### [Grammar](zig-0.15.1.md#toc-Grammar) <a href="zig-0.15.1.md#Grammar" class="hdr">§</a>

<figure>
<pre><code>Root &lt;- skip container_doc_comment? ContainerMembers eof

# *** Top level ***
ContainerMembers &lt;- ContainerDeclaration* (ContainerField COMMA)* (ContainerField / ContainerDeclaration*)

ContainerDeclaration &lt;- TestDecl / ComptimeDecl / doc_comment? KEYWORD_pub? Decl

TestDecl &lt;- KEYWORD_test (STRINGLITERALSINGLE / IDENTIFIER)? Block

ComptimeDecl &lt;- KEYWORD_comptime Block

Decl
    &lt;- (KEYWORD_export / KEYWORD_extern STRINGLITERALSINGLE? / KEYWORD_inline / KEYWORD_noinline)? FnProto (SEMICOLON / Block)
     / (KEYWORD_export / KEYWORD_extern STRINGLITERALSINGLE?)? KEYWORD_threadlocal? GlobalVarDecl

FnProto &lt;- KEYWORD_fn IDENTIFIER? LPAREN ParamDeclList RPAREN ByteAlign? AddrSpace? LinkSection? CallConv? EXCLAMATIONMARK? TypeExpr

VarDeclProto &lt;- (KEYWORD_const / KEYWORD_var) IDENTIFIER (COLON TypeExpr)? ByteAlign? AddrSpace? LinkSection?

GlobalVarDecl &lt;- VarDeclProto (EQUAL Expr)? SEMICOLON

ContainerField &lt;- doc_comment? KEYWORD_comptime? !KEYWORD_fn (IDENTIFIER COLON)? TypeExpr ByteAlign? (EQUAL Expr)?

# *** Block Level ***
Statement
    &lt;- KEYWORD_comptime ComptimeStatement
     / KEYWORD_nosuspend BlockExprStatement
     / KEYWORD_suspend BlockExprStatement
     / KEYWORD_defer BlockExprStatement
     / KEYWORD_errdefer Payload? BlockExprStatement
     / IfStatement
     / LabeledStatement
     / SwitchExpr
     / VarDeclExprStatement

ComptimeStatement
    &lt;- BlockExpr
     / VarDeclExprStatement

IfStatement
    &lt;- IfPrefix BlockExpr ( KEYWORD_else Payload? Statement )?
     / IfPrefix AssignExpr ( SEMICOLON / KEYWORD_else Payload? Statement )

LabeledStatement &lt;- BlockLabel? (Block / LoopStatement)

LoopStatement &lt;- KEYWORD_inline? (ForStatement / WhileStatement)

ForStatement
    &lt;- ForPrefix BlockExpr ( KEYWORD_else Statement )?
     / ForPrefix AssignExpr ( SEMICOLON / KEYWORD_else Statement )

WhileStatement
    &lt;- WhilePrefix BlockExpr ( KEYWORD_else Payload? Statement )?
     / WhilePrefix AssignExpr ( SEMICOLON / KEYWORD_else Payload? Statement )

BlockExprStatement
    &lt;- BlockExpr
     / AssignExpr SEMICOLON

BlockExpr &lt;- BlockLabel? Block

# An expression, assignment, or any destructure, as a statement.
VarDeclExprStatement
    &lt;- VarDeclProto (COMMA (VarDeclProto / Expr))* EQUAL Expr SEMICOLON
     / Expr (AssignOp Expr / (COMMA (VarDeclProto / Expr))+ EQUAL Expr)? SEMICOLON

# *** Expression Level ***

# An assignment or a destructure whose LHS are all lvalue expressions.
AssignExpr &lt;- Expr (AssignOp Expr / (COMMA Expr)+ EQUAL Expr)?

SingleAssignExpr &lt;- Expr (AssignOp Expr)?

Expr &lt;- BoolOrExpr

BoolOrExpr &lt;- BoolAndExpr (KEYWORD_or BoolAndExpr)*

BoolAndExpr &lt;- CompareExpr (KEYWORD_and CompareExpr)*

CompareExpr &lt;- BitwiseExpr (CompareOp BitwiseExpr)?

BitwiseExpr &lt;- BitShiftExpr (BitwiseOp BitShiftExpr)*

BitShiftExpr &lt;- AdditionExpr (BitShiftOp AdditionExpr)*

AdditionExpr &lt;- MultiplyExpr (AdditionOp MultiplyExpr)*

MultiplyExpr &lt;- PrefixExpr (MultiplyOp PrefixExpr)*

PrefixExpr &lt;- PrefixOp* PrimaryExpr

PrimaryExpr
    &lt;- AsmExpr
     / IfExpr
     / KEYWORD_break BreakLabel? Expr?
     / KEYWORD_comptime Expr
     / KEYWORD_nosuspend Expr
     / KEYWORD_continue BreakLabel?
     / KEYWORD_resume Expr
     / KEYWORD_return Expr?
     / BlockLabel? LoopExpr
     / Block
     / CurlySuffixExpr

IfExpr &lt;- IfPrefix Expr (KEYWORD_else Payload? Expr)?

Block &lt;- LBRACE Statement* RBRACE

LoopExpr &lt;- KEYWORD_inline? (ForExpr / WhileExpr)

ForExpr &lt;- ForPrefix Expr (KEYWORD_else Expr)?

WhileExpr &lt;- WhilePrefix Expr (KEYWORD_else Payload? Expr)?

CurlySuffixExpr &lt;- TypeExpr InitList?

InitList
    &lt;- LBRACE FieldInit (COMMA FieldInit)* COMMA? RBRACE
     / LBRACE Expr (COMMA Expr)* COMMA? RBRACE
     / LBRACE RBRACE

TypeExpr &lt;- PrefixTypeOp* ErrorUnionExpr

ErrorUnionExpr &lt;- SuffixExpr (EXCLAMATIONMARK TypeExpr)?

SuffixExpr
    &lt;- PrimaryTypeExpr (SuffixOp / FnCallArguments)*

PrimaryTypeExpr
    &lt;- BUILTINIDENTIFIER FnCallArguments
     / CHAR_LITERAL
     / ContainerDecl
     / DOT IDENTIFIER
     / DOT InitList
     / ErrorSetDecl
     / FLOAT
     / FnProto
     / GroupedExpr
     / LabeledTypeExpr
     / IDENTIFIER
     / IfTypeExpr
     / INTEGER
     / KEYWORD_comptime TypeExpr
     / KEYWORD_error DOT IDENTIFIER
     / KEYWORD_anyframe
     / KEYWORD_unreachable
     / STRINGLITERAL
     / SwitchExpr

ContainerDecl &lt;- (KEYWORD_extern / KEYWORD_packed)? ContainerDeclAuto

ErrorSetDecl &lt;- KEYWORD_error LBRACE IdentifierList RBRACE

GroupedExpr &lt;- LPAREN Expr RPAREN

IfTypeExpr &lt;- IfPrefix TypeExpr (KEYWORD_else Payload? TypeExpr)?

LabeledTypeExpr
    &lt;- BlockLabel Block
     / BlockLabel? LoopTypeExpr

LoopTypeExpr &lt;- KEYWORD_inline? (ForTypeExpr / WhileTypeExpr)

ForTypeExpr &lt;- ForPrefix TypeExpr (KEYWORD_else TypeExpr)?

WhileTypeExpr &lt;- WhilePrefix TypeExpr (KEYWORD_else Payload? TypeExpr)?

SwitchExpr &lt;- KEYWORD_switch LPAREN Expr RPAREN LBRACE SwitchProngList RBRACE

# *** Assembly ***
AsmExpr &lt;- KEYWORD_asm KEYWORD_volatile? LPAREN Expr AsmOutput? RPAREN

AsmOutput &lt;- COLON AsmOutputList AsmInput?

AsmOutputItem &lt;- LBRACKET IDENTIFIER RBRACKET STRINGLITERAL LPAREN (MINUSRARROW TypeExpr / IDENTIFIER) RPAREN

AsmInput &lt;- COLON AsmInputList AsmClobbers?

AsmInputItem &lt;- LBRACKET IDENTIFIER RBRACKET STRINGLITERAL LPAREN Expr RPAREN

AsmClobbers &lt;- COLON Expr

# *** Helper grammar ***
BreakLabel &lt;- COLON IDENTIFIER

BlockLabel &lt;- IDENTIFIER COLON

FieldInit &lt;- DOT IDENTIFIER EQUAL Expr

WhileContinueExpr &lt;- COLON LPAREN AssignExpr RPAREN

LinkSection &lt;- KEYWORD_linksection LPAREN Expr RPAREN

AddrSpace &lt;- KEYWORD_addrspace LPAREN Expr RPAREN

# Fn specific
CallConv &lt;- KEYWORD_callconv LPAREN Expr RPAREN

ParamDecl
    &lt;- doc_comment? (KEYWORD_noalias / KEYWORD_comptime)? (IDENTIFIER COLON)? ParamType
     / DOT3

ParamType
    &lt;- KEYWORD_anytype
     / TypeExpr

# Control flow prefixes
IfPrefix &lt;- KEYWORD_if LPAREN Expr RPAREN PtrPayload?

WhilePrefix &lt;- KEYWORD_while LPAREN Expr RPAREN PtrPayload? WhileContinueExpr?

ForPrefix &lt;- KEYWORD_for LPAREN ForArgumentsList RPAREN PtrListPayload

# Payloads
Payload &lt;- PIPE IDENTIFIER PIPE

PtrPayload &lt;- PIPE ASTERISK? IDENTIFIER PIPE

PtrIndexPayload &lt;- PIPE ASTERISK? IDENTIFIER (COMMA IDENTIFIER)? PIPE

PtrListPayload &lt;- PIPE ASTERISK? IDENTIFIER (COMMA ASTERISK? IDENTIFIER)* COMMA? PIPE

# Switch specific
SwitchProng &lt;- KEYWORD_inline? SwitchCase EQUALRARROW PtrIndexPayload? SingleAssignExpr

SwitchCase
    &lt;- SwitchItem (COMMA SwitchItem)* COMMA?
     / KEYWORD_else

SwitchItem &lt;- Expr (DOT3 Expr)?

# For specific
ForArgumentsList &lt;- ForItem (COMMA ForItem)* COMMA?

ForItem &lt;- Expr (DOT2 Expr?)?

# Operators
AssignOp
    &lt;- ASTERISKEQUAL
     / ASTERISKPIPEEQUAL
     / SLASHEQUAL
     / PERCENTEQUAL
     / PLUSEQUAL
     / PLUSPIPEEQUAL
     / MINUSEQUAL
     / MINUSPIPEEQUAL
     / LARROW2EQUAL
     / LARROW2PIPEEQUAL
     / RARROW2EQUAL
     / AMPERSANDEQUAL
     / CARETEQUAL
     / PIPEEQUAL
     / ASTERISKPERCENTEQUAL
     / PLUSPERCENTEQUAL
     / MINUSPERCENTEQUAL
     / EQUAL

CompareOp
    &lt;- EQUALEQUAL
     / EXCLAMATIONMARKEQUAL
     / LARROW
     / RARROW
     / LARROWEQUAL
     / RARROWEQUAL

BitwiseOp
    &lt;- AMPERSAND
     / CARET
     / PIPE
     / KEYWORD_orelse
     / KEYWORD_catch Payload?

BitShiftOp
    &lt;- LARROW2
     / RARROW2
     / LARROW2PIPE

AdditionOp
    &lt;- PLUS
     / MINUS
     / PLUS2
     / PLUSPERCENT
     / MINUSPERCENT
     / PLUSPIPE
     / MINUSPIPE

MultiplyOp
    &lt;- PIPE2
     / ASTERISK
     / SLASH
     / PERCENT
     / ASTERISK2
     / ASTERISKPERCENT
     / ASTERISKPIPE

PrefixOp
    &lt;- EXCLAMATIONMARK
     / MINUS
     / TILDE
     / MINUSPERCENT
     / AMPERSAND
     / KEYWORD_try

PrefixTypeOp
    &lt;- QUESTIONMARK
     / KEYWORD_anyframe MINUSRARROW
     / SliceTypeStart (ByteAlign / AddrSpace / KEYWORD_const / KEYWORD_volatile / KEYWORD_allowzero)*
     / PtrTypeStart (AddrSpace / KEYWORD_align LPAREN Expr (COLON Expr COLON Expr)? RPAREN / KEYWORD_const / KEYWORD_volatile / KEYWORD_allowzero)*
     / ArrayTypeStart

SuffixOp
    &lt;- LBRACKET Expr (DOT2 (Expr? (COLON Expr)?)?)? RBRACKET
     / DOT IDENTIFIER
     / DOTASTERISK
     / DOTQUESTIONMARK

FnCallArguments &lt;- LPAREN ExprList RPAREN

# Ptr specific
SliceTypeStart &lt;- LBRACKET (COLON Expr)? RBRACKET

PtrTypeStart
    &lt;- ASTERISK
     / ASTERISK2
     / LBRACKET ASTERISK (LETTERC / COLON Expr)? RBRACKET

ArrayTypeStart &lt;- LBRACKET Expr (COLON Expr)? RBRACKET

# ContainerDecl specific
ContainerDeclAuto &lt;- ContainerDeclType LBRACE container_doc_comment? ContainerMembers RBRACE

ContainerDeclType
    &lt;- KEYWORD_struct (LPAREN Expr RPAREN)?
     / KEYWORD_opaque
     / KEYWORD_enum (LPAREN Expr RPAREN)?
     / KEYWORD_union (LPAREN (KEYWORD_enum (LPAREN Expr RPAREN)? / Expr) RPAREN)?

# Alignment
ByteAlign &lt;- KEYWORD_align LPAREN Expr RPAREN

# Lists
IdentifierList &lt;- (doc_comment? IDENTIFIER COMMA)* (doc_comment? IDENTIFIER)?

SwitchProngList &lt;- (SwitchProng COMMA)* SwitchProng?

AsmOutputList &lt;- (AsmOutputItem COMMA)* AsmOutputItem?

AsmInputList &lt;- (AsmInputItem COMMA)* AsmInputItem?

StringList &lt;- (STRINGLITERAL COMMA)* STRINGLITERAL?

ParamDeclList &lt;- (ParamDecl COMMA)* ParamDecl?

ExprList &lt;- (Expr COMMA)* Expr?

# *** Tokens ***
eof &lt;- !.
bin &lt;- [01]
bin_ &lt;- &#39;_&#39;? bin
oct &lt;- [0-7]
oct_ &lt;- &#39;_&#39;? oct
hex &lt;- [0-9a-fA-F]
hex_ &lt;- &#39;_&#39;? hex
dec &lt;- [0-9]
dec_ &lt;- &#39;_&#39;? dec

bin_int &lt;- bin bin_*
oct_int &lt;- oct oct_*
dec_int &lt;- dec dec_*
hex_int &lt;- hex hex_*

ox80_oxBF &lt;- [\200-\277]
oxF4 &lt;- &#39;\364&#39;
ox80_ox8F &lt;- [\200-\217]
oxF1_oxF3 &lt;- [\361-\363]
oxF0 &lt;- &#39;\360&#39;
ox90_0xBF &lt;- [\220-\277]
oxEE_oxEF &lt;- [\356-\357]
oxED &lt;- &#39;\355&#39;
ox80_ox9F &lt;- [\200-\237]
oxE1_oxEC &lt;- [\341-\354]
oxE0 &lt;- &#39;\340&#39;
oxA0_oxBF &lt;- [\240-\277]
oxC2_oxDF &lt;- [\302-\337]

# From https://lemire.me/blog/2018/05/09/how-quickly-can-you-check-that-a-string-is-valid-unicode-utf-8/
# First Byte      Second Byte     Third Byte      Fourth Byte
# [0x00,0x7F]
# [0xC2,0xDF]     [0x80,0xBF]
#    0xE0         [0xA0,0xBF]     [0x80,0xBF]
# [0xE1,0xEC]     [0x80,0xBF]     [0x80,0xBF]
#    0xED         [0x80,0x9F]     [0x80,0xBF]
# [0xEE,0xEF]     [0x80,0xBF]     [0x80,0xBF]
#    0xF0         [0x90,0xBF]     [0x80,0xBF]     [0x80,0xBF]
# [0xF1,0xF3]     [0x80,0xBF]     [0x80,0xBF]     [0x80,0xBF]
#    0xF4         [0x80,0x8F]     [0x80,0xBF]     [0x80,0xBF]

mb_utf8_literal &lt;-
       oxF4      ox80_ox8F ox80_oxBF ox80_oxBF
     / oxF1_oxF3 ox80_oxBF ox80_oxBF ox80_oxBF
     / oxF0      ox90_0xBF ox80_oxBF ox80_oxBF
     / oxEE_oxEF ox80_oxBF ox80_oxBF
     / oxED      ox80_ox9F ox80_oxBF
     / oxE1_oxEC ox80_oxBF ox80_oxBF
     / oxE0      oxA0_oxBF ox80_oxBF
     / oxC2_oxDF ox80_oxBF

ascii_char_not_nl_slash_squote &lt;- [\000-\011\013-\046\050-\133\135-\177]

char_escape
    &lt;- &quot;\\x&quot; hex hex
     / &quot;\\u{&quot; hex+ &quot;}&quot;
     / &quot;\\&quot; [nr\\t&#39;&quot;]
char_char
    &lt;- mb_utf8_literal
     / char_escape
     / ascii_char_not_nl_slash_squote

string_char
    &lt;- char_escape
     / [^\\&quot;\n]

container_doc_comment &lt;- (&#39;//!&#39; [^\n]* [ \n]* skip)+
doc_comment &lt;- (&#39;///&#39; [^\n]* [ \n]* skip)+
line_comment &lt;- &#39;//&#39; ![!/][^\n]* / &#39;////&#39; [^\n]*
line_string &lt;- (&quot;\\\\&quot; [^\n]* [ \n]*)+
skip &lt;- ([ \n] / line_comment)*

CHAR_LITERAL &lt;- &quot;&#39;&quot; char_char &quot;&#39;&quot; skip
FLOAT
    &lt;- &quot;0x&quot; hex_int &quot;.&quot; hex_int ([pP] [-+]? dec_int)? skip
     /      dec_int &quot;.&quot; dec_int ([eE] [-+]? dec_int)? skip
     / &quot;0x&quot; hex_int [pP] [-+]? dec_int skip
     /      dec_int [eE] [-+]? dec_int skip
INTEGER
    &lt;- &quot;0b&quot; bin_int skip
     / &quot;0o&quot; oct_int skip
     / &quot;0x&quot; hex_int skip
     /      dec_int   skip
STRINGLITERALSINGLE &lt;- &quot;\&quot;&quot; string_char* &quot;\&quot;&quot; skip
STRINGLITERAL
    &lt;- STRINGLITERALSINGLE
     / (line_string                 skip)+
IDENTIFIER
    &lt;- !keyword [A-Za-z_] [A-Za-z0-9_]* skip
     / &quot;@&quot; STRINGLITERALSINGLE
BUILTINIDENTIFIER &lt;- &quot;@&quot;[A-Za-z_][A-Za-z0-9_]* skip


AMPERSAND            &lt;- &#39;&amp;&#39;      ![=]      skip
AMPERSANDEQUAL       &lt;- &#39;&amp;=&#39;               skip
ASTERISK             &lt;- &#39;*&#39;      ![*%=|]   skip
ASTERISK2            &lt;- &#39;**&#39;               skip
ASTERISKEQUAL        &lt;- &#39;*=&#39;               skip
ASTERISKPERCENT      &lt;- &#39;*%&#39;     ![=]      skip
ASTERISKPERCENTEQUAL &lt;- &#39;*%=&#39;              skip
ASTERISKPIPE         &lt;- &#39;*|&#39;     ![=]      skip
ASTERISKPIPEEQUAL    &lt;- &#39;*|=&#39;              skip
CARET                &lt;- &#39;^&#39;      ![=]      skip
CARETEQUAL           &lt;- &#39;^=&#39;               skip
COLON                &lt;- &#39;:&#39;                skip
COMMA                &lt;- &#39;,&#39;                skip
DOT                  &lt;- &#39;.&#39;      ![*.?]    skip
DOT2                 &lt;- &#39;..&#39;     ![.]      skip
DOT3                 &lt;- &#39;...&#39;              skip
DOTASTERISK          &lt;- &#39;.*&#39;               skip
DOTQUESTIONMARK      &lt;- &#39;.?&#39;               skip
EQUAL                &lt;- &#39;=&#39;      ![&gt;=]     skip
EQUALEQUAL           &lt;- &#39;==&#39;               skip
EQUALRARROW          &lt;- &#39;=&gt;&#39;               skip
EXCLAMATIONMARK      &lt;- &#39;!&#39;      ![=]      skip
EXCLAMATIONMARKEQUAL &lt;- &#39;!=&#39;               skip
LARROW               &lt;- &#39;&lt;&#39;      ![&lt;=]     skip
LARROW2              &lt;- &#39;&lt;&lt;&#39;     ![=|]     skip
LARROW2EQUAL         &lt;- &#39;&lt;&lt;=&#39;              skip
LARROW2PIPE          &lt;- &#39;&lt;&lt;|&#39;    ![=]      skip
LARROW2PIPEEQUAL     &lt;- &#39;&lt;&lt;|=&#39;             skip
LARROWEQUAL          &lt;- &#39;&lt;=&#39;               skip
LBRACE               &lt;- &#39;{&#39;                skip
LBRACKET             &lt;- &#39;[&#39;                skip
LPAREN               &lt;- &#39;(&#39;                skip
MINUS                &lt;- &#39;-&#39;      ![%=&gt;|]   skip
MINUSEQUAL           &lt;- &#39;-=&#39;               skip
MINUSPERCENT         &lt;- &#39;-%&#39;     ![=]      skip
MINUSPERCENTEQUAL    &lt;- &#39;-%=&#39;              skip
MINUSPIPE            &lt;- &#39;-|&#39;     ![=]      skip
MINUSPIPEEQUAL       &lt;- &#39;-|=&#39;              skip
MINUSRARROW          &lt;- &#39;-&gt;&#39;               skip
PERCENT              &lt;- &#39;%&#39;      ![=]      skip
PERCENTEQUAL         &lt;- &#39;%=&#39;               skip
PIPE                 &lt;- &#39;|&#39;      ![|=]     skip
PIPE2                &lt;- &#39;||&#39;               skip
PIPEEQUAL            &lt;- &#39;|=&#39;               skip
PLUS                 &lt;- &#39;+&#39;      ![%+=|]   skip
PLUS2                &lt;- &#39;++&#39;               skip
PLUSEQUAL            &lt;- &#39;+=&#39;               skip
PLUSPERCENT          &lt;- &#39;+%&#39;     ![=]      skip
PLUSPERCENTEQUAL     &lt;- &#39;+%=&#39;              skip
PLUSPIPE             &lt;- &#39;+|&#39;     ![=]      skip
PLUSPIPEEQUAL        &lt;- &#39;+|=&#39;              skip
LETTERC              &lt;- &#39;c&#39;                skip
QUESTIONMARK         &lt;- &#39;?&#39;                skip
RARROW               &lt;- &#39;&gt;&#39;      ![&gt;=]     skip
RARROW2              &lt;- &#39;&gt;&gt;&#39;     ![=]      skip
RARROW2EQUAL         &lt;- &#39;&gt;&gt;=&#39;              skip
RARROWEQUAL          &lt;- &#39;&gt;=&#39;               skip
RBRACE               &lt;- &#39;}&#39;                skip
RBRACKET             &lt;- &#39;]&#39;                skip
RPAREN               &lt;- &#39;)&#39;                skip
SEMICOLON            &lt;- &#39;;&#39;                skip
SLASH                &lt;- &#39;/&#39;      ![=]      skip
SLASHEQUAL           &lt;- &#39;/=&#39;               skip
TILDE                &lt;- &#39;~&#39;                skip

end_of_word &lt;- ![a-zA-Z0-9_] skip
KEYWORD_addrspace   &lt;- &#39;addrspace&#39;   end_of_word
KEYWORD_align       &lt;- &#39;align&#39;       end_of_word
KEYWORD_allowzero   &lt;- &#39;allowzero&#39;   end_of_word
KEYWORD_and         &lt;- &#39;and&#39;         end_of_word
KEYWORD_anyframe    &lt;- &#39;anyframe&#39;    end_of_word
KEYWORD_anytype     &lt;- &#39;anytype&#39;     end_of_word
KEYWORD_asm         &lt;- &#39;asm&#39;         end_of_word
KEYWORD_break       &lt;- &#39;break&#39;       end_of_word
KEYWORD_callconv    &lt;- &#39;callconv&#39;    end_of_word
KEYWORD_catch       &lt;- &#39;catch&#39;       end_of_word
KEYWORD_comptime    &lt;- &#39;comptime&#39;    end_of_word
KEYWORD_const       &lt;- &#39;const&#39;       end_of_word
KEYWORD_continue    &lt;- &#39;continue&#39;    end_of_word
KEYWORD_defer       &lt;- &#39;defer&#39;       end_of_word
KEYWORD_else        &lt;- &#39;else&#39;        end_of_word
KEYWORD_enum        &lt;- &#39;enum&#39;        end_of_word
KEYWORD_errdefer    &lt;- &#39;errdefer&#39;    end_of_word
KEYWORD_error       &lt;- &#39;error&#39;       end_of_word
KEYWORD_export      &lt;- &#39;export&#39;      end_of_word
KEYWORD_extern      &lt;- &#39;extern&#39;      end_of_word
KEYWORD_fn          &lt;- &#39;fn&#39;          end_of_word
KEYWORD_for         &lt;- &#39;for&#39;         end_of_word
KEYWORD_if          &lt;- &#39;if&#39;          end_of_word
KEYWORD_inline      &lt;- &#39;inline&#39;      end_of_word
KEYWORD_noalias     &lt;- &#39;noalias&#39;     end_of_word
KEYWORD_nosuspend   &lt;- &#39;nosuspend&#39;   end_of_word
KEYWORD_noinline    &lt;- &#39;noinline&#39;    end_of_word
KEYWORD_opaque      &lt;- &#39;opaque&#39;      end_of_word
KEYWORD_or          &lt;- &#39;or&#39;          end_of_word
KEYWORD_orelse      &lt;- &#39;orelse&#39;      end_of_word
KEYWORD_packed      &lt;- &#39;packed&#39;      end_of_word
KEYWORD_pub         &lt;- &#39;pub&#39;         end_of_word
KEYWORD_resume      &lt;- &#39;resume&#39;      end_of_word
KEYWORD_return      &lt;- &#39;return&#39;      end_of_word
KEYWORD_linksection &lt;- &#39;linksection&#39; end_of_word
KEYWORD_struct      &lt;- &#39;struct&#39;      end_of_word
KEYWORD_suspend     &lt;- &#39;suspend&#39;     end_of_word
KEYWORD_switch      &lt;- &#39;switch&#39;      end_of_word
KEYWORD_test        &lt;- &#39;test&#39;        end_of_word
KEYWORD_threadlocal &lt;- &#39;threadlocal&#39; end_of_word
KEYWORD_try         &lt;- &#39;try&#39;         end_of_word
KEYWORD_union       &lt;- &#39;union&#39;       end_of_word
KEYWORD_unreachable &lt;- &#39;unreachable&#39; end_of_word
KEYWORD_var         &lt;- &#39;var&#39;         end_of_word
KEYWORD_volatile    &lt;- &#39;volatile&#39;    end_of_word
KEYWORD_while       &lt;- &#39;while&#39;       end_of_word

keyword &lt;- KEYWORD_addrspace / KEYWORD_align / KEYWORD_allowzero / KEYWORD_and
         / KEYWORD_anyframe / KEYWORD_anytype / KEYWORD_asm
         / KEYWORD_break / KEYWORD_callconv / KEYWORD_catch
         / KEYWORD_comptime / KEYWORD_const / KEYWORD_continue / KEYWORD_defer
         / KEYWORD_else / KEYWORD_enum / KEYWORD_errdefer / KEYWORD_error / KEYWORD_export
         / KEYWORD_extern / KEYWORD_fn / KEYWORD_for / KEYWORD_if
         / KEYWORD_inline / KEYWORD_noalias / KEYWORD_nosuspend / KEYWORD_noinline
         / KEYWORD_opaque / KEYWORD_or / KEYWORD_orelse / KEYWORD_packed
         / KEYWORD_pub / KEYWORD_resume / KEYWORD_return / KEYWORD_linksection
         / KEYWORD_struct / KEYWORD_suspend / KEYWORD_switch / KEYWORD_test
         / KEYWORD_threadlocal / KEYWORD_try / KEYWORD_union / KEYWORD_unreachable
         / KEYWORD_var / KEYWORD_volatile / KEYWORD_while</code></pre>
<figcaption>grammar.y</figcaption>
</figure>

### [Zen](zig-0.15.1.md#toc-Zen) <a href="zig-0.15.1.md#Zen" class="hdr">§</a>

- Communicate intent precisely.
- Edge cases matter.
- Favor reading code over writing code.
- Only one obvious way to do things.
- Runtime crashes are better than bugs.
- Compile errors are better than runtime crashes.
- Incremental improvements.
- Avoid local maximums.
- Reduce the amount one must remember.
- Focus on code rather than style.
- Resource allocation may fail; resource deallocation must succeed.
- Memory is a resource.
- Together we serve the users.

