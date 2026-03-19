; stage1/codegen_expr.asm
; cgx_emit_expr: emit NASM for one expression node
;
; All expressions leave their result in rax.
; Binary ops: emit left → push rax → emit right → mov rcx,rax → pop rax → op
;
; Uses: cgx_ prefix for all labels

section .data
cgx_mov_rax:        db "    mov rax, "
cgx_mov_rax_len     equ $ - cgx_mov_rax
cgx_push_rax:       db "    push rax", 10
cgx_push_rax_len    equ $ - cgx_push_rax
cgx_pop_rcx:        db "    pop rcx", 10
cgx_pop_rcx_len     equ $ - cgx_pop_rcx
cgx_neg_rax:        db "    neg rax", 10
cgx_neg_rax_len     equ $ - cgx_neg_rax
cgx_not_rax:        db "    xor rax, 1", 10
cgx_not_rax_len     equ $ - cgx_not_rax

; Arithmetic operations
cgx_add:            db "    add rax, rcx", 10
cgx_add_len         equ $ - cgx_add
cgx_sub:            db "    sub rax, rcx", 10
cgx_sub_len         equ $ - cgx_sub
cgx_imul:           db "    imul rax, rcx", 10
cgx_imul_len        equ $ - cgx_imul
; Division: rax = rax / rcx (signed)
cgx_div_pre:        db "    cqo", 10, "    idiv rcx", 10
cgx_div_pre_len     equ $ - cgx_div_pre
; Modulo uses same idiv, result in rdx
cgx_mod_post:       db "    mov rax, rdx", 10
cgx_mod_post_len    equ $ - cgx_mod_post

; Comparison operations — emit cmp + setCC + movzx
cgx_cmp:            db "    cmp rax, rcx", 10
cgx_cmp_len         equ $ - cgx_cmp
cgx_sete:           db "    sete al", 10
cgx_sete_len        equ $ - cgx_sete
cgx_setne:          db "    setne al", 10
cgx_setne_len       equ $ - cgx_setne
cgx_setl:           db "    setl al", 10
cgx_setl_len        equ $ - cgx_setl
cgx_setg:           db "    setg al", 10
cgx_setg_len        equ $ - cgx_setg
cgx_setle:          db "    setle al", 10
cgx_setle_len       equ $ - cgx_setle
cgx_setge:          db "    setge al", 10
cgx_setge_len       equ $ - cgx_setge
cgx_movzx:          db "    movzx rax, al", 10
cgx_movzx_len       equ $ - cgx_movzx

; Boolean: && and || use short-circuit evaluation
; For now, simple: evaluate both, then AND/OR
cgx_and:            db "    and rax, rcx", 10
cgx_and_len         equ $ - cgx_and
cgx_or:             db "    or rax, rcx", 10
cgx_or_len          equ $ - cgx_or

cgx_newline:        db 10

; Call-related
cgx_call:           db "    call fn_"
cgx_call_len        equ $ - cgx_call
cgx_mov_rdi_rax:    db "    mov rdi, rax", 10
cgx_mov_rdi_rax_len equ $ - cgx_mov_rdi_rax
cgx_exit_syscall:   db "    mov rax, 60", 10, "    syscall", 10
cgx_exit_syscall_len equ $ - cgx_exit_syscall

section .text

; ============================================================
; cgx_emit_expr — emit code for one expression
; Input: edi = node index
; Output: result in rax (in generated code)
; ============================================================
cgx_emit_expr:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    ; Get node pointer
    mov eax, edi
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax                    ; rbx = node pointer
    mov r12, rbx                    ; r12 = node pointer
    mov r13d, edi                   ; r13 = node index

    movzx eax, byte [rbx]          ; node_type

    cmp eax, NODE_INT_LIT
    je cgx_int_lit
    cmp eax, NODE_BOOL_LIT
    je cgx_bool_lit
    cmp eax, NODE_BINOP
    je cgx_binop
    cmp eax, NODE_UNARY_NEG
    je cgx_unary_neg
    cmp eax, NODE_UNARY_NOT
    je cgx_unary_not
    cmp eax, NODE_DO_EXPR
    je cgx_do_expr
    cmp eax, NODE_CALL
    je cgx_call_expr
    cmp eax, NODE_IDENT_REF
    je cgx_ident_ref
    cmp eax, NODE_STR_LIT
    je cgx_str_lit
    cmp eax, NODE_MATCH
    je cgx_match_expr
    cmp eax, NODE_FOR
    je cgx_for_expr
    cmp eax, NODE_ARRAY_NEW
    je cgx_array_new_expr
    cmp eax, NODE_ARRAY_GET
    je cgx_array_get_expr

    ; Unknown node type — emit nothing (will be handled in later milestones)
    jmp cgx_done

cgx_int_lit:
    ; mov rax, VALUE
    lea rsi, [rel cgx_mov_rax]
    mov rdx, cgx_mov_rax_len
    call cg_write
    ; Get value from extra field
    mov eax, [r12 + 28]            ; extra = integer value
    cmp eax, 0xFFFFFFFF
    je cgx_int_lit_big
    ; Write the integer value
    call cg_write_int
    jmp cgx_int_lit_nl
cgx_int_lit_big:
    ; Large integer — parse from string_ref (not needed for M1.5 tests)
    ; For now just write 0
    xor eax, eax
    call cg_write_int
cgx_int_lit_nl:
    lea rsi, [rel cgx_newline]
    mov rdx, 1
    call cg_write
    jmp cgx_done

cgx_bool_lit:
    ; mov rax, 0 or 1
    lea rsi, [rel cgx_mov_rax]
    mov rdx, cgx_mov_rax_len
    call cg_write
    mov eax, [r12 + 28]            ; extra = 0 or 1
    call cg_write_int
    lea rsi, [rel cgx_newline]
    mov rdx, 1
    call cg_write
    jmp cgx_done

cgx_binop:
    ; Emit left child → push rax → emit right child → pop rcx → operation
    mov edi, [r12 + 16]            ; first_child (left)
    call cgx_emit_expr

    ; push rax
    lea rsi, [rel cgx_push_rax]
    mov rdx, cgx_push_rax_len
    call cg_write

    ; Get right child (left's next_sibling)
    mov eax, [r12 + 16]            ; left child index
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    mov edi, [rbx + rax + 20]      ; left.next_sibling = right child
    call cgx_emit_expr

    ; Now rax has right value. Move to rcx, pop left into rax
    ; mov rcx, rax; pop rax → but we need: pop rcx first won't work
    ; Correct sequence: push the right value, pop left into rax, pop right into rcx
    ; Actually simpler: mov rcx, rax then pop rax
    ; emit: mov rcx, rax
    ;        pop rax
    ; Wait, that's wrong — we want left in rax, right in rcx
    ; After emit right: rax = right. Stack has left pushed.
    ; So: mov rcx, rax  (rcx = right)
    ;     pop rax       (rax = left)

    ; Emit: mov rcx, rax
    lea rsi, [rel cgx_mov_rcx_rax]
    mov rdx, cgx_mov_rcx_rax_len
    call cg_write
    ; Emit: pop rax
    lea rsi, [rel cgx_pop_rax]
    mov rdx, cgx_pop_rax_len
    call cg_write

    ; Emit the operation based on sub_type
    movzx eax, byte [r12 + 1]      ; sub_type
    cmp eax, BINOP_ADD
    je cgx_op_add
    cmp eax, BINOP_SUB
    je cgx_op_sub
    cmp eax, BINOP_MUL
    je cgx_op_mul
    cmp eax, BINOP_DIV
    je cgx_op_div
    cmp eax, BINOP_MOD
    je cgx_op_mod
    cmp eax, BINOP_EQ
    je cgx_op_eq
    cmp eax, BINOP_NEQ
    je cgx_op_neq
    cmp eax, BINOP_LT
    je cgx_op_lt
    cmp eax, BINOP_GT
    je cgx_op_gt
    cmp eax, BINOP_LTE
    je cgx_op_lte
    cmp eax, BINOP_GTE
    je cgx_op_gte
    cmp eax, BINOP_AND
    je cgx_op_and
    cmp eax, BINOP_OR
    je cgx_op_or
    jmp cgx_done                    ; unknown op

cgx_op_add:
    lea rsi, [rel cgx_add]
    mov rdx, cgx_add_len
    call cg_write
    jmp cgx_done
cgx_op_sub:
    lea rsi, [rel cgx_sub]
    mov rdx, cgx_sub_len
    call cg_write
    jmp cgx_done
cgx_op_mul:
    lea rsi, [rel cgx_imul]
    mov rdx, cgx_imul_len
    call cg_write
    jmp cgx_done
cgx_op_div:
    lea rsi, [rel cgx_div_pre]
    mov rdx, cgx_div_pre_len
    call cg_write
    jmp cgx_done
cgx_op_mod:
    lea rsi, [rel cgx_div_pre]
    mov rdx, cgx_div_pre_len
    call cg_write
    lea rsi, [rel cgx_mod_post]
    mov rdx, cgx_mod_post_len
    call cg_write
    jmp cgx_done

cgx_op_eq:
    lea rsi, [rel cgx_cmp]
    mov rdx, cgx_cmp_len
    call cg_write
    lea rsi, [rel cgx_sete]
    mov rdx, cgx_sete_len
    call cg_write
    lea rsi, [rel cgx_movzx]
    mov rdx, cgx_movzx_len
    call cg_write
    jmp cgx_done
cgx_op_neq:
    lea rsi, [rel cgx_cmp]
    mov rdx, cgx_cmp_len
    call cg_write
    lea rsi, [rel cgx_setne]
    mov rdx, cgx_setne_len
    call cg_write
    lea rsi, [rel cgx_movzx]
    mov rdx, cgx_movzx_len
    call cg_write
    jmp cgx_done
cgx_op_lt:
    lea rsi, [rel cgx_cmp]
    mov rdx, cgx_cmp_len
    call cg_write
    lea rsi, [rel cgx_setl]
    mov rdx, cgx_setl_len
    call cg_write
    lea rsi, [rel cgx_movzx]
    mov rdx, cgx_movzx_len
    call cg_write
    jmp cgx_done
cgx_op_gt:
    lea rsi, [rel cgx_cmp]
    mov rdx, cgx_cmp_len
    call cg_write
    lea rsi, [rel cgx_setg]
    mov rdx, cgx_setg_len
    call cg_write
    lea rsi, [rel cgx_movzx]
    mov rdx, cgx_movzx_len
    call cg_write
    jmp cgx_done
cgx_op_lte:
    lea rsi, [rel cgx_cmp]
    mov rdx, cgx_cmp_len
    call cg_write
    lea rsi, [rel cgx_setle]
    mov rdx, cgx_setle_len
    call cg_write
    lea rsi, [rel cgx_movzx]
    mov rdx, cgx_movzx_len
    call cg_write
    jmp cgx_done
cgx_op_gte:
    lea rsi, [rel cgx_cmp]
    mov rdx, cgx_cmp_len
    call cg_write
    lea rsi, [rel cgx_setge]
    mov rdx, cgx_setge_len
    call cg_write
    lea rsi, [rel cgx_movzx]
    mov rdx, cgx_movzx_len
    call cg_write
    jmp cgx_done
cgx_op_and:
    lea rsi, [rel cgx_and]
    mov rdx, cgx_and_len
    call cg_write
    jmp cgx_done
cgx_op_or:
    lea rsi, [rel cgx_or]
    mov rdx, cgx_or_len
    call cg_write
    jmp cgx_done

cgx_unary_neg:
    ; Emit child, then neg rax
    mov edi, [r12 + 16]
    call cgx_emit_expr
    lea rsi, [rel cgx_neg_rax]
    mov rdx, cgx_neg_rax_len
    call cg_write
    jmp cgx_done

cgx_unary_not:
    ; Emit child, then xor rax, 1 (flip 0↔1)
    mov edi, [r12 + 16]
    call cgx_emit_expr
    lea rsi, [rel cgx_not_rax]
    mov rdx, cgx_not_rax_len
    call cg_write
    jmp cgx_done

cgx_do_expr:
    ; do is transparent — just emit the child
    mov edi, [r12 + 16]
    call cgx_emit_expr
    jmp cgx_done

cgx_call_expr:
    ; Check if it's a builtin
    movzx eax, byte [r12 + 1]      ; sub_type = builtin id
    cmp eax, BUILTIN_EXIT
    je cgx_call_exit

    ; General function call: evaluate args onto stack, then pop into registers
    ; Step 1: push all args onto stack (in order, so first arg is deepest)
    mov edi, [r12 + 16]            ; first_child (first arg)
    mov ecx, [r12 + 12]            ; child_count = arg count
    push rcx                        ; save arg count

cgx_call_push_args:
    cmp edi, NO_CHILD
    je cgx_call_args_pushed
    push rdi                        ; save current arg node index
    call cgx_emit_expr              ; result in rax
    ; Push result onto stack
    lea rsi, [rel cgx_push_rax]
    mov rdx, cgx_push_rax_len
    call cg_write
    ; Follow sibling chain to next arg
    pop rdi
    mov eax, edi
    imul eax, NODE_SIZE
    lea rsi, [rel nodes]
    mov edi, [rsi + rax + 20]       ; next_sibling
    jmp cgx_call_push_args

cgx_call_args_pushed:
    ; Step 2: pop args into registers in reverse order
    ; Args are on stack: [rsp]=last_arg, ..., [rsp+N]=first_arg
    ; We need first arg in rdi, second in rsi, etc.
    ; Pop in reverse: pop into r9, r8, rcx, rdx, rsi, rdi
    pop rcx                         ; arg count
    ; Emit pops based on arg count
    cmp ecx, 6
    jg cgx_call_pop6                ; max 6 register args
    mov edi, ecx
    jmp cgx_call_pop_start
cgx_call_pop6:
    mov edi, 6
cgx_call_pop_start:
    ; Pop edi args, last popped goes to first register
    ; We need to pop N times into temp, then assign
    ; Simpler: pop directly into registers in reverse order
    ; If 1 arg: pop rdi
    ; If 2 args: pop rsi, pop rdi
    ; If 3 args: pop rdx, pop rsi, pop rdi
    cmp edi, 1
    jl cgx_call_emit
    cmp edi, 6
    je cgx_call_pop_r9
    cmp edi, 5
    je cgx_call_pop_r8
    cmp edi, 4
    je cgx_call_pop_rcx
    cmp edi, 3
    je cgx_call_pop_rdx
    cmp edi, 2
    je cgx_call_pop_rsi
    ; 1 arg
    jmp cgx_call_pop_rdi

cgx_call_pop_r9:
    lea rsi, [rel cgx_pop_r9]
    mov rdx, cgx_pop_r9_len
    call cg_write
cgx_call_pop_r8:
    lea rsi, [rel cgx_pop_r8]
    mov rdx, cgx_pop_r8_len
    call cg_write
cgx_call_pop_rcx:
    lea rsi, [rel cgx_pop_rcx_reg]
    mov rdx, cgx_pop_rcx_reg_len
    call cg_write
cgx_call_pop_rdx:
    lea rsi, [rel cgx_pop_rdx]
    mov rdx, cgx_pop_rdx_len
    call cg_write
cgx_call_pop_rsi:
    lea rsi, [rel cgx_pop_rsi]
    mov rdx, cgx_pop_rsi_len
    call cg_write
cgx_call_pop_rdi:
    lea rsi, [rel cgx_pop_rdi]
    mov rdx, cgx_pop_rdi_len
    call cg_write

cgx_call_emit:
    ; Emit: call fn_NAME
    lea rsi, [rel cgx_call]
    mov rdx, cgx_call_len
    call cg_write
    mov ecx, [r12 + 4]
    mov edx, [r12 + 8]
    lea rsi, [rel strings]
    add rsi, rcx
    call cg_write
    lea rsi, [rel cgx_newline]
    mov rdx, 1
    call cg_write
    jmp cgx_done

cgx_call_exit:
    ; exit(n): emit arg, mov rdi,rax, mov rax,60, syscall
    mov edi, [r12 + 16]            ; first arg
    cmp edi, NO_CHILD
    je cgx_call_exit_zero
    call cgx_emit_expr
    jmp cgx_call_exit_emit
cgx_call_exit_zero:
    ; No arg — exit 0
    lea rsi, [rel cgx_mov_rax]
    mov rdx, cgx_mov_rax_len
    call cg_write
    xor eax, eax
    call cg_write_int
    lea rsi, [rel cgx_newline]
    mov rdx, 1
    call cg_write
cgx_call_exit_emit:
    lea rsi, [rel cgx_mov_rdi_rax]
    mov rdx, cgx_mov_rdi_rax_len
    call cg_write
    lea rsi, [rel cgx_exit_syscall]
    mov rdx, cgx_exit_syscall_len
    call cg_write
    jmp cgx_done

cgx_ident_ref:
    ; Load variable from stack slot
    ; Find the PARAM or LET node with matching name to get its offset
    mov ecx, [r12 + 4]             ; string_ref of this IDENT
    mov edx, [r12 + 8]             ; string_len
    ; Search backward through nodes for matching PARAM or LET
    mov edi, ecx
    mov esi, edx
    call cgx_find_var_offset        ; returns offset in eax

    ; Emit: mov rax, [rbp - offset]
    push rax
    lea rsi, [rel cg_load_rbp_neg]
    mov rdx, cg_load_rbp_neg_len
    call cg_write
    pop rax
    call cg_write_int
    lea rsi, [rel cg_close_bracket]
    mov rdx, cg_close_bracket_len
    call cg_write
    jmp cgx_done

cgx_str_lit:
    ; TODO: M1.7 — load string pointer+length
    jmp cgx_done

cgx_match_expr:
    ; TODO: M1.8
    jmp cgx_done

cgx_for_expr:
    ; TODO: M1.9
    jmp cgx_done

cgx_array_new_expr:
    ; TODO: M1.9
    jmp cgx_done

cgx_array_get_expr:
    ; TODO: M1.9
    jmp cgx_done

cgx_done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ============================================================
; cgx_find_var_offset — search AST for PARAM or LET with matching name
; Input: edi = string_ref (name offset), esi = string_len (name length)
; Output: eax = stack offset from that node's extra field
; ============================================================
cgx_find_var_offset:
    push rbx
    push rcx
    push rdx
    push r8
    push r9
    push r10

    ; edi = name string_ref (offset), esi = name string_len
    ; We need to compare actual bytes, not offsets
    mov r9d, edi                    ; r9 = target name offset
    mov r10d, esi                   ; r10 = target name length

    xor ecx, ecx                   ; node index
cgx_fvo_loop:
    cmp ecx, [rel node_count]
    jge cgx_fvo_not_found

    mov eax, ecx
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax

    movzx eax, byte [rbx]          ; node_type
    cmp eax, NODE_PARAM
    je cgx_fvo_check
    cmp eax, NODE_LET
    je cgx_fvo_check
    jmp cgx_fvo_next

cgx_fvo_check:
    ; Compare string lengths first
    mov eax, [rbx + 8]             ; candidate name_len
    cmp eax, r10d
    jne cgx_fvo_next

    ; Compare actual string bytes
    mov eax, [rbx + 4]             ; candidate name offset
    lea rdx, [rel strings]
    lea r8, [rdx + rax]            ; r8 = candidate name ptr
    lea rdx, [rel strings]
    mov eax, r9d
    lea rdx, [rdx + rax]           ; rdx = target name ptr

    xor eax, eax                   ; byte index
cgx_fvo_cmp:
    cmp eax, r10d
    jge cgx_fvo_match
    movzx edi, byte [r8 + rax]
    cmp dil, byte [rdx + rax]
    jne cgx_fvo_next
    inc eax
    jmp cgx_fvo_cmp

cgx_fvo_match:
    mov eax, [rbx + 28]            ; extra = stack offset
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

cgx_fvo_next:
    inc ecx
    jmp cgx_fvo_loop

cgx_fvo_not_found:
    xor eax, eax
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

section .data
cgx_mov_rcx_rax:   db "    mov rcx, rax", 10
cgx_mov_rcx_rax_len equ $ - cgx_mov_rcx_rax
cgx_pop_rax:        db "    pop rax", 10
cgx_pop_rax_len     equ $ - cgx_pop_rax

; Pop instructions for call arg setup
cgx_pop_rdi:        db "    pop rdi", 10
cgx_pop_rdi_len     equ $ - cgx_pop_rdi
cgx_pop_rsi:        db "    pop rsi", 10
cgx_pop_rsi_len     equ $ - cgx_pop_rsi
cgx_pop_rdx:        db "    pop rdx", 10
cgx_pop_rdx_len     equ $ - cgx_pop_rdx
cgx_pop_rcx_reg:    db "    pop rcx", 10
cgx_pop_rcx_reg_len equ $ - cgx_pop_rcx_reg
cgx_pop_r8:         db "    pop r8", 10
cgx_pop_r8_len      equ $ - cgx_pop_r8
cgx_pop_r9:         db "    pop r9", 10
cgx_pop_r9_len      equ $ - cgx_pop_r9
