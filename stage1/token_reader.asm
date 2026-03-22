; stage1/token_reader.asm
; tok_read_all: read Stage 0 lexer output from stdin into token array
;
; Entry: none (reads from stdin)
; Exit: tok_count set, token array populated, string table populated
; Error: prints to stderr, exits 1
;
; Input format (one token per line):
;   TYPE line:col              (keywords, operators, delimiters, EOF)
;   TYPE "value" line:col      (IDENT, LIT_INT, LIT_FLOAT, LIT_STRING)
;
; Token memory layout (20 bytes each):
;   0:1  token_type   (enum 0-44)
;   1:3  padding      (zero)
;   4:4  string_offset (into string table)
;   8:4  string_length
;   12:4 line
;   16:4 col
;
; Max tokens: 52428 (1048576 / 20)
; Max string table: 131072 bytes

%define MAX_TOKENS 52428
%define TOKEN_SIZE 20
%define MAX_STRINGS 262144
%define STDIN 0
%define STDERR 2
%define SYS_READ 0
%define SYS_WRITE 1
%define SYS_EXIT 60

%define STDIN_BUF_SIZE 65536

section .bss
    tok_stdin_buf resb STDIN_BUF_SIZE  ; raw stdin read buffer
    tok_stdin_pos resq 1               ; current read position in stdin buffer
    tok_stdin_end resq 1               ; end of valid data in stdin buffer
    tok_line_buf  resb 512             ; one line of input

section .data

; Error messages
tok_err_overflow:  db "error: token buffer overflow", 10
tok_err_overflow_len equ $ - tok_err_overflow
tok_err_str_overflow: db "error: string table overflow", 10
tok_err_str_overflow_len equ $ - tok_err_str_overflow
tok_err_unknown:   db "error: unknown token type: "
tok_err_unknown_len equ $ - tok_err_unknown
tok_err_parse:     db "error: malformed token line", 10
tok_err_parse_len  equ $ - tok_err_parse

; Token type names — must match ast-format.md enum values exactly
; Format: pointer, length, enum value (3 qwords per entry)
tok_type_table:
    dq tok_n_KW_FN, 5, 0
    dq tok_n_KW_LET, 6, 1
    dq tok_n_KW_TYPE, 7, 2
    dq tok_n_KW_MATCH, 8, 3
    dq tok_n_KW_FOR, 6, 4
    dq tok_n_KW_IN, 5, 5
    dq tok_n_KW_DO, 5, 6
    dq tok_n_KW_MODULE, 9, 7
    dq tok_n_KW_IMPORTS, 10, 8
    dq tok_n_KW_EXPORTS, 10, 9
    dq tok_n_KW_SEQUENTIAL, 13, 10
    dq tok_n_KW_TRUE, 7, 11
    dq tok_n_KW_FALSE, 8, 12
    dq tok_n_IDENT, 5, 13
    dq tok_n_LIT_INT, 7, 14
    dq tok_n_LIT_FLOAT, 9, 15
    dq tok_n_LIT_STRING, 10, 16
    dq tok_n_LBRACE, 6, 17
    dq tok_n_RBRACE, 6, 18
    dq tok_n_LPAREN, 6, 19
    dq tok_n_RPAREN, 6, 20
    dq tok_n_LBRACKET, 8, 21
    dq tok_n_RBRACKET, 8, 22
    dq tok_n_ASSIGN, 6, 23
    dq tok_n_PLUS, 4, 24
    dq tok_n_MINUS, 5, 25
    dq tok_n_STAR, 4, 26
    dq tok_n_SLASH, 5, 27
    dq tok_n_PERCENT, 7, 28
    dq tok_n_EQ, 2, 29
    dq tok_n_NEQ, 3, 30
    dq tok_n_LT, 2, 31
    dq tok_n_GT, 2, 32
    dq tok_n_LTE, 3, 33
    dq tok_n_GTE, 3, 34
    dq tok_n_AND, 3, 35
    dq tok_n_OR, 2, 36
    dq tok_n_NOT, 3, 37
    dq tok_n_ARROW, 5, 38
    dq tok_n_PIPE, 4, 39
    dq tok_n_COLON, 5, 40
    dq tok_n_SEMICOLON, 9, 41
    dq tok_n_COMMA, 5, 42
    dq tok_n_DOT, 3, 43
    dq tok_n_EOF, 3, 44
tok_type_table_end:

%define TOK_TYPE_COUNT 45
%define TOK_TYPE_ENTRY_SIZE 24    ; 3 qwords

; Token type name strings
tok_n_KW_FN:       db "KW_FN"
tok_n_KW_LET:      db "KW_LET"
tok_n_KW_TYPE:     db "KW_TYPE"
tok_n_KW_MATCH:    db "KW_MATCH"
tok_n_KW_FOR:      db "KW_FOR"
tok_n_KW_IN:       db "KW_IN"
tok_n_KW_DO:       db "KW_DO"
tok_n_KW_MODULE:   db "KW_MODULE"
tok_n_KW_IMPORTS:  db "KW_IMPORTS"
tok_n_KW_EXPORTS:  db "KW_EXPORTS"
tok_n_KW_SEQUENTIAL: db "KW_SEQUENTIAL"
tok_n_KW_TRUE:     db "KW_TRUE"
tok_n_KW_FALSE:    db "KW_FALSE"
tok_n_IDENT:       db "IDENT"
tok_n_LIT_INT:     db "LIT_INT"
tok_n_LIT_FLOAT:   db "LIT_FLOAT"
tok_n_LIT_STRING:  db "LIT_STRING"
tok_n_LBRACE:      db "LBRACE"
tok_n_RBRACE:      db "RBRACE"
tok_n_LPAREN:      db "LPAREN"
tok_n_RPAREN:      db "RPAREN"
tok_n_LBRACKET:    db "LBRACKET"
tok_n_RBRACKET:    db "RBRACKET"
tok_n_ASSIGN:      db "ASSIGN"
tok_n_PLUS:        db "PLUS"
tok_n_MINUS:       db "MINUS"
tok_n_STAR:        db "STAR"
tok_n_SLASH:       db "SLASH"
tok_n_PERCENT:     db "PERCENT"
tok_n_EQ:          db "EQ"
tok_n_NEQ:         db "NEQ"
tok_n_LT:          db "LT"
tok_n_GT:          db "GT"
tok_n_LTE:         db "LTE"
tok_n_GTE:         db "GTE"
tok_n_AND:         db "AND"
tok_n_OR:          db "OR"
tok_n_NOT:         db "NOT"
tok_n_ARROW:       db "ARROW"
tok_n_PIPE:        db "PIPE"
tok_n_COLON:       db "COLON"
tok_n_SEMICOLON:   db "SEMICOLON"
tok_n_COMMA:       db "COMMA"
tok_n_DOT:         db "DOT"
tok_n_EOF:         db "EOF"

section .text

; ============================================================
; tok_read_all — main entry point
; Reads stdin line by line. Parses each line into a token.
; Stores tokens in the global `tokens` array, strings in `strings`.
; Sets `tok_count` when done.
; ============================================================
tok_read_all:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Initialize stdin buffer state
    xor rax, rax
    mov [rel tok_stdin_pos], rax
    mov [rel tok_stdin_end], rax

tok_ra_read_loop:
    ; Read one line from stdin into tok_line_buf
    call tok_read_line              ; returns line length in rax, 0 = EOF
    cmp rax, 0
    je tok_ra_done                  ; stdin EOF with no more data

    ; rax = line length (excluding newline)
    mov r12, rax                    ; r12 = line length

    ; Parse the line: extract token type name
    lea r13, [rel tok_line_buf]     ; r13 = pointer to start of line
    xor r14d, r14d                  ; r14 = current position in line

    ; Find end of token type name (first space or end of line)
    xor ecx, ecx                    ; ecx = name length
tok_ra_find_name_end:
    cmp r14, r12
    jge tok_ra_name_done
    movzx eax, byte [r13 + r14]
    cmp al, ' '
    je tok_ra_name_done
    inc r14
    inc ecx
    jmp tok_ra_find_name_end

tok_ra_name_done:
    ; r13 = name start, ecx = name length, r14 = position after name
    ; Look up the token type in the table
    push rcx                        ; save name length
    mov rdi, r13                    ; name pointer
    mov rsi, rcx                    ; name length
    call tok_lookup_type            ; returns type enum in rax, or -1
    pop rcx
    cmp rax, -1
    je tok_err_unknown_type

    mov r15, rax                    ; r15 = token type enum value

    ; Bounds check token count
    mov rax, [rel tok_count]
    cmp rax, MAX_TOKENS
    jge tok_err_buf_overflow

    ; Calculate token pointer: tokens + tok_count * TOKEN_SIZE
    mov rbx, rax                    ; rbx = current token index
    imul rax, TOKEN_SIZE
    lea rdi, [rel tokens]
    add rdi, rax                    ; rdi = pointer to new token slot

    ; Zero the token slot (20 bytes)
    xor eax, eax
    mov [rdi], eax                  ; bytes 0-3
    mov [rdi+4], eax                ; bytes 4-7
    mov [rdi+8], eax                ; bytes 8-11
    mov [rdi+12], eax               ; bytes 12-15
    mov [rdi+16], eax               ; bytes 16-19

    ; Write token_type
    mov byte [rdi], r15b

    ; Skip space after type name
    cmp r14, r12
    jge tok_err_malformed           ; no position info — malformed
    inc r14                         ; skip space

    ; Check if next char is a quote (token has a value)
    movzx eax, byte [r13 + r14]
    cmp al, '"'
    je tok_ra_parse_value

    ; No value — parse line:col directly
    jmp tok_ra_parse_position

tok_ra_parse_value:
    ; Skip opening quote
    inc r14

    ; Find closing quote — copy value to string table
    mov rax, [rel str_pos]
    cmp rax, MAX_STRINGS
    jge tok_err_str_buf_overflow

    mov dword [rdi+4], eax          ; string_offset = current str_pos
    lea rsi, [rel strings]
    add rsi, rax                    ; rsi = write position in string table
    xor ecx, ecx                    ; ecx = value length

tok_ra_copy_value:
    cmp r14, r12
    jge tok_err_malformed           ; unterminated string
    movzx eax, byte [r13 + r14]
    cmp al, '"'
    je tok_ra_value_done
    ; Copy byte to string table
    mov byte [rsi + rcx], al
    inc ecx
    inc r14
    jmp tok_ra_copy_value

tok_ra_value_done:
    ; ecx = value length
    mov dword [rdi+8], ecx          ; string_length
    ; Update str_pos with bounds check
    mov rax, [rel str_pos]
    add rax, rcx
    cmp rax, MAX_STRINGS
    jge tok_err_str_buf_overflow
    mov [rel str_pos], rax
    ; Skip closing quote
    inc r14
    ; Skip space before position
    cmp r14, r12
    jge tok_err_malformed
    inc r14

tok_ra_parse_position:
    ; Parse "line:col" from r13+r14 to end of line
    ; Parse line number (digits until ':')
    xor eax, eax                    ; accumulator for line number
tok_ra_parse_line_num:
    cmp r14, r12
    jge tok_err_malformed
    movzx ecx, byte [r13 + r14]
    cmp cl, ':'
    je tok_ra_line_num_done
    sub cl, '0'
    cmp cl, 9
    ja tok_err_malformed            ; not a digit
    imul eax, 10
    add eax, ecx
    inc r14
    jmp tok_ra_parse_line_num

tok_ra_line_num_done:
    mov dword [rdi+12], eax         ; line
    inc r14                         ; skip ':'

    ; Parse col number (digits to end of line)
    xor eax, eax
tok_ra_parse_col_num:
    cmp r14, r12
    jge tok_ra_col_num_done
    movzx ecx, byte [r13 + r14]
    sub cl, '0'
    cmp cl, 9
    ja tok_ra_col_num_done          ; non-digit ends the number
    imul eax, 10
    add eax, ecx
    inc r14
    jmp tok_ra_parse_col_num

tok_ra_col_num_done:
    mov dword [rdi+16], eax         ; col

    ; Increment token count
    inc qword [rel tok_count]

    ; Check if this was EOF token — if so, we're done
    cmp r15, 44                     ; TOK_EOF
    je tok_ra_done

    jmp tok_ra_read_loop

tok_ra_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ============================================================
; tok_lookup_type — look up token type name in table
; Input: rdi = name pointer, rsi = name length
; Output: rax = enum value (0-44), or -1 if not found
; ============================================================
tok_lookup_type:
    push rbx
    push rcx
    push rdx
    push r8

    lea rbx, [rel tok_type_table]

tok_lt_loop:
    lea rax, [rel tok_type_table_end]
    cmp rbx, rax
    jge tok_lt_not_found

    ; Load entry: [rbx]=name_ptr, [rbx+8]=name_len, [rbx+16]=enum_val
    mov r8, [rbx + 8]              ; entry name length
    cmp rsi, r8                    ; compare lengths first
    jne tok_lt_next

    ; Lengths match — compare bytes
    mov rdx, [rbx]                 ; entry name pointer
    xor ecx, ecx                   ; byte index
tok_lt_cmp:
    cmp rcx, rsi
    jge tok_lt_found               ; all bytes matched
    movzx eax, byte [rdi + rcx]
    cmp al, byte [rdx + rcx]
    jne tok_lt_next
    inc ecx
    jmp tok_lt_cmp

tok_lt_found:
    mov rax, [rbx + 16]            ; return enum value
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

tok_lt_next:
    add rbx, TOK_TYPE_ENTRY_SIZE
    jmp tok_lt_loop

tok_lt_not_found:
    mov rax, -1
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================
; tok_read_line — read one line from stdin into tok_line_buf
; Returns: rax = line length (excluding newline), 0 if no more data
; Uses a buffered approach: reads 64KB chunks from stdin.
; ============================================================
tok_read_line:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    lea rdi, [rel tok_line_buf]    ; output pointer
    xor ecx, ecx                   ; output length

tok_rl_loop:
    ; Check if we have data in the stdin buffer
    mov rax, [rel tok_stdin_pos]
    cmp rax, [rel tok_stdin_end]
    jge tok_rl_refill

    ; Read one byte from buffer
    lea rsi, [rel tok_stdin_buf]
    movzx edx, byte [rsi + rax]
    inc qword [rel tok_stdin_pos]

    ; Check for newline
    cmp dl, 10
    je tok_rl_done

    ; Check for carriage return (skip it)
    cmp dl, 13
    je tok_rl_loop

    ; Store byte in line buffer
    mov byte [rdi + rcx], dl
    inc ecx

    ; Guard against line buffer overflow (512 bytes)
    cmp ecx, 510
    jge tok_rl_done

    jmp tok_rl_loop

tok_rl_refill:
    ; Read more data from stdin
    push rcx                       ; save current line length
    push rdi                       ; save line buf pointer
    mov rdi, STDIN
    lea rsi, [rel tok_stdin_buf]
    mov rdx, STDIN_BUF_SIZE
    mov rax, SYS_READ
    syscall
    pop rdi
    pop rcx

    cmp rax, 0
    jle tok_rl_eof                 ; EOF or error

    ; Update buffer pointers
    xor edx, edx
    mov [rel tok_stdin_pos], rdx   ; reset to start of buffer
    mov [rel tok_stdin_end], rax   ; end = bytes read

    jmp tok_rl_loop

tok_rl_eof:
    ; Return whatever we have (could be a partial last line)
    mov rax, rcx
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

tok_rl_done:
    mov rax, rcx                   ; return line length
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================
; Error handlers — all print to stderr and exit 1
; ============================================================
tok_err_buf_overflow:
    mov rdi, STDERR
    lea rsi, [rel tok_err_overflow]
    mov rdx, tok_err_overflow_len
    mov rax, SYS_WRITE
    syscall
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall

tok_err_str_buf_overflow:
    mov rdi, STDERR
    lea rsi, [rel tok_err_str_overflow]
    mov rdx, tok_err_str_overflow_len
    mov rax, SYS_WRITE
    syscall
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall

tok_err_unknown_type:
    ; Print "error: unknown token type: " + the name
    mov rdi, STDERR
    lea rsi, [rel tok_err_unknown]
    mov rdx, tok_err_unknown_len
    mov rax, SYS_WRITE
    syscall
    ; Print the token name from the line
    mov rdi, STDERR
    mov rsi, r13                   ; start of line = start of name
    xor rdx, rdx
tok_err_unknown_len_loop:
    cmp rdx, r12
    jge tok_err_unknown_print
    movzx eax, byte [r13 + rdx]
    cmp al, ' '
    je tok_err_unknown_print
    inc rdx
    jmp tok_err_unknown_len_loop
tok_err_unknown_print:
    mov rax, SYS_WRITE
    syscall
    ; Print newline
    push 10
    mov rdi, STDERR
    mov rsi, rsp
    mov rdx, 1
    mov rax, SYS_WRITE
    syscall
    pop rax
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall

tok_err_malformed:
    mov rdi, STDERR
    lea rsi, [rel tok_err_parse]
    mov rdx, tok_err_parse_len
    mov rax, SYS_WRITE
    syscall
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall
