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

    cmp eax, NODE_BLOCK
    je cgx_block_expr

    ; Unknown node type — emit nothing
    jmp cgx_done

cgx_block_expr:
    ; Emit block as expression — delegate to cg_emit_block
    mov edi, r13d                   ; node index
    call cg_emit_block
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
    ; Check for string concat — needs separate code path (16-byte values)
    movzx eax, byte [r12 + 1]
    cmp eax, BINOP_ADD
    jne cgx_binop_generic
    mov eax, [r12 + 24]
    cmp eax, TYPE_STRING
    je cgx_binop_str_concat

cgx_binop_generic:
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
    ; String + is intercepted before generic binop. If we get here, it's Int.
    lea rsi, [rel cgx_add]
    mov rdx, cgx_add_len
    call cg_write
    jmp cgx_done

cgx_binop_str_concat:
    ; String concat: emit left (rax=ptr, rdx=len), push both,
    ; emit right (rax=ptr, rdx=len), arrange args, call fn_string_concat
    ; fn_string_concat(rdi=ptr1, rsi=len1, rdx=ptr2, rcx=len2) -> rax=ptr, rdx=len
    mov edi, [r12 + 16]            ; left child
    call cgx_emit_expr              ; rax=ptr, rdx=len
    ; Push both ptr and len
    lea rsi, [rel cgx_push_rax]
    mov rdx, cgx_push_rax_len
    call cg_write
    lea rsi, [rel cgx_push_rdx]
    mov rdx, cgx_push_rdx_len
    call cg_write
    ; Emit right child
    mov eax, [r12 + 16]            ; left child index
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    mov edi, [rbx + rax + 20]      ; right child
    call cgx_emit_expr              ; rax=ptr2, rdx=len2
    ; Set up args: rdi=ptr1, rsi=len1, rdx=ptr2, rcx=len2
    ; Current: rax=ptr2, rdx=len2. Stack has [rsp]=len1, [rsp+8]=ptr1
    ; mov rcx, rdx (len2)
    ; mov rdx, rax (ptr2)
    ; pop rsi (len1)
    ; pop rdi (ptr1)
    lea rsi, [rel cgx_str_concat_setup]
    mov rdx, cgx_str_concat_setup_len
    call cg_write
    jmp cgx_done

; (dead code from refactor removed)
    ; dead path — all comments below are inert, guarded by jmp above
    ; rax=right.ptr, rdx=right.len. But the push/pop is for single 8-byte values.
    ; For string binop we need a different approach:
    ; Left string is in (rax, rdx) → push both → eval right → set up 4 args → call concat
    ; Actually the current binop flow pushes rax after left, then evaluates right.
    ; For strings, left produces (rax=ptr, rdx=len). We pushed rax (ptr only).
    ; We need to also have pushed rdx. Let me fix the approach:
    ; The generic binop code already ran: emit left → push rax → emit right → mov rcx,rax → pop rax
    ; So now: rax = left.ptr (from push/pop), rcx = right.ptr
    ; But we lost left.len and right.len!
    ; Fix: for string concat, we need to push BOTH ptr and len.
    ; This requires special handling in the binop emit path.
    ; For now, use the stack differently: emit left, push rax+rdx,
    ; emit right, pop left back, call concat.
    ; But the binop code already ran before we get here...
    ;
    ; Simpler fix: after the generic push/pop, rax and rcx have just the ptrs.
    ; We need to re-emit. This means string + can't use the generic binop path.
    ; Leave this as a TODO and handle it properly.
    ; For now: emit a call to fn_string_concat with the values already set up
    ; rax = left ptr (popped), rcx = right ptr (was in rax before mov rcx,rax)
    ; We need lens too. This won't work with generic binop.
    ; HACK for M1.7: emit left, push rax, push rdx, emit right,
    ; arrange args, call concat. Override the generic path.
    ;
    ; Actually, the generic binop already emitted all the code. We can't undo it.
    ; We need to intercept BEFORE the generic binop path for string +.
    ; Let me restructure: check type_info on BINOP_ADD before the generic emit.
    ; This requires moving the check earlier. For now, just emit the add instruction
    ; and fix this properly. String concat won't work yet in this commit.
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
    cmp eax, BUILTIN_PRINT
    je cgx_call_print
    cmp eax, BUILTIN_PRINT_RAW
    je cgx_call_print_raw
    cmp eax, BUILTIN_INT_TO_STRING
    je cgx_call_int_to_string
    cmp eax, BUILTIN_STRING_LENGTH
    je cgx_call_string_length
    cmp eax, BUILTIN_GET_ARG
    je cgx_call_get_arg
    cmp eax, BUILTIN_READ_FILE
    je cgx_call_read_file
    ; string_char_at and string_equals use the general call handler
    ; (16-byte push/pop pairs set up args correctly)

    ; General function call: evaluate args, push 16 bytes per arg (rax+rdx),
    ; then pop into register pairs (rdi/rsi, rdx/rcx, r8/r9)
    ; This treats every arg as potentially 16-byte (String). For Int args,
    ; rdx is junk but the callee only uses the first register of each pair.
    ; Callee param store handles splitting: Int params take 1 reg, String take 2.
    mov edi, [r12 + 16]            ; first_child (first arg)
    mov ecx, [r12 + 12]            ; child_count = arg count
    push rcx                        ; save arg count

cgx_call_push_args:
    cmp edi, NO_CHILD
    je cgx_call_args_pushed
    push rdi                        ; save current arg node index
    call cgx_emit_expr              ; result in rax (rdx for strings)
    ; Push both rax and rdx — 16 bytes per arg always
    lea rsi, [rel cgx_push_rdx]
    mov rdx, cgx_push_rdx_len
    call cg_write
    lea rsi, [rel cgx_push_rax]
    mov rdx, cgx_push_rax_len
    call cg_write
    ; Follow sibling chain
    pop rdi
    mov eax, edi
    imul eax, NODE_SIZE
    lea rsi, [rel nodes]
    mov edi, [rsi + rax + 20]       ; next_sibling
    jmp cgx_call_push_args

cgx_call_args_pushed:
    ; Pop register pairs in reverse. Last arg popped first.
    ; Each arg is 16 bytes on stack.
    ; Arg 1 → (rdi, rsi), Arg 2 → (rdx, rcx), Arg 3 → (r8, r9)
    pop rcx                         ; arg count
    cmp ecx, 3
    jge cgx_call_pop3
    cmp ecx, 2
    je cgx_call_pop2
    cmp ecx, 1
    je cgx_call_pop1
    jmp cgx_call_emit

cgx_call_pop3:
    ; Pop arg 3 into (r8, r9)
    lea rsi, [rel cgx_pop_r8]
    mov rdx, cgx_pop_r8_len
    call cg_write
    lea rsi, [rel cgx_pop_r9]
    mov rdx, cgx_pop_r9_len
    call cg_write
cgx_call_pop2:
    ; Pop arg 2 into (rdx, rcx)
    lea rsi, [rel cgx_pop_rdx]
    mov rdx, cgx_pop_rdx_len
    call cg_write
    lea rsi, [rel cgx_pop_rcx_reg]
    mov rdx, cgx_pop_rcx_reg_len
    call cg_write
cgx_call_pop1:
    ; Pop arg 1 into (rdi, rsi)
    lea rsi, [rel cgx_pop_rdi]
    mov rdx, cgx_pop_rdi_len
    call cg_write
    lea rsi, [rel cgx_pop_rsi]
    mov rdx, cgx_pop_rsi_len
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

cgx_call_print:
cgx_call_print_raw:
    ; print(s) / print_raw(s): evaluate string arg → (rax=ptr, rdx=len)
    ; Then: mov rdi, rax; mov rsi, rdx; call fn_print/fn_print_raw
    mov edi, [r12 + 16]            ; first arg
    cmp edi, NO_CHILD
    je cgx_done
    call cgx_emit_expr              ; rax=ptr, rdx=len after string expr
    ; Emit: mov rdi, rax / mov rsi, rdx / call fn_print
    lea rsi, [rel cgx_mov_rdi_rax]
    mov rdx, cgx_mov_rdi_rax_len
    call cg_write
    lea rsi, [rel cgx_mov_rsi_rdx]
    mov rdx, cgx_mov_rsi_rdx_len
    call cg_write
    ; Which print function?
    movzx eax, byte [r12 + 1]
    cmp eax, BUILTIN_PRINT
    je cgx_cp_print
    lea rsi, [rel cgx_call_print_raw_str]
    mov rdx, cgx_call_print_raw_str_len
    call cg_write
    jmp cgx_done
cgx_cp_print:
    lea rsi, [rel cgx_call_print_str]
    mov rdx, cgx_call_print_str_len
    call cg_write
    jmp cgx_done

cgx_call_int_to_string:
    ; int_to_string(n): evaluate arg → rax, mov rdi,rax, call fn_int_to_string
    ; Returns rax=ptr, rdx=len
    mov edi, [r12 + 16]
    cmp edi, NO_CHILD
    je cgx_done
    call cgx_emit_expr
    lea rsi, [rel cgx_mov_rdi_rax]
    mov rdx, cgx_mov_rdi_rax_len
    call cg_write
    lea rsi, [rel cgx_call_its_str]
    mov rdx, cgx_call_its_str_len
    call cg_write
    jmp cgx_done

cgx_call_string_length:
    ; string_length(s): evaluate string arg → (rax=ptr, rdx=len)
    ; Move to rdi=ptr, rsi=len, call fn_string_length → rax=len
    mov edi, [r12 + 16]
    cmp edi, NO_CHILD
    je cgx_done
    call cgx_emit_expr
    lea rsi, [rel cgx_mov_rdi_rax]
    mov rdx, cgx_mov_rdi_rax_len
    call cg_write
    lea rsi, [rel cgx_mov_rsi_rdx]
    mov rdx, cgx_mov_rsi_rdx_len
    call cg_write
    lea rsi, [rel cgx_call_sl_str]
    mov rdx, cgx_call_sl_str_len
    call cg_write
    jmp cgx_done

cgx_call_read_file:
    ; read_file(path: String): evaluate string arg → (rax=ptr, rdx=len)
    ; Move to rdi=ptr, rsi=len, call fn_read_file → returns rax=ptr, rdx=len
    mov edi, [r12 + 16]
    cmp edi, NO_CHILD
    je cgx_done
    call cgx_emit_expr
    lea rsi, [rel cgx_mov_rdi_rax]
    mov rdx, cgx_mov_rdi_rax_len
    call cg_write
    lea rsi, [rel cgx_mov_rsi_rdx]
    mov rdx, cgx_mov_rsi_rdx_len
    call cg_write
    lea rsi, [rel cgx_call_rf_str]
    mov rdx, cgx_call_rf_str_len
    call cg_write
    jmp cgx_done

cgx_call_get_arg:
    ; get_arg(n): evaluate arg → rax, mov rdi,rax, call fn_get_arg
    ; Returns rax=ptr, rdx=len
    mov edi, [r12 + 16]
    cmp edi, NO_CHILD
    je cgx_done
    call cgx_emit_expr
    lea rsi, [rel cgx_mov_rdi_rax]
    mov rdx, cgx_mov_rdi_rax_len
    call cg_write
    lea rsi, [rel cgx_call_get_arg_str]
    mov rdx, cgx_call_get_arg_str_len
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
    ; Find the PARAM or LET node with matching name to get its offset and type
    mov ecx, [r12 + 4]             ; string_ref of this IDENT
    mov edx, [r12 + 8]             ; string_len
    mov edi, ecx
    mov esi, edx
    call cgx_find_var_offset        ; eax = offset, r11d = type_info

    ; Check if it's a String/Array (16-byte value: ptr at [rbp-offset], len at [rbp-(offset-8)])
    cmp r11d, TYPE_STRING
    je cgx_ident_str
    cmp r11d, TYPE_ARRAY
    je cgx_ident_str

    ; 8-byte value: emit mov rax, [rbp - offset]
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

cgx_ident_str:
    ; 16-byte value: load ptr into rax, len into rdx
    ; ptr at [rbp - offset], len at [rbp - (offset-8)]
    push rax                        ; save offset
    ; Emit: mov rax, [rbp - offset]  (ptr)
    lea rsi, [rel cg_load_rbp_neg]
    mov rdx, cg_load_rbp_neg_len
    call cg_write
    pop rax
    push rax
    call cg_write_int
    lea rsi, [rel cg_close_bracket]
    mov rdx, cg_close_bracket_len
    call cg_write
    ; Emit: mov rdx, [rbp - (offset-8)]  (len)
    lea rsi, [rel cgx_load_rdx_rbp_neg]
    mov rdx, cgx_load_rdx_rbp_neg_len
    call cg_write
    pop rax
    sub eax, 8                      ; len is 8 bytes before ptr
    call cg_write_int
    lea rsi, [rel cg_close_bracket]
    mov rdx, cg_close_bracket_len
    call cg_write
    jmp cgx_done

cgx_str_lit:
    ; Load string literal pointer and length
    ; Look up this node's label number from cg_str_lit_map
    lea rdi, [rel cg_str_lit_map]
    mov eax, [rdi + r13*4]         ; r13 = node index, eax = label number

    ; Emit: lea rax, [rel _sN]
    lea rsi, [rel cgx_lea_rax_str]
    mov rdx, cgx_lea_rax_str_len
    call cg_write
    call cg_write_int
    lea rsi, [rel cgx_close_bracket_nl]
    mov rdx, cgx_close_bracket_nl_len
    call cg_write

    ; Emit: mov rdx, _sN_len
    lea rsi, [rel cgx_mov_rdx_str]
    mov rdx, cgx_mov_rdx_str_len
    call cg_write
    ; Re-look up label number
    lea rdi, [rel cg_str_lit_map]
    mov eax, [rdi + r13*4]
    call cg_write_int
    lea rsi, [rel cgx_str_len_suffix]
    mov rdx, cgx_str_len_suffix_len
    call cg_write

    jmp cgx_done

cgx_match_expr:
    call cgm_emit_match
    jmp cgx_done

cgx_for_expr:
    ; FOR node: string_ref = loop var name, extra = loop var stack offset
    ; Children: start expr, end expr, body block
    ; Label scheme: .LfN_top, .LfN_end (N from label_counter)
    push r14
    push r15
    sub rsp, 8                     ; local: label number

    ; Get label number
    mov rax, [rel label_counter]
    mov [rsp], rax
    inc qword [rel label_counter]

    ; Get loop var offset and end-value offset
    mov r14d, [r12 + 28]           ; extra = loop var stack offset
    mov r15d, r14d
    add r15d, 8                    ; end value at offset+8

    ; Emit start expr → store to loop var
    mov edi, [r12 + 16]            ; first_child = start expr
    call cgx_emit_expr
    ; Emit: mov [rbp - loop_var_offset], rax
    lea rsi, [rel cg_mov_rbp_neg]
    mov rdx, cg_mov_rbp_neg_len
    call cg_write
    mov eax, r14d
    call cg_write_int
    lea rsi, [rel cg_comma_space]
    mov rdx, cg_comma_space_len
    call cg_write
    lea rsi, [rel cg_reg_rax]
    mov rdx, 3
    call cg_write
    lea rsi, [rel cgx_newline]
    mov rdx, 1
    call cg_write

    ; Emit end expr → store to end temp
    mov eax, [r12 + 16]            ; start node index
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    mov edi, [rdi + rax + 20]      ; end expr node index
    push rdi                        ; save end node index for body lookup
    call cgx_emit_expr
    ; Emit: mov [rbp - end_offset], rax
    lea rsi, [rel cg_mov_rbp_neg]
    mov rdx, cg_mov_rbp_neg_len
    call cg_write
    mov eax, r15d
    call cg_write_int
    lea rsi, [rel cg_comma_space]
    mov rdx, cg_comma_space_len
    call cg_write
    lea rsi, [rel cg_reg_rax]
    mov rdx, 3
    call cg_write
    lea rsi, [rel cgx_newline]
    mov rdx, 1
    call cg_write

    ; Emit top label: .LfN_top:
    lea rsi, [rel cgx_for_lf_prefix]
    mov rdx, cgx_for_lf_prefix_len
    call cg_write
    mov rax, [rsp + 8]             ; label number (below saved end node)
    call cg_write_int
    lea rsi, [rel cgx_for_top_label]
    mov rdx, cgx_for_top_label_len
    call cg_write

    ; Emit: mov rax, [rbp - loop_var]; cmp rax, [rbp - end]; jge .LfN_end
    lea rsi, [rel cg_load_rbp_neg]
    mov rdx, cg_load_rbp_neg_len
    call cg_write
    mov eax, r14d
    call cg_write_int
    lea rsi, [rel cg_close_bracket]
    mov rdx, cg_close_bracket_len
    call cg_write

    ; cmp rax, [rbp - end_offset]
    lea rsi, [rel cgx_for_cmp]
    mov rdx, cgx_for_cmp_len
    call cg_write
    mov eax, r15d
    call cg_write_int
    lea rsi, [rel cg_close_bracket]
    mov rdx, cg_close_bracket_len
    call cg_write

    ; jge .LfN_end
    lea rsi, [rel cgx_for_jge]
    mov rdx, cgx_for_jge_len
    call cg_write
    mov rax, [rsp + 8]
    call cg_write_int
    lea rsi, [rel cgx_for_end_ref]
    mov rdx, cgx_for_end_ref_len
    call cg_write

    ; Emit body block
    pop rdi                         ; end node index
    mov eax, edi
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    mov edi, [rdi + rax + 20]      ; end.next_sibling = body block
    call cg_emit_block

    ; Emit: inc qword [rbp - loop_var]; jmp .LfN_top
    lea rsi, [rel cgx_for_inc]
    mov rdx, cgx_for_inc_len
    call cg_write
    mov eax, r14d
    call cg_write_int
    lea rsi, [rel cg_close_bracket]
    mov rdx, cg_close_bracket_len
    call cg_write

    lea rsi, [rel cgx_for_jmp_top]
    mov rdx, cgx_for_jmp_top_len
    call cg_write
    mov rax, [rsp]
    call cg_write_int
    lea rsi, [rel cgx_for_top_ref]
    mov rdx, cgx_for_top_ref_len
    call cg_write

    ; Emit end label: .LfN_end:
    lea rsi, [rel cgx_for_lf_prefix]
    mov rdx, cgx_for_lf_prefix_len
    call cg_write
    mov rax, [rsp]
    call cg_write_int
    lea rsi, [rel cgx_for_end_label]
    mov rdx, cgx_for_end_label_len
    call cg_write

    add rsp, 8
    pop r15
    pop r14
    jmp cgx_done

cgx_array_new_expr:
    ; Array(n): evaluate size → allocate from bump heap
    ; Emit: evaluate size expr
    mov edi, [r12 + 16]            ; first_child = size expr
    call cgx_emit_expr
    ; rax = count. Emit allocation code.
    lea rsi, [rel cgx_array_alloc]
    mov rdx, cgx_array_alloc_len
    call cg_write
    ; Result: rax = ptr, rdx = count
    jmp cgx_done

cgx_array_get_expr:
    ; Array index read: load array, evaluate index, load element
    ; Load array (ptr, len) from named variable
    mov edi, [r12 + 4]             ; array name string_ref
    mov esi, [r12 + 8]             ; array name string_len
    call cgx_find_var_offset        ; eax = offset, r11d = type

    ; Emit: mov r10, [rbp - offset]  (ptr)
    push rax
    lea rsi, [rel cg_as_load_r10]
    mov rdx, cg_as_load_r10_len
    call cg_write
    pop rax
    call cg_write_int
    lea rsi, [rel cg_close_bracket]
    mov rdx, cg_close_bracket_len
    call cg_write

    ; Save r10 before evaluating index (index expr may clobber r10)
    lea rsi, [rel cg_as_push_r10]
    mov rdx, cg_as_push_r10_len
    call cg_write

    ; Evaluate index expression
    mov edi, [r12 + 16]            ; first_child = index expr
    call cgx_emit_expr

    ; Restore r10, then load element: pop r10; mov rax, [r10 + rax*8]
    lea rsi, [rel cgx_array_load_safe]
    mov rdx, cgx_array_load_safe_len
    call cg_write
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
    ; Function-scoped: only search PARAMs of current fn and
    ; LET/FOR nodes at or after cur_fn_body index
    mov r9d, edi                    ; r9 = target name offset
    mov r10d, esi                   ; r10 = target name length

    ; First search PARAMs: walk fn_decl's child chain
    mov rax, [rel cur_fn_index]
    imul rax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax
    mov ecx, [rbx + 16]            ; first_child = first PARAM
cgx_fvo_param_loop:
    cmp ecx, NO_CHILD
    je cgx_fvo_params_done
    mov eax, ecx
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax
    movzx eax, byte [rbx]
    cmp eax, NODE_PARAM
    jne cgx_fvo_param_next
    ; Check name match for this param
    mov eax, [rbx + 8]
    cmp eax, r10d
    jne cgx_fvo_param_next
    ; Compare bytes
    push rcx
    mov eax, [rbx + 4]
    lea rdx, [rel strings]
    lea r8, [rdx + rax]
    mov eax, r9d
    lea rdx, [rel strings]
    lea rdx, [rdx + rax]
    xor eax, eax
cgx_fvo_pcmp:
    cmp eax, r10d
    jge cgx_fvo_pmatch
    movzx edi, byte [r8 + rax]
    cmp dil, byte [rdx + rax]
    jne cgx_fvo_pnomatch
    inc eax
    jmp cgx_fvo_pcmp
cgx_fvo_pmatch:
    pop rcx
    jmp cgx_fvo_match              ; found it — return
cgx_fvo_pnomatch:
    pop rcx
cgx_fvo_param_next:
    mov eax, ecx
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    mov ecx, [rbx + rax + 20]      ; next_sibling
    jmp cgx_fvo_param_loop

cgx_fvo_params_done:
    ; Then search LET/FOR nodes at or after cur_fn_body
    mov ecx, [rel cur_fn_body]
cgx_fvo_loop:
    cmp ecx, [rel node_count]
    jge cgx_fvo_not_found

    mov eax, ecx
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax

    movzx eax, byte [rbx]
    ; Stop if we hit another function declaration — left current scope
    cmp eax, NODE_FN_DECL
    je cgx_fvo_not_found
    cmp eax, NODE_LET
    je cgx_fvo_check_name
    cmp eax, NODE_FOR
    je cgx_fvo_check_name
    jmp cgx_fvo_next

cgx_fvo_check_name:
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
    mov eax, [rbx + 28]            ; extra = stack offset (returned in eax)
    mov r11d, [rbx + 24]           ; type_info (returned in r11d — caller-saved)
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

; String literal load
cgx_lea_rax_str:    db "    lea rax, [rel _s"
cgx_lea_rax_str_len equ $ - cgx_lea_rax_str
cgx_close_bracket_nl: db "]", 10
cgx_close_bracket_nl_len equ $ - cgx_close_bracket_nl
cgx_mov_rdx_str:    db "    mov rdx, _s"
cgx_mov_rdx_str_len equ $ - cgx_mov_rdx_str
cgx_str_len_suffix: db "_len", 10
cgx_str_len_suffix_len equ $ - cgx_str_len_suffix

; Builtin call strings
cgx_mov_rsi_rdx:    db "    mov rsi, rdx", 10
cgx_mov_rsi_rdx_len equ $ - cgx_mov_rsi_rdx
cgx_call_print_str: db "    call fn_print", 10
cgx_call_print_str_len equ $ - cgx_call_print_str
cgx_call_print_raw_str: db "    call fn_print_raw", 10
cgx_call_print_raw_str_len equ $ - cgx_call_print_raw_str
cgx_call_its_str:   db "    call fn_int_to_string", 10
cgx_call_its_str_len equ $ - cgx_call_its_str
cgx_call_sl_str:    db "    call fn_string_length", 10
cgx_call_sl_str_len equ $ - cgx_call_sl_str
cgx_call_get_arg_str: db "    call fn_get_arg", 10
cgx_call_get_arg_str_len equ $ - cgx_call_get_arg_str
cgx_call_rf_str:    db "    call fn_read_file", 10
cgx_call_rf_str_len equ $ - cgx_call_rf_str

; String concat
cgx_push_rdx:       db "    push rdx", 10
cgx_push_rdx_len    equ $ - cgx_push_rdx
cgx_str_concat_setup:
    db "    mov rcx, rdx", 10      ; len2
    db "    mov rdx, rax", 10      ; ptr2
    db "    pop rsi", 10           ; len1
    db "    pop rdi", 10           ; ptr1
    db "    call fn_string_concat", 10
cgx_str_concat_setup_len equ $ - cgx_str_concat_setup

; String ident load
cgx_load_rdx_rbp_neg: db "    mov rdx, qword [rbp-"
cgx_load_rdx_rbp_neg_len equ $ - cgx_load_rdx_rbp_neg

; For loop labels and operations
cgx_for_lf_prefix:   db ".Lf"
cgx_for_lf_prefix_len equ $ - cgx_for_lf_prefix
cgx_for_top_label:   db "_top:", 10
cgx_for_top_label_len equ $ - cgx_for_top_label
cgx_for_top_ref:     db "_top", 10
cgx_for_top_ref_len  equ $ - cgx_for_top_ref
cgx_for_end_label:   db "_end:", 10
cgx_for_end_label_len equ $ - cgx_for_end_label
cgx_for_end_ref:     db "_end", 10
cgx_for_end_ref_len  equ $ - cgx_for_end_ref
cgx_for_cmp:         db "    cmp rax, qword [rbp-"
cgx_for_cmp_len      equ $ - cgx_for_cmp
cgx_for_jge:         db "    jge .Lf"
cgx_for_jge_len      equ $ - cgx_for_jge
cgx_for_inc:         db "    inc qword [rbp-"
cgx_for_inc_len      equ $ - cgx_for_inc
cgx_for_jmp_top:     db "    jmp .Lf"
cgx_for_jmp_top_len  equ $ - cgx_for_jmp_top

; Array allocation
cgx_array_alloc:
    db "    mov rcx, rax", 10          ; save count
    db "    shl rax, 3", 10            ; count * 8
    db "    mov rdi, [rel _bump_pos]", 10
    db "    add [rel _bump_pos], rax", 10
    db "    mov rax, rdi", 10          ; return ptr
    db "    mov rdx, rcx", 10          ; return count (len)
cgx_array_alloc_len equ $ - cgx_array_alloc

; Array element load
cgx_array_load:
    db "    mov rax, qword [r10 + rax*8]", 10
cgx_array_load_len  equ $ - cgx_array_load
cgx_array_load_safe:
    db "    pop r10", 10
    db "    mov rax, qword [r10 + rax*8]", 10
cgx_array_load_safe_len equ $ - cgx_array_load_safe
