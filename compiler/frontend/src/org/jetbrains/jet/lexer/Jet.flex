package org.jetbrains.jet.lexer;

import java.util.*;
import com.intellij.lexer.*;
import com.intellij.psi.*;
import com.intellij.psi.tree.IElementType;

import org.jetbrains.jet.lexer.JetTokens;

%%

%unicode
%class _JetLexer
%implements FlexLexer

%{
    private static final class State {
        final int lBraceCount;
        final int state;

        public State(int state, int lBraceCount) {
            this.state = state;
            this.lBraceCount = lBraceCount;
        }
    }

    private final Stack<State> states = new Stack<State>();
    private int lBraceCount;

    private void pushState(int state) {
        states.push(new State(yystate(), lBraceCount));
        lBraceCount = 0;
        yybegin(state);
    }

    private void popState() {
        State state = states.pop();
        lBraceCount = state.lBraceCount;
        yybegin(state.state);
    }
%}

%function advance
%type IElementType
%eof{  return;
%eof}

%xstate STRING SHORT_TEMPLATE_ENTRY
%state LONG_TEMPLATE_ENTRY

DIGIT=[0-9]
HEX_DIGIT=[0-9A-Fa-f]
WHITE_SPACE_CHAR=[\ \n\t\f]

// TODO: prohibit '$' in identifiers?
LETTER = [:letter:]|_
IDENTIFIER_PART=[:digit:]|{LETTER}
PLAIN_IDENTIFIER={LETTER} {IDENTIFIER_PART}*
// TODO: this one MUST allow everything accepted by the runtime
// TODO: Replace backticks by one backslash in the begining
ESCAPED_IDENTIFIER = `[^`\n]+`
IDENTIFIER = {PLAIN_IDENTIFIER}|{ESCAPED_IDENTIFIER}
FIELD_IDENTIFIER = \${IDENTIFIER}
LABEL_IDENTIFIER = \@{IDENTIFIER}

BLOCK_COMMENT=("/*"[^"*"]{COMMENT_TAIL})|"/*"
// TODO: Wiki markup for doc comments?
DOC_COMMENT="/*""*"+("/"|([^"/""*"]{COMMENT_TAIL}))?
COMMENT_TAIL=([^"*"]*("*"+[^"*""/"])?)*("*"+"/")?
EOL_COMMENT="/""/"[^\n]*

INTEGER_LITERAL={DECIMAL_INTEGER_LITERAL}|{HEX_INTEGER_LITERAL}|{BIN_INTEGER_LITERAL}
DECIMAL_INTEGER_LITERAL=(0|([1-9]({DIGIT})*))
HEX_INTEGER_LITERAL=0[Xx]({HEX_DIGIT})*
BIN_INTEGER_LITERAL=0[Bb]({DIGIT})*

//FLOAT_LITERAL=(({FLOATING_POINT_LITERAL1})[Ff])|(({FLOATING_POINT_LITERAL2})[Ff])|(({FLOATING_POINT_LITERAL3})[Ff])|(({FLOATING_POINT_LITERAL4})[Ff])
//DOUBLE_LITERAL=(({FLOATING_POINT_LITERAL1})[Dd]?)|(({FLOATING_POINT_LITERAL2})[Dd]?)|(({FLOATING_POINT_LITERAL3})[Dd]?)|(({FLOATING_POINT_LITERAL4})[Dd])
DOUBLE_LITERAL={FLOATING_POINT_LITERAL1}|{FLOATING_POINT_LITERAL2}|{FLOATING_POINT_LITERAL3}|{FLOATING_POINT_LITERAL4}
FLOATING_POINT_LITERAL1=({DIGIT})+"."({DIGIT})+({EXPONENT_PART})?
FLOATING_POINT_LITERAL2="."({DIGIT})+({EXPONENT_PART})?
FLOATING_POINT_LITERAL3=({DIGIT})+({EXPONENT_PART})
FLOATING_POINT_LITERAL4=({DIGIT})+
EXPONENT_PART=[Ee]["+""-"]?({DIGIT})*
HEX_FLOAT_LITERAL={HEX_SIGNIFICAND}{BINARY_EXPONENT}[Ff]
//HEX_DOUBLE_LITERAL={HEX_SIGNIFICAND}{BINARY_EXPONENT}[Dd]?
HEX_DOUBLE_LITERAL={HEX_SIGNIFICAND}{BINARY_EXPONENT}?
BINARY_EXPONENT=[Pp][+-]?{DIGIT}+
HEX_SIGNIFICAND={HEX_INTEGER_LITERAL}|0[Xx]{HEX_DIGIT}*\.{HEX_DIGIT}+
//HEX_SIGNIFICAND={HEX_INTEGER_LITERAL}|{HEX_INTEGER_LITERAL}\.|0[Xx]{HEX_DIGIT}*\.{HEX_DIGIT}+

CHARACTER_LITERAL="'"([^\\\'\n]|{ESCAPE_SEQUENCE})*("'"|\\)?
// TODO: introduce symbols (e.g. 'foo) as another way to write string literals
STRING_LITERAL=\"([^\\\"\n]|{ESCAPE_SEQUENCE})*(\"|\\)?
ESCAPE_SEQUENCE=\\(u{HEX_DIGIT}{HEX_DIGIT}{HEX_DIGIT}{HEX_DIGIT}|[^\n])

// ANY_ESCAPE_SEQUENCE = \\[^]
THREE_QUO = (\"\"\")
ONE_TWO_QUO = (\"[^\"]) | (\"\"[^\"])
QUO_STRING_CHAR = [^\"] | {ONE_TWO_QUO}
RAW_STRING_LITERAL = {THREE_QUO} {QUO_STRING_CHAR}* {THREE_QUO}?

REGULAR_STRING_PART=[^\\\"\n\$]+
SHORT_TEMPLATE_ENTRY=\${IDENTIFIER}
LONELY_DOLLAR=\$
LONG_TEMPLATE_ENTRY_START=\$\{
LONG_TEMPLATE_ENTRY_END=\}

%%

// String templates

\"                                     { pushState(STRING); return JetTokens.OPEN_QUOTE; }

<STRING> \"                            { popState(); return JetTokens.CLOSING_QUOTE; }
<STRING> \n                            { popState(); yypushback(1); return JetTokens.DANGLING_NEWLINE; }
<STRING> {REGULAR_STRING_PART}         { return JetTokens.REGULAR_STRING_PART; }
<STRING> {ESCAPE_SEQUENCE}             { return JetTokens.ESCAPE_SEQUENCE; }
<STRING> {SHORT_TEMPLATE_ENTRY}        {
                                            pushState(SHORT_TEMPLATE_ENTRY);
                                            yypushback(yylength() - 1);
                                            return JetTokens.SHORT_TEMPLATE_ENTRY_START;
                                       }
<SHORT_TEMPLATE_ENTRY> {IDENTIFIER}    { popState(); return JetTokens.IDENTIFIER; }

<STRING> {LONELY_DOLLAR}               { return JetTokens.REGULAR_STRING_PART; }
<STRING> {LONG_TEMPLATE_ENTRY_START}   { pushState(LONG_TEMPLATE_ENTRY); return JetTokens.LONG_TEMPLATE_ENTRY_START; }

<LONG_TEMPLATE_ENTRY> "{"              { lBraceCount++; return JetTokens.LBRACE; }
<LONG_TEMPLATE_ENTRY> "}"              {
                                           if (lBraceCount == 0) {
                                             popState();
                                             return JetTokens.LONG_TEMPLATE_ENTRY_END;
                                           }
                                           lBraceCount--;
                                           return JetTokens.RBRACE;
                                       }

// Mere mortals

{BLOCK_COMMENT} { return JetTokens.BLOCK_COMMENT; }
{DOC_COMMENT} { return JetTokens.DOC_COMMENT; }

({WHITE_SPACE_CHAR})+ { return JetTokens.WHITE_SPACE; }

{EOL_COMMENT} { return JetTokens.EOL_COMMENT; }

{INTEGER_LITERAL}\.\. { yypushback(2); return JetTokens.INTEGER_LITERAL; }
{INTEGER_LITERAL} { return JetTokens.INTEGER_LITERAL; }

{DOUBLE_LITERAL}     { return JetTokens.FLOAT_LITERAL; }
{HEX_DOUBLE_LITERAL} { return JetTokens.FLOAT_LITERAL; }

{CHARACTER_LITERAL} { return JetTokens.CHARACTER_LITERAL; }
//{STRING_LITERAL} { return JetTokens.STRING_LITERAL; }

// TODO: Decide what to do with """ ... """"
{RAW_STRING_LITERAL} { return JetTokens.RAW_STRING_LITERAL; }

"namespace"  { return JetTokens.NAMESPACE_KEYWORD ;}
"continue"   { return JetTokens.CONTINUE_KEYWORD ;}
"return"     { return JetTokens.RETURN_KEYWORD ;}
"object"     { return JetTokens.OBJECT_KEYWORD ;}
"while"      { return JetTokens.WHILE_KEYWORD ;}
"break"      { return JetTokens.BREAK_KEYWORD ;}
"class"      { return JetTokens.CLASS_KEYWORD ;}
"trait"      { return JetTokens.TRAIT_KEYWORD ;}
"throw"      { return JetTokens.THROW_KEYWORD ;}
"false"      { return JetTokens.FALSE_KEYWORD ;}
"super"      { return JetTokens.SUPER_KEYWORD ;}
"when"       { return JetTokens.WHEN_KEYWORD ;}
"true"       { return JetTokens.TRUE_KEYWORD ;}
"type"       { return JetTokens.TYPE_KEYWORD ;}
"this"       { return JetTokens.THIS_KEYWORD ;}
"null"       { return JetTokens.NULL_KEYWORD ;}
"else"       { return JetTokens.ELSE_KEYWORD ;}
"This"       { return JetTokens.CAPITALIZED_THIS_KEYWORD ;}
"try"        { return JetTokens.TRY_KEYWORD ;}
"val"        { return JetTokens.VAL_KEYWORD ;}
"var"        { return JetTokens.VAR_KEYWORD ;}
"fun"        { return JetTokens.FUN_KEYWORD ;}
"for"        { return JetTokens.FOR_KEYWORD ;}
//"new"        { return JetTokens.NEW_KEYWORD ;}
"is"         { return JetTokens.IS_KEYWORD ;}
"in"         { return JetTokens.IN_KEYWORD ;}
"if"         { return JetTokens.IF_KEYWORD ;}
"do"         { return JetTokens.DO_KEYWORD ;}
"as"         { return JetTokens.AS_KEYWORD ;}

{FIELD_IDENTIFIER} { return JetTokens.FIELD_IDENTIFIER; }
{IDENTIFIER} { return JetTokens.IDENTIFIER; }
{LABEL_IDENTIFIER}   { return JetTokens.LABEL_IDENTIFIER; }
\!in{IDENTIFIER_PART}        { yypushback(3); return JetTokens.EXCL; }
\!is{IDENTIFIER_PART}        { yypushback(3); return JetTokens.EXCL; }

"==="        { return JetTokens.EQEQEQ    ; }
"!=="        { return JetTokens.EXCLEQEQEQ; }
"!in"        { return JetTokens.NOT_IN; }
"!is"        { return JetTokens.NOT_IS; }
"as?"        { return JetTokens.AS_SAFE; }
"++"         { return JetTokens.PLUSPLUS  ; }
"--"         { return JetTokens.MINUSMINUS; }
"<="         { return JetTokens.LTEQ      ; }
">="         { return JetTokens.GTEQ      ; }
"=="         { return JetTokens.EQEQ      ; }
"!="         { return JetTokens.EXCLEQ    ; }
"&&"         { return JetTokens.ANDAND    ; }
"||"         { return JetTokens.OROR      ; }
//"?."         { return JetTokens.SAFE_ACCESS;}
//"?:"         { return JetTokens.ELVIS     ; }
//".*"         { return JetTokens.MAP       ; }
//".?"         { return JetTokens.FILTER    ; }
"*="         { return JetTokens.MULTEQ    ; }
"/="         { return JetTokens.DIVEQ     ; }
"%="         { return JetTokens.PERCEQ    ; }
"+="         { return JetTokens.PLUSEQ    ; }
"-="         { return JetTokens.MINUSEQ   ; }
"->"         { return JetTokens.ARROW     ; }
"=>"         { return JetTokens.DOUBLE_ARROW; }
".."         { return JetTokens.RANGE     ; }
"@@"         { return JetTokens.ATAT      ; }
"["          { return JetTokens.LBRACKET  ; }
"]"          { return JetTokens.RBRACKET  ; }
"{"          { return JetTokens.LBRACE    ; }
"}"          { return JetTokens.RBRACE    ; }
"("          { return JetTokens.LPAR      ; }
")"          { return JetTokens.RPAR      ; }
"."          { return JetTokens.DOT       ; }
"*"          { return JetTokens.MUL       ; }
"+"          { return JetTokens.PLUS      ; }
"-"          { return JetTokens.MINUS     ; }
"!"          { return JetTokens.EXCL      ; }
"/"          { return JetTokens.DIV       ; }
"%"          { return JetTokens.PERC      ; }
"<"          { return JetTokens.LT        ; }
">"          { return JetTokens.GT        ; }
"?"          { return JetTokens.QUEST     ; }
":"          { return JetTokens.COLON     ; }
";"          { return JetTokens.SEMICOLON ; }
"="          { return JetTokens.EQ        ; }
","          { return JetTokens.COMMA     ; }
"#"          { return JetTokens.HASH      ; }
"@"          { return JetTokens.AT        ; }

. { return TokenType.BAD_CHARACTER; }

