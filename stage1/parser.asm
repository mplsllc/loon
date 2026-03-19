; stage1/parser.asm
; par_parse_program: two-pass parser for Loon-0 declarations
;
; Pass 1: collect function names and parameter counts into func_table
; Pass 2: parse module decl + fn declarations, build AST nodes
;
; Entry: tok_count set, tokens array populated
; Exit: node_count set, nodes array populated, func_table populated
; Error: prints to stderr, exits 1
;
; Uses: par_ prefix for all labels
;
; AST node layout (32 bytes) — see ast-format.md:
;   0:1  node_type
;   1:1  sub_type
;   2:2  padding
;   4:4  string_ref (byte offset into string table)
;   8:4  string_len
;   12:4 child_count
;   16:4 first_child (node index, or 0xFFFFFFFF)
;   20:4 next_sibling (node index, or 0xFFFFFFFF)
;   24:4 type_info
;   28:4 extra
;
; Function table entry (32 bytes):
;   0:4  name_offset (into string table)
;   4:4  name_len
;   8:4  param_count
;   12:4 node_index (filled in pass 2)
;   16:4 return_type
;   20:12 padding

%define NODE_SIZE 32
%define MAX_NODES 16384
%define FUNC_ENTRY_SIZE 32
%define MAX_FUNCS 256
%define NO_CHILD 0xFFFFFFFF

; Token type constants (from ast-format.md)
%define TOK_KW_FN      0
%define TOK_KW_LET     1
%define TOK_KW_MATCH   3
%define TOK_KW_FOR     4
%define TOK_KW_IN      5
%define TOK_KW_DO      6
%define TOK_KW_MODULE  7
%define TOK_KW_TRUE    11
%define TOK_KW_FALSE   12
%define TOK_IDENT      13
%define TOK_LIT_INT    14
%define TOK_LIT_STRING 16
%define TOK_LBRACE     17
%define TOK_RBRACE     18
%define TOK_LPAREN     19
%define TOK_RPAREN     20
%define TOK_LBRACKET   21
%define TOK_RBRACKET   22
%define TOK_ASSIGN     23
%define TOK_ARROW      38
%define TOK_COLON      40
%define TOK_SEMICOLON  41
%define TOK_COMMA      42
%define TOK_EOF        44

; AST node types (from ast-format.md)
%define NODE_MODULE     0
%define NODE_FN_DECL    1
%define NODE_PARAM      2
%define NODE_BLOCK      3

; Type info
%define TYPE_INT     0
%define TYPE_BOOL    1
%define TYPE_STRING  2
%define TYPE_UNIT    3
%define TYPE_ARRAY   4
%define TYPE_UNKNOWN 5

%define TOKEN_SIZE 20

section .data
par_err_expect_module: db "error: expected 'module' at start of program", 10
par_err_expect_module_len equ $ - par_err_expect_module
par_err_expect_ident: db "error: expected identifier", 10
par_err_expect_ident_len equ $ - par_err_expect_ident
par_err_expect_semi: db "error: expected ';'", 10
par_err_expect_semi_len equ $ - par_err_expect_semi
par_err_expect_lparen: db "error: expected '('", 10
par_err_expect_lparen_len equ $ - par_err_expect_lparen
par_err_expect_rparen: db "error: expected ')'", 10
par_err_expect_rparen_len equ $ - par_err_expect_rparen
par_err_expect_lbracket: db "error: expected '['", 10
par_err_expect_lbracket_len equ $ - par_err_expect_lbracket
par_err_expect_rbracket: db "error: expected ']'", 10
par_err_expect_rbracket_len equ $ - par_err_expect_rbracket
par_err_expect_arrow: db "error: expected '->'", 10
par_err_expect_arrow_len equ $ - par_err_expect_arrow
par_err_expect_colon: db "error: expected ':'", 10
par_err_expect_colon_len equ $ - par_err_expect_colon
par_err_expect_lbrace: db "error: expected '{'", 10
par_err_expect_lbrace_len equ $ - par_err_expect_lbrace
par_err_node_overflow: db "error: AST node buffer overflow", 10
par_err_node_overflow_len equ $ - par_err_node_overflow
par_err_func_overflow: db "error: function table overflow", 10
par_err_func_overflow_len equ $ - par_err_func_overflow
par_err_at: db " at "
par_err_at_len equ $ - par_err_at
par_colon_str: db ":"

; Dump labels
par_dump_module_str: db "  MODULE "
par_dump_module_str_len equ $ - par_dump_module_str
par_dump_fn_str: db "  FN "
par_dump_fn_str_len equ $ - par_dump_fn_str
par_dump_param_str: db "    PARAM "
par_dump_param_str_len equ $ - par_dump_param_str
par_dump_colon: db ":"
par_dump_space: db " "
par_dump_body_str: db "    BLOCK (body)", 10
par_dump_body_str_len equ $ - par_dump_body_str
par_dump_params_str: db " params="
par_dump_params_str_len equ $ - par_dump_params_str
par_dump_newline: db 10
par_dump_indent: db "    "
par_dump_indent_len equ $ - par_dump_indent
par_dump_lbracket: db "["
par_dump_type_eq: db "] type="
par_dump_type_eq_len equ $ - par_dump_type_eq
par_dump_sub_eq: db " sub="
par_dump_sub_eq_len equ $ - par_dump_sub_eq
par_dump_ch_eq: db " children="
par_dump_ch_eq_len equ $ - par_dump_ch_eq
par_dump_first_eq: db " first="
par_dump_first_eq_len equ $ - par_dump_first_eq
par_dump_name_eq: db " name="
par_dump_name_eq_len equ $ - par_dump_name_eq

section .bss
par_itoa_buf resb 32

section .text

; ============================================================
; par_parse_program — main entry point (two passes)
; ============================================================
par_parse_program:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; === Pass 1: collect function names and parameter counts ===
    xor rax, rax
    mov [rel func_count], rax
    mov [rel tok_pos], rax          ; start from token 0

par_pass1_loop:
    call par_peek_type              ; rax = current token type
    cmp eax, TOK_EOF
    je par_pass1_done
    cmp eax, TOK_KW_FN
    je par_pass1_fn
    ; Skip any other token
    inc qword [rel tok_pos]
    jmp par_pass1_loop

par_pass1_fn:
    ; Found KW_FN — next token should be IDENT (function name)
    inc qword [rel tok_pos]         ; skip KW_FN
    call par_peek_type
    cmp eax, TOK_IDENT
    jne par_pass1_skip_fn           ; malformed, skip (pass 2 will catch it)

    ; Record function name in func_table
    mov rax, [rel func_count]
    cmp rax, MAX_FUNCS
    jge par_die_func_overflow

    ; Get function name from token
    call par_current_token_ptr      ; rax = pointer to current token
    mov r12, rax                    ; r12 = token pointer
    mov ecx, [r12 + 4]             ; string_offset
    mov edx, [r12 + 8]             ; string_length

    ; Calculate func_table entry pointer
    mov rax, [rel func_count]
    imul rax, FUNC_ENTRY_SIZE
    lea rdi, [rel func_table]
    add rdi, rax                    ; rdi = entry pointer

    ; Zero the entry
    xor eax, eax
    mov [rdi], eax
    mov [rdi+4], eax
    mov [rdi+8], eax
    mov [rdi+12], eax
    mov [rdi+16], eax
    mov [rdi+20], eax
    mov [rdi+24], eax
    mov [rdi+28], eax

    ; Write name_offset and name_len
    mov [rdi], ecx                  ; name_offset
    mov [rdi+4], edx                ; name_len

    ; Count parameters: skip to LPAREN, count IDENTs before RPAREN
    inc qword [rel tok_pos]         ; skip IDENT (fn name)
    call par_peek_type
    cmp eax, TOK_LPAREN
    jne par_pass1_skip_fn
    inc qword [rel tok_pos]         ; skip LPAREN

    xor r13d, r13d                  ; r13 = param count
par_pass1_count_params:
    call par_peek_type
    cmp eax, TOK_RPAREN
    je par_pass1_params_done
    cmp eax, TOK_EOF
    je par_pass1_params_done
    cmp eax, TOK_IDENT
    je par_pass1_got_param
    ; Skip commas, colons, type names
    inc qword [rel tok_pos]
    jmp par_pass1_count_params

par_pass1_got_param:
    ; Check if next token after IDENT is COLON (it's a param name, not type)
    ; Peek at token after this IDENT
    mov rax, [rel tok_pos]
    inc rax
    cmp rax, [rel tok_count]
    jge par_pass1_count_params
    ; Get token at tok_pos+1
    imul rax, TOKEN_SIZE
    lea rsi, [rel tokens]
    movzx eax, byte [rsi + rax]    ; type of next token
    cmp eax, TOK_COLON
    jne par_pass1_skip_param        ; it's a type name, not a param
    inc r13                         ; count this param
par_pass1_skip_param:
    inc qword [rel tok_pos]
    jmp par_pass1_count_params

par_pass1_params_done:
    mov [rdi+8], r13d               ; param_count
    inc qword [rel tok_pos]         ; skip RPAREN
    inc qword [rel func_count]

par_pass1_skip_fn:
    ; Skip remaining tokens until next KW_FN or EOF
    jmp par_pass1_loop

par_pass1_done:

    ; === Pass 2: parse declarations and build AST ===
    xor rax, rax
    mov [rel tok_pos], rax          ; reset to token 0
    mov [rel node_count], rax       ; reset nodes

    ; Parse module declaration: KW_MODULE IDENT SEMICOLON
    call par_peek_type
    cmp eax, TOK_KW_MODULE
    jne par_die_expect_module
    inc qword [rel tok_pos]         ; consume KW_MODULE

    call par_peek_type
    cmp eax, TOK_IDENT
    jne par_die_expect_ident

    ; Allocate NODE_MODULE
    call par_alloc_node             ; rax = pointer to new node
    mov r12, rax                    ; r12 = module node
    mov byte [r12], NODE_MODULE     ; node_type
    ; Copy module name from current token
    call par_current_token_ptr
    mov ecx, [rax + 4]             ; string_offset
    mov edx, [rax + 8]             ; string_length
    mov [r12 + 4], ecx             ; string_ref
    mov [r12 + 8], edx             ; string_len
    mov dword [r12 + 16], NO_CHILD ; no children
    mov dword [r12 + 20], NO_CHILD ; no sibling

    inc qword [rel tok_pos]         ; consume IDENT

    ; Expect semicolon
    call par_peek_type
    cmp eax, TOK_SEMICOLON
    jne par_die_expect_semi
    inc qword [rel tok_pos]         ; consume SEMICOLON

    ; Parse function declarations until EOF
    xor r14d, r14d                  ; r14 = func_table index for pass 2
par_pass2_loop:
    call par_peek_type
    cmp eax, TOK_EOF
    je par_pass2_done
    cmp eax, TOK_KW_FN
    jne par_die_expect_fn           ; only fn declarations allowed at top level
    call par_parse_fn_decl
    jmp par_pass2_loop

par_pass2_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ============================================================
; par_parse_fn_decl — parse one function declaration
; Expects tok_pos at KW_FN
; ============================================================
par_parse_fn_decl:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    inc qword [rel tok_pos]         ; consume KW_FN

    ; Expect function name (IDENT)
    call par_peek_type
    cmp eax, TOK_IDENT
    jne par_die_expect_ident

    ; Allocate NODE_FN_DECL
    call par_alloc_node
    mov r12, rax                    ; r12 = fn_decl node pointer
    mov byte [r12], NODE_FN_DECL
    ; Copy function name
    call par_current_token_ptr
    mov ecx, [rax + 4]
    mov edx, [rax + 8]
    mov [r12 + 4], ecx             ; string_ref
    mov [r12 + 8], edx             ; string_len
    mov dword [r12 + 16], NO_CHILD ; first_child (set later)
    mov dword [r12 + 20], NO_CHILD ; next_sibling
    mov dword [r12 + 28], NO_CHILD ; extra = body index (set later)

    ; Update func_table node_index for this function
    ; Find matching func_table entry by name
    mov r13d, ecx                   ; r13 = name_offset
    mov r14d, edx                   ; r14 = name_len
    ; r12 node index = node_count - 1
    mov rax, [rel node_count]
    dec rax
    mov r15, rax                    ; r15 = this fn_decl's node index

    ; Search func_table for matching name
    xor ecx, ecx                    ; index
par_pfd_find_func:
    cmp ecx, [rel func_count]
    jge par_pfd_func_not_found      ; shouldn't happen
    mov eax, ecx
    imul eax, FUNC_ENTRY_SIZE
    lea rdi, [rel func_table]
    add rdi, rax
    cmp [rdi], r13d                 ; name_offset match?
    jne par_pfd_find_next
    cmp [rdi+4], r14d              ; name_len match?
    jne par_pfd_find_next
    ; Found — store node_index
    mov [rdi+12], r15d
    jmp par_pfd_func_found
par_pfd_find_next:
    inc ecx
    jmp par_pfd_find_func
par_pfd_func_not_found:
par_pfd_func_found:

    inc qword [rel tok_pos]         ; consume function name IDENT

    ; Parse parameter list: LPAREN params RPAREN
    call par_peek_type
    cmp eax, TOK_LPAREN
    jne par_die_expect_lparen
    inc qword [rel tok_pos]

    xor r13d, r13d                  ; r13 = param count
    mov r14d, NO_CHILD              ; r14 = first param node index
    mov r15d, NO_CHILD              ; r15 = last param node index

par_pfd_params:
    call par_peek_type
    cmp eax, TOK_RPAREN
    je par_pfd_params_done
    ; Parse one param: IDENT COLON type_expr
    cmp eax, TOK_IDENT
    jne par_die_expect_ident

    ; Allocate NODE_PARAM
    call par_alloc_node
    mov rbx, rax                    ; rbx = param node pointer
    mov byte [rbx], NODE_PARAM
    ; Copy param name
    call par_current_token_ptr
    mov ecx, [rax + 4]
    mov edx, [rax + 8]
    mov [rbx + 4], ecx
    mov [rbx + 8], edx
    mov dword [rbx + 16], NO_CHILD
    mov dword [rbx + 20], NO_CHILD

    ; Get this param's node index
    mov rax, [rel node_count]
    dec rax                         ; index of node we just allocated

    ; Link into sibling chain
    cmp r14d, NO_CHILD
    jne par_pfd_link_param
    ; First param
    mov r14d, eax                   ; first_child
    mov r15d, eax                   ; last param
    jmp par_pfd_param_linked
par_pfd_link_param:
    ; Set previous param's next_sibling
    push rax
    movzx eax, r15b                 ; prev param index — wait, r15d is 32-bit
    pop rax
    push rax
    mov eax, r15d                   ; prev param node index
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    add rdi, rax
    pop rax                         ; current param node index
    mov [rdi + 20], eax             ; prev.next_sibling = current
    mov r15d, eax                   ; update last param
par_pfd_param_linked:

    inc r13                         ; param count++
    inc qword [rel tok_pos]         ; consume param name IDENT

    ; Expect COLON
    call par_peek_type
    cmp eax, TOK_COLON
    jne par_die_expect_colon
    inc qword [rel tok_pos]

    ; Parse type expression (just an IDENT for now)
    call par_peek_type
    cmp eax, TOK_IDENT
    jne par_die_expect_ident

    ; Set param type_info from type name
    call par_current_token_ptr
    mov ecx, [rax + 4]             ; type name offset
    mov edx, [rax + 8]             ; type name length
    push rbx
    mov edi, ecx                    ; zero-extends to rdi
    mov esi, edx                    ; zero-extends to rsi
    call par_resolve_type           ; rax = TYPE_* enum
    pop rbx
    mov [rbx + 24], eax            ; type_info

    inc qword [rel tok_pos]         ; consume type name

    ; Check for generic: LT type_expr GT (e.g., Array<Int>)
    call par_peek_type
    cmp eax, 31                     ; TOK_LT
    jne par_pfd_no_generic
    inc qword [rel tok_pos]         ; skip LT
    call par_peek_type              ; skip inner type
    cmp eax, TOK_IDENT
    jne par_die_expect_ident
    inc qword [rel tok_pos]
    call par_peek_type
    cmp eax, 32                     ; TOK_GT
    jne par_pfd_no_generic          ; tolerate missing GT
    inc qword [rel tok_pos]
par_pfd_no_generic:

    ; Check for comma
    call par_peek_type
    cmp eax, TOK_COMMA
    jne par_pfd_params              ; no comma, check for RPAREN
    inc qword [rel tok_pos]         ; consume comma
    jmp par_pfd_params

par_pfd_params_done:
    inc qword [rel tok_pos]         ; consume RPAREN

    ; Store param count and first_child on fn_decl node
    mov [r12 + 12], r13d            ; child_count = param count
    mov [r12 + 16], r14d            ; first_child = first param (or NO_CHILD)

    ; Parse effects: LBRACKET ident_list RBRACKET
    call par_peek_type
    cmp eax, TOK_LBRACKET
    jne par_die_expect_lbracket
    inc qword [rel tok_pos]
par_pfd_effects:
    call par_peek_type
    cmp eax, TOK_RBRACKET
    je par_pfd_effects_done
    ; Skip everything inside brackets
    inc qword [rel tok_pos]
    jmp par_pfd_effects
par_pfd_effects_done:
    inc qword [rel tok_pos]         ; consume RBRACKET

    ; Parse return type: ARROW type_expr
    call par_peek_type
    cmp eax, TOK_ARROW
    jne par_die_expect_arrow
    inc qword [rel tok_pos]

    ; Parse return type (IDENT, possibly generic)
    call par_peek_type
    cmp eax, TOK_IDENT
    jne par_die_expect_ident

    call par_current_token_ptr
    mov ecx, [rax + 4]
    mov edx, [rax + 8]
    mov rdi, rcx
    mov rsi, rdx
    call par_resolve_type
    mov [r12 + 24], eax             ; type_info = return type

    inc qword [rel tok_pos]         ; consume type name

    ; Check for generic on return type
    call par_peek_type
    cmp eax, 31                     ; TOK_LT
    jne par_pfd_no_ret_generic
    inc qword [rel tok_pos]
    call par_peek_type
    cmp eax, TOK_IDENT
    jne par_die_expect_ident
    inc qword [rel tok_pos]
    call par_peek_type
    cmp eax, 32                     ; TOK_GT
    jne par_pfd_no_ret_generic
    inc qword [rel tok_pos]
par_pfd_no_ret_generic:

    ; Parse body block: { stmts; expr? }
    call par_peek_type
    cmp eax, TOK_LBRACE
    jne par_die_expect_lbrace

    call expr_parse_block           ; eax = BLOCK node index
    mov [r12 + 28], eax             ; fn_decl.extra = body node index

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ============================================================
; par_alloc_node — allocate one 32-byte AST node, bounds-checked
; Returns: rax = pointer to new zeroed node
; ============================================================
par_alloc_node:
    push rcx
    push rdi

    mov rax, [rel node_count]
    cmp rax, MAX_NODES
    jge par_die_node_overflow

    ; Calculate pointer: nodes + count * NODE_SIZE
    mov rcx, rax
    imul rcx, NODE_SIZE
    lea rdi, [rel nodes]
    add rdi, rcx                    ; rdi = new node pointer

    ; Zero 32 bytes
    xor eax, eax
    mov [rdi], rax                  ; bytes 0-7
    mov [rdi+8], rax                ; bytes 8-15
    mov [rdi+16], rax               ; bytes 16-23
    mov [rdi+24], rax               ; bytes 24-31

    inc qword [rel node_count]
    mov rax, rdi                    ; return pointer

    pop rdi
    pop rcx
    ret

; ============================================================
; par_peek_type — return token type at tok_pos without advancing
; Returns: eax = token type (0-44)
; ============================================================
par_peek_type:
    push rcx
    push rsi
    mov rax, [rel tok_pos]
    cmp rax, [rel tok_count]
    jge par_peek_eof
    imul rax, TOKEN_SIZE
    lea rsi, [rel tokens]
    movzx eax, byte [rsi + rax]
    pop rsi
    pop rcx
    ret
par_peek_eof:
    mov eax, TOK_EOF
    pop rsi
    pop rcx
    ret

; ============================================================
; par_current_token_ptr — return pointer to token at tok_pos
; Returns: rax = pointer to 20-byte token
; ============================================================
par_current_token_ptr:
    push rcx
    mov rax, [rel tok_pos]
    imul rax, TOKEN_SIZE
    lea rcx, [rel tokens]
    add rax, rcx
    pop rcx
    ret

; ============================================================
; par_resolve_type — resolve a type name to TYPE_* enum
; Input: rdi = string_offset, rsi = string_length
; Output: eax = TYPE_* value
; Compares against known type names in the string table
; ============================================================
par_resolve_type:
    push rbx
    push rcx
    push rdx

    ; Get pointer to the type name in string table
    lea rbx, [rel strings]
    add rbx, rdi                    ; rbx = pointer to type name

    ; Check each known type
    ; "Int" (3 bytes)
    cmp rsi, 3
    jne par_rt_not_int
    cmp byte [rbx], 'I'
    jne par_rt_not_int
    cmp byte [rbx+1], 'n'
    jne par_rt_not_int
    cmp byte [rbx+2], 't'
    jne par_rt_not_int
    mov eax, TYPE_INT
    jmp par_rt_done

par_rt_not_int:
    ; "Bool" (4 bytes)
    cmp rsi, 4
    jne par_rt_not_bool
    cmp byte [rbx], 'B'
    jne par_rt_not_bool
    cmp byte [rbx+1], 'o'
    jne par_rt_not_bool
    cmp byte [rbx+2], 'o'
    jne par_rt_not_bool
    cmp byte [rbx+3], 'l'
    jne par_rt_not_bool
    mov eax, TYPE_BOOL
    jmp par_rt_done

par_rt_not_bool:
    ; "String" (6 bytes)
    cmp rsi, 6
    jne par_rt_not_string
    cmp byte [rbx], 'S'
    jne par_rt_not_string
    cmp byte [rbx+1], 't'
    jne par_rt_not_string
    mov eax, TYPE_STRING
    jmp par_rt_done

par_rt_not_string:
    ; "Unit" (4 bytes)
    cmp rsi, 4
    jne par_rt_not_unit
    cmp byte [rbx], 'U'
    jne par_rt_not_unit
    mov eax, TYPE_UNIT
    jmp par_rt_done

par_rt_not_unit:
    ; "Array" (5 bytes)
    cmp rsi, 5
    jne par_rt_not_array
    cmp byte [rbx], 'A'
    jne par_rt_not_array
    mov eax, TYPE_ARRAY
    jmp par_rt_done

par_rt_not_array:
    mov eax, TYPE_UNKNOWN

par_rt_done:
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================
; par_dump_ast — print AST nodes to stderr (for --dump-ast)
; ============================================================
par_dump_ast:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    xor r12d, r12d                  ; r12 = node index

par_da_loop:
    cmp r12, [rel node_count]
    jge par_da_done

    ; Get node pointer
    mov rax, r12
    imul rax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax                    ; rbx = node pointer

    movzx eax, byte [rbx]          ; node_type

    cmp eax, NODE_MODULE
    je par_da_module
    cmp eax, NODE_FN_DECL
    je par_da_fn
    cmp eax, NODE_PARAM
    je par_da_param
    cmp eax, NODE_BLOCK
    je par_da_block

    ; All other node types — print generic info
    jmp par_da_generic

par_da_module:
    ; Print "  MODULE name\n"
    mov rdi, STDERR
    lea rsi, [rel par_dump_module_str]
    mov rdx, par_dump_module_str_len
    mov rax, SYS_WRITE
    syscall
    ; Print name from string table
    mov ecx, [rbx + 4]             ; string_ref
    mov edx, [rbx + 8]             ; string_len
    mov rdi, STDERR
    lea rsi, [rel strings]
    add rsi, rcx
    mov rax, SYS_WRITE
    syscall
    ; Newline
    mov rdi, STDERR
    lea rsi, [rel par_dump_newline]
    mov rdx, 1
    mov rax, SYS_WRITE
    syscall
    jmp par_da_next

par_da_fn:
    ; Print "  FN name params=N\n"
    mov rdi, STDERR
    lea rsi, [rel par_dump_fn_str]
    mov rdx, par_dump_fn_str_len
    mov rax, SYS_WRITE
    syscall
    ; Name
    mov ecx, [rbx + 4]
    mov edx, [rbx + 8]
    mov rdi, STDERR
    lea rsi, [rel strings]
    add rsi, rcx
    mov rax, SYS_WRITE
    syscall
    ; " params="
    mov rdi, STDERR
    lea rsi, [rel par_dump_params_str]
    mov rdx, par_dump_params_str_len
    mov rax, SYS_WRITE
    syscall
    ; param count
    movzx eax, word [rbx + 12]     ; child_count (low 16 bits)
    ; Actually child_count is 4 bytes
    mov eax, [rbx + 12]
    lea rdi, [rel par_itoa_buf]
    call par_itoa
    mov rdi, STDERR
    lea rsi, [rel par_itoa_buf]
    mov rdx, rcx
    mov rax, SYS_WRITE
    syscall
    ; Newline
    mov rdi, STDERR
    lea rsi, [rel par_dump_newline]
    mov rdx, 1
    mov rax, SYS_WRITE
    syscall
    jmp par_da_next

par_da_param:
    ; Print "    PARAM name:type\n"
    mov rdi, STDERR
    lea rsi, [rel par_dump_param_str]
    mov rdx, par_dump_param_str_len
    mov rax, SYS_WRITE
    syscall
    ; Name
    mov ecx, [rbx + 4]
    mov edx, [rbx + 8]
    mov rdi, STDERR
    lea rsi, [rel strings]
    add rsi, rcx
    mov rax, SYS_WRITE
    syscall
    ; Newline
    mov rdi, STDERR
    lea rsi, [rel par_dump_newline]
    mov rdx, 1
    mov rax, SYS_WRITE
    syscall
    jmp par_da_next

par_da_block:
    ; Print "    BLOCK children=N\n"
    mov rdi, STDERR
    lea rsi, [rel par_dump_body_str]
    mov rdx, par_dump_body_str_len
    mov rax, SYS_WRITE
    syscall
    jmp par_da_next

par_da_generic:
    ; Print "    [N] type=T sub=S child=C first=F sib=X"
    ; Print node index
    mov rdi, STDERR
    lea rsi, [rel par_dump_indent]
    mov rdx, par_dump_indent_len
    mov rax, SYS_WRITE
    syscall
    ; Print "["
    mov rdi, STDERR
    lea rsi, [rel par_dump_lbracket]
    mov rdx, 1
    mov rax, SYS_WRITE
    syscall
    ; Index number
    mov eax, r12d
    lea rdi, [rel par_itoa_buf]
    call par_itoa
    mov rdi, STDERR
    lea rsi, [rel par_itoa_buf]
    mov rdx, rcx
    mov rax, SYS_WRITE
    syscall
    ; Print "] type="
    mov rdi, STDERR
    lea rsi, [rel par_dump_type_eq]
    mov rdx, par_dump_type_eq_len
    mov rax, SYS_WRITE
    syscall
    ; Node type number
    movzx eax, byte [rbx]
    lea rdi, [rel par_itoa_buf]
    call par_itoa
    mov rdi, STDERR
    lea rsi, [rel par_itoa_buf]
    mov rdx, rcx
    mov rax, SYS_WRITE
    syscall
    ; Print " sub="
    mov rdi, STDERR
    lea rsi, [rel par_dump_sub_eq]
    mov rdx, par_dump_sub_eq_len
    mov rax, SYS_WRITE
    syscall
    movzx eax, byte [rbx + 1]
    lea rdi, [rel par_itoa_buf]
    call par_itoa
    mov rdi, STDERR
    lea rsi, [rel par_itoa_buf]
    mov rdx, rcx
    mov rax, SYS_WRITE
    syscall
    ; Print " children="
    mov rdi, STDERR
    lea rsi, [rel par_dump_ch_eq]
    mov rdx, par_dump_ch_eq_len
    mov rax, SYS_WRITE
    syscall
    mov eax, [rbx + 12]
    lea rdi, [rel par_itoa_buf]
    call par_itoa
    mov rdi, STDERR
    lea rsi, [rel par_itoa_buf]
    mov rdx, rcx
    mov rax, SYS_WRITE
    syscall
    ; Print " first="
    mov rdi, STDERR
    lea rsi, [rel par_dump_first_eq]
    mov rdx, par_dump_first_eq_len
    mov rax, SYS_WRITE
    syscall
    mov eax, [rbx + 16]
    lea rdi, [rel par_itoa_buf]
    call par_itoa
    mov rdi, STDERR
    lea rsi, [rel par_itoa_buf]
    mov rdx, rcx
    mov rax, SYS_WRITE
    syscall
    ; Print name if has one
    mov edx, [rbx + 8]             ; string_len
    cmp edx, 0
    je par_da_gen_noname
    mov rdi, STDERR
    lea rsi, [rel par_dump_name_eq]
    mov rdx, par_dump_name_eq_len
    mov rax, SYS_WRITE
    syscall
    mov ecx, [rbx + 4]
    mov edx, [rbx + 8]
    mov rdi, STDERR
    lea rsi, [rel strings]
    add rsi, rcx
    mov rax, SYS_WRITE
    syscall
par_da_gen_noname:
    ; Newline
    mov rdi, STDERR
    lea rsi, [rel par_dump_newline]
    mov rdx, 1
    mov rax, SYS_WRITE
    syscall
    jmp par_da_next

par_da_next:
    inc r12
    jmp par_da_loop

par_da_done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ============================================================
; par_itoa — convert unsigned 32-bit int in eax to decimal at [rdi]
; Returns: rcx = length
; ============================================================
par_itoa:
    push rbx
    push rdx
    push rsi
    mov rsi, rdi
    xor ecx, ecx

    cmp eax, 0
    jne par_itoa_loop
    mov byte [rdi], '0'
    mov ecx, 1
    jmp par_itoa_done

par_itoa_loop:
    cmp eax, 0
    je par_itoa_reverse
    xor edx, edx
    mov ebx, 10
    div ebx
    add dl, '0'
    mov byte [rdi + rcx], dl
    inc ecx
    jmp par_itoa_loop

par_itoa_reverse:
    xor edx, edx
    mov ebx, ecx
    dec ebx
par_itoa_rev_loop:
    cmp edx, ebx
    jge par_itoa_done
    movzx eax, byte [rsi + rdx]
    movzx r8d, byte [rsi + rbx]
    mov byte [rsi + rdx], r8b
    mov byte [rsi + rbx], al
    inc edx
    dec ebx
    jmp par_itoa_rev_loop

par_itoa_done:
    pop rsi
    pop rdx
    pop rbx
    ret

; ============================================================
; Error handlers
; ============================================================
par_die_expect_module:
    mov rdi, STDERR
    lea rsi, [rel par_err_expect_module]
    mov rdx, par_err_expect_module_len
    jmp par_die_print

par_die_expect_ident:
    mov rdi, STDERR
    lea rsi, [rel par_err_expect_ident]
    mov rdx, par_err_expect_ident_len
    jmp par_die_print

par_die_expect_semi:
    mov rdi, STDERR
    lea rsi, [rel par_err_expect_semi]
    mov rdx, par_err_expect_semi_len
    jmp par_die_print

par_die_expect_lparen:
    mov rdi, STDERR
    lea rsi, [rel par_err_expect_lparen]
    mov rdx, par_err_expect_lparen_len
    jmp par_die_print

par_die_expect_rparen:
    mov rdi, STDERR
    lea rsi, [rel par_err_expect_rparen]
    mov rdx, par_err_expect_rparen_len
    jmp par_die_print

par_die_expect_lbracket:
    mov rdi, STDERR
    lea rsi, [rel par_err_expect_lbracket]
    mov rdx, par_err_expect_lbracket_len
    jmp par_die_print

par_die_expect_rbracket:
    mov rdi, STDERR
    lea rsi, [rel par_err_expect_rbracket]
    mov rdx, par_err_expect_rbracket_len
    jmp par_die_print

par_die_expect_arrow:
    mov rdi, STDERR
    lea rsi, [rel par_err_expect_arrow]
    mov rdx, par_err_expect_arrow_len
    jmp par_die_print

par_die_expect_colon:
    mov rdi, STDERR
    lea rsi, [rel par_err_expect_colon]
    mov rdx, par_err_expect_colon_len
    jmp par_die_print

par_die_expect_lbrace:
    mov rdi, STDERR
    lea rsi, [rel par_err_expect_lbrace]
    mov rdx, par_err_expect_lbrace_len
    jmp par_die_print

par_die_expect_fn:
    lea rsi, [rel par_err_expect_ident]  ; reuse "expected identifier" for now
    mov rdx, par_err_expect_ident_len
    mov rdi, STDERR
    jmp par_die_print

par_die_node_overflow:
    mov rdi, STDERR
    lea rsi, [rel par_err_node_overflow]
    mov rdx, par_err_node_overflow_len
    jmp par_die_print

par_die_func_overflow:
    mov rdi, STDERR
    lea rsi, [rel par_err_func_overflow]
    mov rdx, par_err_func_overflow_len
    jmp par_die_print

par_die_print:
    mov rax, SYS_WRITE
    syscall
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall
