; lexer.asm — Milestone 0.3: Complete Loon Lexer
; Reads a .loon file, emits tokens in the locked-down format:
;   TYPE line:col           (keywords, operators, delimiters, EOF)
;   TYPE "value" line:col   (IDENT, LIT_INT, LIT_FLOAT, LIT_STRING)
;
; Build: nasm -f elf64 -o lexer.o lexer.asm && ld -o lexer lexer.o
; Usage: ./lexer <filename>
;
; Error handling: on invalid character, print ERROR to stderr, exit 1.
; Comments (// to EOL) are silently dropped.
;
; No libc. No external dependencies. Pure Linux syscalls.

; ============================================================
; Syscall numbers
; ============================================================
%define SYS_READ   0
%define SYS_WRITE  1
%define SYS_OPEN   2
%define SYS_CLOSE  3
%define SYS_EXIT   60

%define STDOUT 1
%define STDERR 2

%define BUF_SIZE 65536      ; 64KB input buffer — read entire file at once
%define OUT_SIZE 8192       ; 8KB output buffer

section .bss
    inbuf   resb BUF_SIZE   ; input file contents
    outbuf  resb OUT_SIZE   ; output assembly buffer
    tokbuf  resb 256        ; scratch for building token value strings

section .data

; ---- Error messages ----
err_usage:      db "usage: lexer <filename>", 10
err_usage_len   equ $ - err_usage
err_open:       db "error: could not open file", 10
err_open_len    equ $ - err_open
err_prefix:     db 'ERROR "unexpected character ', "'"
err_prefix_len  equ $ - err_prefix
err_mid:        db "'"
err_mid_len     equ $ - err_mid
err_quote:      db '"'
err_quote_len   equ $ - err_quote
err_space:      db ' '
err_space_len   equ $ - err_space
newline:        db 10
newline_len     equ $ - newline

; ---- Token type strings ----
; Keywords
s_KW_FN:        db "KW_FN"
s_KW_FN_len     equ $ - s_KW_FN
s_KW_LET:       db "KW_LET"
s_KW_LET_len    equ $ - s_KW_LET
s_KW_TYPE:      db "KW_TYPE"
s_KW_TYPE_len   equ $ - s_KW_TYPE
s_KW_MATCH:     db "KW_MATCH"
s_KW_MATCH_len  equ $ - s_KW_MATCH
s_KW_FOR:       db "KW_FOR"
s_KW_FOR_len    equ $ - s_KW_FOR
s_KW_IN:        db "KW_IN"
s_KW_IN_len     equ $ - s_KW_IN
s_KW_DO:        db "KW_DO"
s_KW_DO_len     equ $ - s_KW_DO
s_KW_MODULE:    db "KW_MODULE"
s_KW_MODULE_len equ $ - s_KW_MODULE
s_KW_IMPORTS:   db "KW_IMPORTS"
s_KW_IMPORTS_len equ $ - s_KW_IMPORTS
s_KW_EXPORTS:   db "KW_EXPORTS"
s_KW_EXPORTS_len equ $ - s_KW_EXPORTS
s_KW_SEQ:       db "KW_SEQUENTIAL"
s_KW_SEQ_len    equ $ - s_KW_SEQ
s_KW_TRUE:      db "KW_TRUE"
s_KW_TRUE_len   equ $ - s_KW_TRUE
s_KW_FALSE:     db "KW_FALSE"
s_KW_FALSE_len  equ $ - s_KW_FALSE

; Token type name strings
s_IDENT:        db "IDENT"
s_IDENT_len     equ $ - s_IDENT
s_LIT_INT:      db "LIT_INT"
s_LIT_INT_len   equ $ - s_LIT_INT
s_LIT_FLOAT:    db "LIT_FLOAT"
s_LIT_FLOAT_len equ $ - s_LIT_FLOAT
s_LIT_STRING:   db "LIT_STRING"
s_LIT_STRING_len equ $ - s_LIT_STRING
s_LBRACE:       db "LBRACE"
s_LBRACE_len    equ $ - s_LBRACE
s_RBRACE:       db "RBRACE"
s_RBRACE_len    equ $ - s_RBRACE
s_LPAREN:       db "LPAREN"
s_LPAREN_len    equ $ - s_LPAREN
s_RPAREN:       db "RPAREN"
s_RPAREN_len    equ $ - s_RPAREN
s_LBRACKET:     db "LBRACKET"
s_LBRACKET_len  equ $ - s_LBRACKET
s_RBRACKET:     db "RBRACKET"
s_RBRACKET_len  equ $ - s_RBRACKET
s_ASSIGN:       db "ASSIGN"
s_ASSIGN_len    equ $ - s_ASSIGN
s_PLUS:         db "PLUS"
s_PLUS_len      equ $ - s_PLUS
s_MINUS:        db "MINUS"
s_MINUS_len     equ $ - s_MINUS
s_STAR:         db "STAR"
s_STAR_len      equ $ - s_STAR
s_SLASH:        db "SLASH"
s_SLASH_len     equ $ - s_SLASH
s_PERCENT:      db "PERCENT"
s_PERCENT_len   equ $ - s_PERCENT
s_EQ:           db "EQ"
s_EQ_len        equ $ - s_EQ
s_NEQ:          db "NEQ"
s_NEQ_len       equ $ - s_NEQ
s_LT:           db "LT"
s_LT_len        equ $ - s_LT
s_GT:           db "GT"
s_GT_len        equ $ - s_GT
s_LTE:          db "LTE"
s_LTE_len       equ $ - s_LTE
s_GTE:          db "GTE"
s_GTE_len       equ $ - s_GTE
s_AND:          db "AND"
s_AND_len       equ $ - s_AND
s_OR:           db "OR"
s_OR_len        equ $ - s_OR
s_NOT:          db "NOT"
s_NOT_len       equ $ - s_NOT
s_ARROW:        db "ARROW"
s_ARROW_len     equ $ - s_ARROW
s_PIPE:         db "PIPE"
s_PIPE_len      equ $ - s_PIPE
s_COLON:        db "COLON"
s_COLON_len     equ $ - s_COLON
s_SEMICOLON:    db "SEMICOLON"
s_SEMICOLON_len equ $ - s_SEMICOLON
s_COMMA:        db "COMMA"
s_COMMA_len     equ $ - s_COMMA
s_DOT:          db "DOT"
s_DOT_len       equ $ - s_DOT
s_EOF:          db "EOF"
s_EOF_len       equ $ - s_EOF

; ---- Keyword table ----
; Each entry: pointer to keyword string, keyword length, pointer to token name, token name length
; Order: longest keywords first within same first letter to avoid prefix ambiguity
; (not strictly necessary for exact-match but keeps things clear)

kw_table:
    ; fn
    dq kw_fn, 2, s_KW_FN, s_KW_FN_len
    ; for
    dq kw_for, 3, s_KW_FOR, s_KW_FOR_len
    ; false
    dq kw_false, 5, s_KW_FALSE, s_KW_FALSE_len
    ; let
    dq kw_let, 3, s_KW_LET, s_KW_LET_len
    ; type
    dq kw_type, 4, s_KW_TYPE, s_KW_TYPE_len
    ; true
    dq kw_true, 4, s_KW_TRUE, s_KW_TRUE_len
    ; match
    dq kw_match, 5, s_KW_MATCH, s_KW_MATCH_len
    ; module
    dq kw_module, 6, s_KW_MODULE, s_KW_MODULE_len
    ; in
    dq kw_in, 2, s_KW_IN, s_KW_IN_len
    ; imports
    dq kw_imports, 7, s_KW_IMPORTS, s_KW_IMPORTS_len
    ; do
    dq kw_do, 2, s_KW_DO, s_KW_DO_len
    ; exports
    dq kw_exports, 7, s_KW_EXPORTS, s_KW_EXPORTS_len
    ; sequential
    dq kw_seq, 10, s_KW_SEQ, s_KW_SEQ_len
kw_table_end:

%define KW_COUNT 13
%define KW_ENTRY_SIZE 32       ; 4 qwords = 32 bytes per entry

kw_fn:      db "fn"
kw_for:     db "for"
kw_false:   db "false"
kw_let:     db "let"
kw_type:    db "type"
kw_true:    db "true"
kw_match:   db "match"
kw_module:  db "module"
kw_in:      db "in"
kw_imports: db "imports"
kw_do:      db "do"
kw_exports: db "exports"
kw_seq:     db "sequential"

section .text
    global _start

; ============================================================
; Register conventions during main loop:
;   r12 = pointer to current position in input buffer
;   r13 = pointer to end of input (one past last byte)
;   r14 = current line number (1-indexed)
;   r15 = current column number (1-indexed)
;   rbx = output buffer write position
; ============================================================

_start:
    ; Check argc
    mov rax, [rsp]
    cmp rax, 2
    jl .usage_error

    ; Open file
    mov rdi, [rsp + 16]         ; argv[1]
    xor rsi, rsi                ; O_RDONLY
    xor rdx, rdx
    mov rax, SYS_OPEN
    syscall
    cmp rax, 0
    jl .open_error
    mov r8, rax                 ; r8 = fd

    ; Read entire file into inbuf
    mov rdi, r8
    lea rsi, [rel inbuf]
    mov rdx, BUF_SIZE
    mov rax, SYS_READ
    syscall
    mov r9, rax                 ; r9 = bytes read

    ; Close file
    mov rdi, r8
    mov rax, SYS_CLOSE
    syscall

    ; Initialize state
    lea r12, [rel inbuf]        ; current position
    lea r13, [r12 + r9]         ; end of input
    mov r14, 1                  ; line = 1
    mov r15, 1                  ; col = 1
    lea rbx, [rel outbuf]       ; output write position

; ============================================================
; Main lexer loop
; ============================================================
.main_loop:
    cmp r12, r13
    jge .emit_eof               ; end of input

    movzx eax, byte [r12]      ; al = current byte

    ; Skip whitespace
    cmp al, ' '
    je .skip_whitespace
    cmp al, 9                   ; tab
    je .skip_whitespace
    cmp al, 13                  ; carriage return
    je .skip_whitespace
    cmp al, 10                  ; newline
    je .skip_newline

    ; Check for comment
    cmp al, '/'
    je .maybe_comment

    ; Check for string literal
    cmp al, '"'
    je .lex_string

    ; Check for identifier/keyword (letter or underscore)
    cmp al, '_'
    je .lex_ident
    cmp al, 'a'
    jl .not_lower
    cmp al, 'z'
    jle .lex_ident
.not_lower:
    cmp al, 'A'
    jl .not_upper
    cmp al, 'Z'
    jle .lex_ident
.not_upper:

    ; Check for digit (number literal)
    cmp al, '0'
    jl .not_digit
    cmp al, '9'
    jle .lex_number
.not_digit:

    ; Symbols and operators
    cmp al, '{'
    je .emit_lbrace
    cmp al, '}'
    je .emit_rbrace
    cmp al, '('
    je .emit_lparen
    cmp al, ')'
    je .emit_rparen
    cmp al, '['
    je .emit_lbracket
    cmp al, ']'
    je .emit_rbracket
    cmp al, '+'
    je .emit_plus
    cmp al, '*'
    je .emit_star
    cmp al, '%'
    je .emit_percent
    cmp al, ':'
    je .emit_colon
    cmp al, ';'
    je .emit_semicolon
    cmp al, ','
    je .emit_comma
    cmp al, '.'
    je .emit_dot

    ; Two-character operators that start with specific chars
    cmp al, '-'
    je .maybe_arrow
    cmp al, '='
    je .maybe_eq
    cmp al, '!'
    je .maybe_neq
    cmp al, '<'
    je .maybe_lte
    cmp al, '>'
    je .maybe_gte
    cmp al, '&'
    je .maybe_and
    cmp al, '|'
    je .maybe_pipe_or

    ; Unknown character
    jmp .error_char

; ============================================================
; Whitespace handling
; ============================================================
.skip_whitespace:
    inc r12
    inc r15
    jmp .main_loop

.skip_newline:
    inc r12
    inc r14                     ; next line
    mov r15, 1                  ; reset column
    jmp .main_loop

; ============================================================
; Comment handling: // to end of line
; ============================================================
.maybe_comment:
    ; Check if next char is also /
    lea rax, [r12 + 1]
    cmp rax, r13
    jge .emit_slash             ; at end of input, it's just a slash
    movzx ecx, byte [r12 + 1]
    cmp cl, '/'
    jne .emit_slash             ; single / is SLASH token

    ; It's a comment — skip to end of line
.skip_comment:
    inc r12
    cmp r12, r13
    jge .main_loop              ; EOF ends the comment
    movzx eax, byte [r12]
    cmp al, 10                  ; newline
    jne .skip_comment
    ; Don't consume the newline — let .main_loop handle it for line tracking
    jmp .main_loop

; ============================================================
; String literal: "..."
; ============================================================
.lex_string:
    mov r8, r14                 ; save start line
    mov r9, r15                 ; save start col
    inc r12                     ; skip opening quote
    inc r15
    lea rdi, [rel tokbuf]       ; write decoded chars here
    xor ecx, ecx               ; tokbuf index

.string_loop:
    cmp r12, r13
    jge .error_char             ; unterminated string — error
    movzx eax, byte [r12]
    cmp al, '"'
    je .string_done
    cmp al, 10                  ; newline inside string
    je .error_char              ; strings can't span lines
    cmp al, '\'
    je .string_escape

    ; Normal character
    mov byte [rdi + rcx], al
    inc rcx
    inc r12
    inc r15
    jmp .string_loop

.string_escape:
    inc r12                     ; skip backslash
    inc r15
    cmp r12, r13
    jge .error_char
    movzx eax, byte [r12]
    cmp al, 'n'
    je .esc_newline
    cmp al, 't'
    je .esc_tab
    cmp al, '\'
    je .esc_backslash
    cmp al, '"'
    je .esc_quote
    jmp .error_char             ; invalid escape

.esc_newline:
    mov byte [rdi + rcx], 10
    jmp .esc_done
.esc_tab:
    mov byte [rdi + rcx], 9
    jmp .esc_done
.esc_backslash:
    mov byte [rdi + rcx], '\'
    jmp .esc_done
.esc_quote:
    mov byte [rdi + rcx], '"'
.esc_done:
    inc rcx
    inc r12
    inc r15
    jmp .string_loop

.string_done:
    inc r12                     ; skip closing quote
    inc r15
    ; Emit: LIT_STRING "value" line:col
    push rcx                    ; save string length
    lea rsi, [rel s_LIT_STRING]
    mov rdx, s_LIT_STRING_len
    call .write_str
    call .write_space
    call .write_quote
    lea rsi, [rel tokbuf]
    pop rdx                     ; string length
    push rdx
    call .write_str
    call .write_quote
    call .write_space
    mov rdi, r8                 ; start line
    mov rsi, r9                 ; start col
    call .write_pos
    call .write_newline
    pop rcx                     ; clean stack
    jmp .main_loop

; ============================================================
; Identifier / keyword
; ============================================================
.lex_ident:
    mov r8, r14                 ; save start line
    mov r9, r15                 ; save start col
    lea rdi, [rel tokbuf]
    xor ecx, ecx               ; length

.ident_loop:
    cmp r12, r13
    jge .ident_done
    movzx eax, byte [r12]
    ; Check if [a-zA-Z0-9_]
    cmp al, '_'
    je .ident_char
    cmp al, 'a'
    jl .ident_not_lower
    cmp al, 'z'
    jle .ident_char
.ident_not_lower:
    cmp al, 'A'
    jl .ident_not_upper
    cmp al, 'Z'
    jle .ident_char
.ident_not_upper:
    cmp al, '0'
    jl .ident_done
    cmp al, '9'
    jle .ident_char
    jmp .ident_done

.ident_char:
    mov byte [rdi + rcx], al
    inc rcx
    inc r12
    inc r15
    jmp .ident_loop

.ident_done:
    ; Check if it's a keyword — linear scan through kw_table
    ; rcx = identifier length, tokbuf has the chars
    push rcx                    ; save ident length
    lea r10, [rel kw_table]     ; r10 = current entry pointer

.kw_check_loop:
    lea rax, [rel kw_table_end]
    cmp r10, rax
    jge .emit_ident             ; not a keyword

    ; Load keyword entry: [r10]=kw_str_ptr, [r10+8]=kw_len, [r10+16]=tok_name_ptr, [r10+24]=tok_name_len
    mov rsi, [r10]              ; keyword string pointer
    mov rdx, [r10 + 8]          ; keyword length

    ; Quick length check first
    pop rcx                     ; restore ident length
    push rcx
    cmp rcx, rdx
    jne .kw_next                ; lengths differ — skip

    ; Compare bytes
    lea rdi, [rel tokbuf]
    ; rcx = rdx = length to compare
    push rcx
    xor r11d, r11d              ; index
.kw_cmp_loop:
    cmp r11, rcx
    jge .kw_match               ; all bytes matched
    movzx eax, byte [rdi + r11]
    movzx edx, byte [rsi + r11]
    cmp al, dl
    jne .kw_cmp_fail
    inc r11
    jmp .kw_cmp_loop

.kw_cmp_fail:
    pop rcx                     ; discard saved length
    jmp .kw_next

.kw_match:
    pop rcx                     ; discard saved cmp length
    pop rcx                     ; discard saved ident length
    ; Emit keyword token: tok_name line:col
    mov rsi, [r10 + 16]         ; token name pointer
    mov rdx, [r10 + 24]         ; token name length
    push rdx
    call .write_str
    call .write_space
    mov rdi, r8
    mov rsi, r9
    call .write_pos
    call .write_newline
    pop rdx                     ; clean stack
    jmp .main_loop

.kw_next:
    add r10, KW_ENTRY_SIZE      ; next keyword entry
    jmp .kw_check_loop

.emit_ident:
    pop rcx                     ; restore ident length
    ; Emit: IDENT "value" line:col
    push rcx
    lea rsi, [rel s_IDENT]
    mov rdx, s_IDENT_len
    call .write_str
    call .write_space
    call .write_quote
    lea rsi, [rel tokbuf]
    pop rdx                     ; ident length
    push rdx
    call .write_str
    call .write_quote
    call .write_space
    mov rdi, r8
    mov rsi, r9
    call .write_pos
    call .write_newline
    pop rcx                     ; clean stack
    jmp .main_loop

; ============================================================
; Number literal (integer or float)
; ============================================================
.lex_number:
    mov r8, r14                 ; save start line
    mov r9, r15                 ; save start col
    lea rdi, [rel tokbuf]
    xor ecx, ecx               ; length
    xor r10d, r10d              ; is_float flag (0 = int, 1 = float)

.num_loop:
    cmp r12, r13
    jge .num_done
    movzx eax, byte [r12]
    cmp al, '0'
    jl .num_maybe_dot
    cmp al, '9'
    jle .num_digit
.num_maybe_dot:
    cmp al, '.'
    jne .num_done
    ; Check if already a float
    cmp r10d, 1
    je .num_done                ; second dot ends the number
    mov r10d, 1                 ; mark as float
.num_digit:
    mov byte [rdi + rcx], al
    inc rcx
    inc r12
    inc r15
    jmp .num_loop

.num_done:
    ; Emit LIT_INT or LIT_FLOAT
    push rcx
    cmp r10d, 1
    je .num_emit_float

    ; Integer
    lea rsi, [rel s_LIT_INT]
    mov rdx, s_LIT_INT_len
    jmp .num_emit

.num_emit_float:
    lea rsi, [rel s_LIT_FLOAT]
    mov rdx, s_LIT_FLOAT_len

.num_emit:
    call .write_str
    call .write_space
    call .write_quote
    lea rsi, [rel tokbuf]
    pop rdx
    push rdx
    call .write_str
    call .write_quote
    call .write_space
    mov rdi, r8
    mov rsi, r9
    call .write_pos
    call .write_newline
    pop rcx
    jmp .main_loop

; ============================================================
; Simple single-character tokens
; ============================================================
%macro emit_simple 2
    ; %1 = token name string, %2 = token name length
    push r14
    push r15
    lea rsi, [rel %1]
    mov rdx, %2
    call .write_str
    call .write_space
    pop rsi                     ; col (was r15)
    pop rdi                     ; line (was r14)
    call .write_pos
    call .write_newline
    inc r12
    inc r15
    jmp .main_loop
%endmacro

.emit_lbrace:   emit_simple s_LBRACE, s_LBRACE_len
.emit_rbrace:   emit_simple s_RBRACE, s_RBRACE_len
.emit_lparen:   emit_simple s_LPAREN, s_LPAREN_len
.emit_rparen:   emit_simple s_RPAREN, s_RPAREN_len
.emit_lbracket: emit_simple s_LBRACKET, s_LBRACKET_len
.emit_rbracket: emit_simple s_RBRACKET, s_RBRACKET_len
.emit_plus:     emit_simple s_PLUS, s_PLUS_len
.emit_star:     emit_simple s_STAR, s_STAR_len
.emit_percent:  emit_simple s_PERCENT, s_PERCENT_len
.emit_colon:    emit_simple s_COLON, s_COLON_len
.emit_semicolon: emit_simple s_SEMICOLON, s_SEMICOLON_len
.emit_comma:    emit_simple s_COMMA, s_COMMA_len
.emit_dot:      emit_simple s_DOT, s_DOT_len
.emit_slash:    emit_simple s_SLASH, s_SLASH_len

; ============================================================
; Two-character operator checks
; ============================================================

; - or ->
.maybe_arrow:
    lea rax, [r12 + 1]
    cmp rax, r13
    jge .emit_minus             ; at end, just MINUS
    movzx ecx, byte [r12 + 1]
    cmp cl, '>'
    jne .emit_minus
    ; It's ->
    push r14
    push r15
    lea rsi, [rel s_ARROW]
    mov rdx, s_ARROW_len
    call .write_str
    call .write_space
    pop rsi
    pop rdi
    call .write_pos
    call .write_newline
    add r12, 2
    add r15, 2
    jmp .main_loop

.emit_minus:    emit_simple s_MINUS, s_MINUS_len

; = or ==
.maybe_eq:
    lea rax, [r12 + 1]
    cmp rax, r13
    jge .emit_assign
    movzx ecx, byte [r12 + 1]
    cmp cl, '='
    jne .emit_assign
    ; It's ==
    push r14
    push r15
    lea rsi, [rel s_EQ]
    mov rdx, s_EQ_len
    call .write_str
    call .write_space
    pop rsi
    pop rdi
    call .write_pos
    call .write_newline
    add r12, 2
    add r15, 2
    jmp .main_loop

.emit_assign:   emit_simple s_ASSIGN, s_ASSIGN_len

; ! or !=
.maybe_neq:
    lea rax, [r12 + 1]
    cmp rax, r13
    jge .emit_not
    movzx ecx, byte [r12 + 1]
    cmp cl, '='
    jne .emit_not
    ; It's !=
    push r14
    push r15
    lea rsi, [rel s_NEQ]
    mov rdx, s_NEQ_len
    call .write_str
    call .write_space
    pop rsi
    pop rdi
    call .write_pos
    call .write_newline
    add r12, 2
    add r15, 2
    jmp .main_loop

.emit_not:      emit_simple s_NOT, s_NOT_len

; < or <=
.maybe_lte:
    lea rax, [r12 + 1]
    cmp rax, r13
    jge .emit_lt
    movzx ecx, byte [r12 + 1]
    cmp cl, '='
    jne .emit_lt
    ; It's <=
    push r14
    push r15
    lea rsi, [rel s_LTE]
    mov rdx, s_LTE_len
    call .write_str
    call .write_space
    pop rsi
    pop rdi
    call .write_pos
    call .write_newline
    add r12, 2
    add r15, 2
    jmp .main_loop

.emit_lt:       emit_simple s_LT, s_LT_len

; > or >=
.maybe_gte:
    lea rax, [r12 + 1]
    cmp rax, r13
    jge .emit_gt
    movzx ecx, byte [r12 + 1]
    cmp cl, '='
    jne .emit_gt
    ; It's >=
    push r14
    push r15
    lea rsi, [rel s_GTE]
    mov rdx, s_GTE_len
    call .write_str
    call .write_space
    pop rsi
    pop rdi
    call .write_pos
    call .write_newline
    add r12, 2
    add r15, 2
    jmp .main_loop

.emit_gt:       emit_simple s_GT, s_GT_len

; && or error on single &
.maybe_and:
    lea rax, [r12 + 1]
    cmp rax, r13
    jge .error_char             ; lone & at EOF
    movzx ecx, byte [r12 + 1]
    cmp cl, '&'
    jne .error_char             ; lone &
    ; It's &&
    push r14
    push r15
    lea rsi, [rel s_AND]
    mov rdx, s_AND_len
    call .write_str
    call .write_space
    pop rsi
    pop rdi
    call .write_pos
    call .write_newline
    add r12, 2
    add r15, 2
    jmp .main_loop

; | followed by > (pipe) or | (or) or error
.maybe_pipe_or:
    lea rax, [r12 + 1]
    cmp rax, r13
    jge .error_char             ; lone | at EOF
    movzx ecx, byte [r12 + 1]
    cmp cl, '>'
    je .emit_pipe_tok
    cmp cl, '|'
    je .emit_or_tok
    jmp .error_char             ; lone |

.emit_pipe_tok:
    push r14
    push r15
    lea rsi, [rel s_PIPE]
    mov rdx, s_PIPE_len
    call .write_str
    call .write_space
    pop rsi
    pop rdi
    call .write_pos
    call .write_newline
    add r12, 2
    add r15, 2
    jmp .main_loop

.emit_or_tok:
    push r14
    push r15
    lea rsi, [rel s_OR]
    mov rdx, s_OR_len
    call .write_str
    call .write_space
    pop rsi
    pop rdi
    call .write_pos
    call .write_newline
    add r12, 2
    add r15, 2
    jmp .main_loop

; ============================================================
; EOF token
; ============================================================
.emit_eof:
    lea rsi, [rel s_EOF]
    mov rdx, s_EOF_len
    call .write_str
    call .write_space
    mov rdi, r14
    mov rsi, r15
    call .write_pos
    call .write_newline

    ; Flush output buffer
    call .flush_output

    ; Exit 0
    xor rdi, rdi
    mov rax, SYS_EXIT
    syscall

; ============================================================
; Error: unexpected character
; ============================================================
.error_char:
    ; Flush any pending stdout output first
    call .flush_output

    ; Write to stderr: ERROR "unexpected character 'X'" line:col\n
    ; Build the error message on the stack
    movzx eax, byte [r12]      ; the bad character

    ; Write prefix
    mov rdi, STDERR
    lea rsi, [rel err_prefix]
    mov rdx, err_prefix_len
    push rax                    ; save bad char
    mov rax, SYS_WRITE
    syscall

    ; Write the bad character
    pop rax
    mov byte [rel tokbuf], al
    mov rdi, STDERR
    lea rsi, [rel tokbuf]
    mov rdx, 1
    mov rax, SYS_WRITE
    syscall

    ; Write '" '
    mov rdi, STDERR
    lea rsi, [rel err_mid]
    mov rdx, err_mid_len
    mov rax, SYS_WRITE
    syscall
    mov rdi, STDERR
    lea rsi, [rel err_quote]
    mov rdx, err_quote_len
    mov rax, SYS_WRITE
    syscall
    mov rdi, STDERR
    lea rsi, [rel err_space]
    mov rdx, err_space_len
    mov rax, SYS_WRITE
    syscall

    ; Write line:col
    ; We need to write directly to stderr, not through the buffer
    ; Convert r14 (line) to decimal
    mov rax, r14
    lea rdi, [rel tokbuf]
    call .int_to_dec            ; returns length in rcx
    mov rdi, STDERR
    lea rsi, [rel tokbuf]
    mov rdx, rcx
    mov rax, SYS_WRITE
    syscall

    ; Write ':'
    mov byte [rel tokbuf], ':'
    mov rdi, STDERR
    lea rsi, [rel tokbuf]
    mov rdx, 1
    mov rax, SYS_WRITE
    syscall

    ; Write col
    mov rax, r15
    lea rdi, [rel tokbuf]
    call .int_to_dec
    mov rdi, STDERR
    lea rsi, [rel tokbuf]
    mov rdx, rcx
    mov rax, SYS_WRITE
    syscall

    ; Write newline
    mov rdi, STDERR
    lea rsi, [rel newline]
    mov rdx, 1
    mov rax, SYS_WRITE
    syscall

    ; Exit 1
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall

; ============================================================
; Usage/open errors
; ============================================================
.usage_error:
    mov rdi, STDERR
    lea rsi, [rel err_usage]
    mov rdx, err_usage_len
    mov rax, SYS_WRITE
    syscall
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall

.open_error:
    mov rdi, STDERR
    lea rsi, [rel err_open]
    mov rdx, err_open_len
    mov rax, SYS_WRITE
    syscall
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall

; ============================================================
; Output helpers — buffered writes to stdout
; All preserve r12-r15, rbx
; ============================================================

; Write string at rsi, length rdx, to output buffer
.write_str:
    push rcx
    push rdi
    mov rdi, rbx                ; current output position
    mov rcx, rdx                ; length
    ; Check if buffer needs flushing
    lea rax, [rel outbuf]
    add rax, OUT_SIZE
    sub rax, rbx                ; remaining space
    cmp rax, rdx
    jl .write_str_flush
.write_str_copy:
    ; Copy bytes
    cmp rcx, 0
    jle .write_str_done
    movzx eax, byte [rsi]
    mov byte [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jmp .write_str_copy
.write_str_flush:
    call .flush_output
    lea rdi, [rel outbuf]
    jmp .write_str_copy
.write_str_done:
    mov rbx, rdi                ; update output position
    pop rdi
    pop rcx
    ret

; Write a space to output buffer
.write_space:
    cmp rbx, r13                ; can't use r13 — it's end of input!
    ; Check buffer space
    lea rax, [rel outbuf]
    add rax, OUT_SIZE
    cmp rbx, rax
    jl .write_space_ok
    call .flush_output
.write_space_ok:
    mov byte [rbx], ' '
    inc rbx
    ret

; Write a double quote to output buffer
.write_quote:
    lea rax, [rel outbuf]
    add rax, OUT_SIZE
    cmp rbx, rax
    jl .write_quote_ok
    call .flush_output
.write_quote_ok:
    mov byte [rbx], '"'
    inc rbx
    ret

; Write newline to output buffer
.write_newline:
    lea rax, [rel outbuf]
    add rax, OUT_SIZE
    cmp rbx, rax
    jl .write_nl_ok
    call .flush_output
.write_nl_ok:
    mov byte [rbx], 10
    inc rbx
    ret

; Write position as "line:col" to output buffer
; rdi = line, rsi = col
.write_pos:
    push r8
    push r9
    push rcx
    mov r8, rdi                 ; save line
    mov r9, rsi                 ; save col

    ; Convert line number to decimal
    mov rax, r8
    lea rdi, [rel tokbuf + 128] ; use second half of tokbuf
    call .int_to_dec            ; rcx = length, digits at rdi
    lea rsi, [rel tokbuf + 128]
    mov rdx, rcx
    call .write_str

    ; Write ':'
    lea rax, [rel outbuf]
    add rax, OUT_SIZE
    cmp rbx, rax
    jl .wpos_colon_ok
    call .flush_output
.wpos_colon_ok:
    mov byte [rbx], ':'
    inc rbx

    ; Convert col number to decimal
    mov rax, r9
    lea rdi, [rel tokbuf + 128]
    call .int_to_dec
    lea rsi, [rel tokbuf + 128]
    mov rdx, rcx
    call .write_str

    pop rcx
    pop r9
    pop r8
    ret

; Flush output buffer to stdout
.flush_output:
    push rdi
    push rsi
    push rdx
    push rax
    push rcx

    lea rsi, [rel outbuf]
    mov rdx, rbx
    sub rdx, rsi               ; bytes in buffer
    cmp rdx, 0
    jle .flush_done

    mov rdi, STDOUT
    mov rax, SYS_WRITE
    syscall

    lea rbx, [rel outbuf]      ; reset write position
.flush_done:
    pop rcx
    pop rax
    pop rdx
    pop rsi
    pop rdi
    ret

; Convert unsigned integer in rax to decimal string at [rdi]
; Returns length in rcx
.int_to_dec:
    push rbx
    push rdx
    push rsi

    mov rsi, rdi                ; save output pointer
    xor ecx, ecx               ; digit count

    ; Handle 0 specially
    cmp rax, 0
    jne .itd_loop
    mov byte [rdi], '0'
    mov ecx, 1
    jmp .itd_done

.itd_loop:
    cmp rax, 0
    je .itd_reverse
    xor edx, edx
    mov rbx, 10
    div rbx                     ; rax = quotient, rdx = remainder
    add dl, '0'
    mov byte [rdi + rcx], dl
    inc ecx
    jmp .itd_loop

.itd_reverse:
    ; Digits are in reverse order — swap in place
    xor edx, edx               ; left index
    mov ebx, ecx
    dec ebx                     ; right index
.itd_rev_loop:
    cmp edx, ebx
    jge .itd_done
    movzx eax, byte [rsi + rdx]
    movzx r8d, byte [rsi + rbx]
    mov byte [rsi + rdx], r8b
    mov byte [rsi + rbx], al
    inc edx
    dec ebx
    jmp .itd_rev_loop

.itd_done:
    pop rsi
    pop rdx
    pop rbx
    ret
