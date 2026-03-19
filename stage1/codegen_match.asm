; stage1/codegen_match.asm
; cgm_emit_match: emit NASM for match expressions
;
; Match structure in AST (from ast-format.md):
;   NODE_MATCH: child_count = arm count, extra = discriminant node index
;               first_child = first ARM node (sibling chain)
;   NODE_MATCH_ARM: sub_type = 1 for wildcard, 0 for literal
;                   extra = pattern value (int literal or 0/1 for bool)
;                   first_child = body expression
;
; Generated label scheme (using label_counter for uniqueness):
;   .Lm{N}_arm{I}   — arm I body
;   .Lm{N}_wild     — wildcard arm
;   .Lm{N}_end      — after all arms
;
; Uses: cgm_ prefix for all labels

section .data
cgm_cmp_rax:        db "    cmp rax, "
cgm_cmp_rax_len     equ $ - cgm_cmp_rax
cgm_je:             db "    je .Lm"
cgm_je_len          equ $ - cgm_je
cgm_jmp:            db "    jmp .Lm"
cgm_jmp_len         equ $ - cgm_jmp
cgm_arm_prefix:     db ".Lm"
cgm_arm_prefix_len  equ $ - cgm_arm_prefix
cgm_arm_mid:        db "_arm"
cgm_arm_mid_len     equ $ - cgm_arm_mid
cgm_wild_suffix:    db "_wild"
cgm_wild_suffix_len equ $ - cgm_wild_suffix
cgm_end_suffix:     db "_end"
cgm_end_suffix_len  equ $ - cgm_end_suffix
cgm_colon_nl:       db ":", 10
cgm_colon_nl_len    equ $ - cgm_colon_nl
cgm_newline:        db 10
cgm_push_rax:       db "    push rax", 10
cgm_push_rax_len    equ $ - cgm_push_rax
cgm_pop_rax:        db "    pop rax", 10
cgm_pop_rax_len     equ $ - cgm_pop_rax

section .text

; ============================================================
; cgm_emit_match — emit match expression
; Input: r12 = NODE_MATCH pointer, r13 = node index
; Called from cgx_emit_expr when node_type == NODE_MATCH
; Result of the taken arm is left in rax.
; ============================================================
cgm_emit_match:
    push rbp
    mov rbp, rsp
    push rbx
    push r14
    push r15
    sub rsp, 8                     ; local: match label number

    ; Get match label number from label_counter
    mov rax, [rel label_counter]
    mov [rsp], rax                  ; save label number
    inc qword [rel label_counter]

    ; Emit discriminant expression — result in rax
    mov edi, [r12 + 28]            ; extra = discriminant node index
    call cgx_emit_expr

    ; Save discriminant on stack (generated code pushes rax)
    lea rsi, [rel cgm_push_rax]
    mov rdx, cgm_push_rax_len
    call cg_write

    ; Walk arms and emit comparison chain
    ; For each literal arm: cmp rax, VALUE; je .LmN_armI
    ; For wildcard arm: jmp .LmN_wild
    mov r14d, [r12 + 16]           ; first_child = first arm index
    xor r15d, r15d                  ; arm counter

cgm_em_cmp_loop:
    cmp r14d, NO_CHILD
    je cgm_em_cmp_done

    ; Get arm node
    mov eax, r14d
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax

    ; Check if wildcard
    movzx eax, byte [rbx + 1]      ; sub_type: 1=wildcard, 0=literal
    cmp eax, 1
    je cgm_em_cmp_wildcard

    ; Literal arm: emit cmp rax, VALUE
    ; First restore discriminant for comparison (it's on the stack)
    ; Actually we need rax to hold the discriminant for each cmp.
    ; After the first cmp, rax is still the discriminant (cmp doesn't modify it).
    ; But we already pushed it. We need to peek at it.
    ; Better approach: pop rax before the comparison chain, then the chain
    ; just uses rax directly. Push only once, pop before comparisons.

    ; Emit: cmp rax, VALUE
    lea rsi, [rel cgm_cmp_rax]
    mov rdx, cgm_cmp_rax_len
    call cg_write
    mov eax, [rbx + 28]            ; extra = pattern value
    call cg_write_int
    lea rsi, [rel cgm_newline]
    mov rdx, 1
    call cg_write

    ; Emit: je .LmN_armI
    lea rsi, [rel cgm_je]
    mov rdx, cgm_je_len
    call cg_write
    mov rax, [rsp]                  ; match label number
    call cg_write_int
    lea rsi, [rel cgm_arm_mid]
    mov rdx, cgm_arm_mid_len
    call cg_write
    mov eax, r15d                   ; arm index
    call cg_write_int
    lea rsi, [rel cgm_newline]
    mov rdx, 1
    call cg_write

    jmp cgm_em_cmp_next

cgm_em_cmp_wildcard:
    ; Emit: jmp .LmN_wild
    lea rsi, [rel cgm_jmp]
    mov rdx, cgm_jmp_len
    call cg_write
    mov rax, [rsp]
    call cg_write_int
    lea rsi, [rel cgm_wild_suffix]
    mov rdx, cgm_wild_suffix_len
    call cg_write
    lea rsi, [rel cgm_newline]
    mov rdx, 1
    call cg_write

cgm_em_cmp_next:
    ; Follow sibling chain
    mov eax, r14d
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    mov r14d, [rbx + rax + 20]     ; next_sibling
    inc r15d
    jmp cgm_em_cmp_loop

cgm_em_cmp_done:
    ; Now emit arm bodies
    ; Each arm: label, pop discriminant (discard), emit body, jmp to end
    mov r14d, [r12 + 16]           ; first arm again
    xor r15d, r15d

cgm_em_body_loop:
    cmp r14d, NO_CHILD
    je cgm_em_bodies_done

    mov eax, r14d
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax

    ; Emit label: .LmN_armI: or .LmN_wild:
    movzx eax, byte [rbx + 1]
    cmp eax, 1
    je cgm_em_body_wild_label

    ; Literal arm label
    lea rsi, [rel cgm_arm_prefix]
    mov rdx, cgm_arm_prefix_len
    call cg_write
    mov rax, [rsp]
    call cg_write_int
    lea rsi, [rel cgm_arm_mid]
    mov rdx, cgm_arm_mid_len
    call cg_write
    mov eax, r15d
    call cg_write_int
    lea rsi, [rel cgm_colon_nl]
    mov rdx, cgm_colon_nl_len
    call cg_write
    jmp cgm_em_body_emit

cgm_em_body_wild_label:
    lea rsi, [rel cgm_arm_prefix]
    mov rdx, cgm_arm_prefix_len
    call cg_write
    mov rax, [rsp]
    call cg_write_int
    lea rsi, [rel cgm_wild_suffix]
    mov rdx, cgm_wild_suffix_len
    call cg_write
    lea rsi, [rel cgm_colon_nl]
    mov rdx, cgm_colon_nl_len
    call cg_write

cgm_em_body_emit:
    ; Pop the saved discriminant (discard — we're in a taken arm)
    lea rsi, [rel cgm_pop_rax]
    mov rdx, cgm_pop_rax_len
    call cg_write

    ; Emit body expression — result in rax
    mov edi, [rbx + 16]            ; first_child = body expression
    call cgx_emit_expr

    ; Emit: jmp .LmN_end (skip remaining arms)
    lea rsi, [rel cgm_jmp]
    mov rdx, cgm_jmp_len
    call cg_write
    mov rax, [rsp]
    call cg_write_int
    lea rsi, [rel cgm_end_suffix]
    mov rdx, cgm_end_suffix_len
    call cg_write
    lea rsi, [rel cgm_newline]
    mov rdx, 1
    call cg_write

    ; Next arm
    mov eax, r14d
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    mov r14d, [rbx + rax + 20]
    inc r15d
    jmp cgm_em_body_loop

cgm_em_bodies_done:
    ; Emit end label: .LmN_end:
    lea rsi, [rel cgm_arm_prefix]
    mov rdx, cgm_arm_prefix_len
    call cg_write
    mov rax, [rsp]
    call cg_write_int
    lea rsi, [rel cgm_end_suffix]
    mov rdx, cgm_end_suffix_len
    call cg_write
    lea rsi, [rel cgm_colon_nl]
    mov rdx, cgm_colon_nl_len
    call cg_write

    add rsp, 8
    pop r15
    pop r14
    pop rbx
    pop rbp
    ret
