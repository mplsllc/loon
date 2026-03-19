; stage1/expr_parser.asm
; Expression parsing with precedence climbing for Loon-0
;
; Entry points:
;   expr_parse       — parse one expression, return node index in eax
;   expr_parse_block — parse block { stmts; expr? }, return BLOCK node index
;
; Uses: expr_ prefix for all labels
;
; Precedence levels (lowest to highest):
;   1: ||
;   2: &&
;   3: == != < > <= >=  (not chainable)
;   4: + -
;   5: * / %
;   6: ! - (unary prefix)
;   7: do (prefix)
;   8: f() arr[i] (postfix)

; Additional token type constants needed
%define TOK_PLUS    24
%define TOK_MINUS   25
%define TOK_STAR    26
%define TOK_SLASH   27
%define TOK_PERCENT 28
%define TOK_EQ      29
%define TOK_NEQ     30
%define TOK_LT      31
%define TOK_GT      32
%define TOK_LTE     33
%define TOK_GTE     34
%define TOK_AND     35
%define TOK_OR      36
%define TOK_NOT     37

; Node types
%define NODE_LET        4
%define NODE_EXPR_STMT  5
%define NODE_RETURN_EXPR 6
%define NODE_INT_LIT    7
%define NODE_STR_LIT    8
%define NODE_BOOL_LIT   9
%define NODE_IDENT_REF  10
%define NODE_BINOP      11
%define NODE_UNARY_NOT  12
%define NODE_UNARY_NEG  13
%define NODE_CALL       14
%define NODE_DO_EXPR    15
%define NODE_MATCH      16
%define NODE_MATCH_ARM  17
%define NODE_FOR        18
%define NODE_ARRAY_NEW  19
%define NODE_ARRAY_GET  20
%define NODE_ARRAY_SET  21

; BINOP sub_types
%define BINOP_ADD  0
%define BINOP_SUB  1
%define BINOP_MUL  2
%define BINOP_DIV  3
%define BINOP_MOD  4
%define BINOP_EQ   5
%define BINOP_NEQ  6
%define BINOP_LT   7
%define BINOP_GT   8
%define BINOP_LTE  9
%define BINOP_GTE  10
%define BINOP_AND  11
%define BINOP_OR   12

; Builtin sub_types
%define BUILTIN_NONE          0
%define BUILTIN_PRINT         1
%define BUILTIN_PRINT_RAW     2
%define BUILTIN_INT_TO_STRING 3
%define BUILTIN_STRING_LENGTH 4
%define BUILTIN_STRING_EQUALS 5
%define BUILTIN_STRING_CHAR_AT 6
%define BUILTIN_READ_FILE     7
%define BUILTIN_EXIT          8
%define BUILTIN_GET_ARG       9

section .data
expr_err_expect_expr: db "error: expected expression", 10
expr_err_expect_expr_len equ $ - expr_err_expect_expr
expr_err_expect_rparen: db "error: expected ')' in expression", 10
expr_err_expect_rparen_len equ $ - expr_err_expect_rparen

; Builtin name table: name_offset_in_data, name_length, builtin_id
; These are literal strings in .data, not string table references
expr_bi_print:         db "print"
expr_bi_print_raw:     db "print_raw"
expr_bi_int_to_string: db "int_to_string"
expr_bi_string_length: db "string_length"
expr_bi_string_equals: db "string_equals"
expr_bi_string_char_at: db "string_char_at"
expr_bi_read_file:     db "read_file"
expr_bi_exit:          db "exit"
expr_bi_get_arg:       db "get_arg"

; Builtin lookup table: pointer, length, id
expr_builtin_table:
    dq expr_bi_print, 5, BUILTIN_PRINT
    dq expr_bi_print_raw, 9, BUILTIN_PRINT_RAW
    dq expr_bi_int_to_string, 13, BUILTIN_INT_TO_STRING
    dq expr_bi_string_length, 13, BUILTIN_STRING_LENGTH
    dq expr_bi_string_equals, 14, BUILTIN_STRING_EQUALS
    dq expr_bi_string_char_at, 15, BUILTIN_STRING_CHAR_AT
    dq expr_bi_read_file, 9, BUILTIN_READ_FILE
    dq expr_bi_exit, 4, BUILTIN_EXIT
    dq expr_bi_get_arg, 7, BUILTIN_GET_ARG
expr_builtin_table_end:
%define BUILTIN_ENTRY_SIZE 24

section .text

; ============================================================
; expr_parse_block — parse { statement* expr? }
; Expects tok_pos at LBRACE
; Returns: eax = BLOCK node index
; ============================================================
expr_parse_block:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Consume LBRACE
    inc qword [rel tok_pos]

    ; Allocate BLOCK node
    call par_alloc_node
    mov r12, rax                    ; r12 = block node pointer
    mov byte [r12], NODE_BLOCK
    mov dword [r12 + 12], 0         ; child_count = 0
    mov dword [r12 + 16], NO_CHILD
    mov dword [r12 + 20], NO_CHILD
    ; Get block node index
    mov rax, [rel node_count]
    dec rax
    mov r13d, eax                   ; r13 = block node index
    mov r14d, NO_CHILD              ; r14 = first child index
    mov r15d, NO_CHILD              ; r15 = last child index

expr_pb_loop:
    call par_peek_type
    cmp eax, TOK_RBRACE
    je expr_pb_done
    cmp eax, TOK_EOF
    je expr_pb_done

    ; Determine what this statement/expression is
    ; Check for let statement
    cmp eax, TOK_KW_LET
    je expr_pb_let

    ; Check for array_set: IDENT LBRACKET → always array_set_stmt (LL(1) rule)
    cmp eax, TOK_IDENT
    jne expr_pb_not_array_set
    ; Peek at next token
    mov rax, [rel tok_pos]
    inc rax
    cmp rax, [rel tok_count]
    jge expr_pb_not_array_set
    imul rax, TOKEN_SIZE
    lea rsi, [rel tokens]
    movzx eax, byte [rsi + rax]
    cmp eax, TOK_LBRACKET
    je expr_pb_array_set

expr_pb_not_array_set:
    ; Parse expression
    call expr_parse                 ; eax = expression node index

    ; Check if followed by semicolon (EXPR_STMT) or RBRACE (RETURN_EXPR)
    push rax                        ; save expr node index
    call par_peek_type
    cmp eax, TOK_SEMICOLON
    je expr_pb_expr_stmt
    ; No semicolon — this is the return expression
    pop rax                         ; expr node index
    ; Wrap in RETURN_EXPR
    push rax
    call par_alloc_node
    mov rbx, rax
    mov byte [rbx], NODE_RETURN_EXPR
    mov dword [rbx + 12], 1         ; child_count = 1
    mov dword [rbx + 20], NO_CHILD
    pop rax                         ; child expr index
    mov [rbx + 16], eax             ; first_child = expr
    ; Get RETURN_EXPR node index
    mov rax, [rel node_count]
    dec rax
    jmp expr_pb_add_child

expr_pb_expr_stmt:
    inc qword [rel tok_pos]         ; consume semicolon
    pop rax                         ; expr node index
    ; Wrap in EXPR_STMT
    push rax
    call par_alloc_node
    mov rbx, rax
    mov byte [rbx], NODE_EXPR_STMT
    mov dword [rbx + 12], 1
    mov dword [rbx + 20], NO_CHILD
    pop rax
    mov [rbx + 16], eax             ; first_child = expr
    mov rax, [rel node_count]
    dec rax
    jmp expr_pb_add_child

expr_pb_let:
    call expr_parse_let             ; eax = LET node index
    jmp expr_pb_add_child

expr_pb_array_set:
    call expr_parse_array_set       ; eax = ARRAY_SET node index
    jmp expr_pb_add_child

expr_pb_add_child:
    ; eax = child node index to add to block
    mov ecx, eax                    ; ecx = new child index
    ; Link into sibling chain
    cmp r14d, NO_CHILD
    jne expr_pb_link_child
    ; First child
    mov r14d, ecx
    mov r15d, ecx
    jmp expr_pb_child_linked
expr_pb_link_child:
    ; Set previous child's next_sibling
    push rcx
    mov eax, r15d
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    add rdi, rax
    pop rcx
    mov [rdi + 20], ecx             ; prev.next_sibling = new child
    mov r15d, ecx
expr_pb_child_linked:
    ; Increment block's child_count
    inc dword [r12 + 12]
    jmp expr_pb_loop

expr_pb_done:
    ; Set block's first_child
    mov [r12 + 16], r14d

    ; Consume RBRACE
    call par_peek_type
    cmp eax, TOK_RBRACE
    jne expr_pb_ret                 ; tolerate missing RBRACE at EOF
    inc qword [rel tok_pos]

expr_pb_ret:
    mov eax, r13d                   ; return block node index

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ============================================================
; expr_parse_let — parse let binding: KW_LET IDENT [: type] = expr ;
; Returns: eax = LET node index
; ============================================================
expr_parse_let:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    inc qword [rel tok_pos]         ; consume KW_LET

    ; Expect IDENT
    call par_peek_type
    cmp eax, TOK_IDENT
    jne par_die_expect_ident

    ; Allocate NODE_LET
    call par_alloc_node
    mov r12, rax                    ; r12 = let node
    mov byte [r12], NODE_LET
    ; Copy variable name
    call par_current_token_ptr
    mov ecx, [rax + 4]
    mov edx, [rax + 8]
    mov [r12 + 4], ecx
    mov [r12 + 8], edx
    mov dword [r12 + 16], NO_CHILD
    mov dword [r12 + 20], NO_CHILD
    mov dword [r12 + 24], TYPE_UNKNOWN  ; type_info default

    ; Get let node index
    mov rax, [rel node_count]
    dec rax
    mov rbx, rax                    ; rbx = let node index

    inc qword [rel tok_pos]         ; consume IDENT

    ; Optional type annotation: COLON type_expr
    call par_peek_type
    cmp eax, TOK_COLON
    jne expr_pl_no_type
    inc qword [rel tok_pos]         ; consume COLON
    call par_peek_type
    cmp eax, TOK_IDENT
    jne par_die_expect_ident
    ; Resolve type
    call par_current_token_ptr
    mov edi, [rax + 4]
    mov esi, [rax + 8]
    call par_resolve_type
    mov [r12 + 24], eax
    inc qword [rel tok_pos]         ; consume type name
    ; Skip generic <Type>
    call par_peek_type
    cmp eax, TOK_LT
    jne expr_pl_no_type
    inc qword [rel tok_pos]         ; LT
    call par_peek_type
    cmp eax, TOK_IDENT
    jne par_die_expect_ident
    inc qword [rel tok_pos]         ; inner type
    call par_peek_type
    cmp eax, TOK_GT
    jne expr_pl_no_type
    inc qword [rel tok_pos]         ; GT

expr_pl_no_type:
    ; Expect ASSIGN
    call par_peek_type
    cmp eax, TOK_ASSIGN
    jne par_die_expect_semi         ; reuse error msg
    inc qword [rel tok_pos]

    ; Parse initializer expression
    call expr_parse                 ; eax = expr node index
    mov [r12 + 16], eax             ; first_child = initializer
    mov dword [r12 + 12], 1         ; child_count = 1

    ; Expect semicolon
    call par_peek_type
    cmp eax, TOK_SEMICOLON
    jne par_die_expect_semi
    inc qword [rel tok_pos]

    mov eax, ebx                    ; return let node index

    pop r12
    pop rbx
    pop rbp
    ret

; ============================================================
; expr_parse_array_set — parse arr[idx] = val;
; Expects tok_pos at IDENT (array name), next token is LBRACKET
; Returns: eax = ARRAY_SET node index
; ============================================================
expr_parse_array_set:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    ; Allocate NODE_ARRAY_SET
    call par_alloc_node
    mov r12, rax
    mov byte [r12], NODE_ARRAY_SET
    mov dword [r12 + 20], NO_CHILD

    ; Copy array name
    call par_current_token_ptr
    mov ecx, [rax + 4]
    mov edx, [rax + 8]
    mov [r12 + 4], ecx
    mov [r12 + 8], edx

    ; Get node index
    mov rax, [rel node_count]
    dec rax
    mov r13d, eax                   ; r13 = array_set node index

    inc qword [rel tok_pos]         ; consume IDENT
    inc qword [rel tok_pos]         ; consume LBRACKET

    ; Parse index expression
    call expr_parse
    mov [r12 + 16], eax             ; first_child = index expr

    ; Expect RBRACKET
    call par_peek_type
    cmp eax, TOK_RBRACKET
    jne par_die_expect_rbracket
    inc qword [rel tok_pos]

    ; Expect ASSIGN
    call par_peek_type
    cmp eax, TOK_ASSIGN
    jne par_die_expect_semi
    inc qword [rel tok_pos]

    ; Parse value expression
    call expr_parse
    ; Link as second child (sibling of index)
    mov ebx, eax                    ; ebx = value node index
    ; Get index node and set its next_sibling
    mov eax, [r12 + 16]            ; first_child = index node index
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    add rdi, rax
    mov [rdi + 20], ebx             ; index.next_sibling = value

    mov dword [r12 + 12], 2         ; child_count = 2

    ; Expect semicolon
    call par_peek_type
    cmp eax, TOK_SEMICOLON
    jne par_die_expect_semi
    inc qword [rel tok_pos]

    mov eax, r13d                   ; return node index

    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ============================================================
; expr_parse — parse one expression (entry point)
; Returns: eax = node index
; ============================================================
expr_parse:
    ; Check for match and for first
    push rbx
    call par_peek_type
    cmp eax, TOK_KW_MATCH
    je expr_p_match
    cmp eax, TOK_KW_FOR
    je expr_p_for
    pop rbx
    jmp expr_parse_or               ; start at lowest precedence

expr_p_match:
    pop rbx
    jmp expr_parse_match

expr_p_for:
    pop rbx
    jmp expr_parse_for

; ============================================================
; Precedence climbing: each level calls the next higher level
; ============================================================

; Level 1: ||
expr_parse_or:
    push rbx
    push r12
    call expr_parse_and             ; left operand
    mov r12d, eax                   ; r12 = left node index
expr_po_loop:
    call par_peek_type
    cmp eax, TOK_OR
    jne expr_po_done
    inc qword [rel tok_pos]         ; consume ||
    push r12
    call expr_parse_and             ; right operand
    mov ebx, eax                    ; ebx = right
    pop r12
    ; Create BINOP node
    call par_alloc_node
    mov byte [rax], NODE_BINOP
    mov byte [rax + 1], BINOP_OR
    mov [rax + 16], r12d            ; first_child = left
    mov dword [rax + 12], 2
    mov dword [rax + 24], TYPE_BOOL
    mov dword [rax + 20], NO_CHILD
    ; Link left.next_sibling = right
    push rax
    mov eax, r12d
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    add rdi, rax
    mov [rdi + 20], ebx
    pop rax
    ; New left = this binop node
    mov r12d, eax
    sub r12d, 1                     ; node pointer → node index
    ; Actually: rax is pointer, need index
    mov rax, [rel node_count]
    dec rax
    mov r12d, eax
    jmp expr_po_loop
expr_po_done:
    mov eax, r12d
    pop r12
    pop rbx
    ret

; Level 2: &&
expr_parse_and:
    push rbx
    push r12
    call expr_parse_cmp
    mov r12d, eax
expr_pa_loop:
    call par_peek_type
    cmp eax, TOK_AND
    jne expr_pa_done
    inc qword [rel tok_pos]
    push r12
    call expr_parse_cmp
    mov ebx, eax
    pop r12
    ; Create BINOP AND
    call par_alloc_node
    mov byte [rax], NODE_BINOP
    mov byte [rax + 1], BINOP_AND
    mov [rax + 16], r12d
    mov dword [rax + 12], 2
    mov dword [rax + 24], TYPE_BOOL
    mov dword [rax + 20], NO_CHILD
    ; Link siblings
    push rax
    mov eax, r12d
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    add rdi, rax
    mov [rdi + 20], ebx
    pop rax
    mov rax, [rel node_count]
    dec rax
    mov r12d, eax
    jmp expr_pa_loop
expr_pa_done:
    mov eax, r12d
    pop r12
    pop rbx
    ret

; Level 3: == != < > <= >= (non-chainable — parse at most one operator)
expr_parse_cmp:
    push rbx
    push r12
    push r13
    call expr_parse_add
    mov r12d, eax
    ; Check for comparison operator
    call par_peek_type
    cmp eax, TOK_EQ
    je expr_pc_op
    cmp eax, TOK_NEQ
    je expr_pc_op
    cmp eax, TOK_LT
    je expr_pc_op
    cmp eax, TOK_GT
    je expr_pc_op
    cmp eax, TOK_LTE
    je expr_pc_op
    cmp eax, TOK_GTE
    je expr_pc_op
    ; No comparison — return left
    mov eax, r12d
    pop r13
    pop r12
    pop rbx
    ret
expr_pc_op:
    ; Map token to BINOP sub_type
    mov r13d, eax                   ; save token type
    inc qword [rel tok_pos]
    ; Convert token type to binop sub_type
    sub r13d, TOK_EQ                ; TOK_EQ=29, BINOP_EQ=5
    add r13d, BINOP_EQ              ; offset: 29-29+5 = 5
    ; Parse right operand
    push r12
    call expr_parse_add
    mov ebx, eax
    pop r12
    ; Create BINOP node
    call par_alloc_node
    mov byte [rax], NODE_BINOP
    mov byte [rax + 1], r13b
    mov [rax + 16], r12d
    mov dword [rax + 12], 2
    mov dword [rax + 24], TYPE_BOOL
    mov dword [rax + 20], NO_CHILD
    ; Link left.next_sibling = right
    push rax
    mov eax, r12d
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    add rdi, rax
    mov [rdi + 20], ebx
    pop rax
    mov rax, [rel node_count]
    dec rax
    pop r13
    pop r12
    pop rbx
    ret

; Level 4: + -
expr_parse_add:
    push rbx
    push r12
    push r13
    call expr_parse_mul
    mov r12d, eax
expr_padd_loop:
    call par_peek_type
    cmp eax, TOK_PLUS
    je expr_padd_op
    cmp eax, TOK_MINUS
    je expr_padd_op
    jmp expr_padd_done
expr_padd_op:
    mov r13d, eax                   ; save operator token
    inc qword [rel tok_pos]
    push r12
    call expr_parse_mul
    mov ebx, eax
    pop r12
    ; Determine sub_type
    xor ecx, ecx
    cmp r13d, TOK_PLUS
    je expr_padd_is_add
    mov cl, BINOP_SUB
    jmp expr_padd_mk
expr_padd_is_add:
    mov cl, BINOP_ADD
expr_padd_mk:
    ; Create BINOP node
    call par_alloc_node
    mov byte [rax], NODE_BINOP
    mov byte [rax + 1], cl
    mov [rax + 16], r12d
    mov dword [rax + 12], 2
    mov dword [rax + 24], TYPE_INT  ; default; string dispatch set later
    mov dword [rax + 20], NO_CHILD
    ; Check if this is string + : if left is STR_LIT, set type_info=STRING
    cmp cl, BINOP_ADD
    jne expr_padd_not_str
    push rax                        ; save binop pointer
    mov eax, r12d                   ; left child index
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    movzx ecx, byte [rdi + rax]    ; left node_type
    cmp cl, NODE_STR_LIT
    je expr_padd_set_str
    ; Also check right
    mov eax, ebx
    imul eax, NODE_SIZE
    movzx ecx, byte [rdi + rax]
    cmp cl, NODE_STR_LIT
    je expr_padd_set_str
    pop rax
    jmp expr_padd_not_str
expr_padd_set_str:
    pop rax
    mov dword [rax + 24], TYPE_STRING
expr_padd_not_str:
    ; Link siblings
    push rax
    mov eax, r12d
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    add rdi, rax
    mov [rdi + 20], ebx
    pop rax
    mov rax, [rel node_count]
    dec rax
    mov r12d, eax
    jmp expr_padd_loop
expr_padd_done:
    mov eax, r12d
    pop r13
    pop r12
    pop rbx
    ret

; Level 5: * / %
expr_parse_mul:
    push rbx
    push r12
    push r13
    call expr_parse_unary
    mov r12d, eax
expr_pm_loop:
    call par_peek_type
    cmp eax, TOK_STAR
    je expr_pm_op
    cmp eax, TOK_SLASH
    je expr_pm_op
    cmp eax, TOK_PERCENT
    je expr_pm_op
    jmp expr_pm_done
expr_pm_op:
    mov r13d, eax
    inc qword [rel tok_pos]
    push r12
    call expr_parse_unary
    mov ebx, eax
    pop r12
    ; Map token to sub_type: STAR=26→MUL=2, SLASH=27→DIV=3, PERCENT=28→MOD=4
    mov ecx, r13d
    sub ecx, TOK_STAR
    add ecx, BINOP_MUL
    ; Create BINOP
    call par_alloc_node
    mov byte [rax], NODE_BINOP
    mov byte [rax + 1], cl
    mov [rax + 16], r12d
    mov dword [rax + 12], 2
    mov dword [rax + 24], TYPE_INT
    mov dword [rax + 20], NO_CHILD
    ; Link
    push rax
    mov eax, r12d
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    add rdi, rax
    mov [rdi + 20], ebx
    pop rax
    mov rax, [rel node_count]
    dec rax
    mov r12d, eax
    jmp expr_pm_loop
expr_pm_done:
    mov eax, r12d
    pop r13
    pop r12
    pop rbx
    ret

; Level 6-7: unary ! - do
expr_parse_unary:
    call par_peek_type
    cmp eax, TOK_NOT
    je expr_pu_not
    cmp eax, TOK_MINUS
    je expr_pu_neg
    cmp eax, TOK_KW_DO
    je expr_pu_do
    jmp expr_parse_postfix

expr_pu_not:
    push rbx
    inc qword [rel tok_pos]
    call expr_parse_unary           ; recursive for chained !
    mov ebx, eax                    ; child index
    call par_alloc_node
    mov byte [rax], NODE_UNARY_NOT
    mov [rax + 16], ebx
    mov dword [rax + 12], 1
    mov dword [rax + 20], NO_CHILD
    mov dword [rax + 24], TYPE_BOOL
    mov rax, [rel node_count]
    dec rax
    pop rbx
    ret

expr_pu_neg:
    push rbx
    inc qword [rel tok_pos]
    call expr_parse_unary
    mov ebx, eax
    call par_alloc_node
    mov byte [rax], NODE_UNARY_NEG
    mov [rax + 16], ebx
    mov dword [rax + 12], 1
    mov dword [rax + 20], NO_CHILD
    mov dword [rax + 24], TYPE_INT
    mov rax, [rel node_count]
    dec rax
    pop rbx
    ret

expr_pu_do:
    push rbx
    inc qword [rel tok_pos]
    call expr_parse_postfix         ; do applies to call, not recursive unary
    mov ebx, eax
    call par_alloc_node
    mov byte [rax], NODE_DO_EXPR
    mov [rax + 16], ebx
    mov dword [rax + 12], 1
    mov dword [rax + 20], NO_CHILD
    mov rax, [rel node_count]
    dec rax
    pop rbx
    ret

; Level 8: postfix — f() arr[i]
expr_parse_postfix:
    push rbx
    push r12
    call expr_parse_primary
    mov r12d, eax                   ; r12 = current node index
expr_ppf_loop:
    call par_peek_type
    cmp eax, TOK_LPAREN
    je expr_ppf_call
    cmp eax, TOK_LBRACKET
    je expr_ppf_index
    jmp expr_ppf_done

expr_ppf_call:
    ; This is actually handled in primary (IDENT followed by LPAREN)
    ; If we get here, it means a non-ident was followed by (
    ; which is not valid in Loon-0. Just stop.
    jmp expr_ppf_done

expr_ppf_index:
    ; arr[i] — array index read
    inc qword [rel tok_pos]         ; consume LBRACKET
    push r12
    call expr_parse                 ; index expression
    mov ebx, eax
    pop r12
    ; Expect RBRACKET
    call par_peek_type
    cmp eax, TOK_RBRACKET
    jne par_die_expect_rbracket
    inc qword [rel tok_pos]
    ; Create ARRAY_GET node
    ; Copy name from r12 (the IDENT_REF node)
    mov eax, r12d
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    add rdi, rax
    mov ecx, [rdi + 4]             ; string_ref from ident
    mov edx, [rdi + 8]             ; string_len

    call par_alloc_node
    mov byte [rax], NODE_ARRAY_GET
    mov [rax + 4], ecx
    mov [rax + 8], edx
    mov [rax + 16], ebx             ; first_child = index expr
    mov dword [rax + 12], 1
    mov dword [rax + 20], NO_CHILD
    mov dword [rax + 24], TYPE_INT  ; array elements are Int
    mov rax, [rel node_count]
    dec rax
    mov r12d, eax
    jmp expr_ppf_loop

expr_ppf_done:
    mov eax, r12d
    pop r12
    pop rbx
    ret

; ============================================================
; expr_parse_primary — literals, identifiers, calls, parens, blocks
; Returns: eax = node index
; ============================================================
expr_parse_primary:
    push rbx
    push r12

    call par_peek_type

    cmp eax, TOK_LIT_INT
    je expr_pp_int
    cmp eax, TOK_LIT_STRING
    je expr_pp_string
    cmp eax, TOK_KW_TRUE
    je expr_pp_true
    cmp eax, TOK_KW_FALSE
    je expr_pp_false
    cmp eax, TOK_IDENT
    je expr_pp_ident
    cmp eax, TOK_LPAREN
    je expr_pp_paren
    cmp eax, TOK_LBRACE
    je expr_pp_block

    ; Unknown — error
    jmp expr_die_expect_expr

expr_pp_int:
    call par_alloc_node
    mov byte [rax], NODE_INT_LIT
    mov dword [rax + 24], TYPE_INT
    mov dword [rax + 16], NO_CHILD
    mov dword [rax + 20], NO_CHILD
    call par_current_token_ptr
    mov ecx, [rax + 4]             ; string_offset
    mov edx, [rax + 8]             ; string_length
    ; Store string ref for codegen to parse
    mov rax, [rel node_count]
    dec rax
    imul rax, NODE_SIZE
    lea rdi, [rel nodes]
    add rdi, rax
    mov [rdi + 4], ecx
    mov [rdi + 8], edx
    ; Parse integer value into extra (if fits in 32 bits)
    push rdi
    lea rsi, [rel strings]
    add rsi, rcx                    ; rsi = digit string
    xor eax, eax
    xor ecx, ecx
expr_pp_int_parse:
    cmp ecx, edx
    jge expr_pp_int_done
    imul rax, 10
    movzx ebx, byte [rsi + rcx]
    sub ebx, '0'
    add rax, rbx
    inc ecx
    jmp expr_pp_int_parse
expr_pp_int_done:
    pop rdi
    ; Check if fits in 32 bits
    cmp rax, 0x7FFFFFFF
    ja expr_pp_int_big
    mov [rdi + 28], eax             ; extra = parsed value
    jmp expr_pp_int_ret
expr_pp_int_big:
    mov dword [rdi + 28], 0xFFFFFFFF ; sentinel: too big, use string_ref
expr_pp_int_ret:
    inc qword [rel tok_pos]
    mov rax, [rel node_count]
    dec rax
    pop r12
    pop rbx
    ret

expr_pp_string:
    call par_alloc_node
    mov byte [rax], NODE_STR_LIT
    mov dword [rax + 24], TYPE_STRING
    mov dword [rax + 16], NO_CHILD
    mov dword [rax + 20], NO_CHILD
    mov rbx, rax                    ; save node ptr
    call par_current_token_ptr
    mov ecx, [rax + 4]
    mov edx, [rax + 8]
    mov [rbx + 4], ecx
    mov [rbx + 8], edx
    inc qword [rel tok_pos]
    mov rax, [rel node_count]
    dec rax
    pop r12
    pop rbx
    ret

expr_pp_true:
    call par_alloc_node
    mov byte [rax], NODE_BOOL_LIT
    mov dword [rax + 24], TYPE_BOOL
    mov dword [rax + 28], 1         ; extra = 1 (true)
    mov dword [rax + 16], NO_CHILD
    mov dword [rax + 20], NO_CHILD
    inc qword [rel tok_pos]
    mov rax, [rel node_count]
    dec rax
    pop r12
    pop rbx
    ret

expr_pp_false:
    call par_alloc_node
    mov byte [rax], NODE_BOOL_LIT
    mov dword [rax + 24], TYPE_BOOL
    mov dword [rax + 28], 0         ; extra = 0 (false)
    mov dword [rax + 16], NO_CHILD
    mov dword [rax + 20], NO_CHILD
    inc qword [rel tok_pos]
    mov rax, [rel node_count]
    dec rax
    pop r12
    pop rbx
    ret

expr_pp_ident:
    ; Could be: variable reference, function call, or Array(n)
    call par_current_token_ptr
    mov ecx, [rax + 4]             ; name offset
    mov edx, [rax + 8]             ; name length

    ; Check for Array(n) special syntax
    cmp edx, 5
    jne expr_pp_ident_not_array
    lea rsi, [rel strings]
    add rsi, rcx
    cmp byte [rsi], 'A'
    jne expr_pp_ident_not_array
    cmp byte [rsi+1], 'r'
    jne expr_pp_ident_not_array
    cmp byte [rsi+2], 'r'
    jne expr_pp_ident_not_array
    cmp byte [rsi+3], 'a'
    jne expr_pp_ident_not_array
    cmp byte [rsi+4], 'y'
    jne expr_pp_ident_not_array
    ; Check if followed by LPAREN
    mov rax, [rel tok_pos]
    inc rax
    cmp rax, [rel tok_count]
    jge expr_pp_ident_not_array
    imul rax, TOKEN_SIZE
    lea rsi, [rel tokens]
    movzx eax, byte [rsi + rax]
    cmp eax, TOK_LPAREN
    jne expr_pp_ident_not_array
    ; It's Array(n)
    jmp expr_pp_array_new

expr_pp_ident_not_array:
    ; Check if followed by LPAREN (function call)
    mov rax, [rel tok_pos]
    inc rax
    cmp rax, [rel tok_count]
    jge expr_pp_ident_var
    imul rax, TOKEN_SIZE
    lea rsi, [rel tokens]
    movzx eax, byte [rsi + rax]
    cmp eax, TOK_LPAREN
    je expr_pp_call

expr_pp_ident_var:
    ; Simple variable reference
    call par_alloc_node
    mov byte [rax], NODE_IDENT_REF
    mov dword [rax + 16], NO_CHILD
    mov dword [rax + 20], NO_CHILD
    mov dword [rax + 24], TYPE_UNKNOWN
    mov rbx, rax
    call par_current_token_ptr
    mov ecx, [rax + 4]
    mov edx, [rax + 8]
    mov [rbx + 4], ecx
    mov [rbx + 8], edx
    inc qword [rel tok_pos]
    mov rax, [rel node_count]
    dec rax
    pop r12
    pop rbx
    ret

expr_pp_call:
    ; Function call: IDENT LPAREN args RPAREN
    push r13
    push r14
    push r15
    call par_alloc_node
    mov r12, rax                    ; r12 = call node pointer
    mov byte [r12], NODE_CALL
    mov dword [r12 + 20], NO_CHILD
    ; Copy function name
    call par_current_token_ptr
    mov ecx, [rax + 4]
    mov edx, [rax + 8]
    mov [r12 + 4], ecx
    mov [r12 + 8], edx
    ; Get node index
    mov rax, [rel node_count]
    dec rax
    mov r13d, eax                   ; r13 = call node index

    ; Check if it's a builtin
    mov edi, ecx
    mov esi, edx
    call expr_lookup_builtin        ; rax = builtin id
    mov byte [r12 + 1], al          ; sub_type = builtin id

    inc qword [rel tok_pos]         ; consume IDENT
    inc qword [rel tok_pos]         ; consume LPAREN

    ; Parse arguments
    xor r14d, r14d                  ; arg count
    mov r15d, NO_CHILD              ; last arg index
    mov dword [r12 + 16], NO_CHILD  ; first_child

expr_pp_call_args:
    call par_peek_type
    cmp eax, TOK_RPAREN
    je expr_pp_call_done

    ; Parse one argument expression
    call expr_parse
    mov ebx, eax                    ; ebx = arg node index

    ; Link into chain
    cmp r14d, 0
    jne expr_pp_call_link
    ; First arg
    mov [r12 + 16], ebx             ; first_child
    mov r15d, ebx
    jmp expr_pp_call_arg_linked
expr_pp_call_link:
    ; Set prev arg's next_sibling
    mov eax, r15d
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    add rdi, rax
    mov [rdi + 20], ebx
    mov r15d, ebx
expr_pp_call_arg_linked:
    inc r14d

    ; Check for comma
    call par_peek_type
    cmp eax, TOK_COMMA
    jne expr_pp_call_args
    inc qword [rel tok_pos]         ; consume comma
    jmp expr_pp_call_args

expr_pp_call_done:
    inc qword [rel tok_pos]         ; consume RPAREN
    mov [r12 + 12], r14d            ; child_count = arg count

    mov eax, r13d
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

expr_pp_array_new:
    ; Array(n) — special syntax
    inc qword [rel tok_pos]         ; consume "Array" IDENT
    inc qword [rel tok_pos]         ; consume LPAREN
    call expr_parse                 ; size expression
    mov ebx, eax
    ; Expect RPAREN
    call par_peek_type
    cmp eax, TOK_RPAREN
    jne expr_die_expect_rparen
    inc qword [rel tok_pos]
    ; Create ARRAY_NEW node
    call par_alloc_node
    mov byte [rax], NODE_ARRAY_NEW
    mov [rax + 16], ebx             ; first_child = size expr
    mov dword [rax + 12], 1
    mov dword [rax + 20], NO_CHILD
    mov dword [rax + 24], TYPE_ARRAY
    mov rax, [rel node_count]
    dec rax
    pop r12
    pop rbx
    ret

expr_pp_paren:
    ; ( expr )
    inc qword [rel tok_pos]         ; consume LPAREN
    call expr_parse
    mov ebx, eax
    call par_peek_type
    cmp eax, TOK_RPAREN
    jne expr_die_expect_rparen
    inc qword [rel tok_pos]
    mov eax, ebx                    ; return the inner expr node
    pop r12
    pop rbx
    ret

expr_pp_block:
    call expr_parse_block           ; parse { ... }
    pop r12
    pop rbx
    ret

; ============================================================
; expr_parse_match — parse match expr { arms }
; Returns: eax = MATCH node index
; ============================================================
expr_parse_match:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    inc qword [rel tok_pos]         ; consume KW_MATCH

    ; Parse discriminant expression
    call expr_parse
    mov r14d, eax                   ; r14 = discriminant node index

    ; Allocate MATCH node
    call par_alloc_node
    mov r12, rax                    ; r12 = match node pointer
    mov byte [r12], NODE_MATCH
    mov [r12 + 28], r14d            ; extra = discriminant index
    mov dword [r12 + 20], NO_CHILD
    mov rax, [rel node_count]
    dec rax
    mov r13d, eax                   ; r13 = match node index

    ; Expect LBRACE
    call par_peek_type
    cmp eax, TOK_LBRACE
    jne par_die_expect_lbrace
    inc qword [rel tok_pos]

    ; Parse arms
    xor r14d, r14d                  ; arm count
    mov r15d, NO_CHILD              ; last arm index
    mov dword [r12 + 16], NO_CHILD  ; first_child

expr_pm_arms:
    call par_peek_type
    cmp eax, TOK_RBRACE
    je expr_pm_arms_done
    cmp eax, TOK_EOF
    je expr_pm_arms_done

    ; Parse one arm: pattern -> expr
    call par_alloc_node
    mov rbx, rax                    ; rbx = arm node pointer
    mov byte [rbx], NODE_MATCH_ARM
    mov dword [rbx + 20], NO_CHILD
    mov byte [rbx + 1], 0           ; sub_type = 0 (literal, not wildcard)

    ; Parse pattern
    call par_peek_type
    cmp eax, TOK_KW_TRUE
    je expr_pm_pat_true
    cmp eax, TOK_KW_FALSE
    je expr_pm_pat_false
    cmp eax, TOK_LIT_INT
    je expr_pm_pat_int
    cmp eax, TOK_IDENT
    je expr_pm_pat_wildcard
    jmp par_die_expect_ident        ; unexpected pattern

expr_pm_pat_true:
    mov dword [rbx + 28], 1
    inc qword [rel tok_pos]
    jmp expr_pm_pat_done

expr_pm_pat_false:
    mov dword [rbx + 28], 0
    inc qword [rel tok_pos]
    jmp expr_pm_pat_done

expr_pm_pat_int:
    ; Parse integer value
    call par_current_token_ptr
    mov ecx, [rax + 4]
    mov edx, [rax + 8]
    lea rsi, [rel strings]
    add rsi, rcx
    xor eax, eax
    xor ecx, ecx
expr_pm_pat_int_parse:
    cmp ecx, edx
    jge expr_pm_pat_int_done2
    imul eax, 10
    movzx edi, byte [rsi + rcx]
    sub edi, '0'
    add eax, edi
    inc ecx
    jmp expr_pm_pat_int_parse
expr_pm_pat_int_done2:
    mov [rbx + 28], eax
    inc qword [rel tok_pos]
    jmp expr_pm_pat_done

expr_pm_pat_wildcard:
    ; Check if it's actually "_"
    call par_current_token_ptr
    mov ecx, [rax + 8]             ; length
    cmp ecx, 1
    jne par_die_expect_ident        ; not a valid pattern
    mov ecx, [rax + 4]             ; offset
    lea rsi, [rel strings]
    cmp byte [rsi + rcx], '_'
    jne par_die_expect_ident
    mov byte [rbx + 1], 1          ; sub_type = 1 (wildcard)
    mov dword [rbx + 28], 0
    inc qword [rel tok_pos]

expr_pm_pat_done:
    ; Expect ARROW
    call par_peek_type
    cmp eax, TOK_ARROW
    jne par_die_expect_arrow
    inc qword [rel tok_pos]

    ; Parse arm body expression
    call expr_parse
    mov [rbx + 16], eax             ; first_child = body expr
    mov dword [rbx + 12], 1

    ; Get arm node index
    mov rax, [rel node_count]
    dec rax
    ; Wait — the arm node was allocated before the body. Need to compute correctly.
    ; The arm was allocated at some point, body expr allocated after.
    ; The arm index = node_count at time of arm allocation - 1
    ; We need to track it. Let me use the rbx pointer to derive it.
    mov rax, rbx
    lea rdi, [rel nodes]
    sub rax, rdi
    xor edx, edx
    mov ecx, NODE_SIZE
    div ecx                         ; rax = arm node index
    mov ecx, eax                    ; ecx = arm node index

    ; Link into arm chain
    cmp r14d, 0
    jne expr_pm_link_arm
    mov [r12 + 16], ecx             ; first_child of MATCH
    mov r15d, ecx
    jmp expr_pm_arm_linked
expr_pm_link_arm:
    push rcx
    mov eax, r15d
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    add rdi, rax
    pop rcx
    mov [rdi + 20], ecx
    mov r15d, ecx
expr_pm_arm_linked:
    inc r14d

    ; Optional comma
    call par_peek_type
    cmp eax, TOK_COMMA
    jne expr_pm_arms
    inc qword [rel tok_pos]
    jmp expr_pm_arms

expr_pm_arms_done:
    inc qword [rel tok_pos]         ; consume RBRACE
    mov [r12 + 12], r14d            ; child_count = arm count

    mov eax, r13d                   ; return match node index

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ============================================================
; expr_parse_for — parse for IDENT in range(expr, expr) block
; Returns: eax = FOR node index
; ============================================================
expr_parse_for:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    inc qword [rel tok_pos]         ; consume KW_FOR

    ; Allocate FOR node
    call par_alloc_node
    mov r12, rax
    mov byte [r12], NODE_FOR
    mov dword [r12 + 20], NO_CHILD
    mov rax, [rel node_count]
    dec rax
    mov r13d, eax                   ; r13 = for node index

    ; Expect loop variable IDENT
    call par_peek_type
    cmp eax, TOK_IDENT
    jne par_die_expect_ident
    call par_current_token_ptr
    mov ecx, [rax + 4]
    mov edx, [rax + 8]
    mov [r12 + 4], ecx
    mov [r12 + 8], edx
    inc qword [rel tok_pos]

    ; Expect KW_IN
    call par_peek_type
    cmp eax, TOK_KW_IN
    jne par_die_expect_ident        ; reuse
    inc qword [rel tok_pos]

    ; Expect "range" identifier
    call par_peek_type
    cmp eax, TOK_IDENT
    jne par_die_expect_ident
    ; Verify it's "range" (5 chars)
    call par_current_token_ptr
    mov ecx, [rax + 8]             ; length
    cmp ecx, 5
    jne par_die_expect_ident
    mov ecx, [rax + 4]             ; offset
    lea rsi, [rel strings]
    add rsi, rcx
    cmp byte [rsi], 'r'
    jne par_die_expect_ident
    cmp byte [rsi+1], 'a'
    jne par_die_expect_ident
    cmp byte [rsi+2], 'n'
    jne par_die_expect_ident
    cmp byte [rsi+3], 'g'
    jne par_die_expect_ident
    cmp byte [rsi+4], 'e'
    jne par_die_expect_ident
    inc qword [rel tok_pos]

    ; Expect LPAREN
    call par_peek_type
    cmp eax, TOK_LPAREN
    jne par_die_expect_lparen
    inc qword [rel tok_pos]

    ; Parse start expression
    call expr_parse
    mov [r12 + 16], eax             ; first_child = start expr
    mov ebx, eax                    ; save start node index

    ; Expect COMMA
    call par_peek_type
    cmp eax, TOK_COMMA
    jne par_die_expect_semi         ; reuse
    inc qword [rel tok_pos]

    ; Parse end expression
    call expr_parse
    ; Link start.next_sibling = end
    push rax                        ; save end index
    mov eax, ebx
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    add rdi, rax
    pop rax
    mov [rdi + 20], eax
    mov ebx, eax                    ; ebx = end node index

    ; Expect RPAREN
    call par_peek_type
    cmp eax, TOK_RPAREN
    jne par_die_expect_rparen
    inc qword [rel tok_pos]

    ; Parse body block
    call par_peek_type
    cmp eax, TOK_LBRACE
    jne par_die_expect_lbrace
    call expr_parse_block
    ; Link end.next_sibling = body block
    push rax
    mov eax, ebx
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    add rdi, rax
    pop rax
    mov [rdi + 20], eax

    mov dword [r12 + 12], 3         ; child_count = 3 (start, end, body)
    mov dword [r12 + 24], TYPE_UNIT ; for evaluates to Unit

    mov eax, r13d                   ; return for node index

    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ============================================================
; expr_lookup_builtin — check if function name is a builtin
; Input: edi = string_offset, esi = string_length
; Output: eax = builtin id (0 = not a builtin)
; ============================================================
expr_lookup_builtin:
    push rbx
    push rcx
    push rdx
    push r8

    ; Get pointer to name in string table
    lea rbx, [rel strings]
    mov edi, edi                    ; zero-extend 32→64
    add rbx, rdi                    ; rbx = name pointer
    mov esi, esi                    ; zero-extend 32→64

    lea r8, [rel expr_builtin_table]
expr_lb_loop:
    lea rax, [rel expr_builtin_table_end]
    cmp r8, rax
    jge expr_lb_not_found

    mov rdx, [r8 + 8]              ; entry length
    cmp rsi, rdx
    jne expr_lb_next

    ; Compare bytes
    mov rdx, [r8]                   ; entry name pointer
    xor ecx, ecx
expr_lb_cmp:
    cmp rcx, rsi
    jge expr_lb_found
    movzx eax, byte [rbx + rcx]
    cmp al, byte [rdx + rcx]
    jne expr_lb_next
    inc ecx
    jmp expr_lb_cmp

expr_lb_found:
    mov rax, [r8 + 16]             ; builtin id
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

expr_lb_next:
    add r8, BUILTIN_ENTRY_SIZE
    jmp expr_lb_loop

expr_lb_not_found:
    xor eax, eax                    ; BUILTIN_NONE
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================
; Error handlers
; ============================================================
expr_die_expect_expr:
    mov rdi, STDERR
    lea rsi, [rel expr_err_expect_expr]
    mov rdx, expr_err_expect_expr_len
    mov rax, SYS_WRITE
    syscall
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall

expr_die_expect_rparen:
    mov rdi, STDERR
    lea rsi, [rel expr_err_expect_rparen]
    mov rdx, expr_err_expect_rparen_len
    mov rax, SYS_WRITE
    syscall
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall
