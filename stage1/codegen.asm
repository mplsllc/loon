; stage1/codegen.asm
; cg_emit_program: walk AST, emit NASM x86-64 assembly to stdout
;
; Entry: node_count set, nodes array populated, func_table populated
; Exit: NASM assembly written to stdout
;
; Uses: cg_ prefix for all labels
;
; Output structure:
;   section .data   — string literals (future)
;   section .bss    — bump heap (future)
;   section .text   — _start + compiled functions
;
; Calling convention (AMD64 System V ABI):
;   Args: rdi, rsi, rdx, rcx, r8, r9
;   Return: rax
;   Caller-saved: rax, rcx, rdx, rsi, rdi, r8, r9, r10, r11
;   Callee-saved: rbx, rbp, rsp, r12, r13, r14, r15
;   Stack frame: push rbp; mov rbp, rsp; sub rsp, N

%define SYS_WRITE 1
%define SYS_EXIT  60
%define STDOUT 1
%define STDERR 2

%define NODE_SIZE 32
%define NO_CHILD 0xFFFFFFFF
%define FUNC_ENTRY_SIZE 32

; Re-use node type constants from expr_parser.asm
; (already defined via %include order)

section .data
; Output strings — each is a fragment of NASM assembly text
cg_section_text:    db "section .text", 10
cg_section_text_len equ $ - cg_section_text
cg_global_start:    db "global _start", 10
cg_global_start_len equ $ - cg_global_start

cg_start_label:     db "_start:", 10
cg_start_label_len  equ $ - cg_start_label
cg_start_align:     db "    and rsp, -16", 10
cg_start_align_len  equ $ - cg_start_align
cg_start_call_main: db "    call fn_main", 10
cg_start_call_main_len equ $ - cg_start_call_main
cg_start_exit:      db "    mov rdi, rax", 10, "    mov rax, 60", 10, "    syscall", 10
cg_start_exit_len   equ $ - cg_start_exit

cg_fn_prefix:       db "fn_"
cg_fn_prefix_len    equ $ - cg_fn_prefix
cg_colon_nl:        db ":", 10
cg_colon_nl_len     equ $ - cg_colon_nl

cg_prologue1:       db "    push rbp", 10
cg_prologue1_len    equ $ - cg_prologue1
cg_prologue2:       db "    mov rbp, rsp", 10
cg_prologue2_len    equ $ - cg_prologue2
cg_sub_rsp:         db "    sub rsp, "
cg_sub_rsp_len      equ $ - cg_sub_rsp

cg_epilogue:        db "    mov rsp, rbp", 10, "    pop rbp", 10, "    ret", 10
cg_epilogue_len     equ $ - cg_epilogue

cg_newline:         db 10

; Variable access
cg_mov_rbp_neg:     db "    mov qword [rbp-"
cg_mov_rbp_neg_len  equ $ - cg_mov_rbp_neg
cg_comma_space:     db "], "
cg_comma_space_len  equ $ - cg_comma_space
cg_load_rbp_neg:    db "    mov rax, qword [rbp-"
cg_load_rbp_neg_len equ $ - cg_load_rbp_neg
cg_close_bracket:   db "]", 10
cg_close_bracket_len equ $ - cg_close_bracket

; Register names
cg_reg_rdi:         db "rdi"
cg_reg_rsi:         db "rsi"
cg_reg_rdx:         db "rdx"
cg_reg_rcx:         db "rcx"
cg_reg_r8:          db "r8"
cg_reg_r9:          db "r9"
cg_reg_rax:         db "rax"

section .bss
cg_outbuf   resb 8192      ; output buffer
cg_outpos   resq 1         ; current write position in output buffer
cg_itoa_buf resb 32        ; scratch for number→string

section .text

; ============================================================
; cg_emit_program — main codegen entry point
; Walk the AST and emit NASM assembly
; ============================================================
cg_emit_program:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Initialize output buffer
    xor rax, rax
    mov [rel cg_outpos], rax

    ; Emit: section .text
    lea rsi, [rel cg_section_text]
    mov rdx, cg_section_text_len
    call cg_write

    ; Emit: global _start
    lea rsi, [rel cg_global_start]
    mov rdx, cg_global_start_len
    call cg_write

    ; Emit newline
    lea rsi, [rel cg_newline]
    mov rdx, 1
    call cg_write

    ; Walk all function declarations and emit them
    xor r12d, r12d                  ; node index
cg_ep_walk:
    cmp r12, [rel node_count]
    jge cg_ep_funcs_done

    ; Get node pointer
    mov rax, r12
    imul rax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax

    movzx eax, byte [rbx]
    cmp eax, NODE_FN_DECL
    jne cg_ep_next

    ; Emit this function
    mov rdi, r12                    ; pass node index
    call cg_emit_fn

cg_ep_next:
    inc r12
    jmp cg_ep_walk

cg_ep_funcs_done:
    ; Emit _start
    lea rsi, [rel cg_start_label]
    mov rdx, cg_start_label_len
    call cg_write
    lea rsi, [rel cg_start_align]
    mov rdx, cg_start_align_len
    call cg_write
    lea rsi, [rel cg_start_call_main]
    mov rdx, cg_start_call_main_len
    call cg_write
    lea rsi, [rel cg_start_exit]
    mov rdx, cg_start_exit_len
    call cg_write

    ; Flush output buffer
    call cg_flush

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ============================================================
; cg_emit_fn — emit one function
; Input: rdi = NODE_FN_DECL node index
; ============================================================
cg_emit_fn:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8                     ; local: current stack offset

    ; Get fn_decl node pointer
    mov rax, rdi
    imul rax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax
    mov r12, rbx                    ; r12 = fn_decl node pointer

    ; ---- Pre-pass: assign stack slots to params and locals ----
    ; Stack layout (negative offsets from rbp):
    ;   [rbp-8]   first param (Int) or first 8 bytes of String param
    ;   [rbp-16]  second param or second 8 bytes of String param
    ;   etc.
    ; Int/Bool: 8 bytes. String/Array: 16 bytes (ptr then len).

    xor r14d, r14d                  ; r14 = current offset (positive, negate for rbp)
    ; Offset starts at 8 (first slot is [rbp-8])

    ; Walk params via sibling chain
    mov r13d, [r12 + 12]           ; param count
    mov ebx, [r12 + 16]            ; first_child = first param index
    xor r15d, r15d                  ; r15 = param counter

    ; AMD64 ABI arg registers: rdi, rsi, rdx, rcx, r8, r9
    ; For String params, ptr in one reg, len in next

cg_ef_param_loop:
    cmp r15d, r13d
    jge cg_ef_params_done
    cmp ebx, NO_CHILD
    je cg_ef_params_done

    ; Get param node
    mov eax, ebx
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    add rdi, rax                    ; rdi = param node pointer

    ; Check type_info for size
    mov eax, [rdi + 24]            ; type_info
    cmp eax, TYPE_STRING
    je cg_ef_param_16
    cmp eax, TYPE_ARRAY
    je cg_ef_param_16

    ; 8-byte param (Int, Bool, Unit)
    add r14d, 8
    mov [rdi + 28], r14d            ; extra = stack offset (positive)
    jmp cg_ef_param_next

cg_ef_param_16:
    ; 16-byte param (String, Array) — ptr at offset, len at offset+8
    add r14d, 16
    mov [rdi + 28], r14d            ; extra = stack offset (of len; ptr is at offset-8)
    jmp cg_ef_param_next

cg_ef_param_next:
    ; Follow sibling chain
    mov eax, ebx
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    mov ebx, [rdi + rax + 20]      ; next_sibling
    inc r15d
    jmp cg_ef_param_loop

cg_ef_params_done:
    ; Walk body block to find LET bindings and assign slots
    mov r13d, [r12 + 28]           ; extra = body block node index
    cmp r13d, NO_CHILD
    je cg_ef_prepass_done
    mov edi, r13d
    ; r14 still has current offset
    call cg_assign_let_slots        ; walks block, assigns offsets, updates r14

cg_ef_prepass_done:
    ; Round up stack size to 16-byte alignment
    mov eax, r14d
    add eax, 15
    and eax, 0xFFFFFFF0
    cmp eax, 16
    jge cg_ef_has_stack
    mov eax, 16                     ; minimum 16 bytes
cg_ef_has_stack:
    mov [rsp], rax                  ; save stack size on our local

    ; ---- Emit function code ----

    ; Emit label: fn_NAME:
    lea rsi, [rel cg_fn_prefix]
    mov rdx, cg_fn_prefix_len
    call cg_write
    mov ecx, [r12 + 4]
    mov edx, [r12 + 8]
    lea rsi, [rel strings]
    add rsi, rcx
    call cg_write
    lea rsi, [rel cg_colon_nl]
    mov rdx, cg_colon_nl_len
    call cg_write

    ; Emit prologue
    lea rsi, [rel cg_prologue1]
    mov rdx, cg_prologue1_len
    call cg_write
    lea rsi, [rel cg_prologue2]
    mov rdx, cg_prologue2_len
    call cg_write

    ; sub rsp, N
    lea rsi, [rel cg_sub_rsp]
    mov rdx, cg_sub_rsp_len
    call cg_write
    mov rax, [rsp]                  ; stack size
    lea rdi, [rel cg_itoa_buf]
    call cg_itoa
    lea rsi, [rel cg_itoa_buf]
    mov rdx, rcx
    call cg_write
    lea rsi, [rel cg_newline]
    mov rdx, 1
    call cg_write

    ; Emit parameter stores: move from registers to stack slots
    ; AMD64 arg registers in order: rdi, rsi, rdx, rcx, r8, r9
    mov r13d, [r12 + 12]           ; param count
    mov ebx, [r12 + 16]            ; first param node index
    xor r15d, r15d                  ; param index (for register selection)
    xor r14d, r14d                  ; register index (advances by 2 for String params)

cg_ef_store_params:
    cmp r15d, r13d
    jge cg_ef_store_done
    cmp ebx, NO_CHILD
    je cg_ef_store_done

    ; Get param node
    mov eax, ebx
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    add rdi, rax

    mov eax, [rdi + 24]            ; type_info
    mov ecx, [rdi + 28]            ; stack offset

    cmp eax, TYPE_STRING
    je cg_ef_store_str_param
    cmp eax, TYPE_ARRAY
    je cg_ef_store_str_param

    ; 8-byte param: mov [rbp - offset], REG
    push rbx
    push rcx
    lea rsi, [rel cg_mov_rbp_neg]
    mov rdx, cg_mov_rbp_neg_len
    call cg_write
    pop rcx
    mov eax, ecx
    call cg_write_int
    lea rsi, [rel cg_comma_space]
    mov rdx, cg_comma_space_len
    call cg_write
    ; Write register name based on r14 (register index)
    mov edi, r14d
    call cg_write_argreg
    lea rsi, [rel cg_newline]
    mov rdx, 1
    call cg_write
    pop rbx
    inc r14d                        ; next register
    jmp cg_ef_store_param_next

cg_ef_store_str_param:
    ; 16-byte: store ptr at [rbp-(offset)], len at [rbp-(offset-8)]
    ; ptr register = r14, len register = r14+1
    push rbx
    push rcx
    ; Store ptr: mov [rbp - (offset)], REG
    lea rsi, [rel cg_mov_rbp_neg]
    mov rdx, cg_mov_rbp_neg_len
    call cg_write
    pop rcx
    push rcx
    mov eax, ecx                    ; offset = len position
    ; ptr is at offset-8 for the convention: extra points to end of slot
    ; Actually let's store ptr at lower address: [rbp - offset] = ptr, [rbp - (offset-8)] = len
    call cg_write_int
    lea rsi, [rel cg_comma_space]
    mov rdx, cg_comma_space_len
    call cg_write
    mov edi, r14d
    call cg_write_argreg
    lea rsi, [rel cg_newline]
    mov rdx, 1
    call cg_write
    inc r14d
    ; Store len
    lea rsi, [rel cg_mov_rbp_neg]
    mov rdx, cg_mov_rbp_neg_len
    call cg_write
    pop rcx
    mov eax, ecx
    sub eax, 8                      ; len at offset-8
    call cg_write_int
    lea rsi, [rel cg_comma_space]
    mov rdx, cg_comma_space_len
    call cg_write
    mov edi, r14d
    call cg_write_argreg
    lea rsi, [rel cg_newline]
    mov rdx, 1
    call cg_write
    inc r14d
    pop rbx
    jmp cg_ef_store_param_next

cg_ef_store_param_next:
    ; Follow sibling chain
    mov eax, ebx
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    mov ebx, [rdi + rax + 20]
    inc r15d
    jmp cg_ef_store_params

cg_ef_store_done:
    ; Emit body block
    mov r13d, [r12 + 28]
    cmp r13d, NO_CHILD
    je cg_ef_epilogue
    mov edi, r13d
    call cg_emit_block

cg_ef_epilogue:
    lea rsi, [rel cg_epilogue]
    mov rdx, cg_epilogue_len
    call cg_write
    lea rsi, [rel cg_newline]
    mov rdx, 1
    call cg_write

    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ============================================================
; cg_assign_let_slots — walk block children, assign stack offsets to LETs
; Input: edi = block node index, r14d = current offset
; Output: r14d updated with new offset after all let bindings
; ============================================================
cg_assign_let_slots:
    push rbx
    push r12

    ; Get block node
    mov eax, edi
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax
    mov r12d, [rbx + 16]           ; first_child

cg_als_loop:
    cmp r12d, NO_CHILD
    je cg_als_done

    mov eax, r12d
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax

    movzx eax, byte [rbx]
    cmp eax, NODE_LET
    jne cg_als_next

    ; Found a LET — assign stack slot
    mov eax, [rbx + 24]            ; type_info
    cmp eax, TYPE_STRING
    je cg_als_let_16
    cmp eax, TYPE_ARRAY
    je cg_als_let_16

    ; 8-byte let binding
    add r14d, 8
    mov [rbx + 28], r14d            ; extra = offset
    jmp cg_als_next

cg_als_let_16:
    add r14d, 16
    mov [rbx + 28], r14d
    jmp cg_als_next

cg_als_next:
    mov r12d, [rbx + 20]           ; next_sibling
    jmp cg_als_loop

cg_als_done:
    pop r12
    pop rbx
    ret

; ============================================================
; cg_write_argreg — emit register name for AMD64 arg position
; Input: edi = register index (0=rdi, 1=rsi, 2=rdx, 3=rcx, 4=r8, 5=r9)
; ============================================================
cg_write_argreg:
    cmp edi, 0
    je cg_war_rdi
    cmp edi, 1
    je cg_war_rsi
    cmp edi, 2
    je cg_war_rdx
    cmp edi, 3
    je cg_war_rcx
    cmp edi, 4
    je cg_war_r8
    cmp edi, 5
    je cg_war_r9
    ; Fallback
    lea rsi, [rel cg_reg_rdi]
    mov rdx, 3
    jmp cg_write
cg_war_rdi:
    lea rsi, [rel cg_reg_rdi]
    mov rdx, 3
    jmp cg_write
cg_war_rsi:
    lea rsi, [rel cg_reg_rsi]
    mov rdx, 3
    jmp cg_write
cg_war_rdx:
    lea rsi, [rel cg_reg_rdx]
    mov rdx, 3
    jmp cg_write
cg_war_rcx:
    lea rsi, [rel cg_reg_rcx]
    mov rdx, 3
    jmp cg_write
cg_war_r8:
    lea rsi, [rel cg_reg_r8]
    mov rdx, 2
    jmp cg_write
cg_war_r9:
    lea rsi, [rel cg_reg_r9]
    mov rdx, 2
    jmp cg_write

; ============================================================
; cg_emit_block — emit a BLOCK node's children
; Input: edi = BLOCK node index
; ============================================================
cg_emit_block:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    ; Get block node
    mov eax, edi
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax                    ; rbx = block node

    ; Walk children via sibling chain
    mov r12d, [rbx + 16]           ; first_child

cg_eb_loop:
    cmp r12d, NO_CHILD
    je cg_eb_done

    ; Get child node
    mov eax, r12d
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax

    movzx eax, byte [rbx]          ; node_type

    cmp eax, NODE_EXPR_STMT
    je cg_eb_expr_stmt
    cmp eax, NODE_RETURN_EXPR
    je cg_eb_return_expr
    cmp eax, NODE_LET
    je cg_eb_let

    ; Skip unknown
    jmp cg_eb_next

cg_eb_expr_stmt:
    ; Emit the child expression, discard result
    mov edi, [rbx + 16]            ; first_child = the expression
    call cgx_emit_expr
    jmp cg_eb_next

cg_eb_return_expr:
    ; Emit the child expression, leave result in rax
    mov edi, [rbx + 16]
    call cgx_emit_expr
    ; Result stays in rax for function return
    jmp cg_eb_next

cg_eb_let:
    ; Emit initializer expression (result in rax)
    mov edi, [rbx + 16]            ; first_child = initializer
    cmp edi, NO_CHILD
    je cg_eb_next
    push rbx                        ; save current node pointer
    call cgx_emit_expr
    pop rbx

    ; Store rax to stack slot: mov [rbp - offset], rax
    mov ecx, [rbx + 28]            ; extra = stack offset
    cmp ecx, 0
    je cg_eb_next                   ; no slot assigned
    push rbx
    lea rsi, [rel cg_mov_rbp_neg]
    mov rdx, cg_mov_rbp_neg_len
    call cg_write
    mov eax, ecx
    call cg_write_int
    lea rsi, [rel cg_comma_space]
    mov rdx, cg_comma_space_len
    call cg_write
    lea rsi, [rel cg_reg_rax]
    mov rdx, 3
    call cg_write
    lea rsi, [rel cg_newline]
    mov rdx, 1
    call cg_write
    pop rbx
    jmp cg_eb_next

cg_eb_next:
    ; Follow sibling chain
    mov eax, r12d
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax
    mov r12d, [rbx + 20]           ; next_sibling
    jmp cg_eb_loop

cg_eb_done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ============================================================
; Output helpers — buffered writes to stdout
; ============================================================

; cg_write — write bytes to output buffer, flush if needed
; Input: rsi = data pointer, rdx = length
cg_write:
    push rax
    push rcx
    push rdi

    mov rcx, rdx                   ; bytes to write
    mov rdi, [rel cg_outpos]
    lea rax, [rel cg_outbuf]
    add rdi, rax                    ; rdi = write position

    ; Check if buffer has space
    mov rax, [rel cg_outpos]
    add rax, rcx
    cmp rax, 8192
    jge cg_write_flush_first

cg_write_copy:
    cmp rcx, 0
    jle cg_write_done
    movzx eax, byte [rsi]
    mov byte [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jmp cg_write_copy

cg_write_flush_first:
    call cg_flush
    lea rdi, [rel cg_outbuf]
    jmp cg_write_copy

cg_write_done:
    ; Update outpos
    mov rdi, [rel cg_outpos]
    add rdi, rdx
    mov [rel cg_outpos], rdi

    pop rdi
    pop rcx
    pop rax
    ret

; cg_flush — write output buffer to stdout
cg_flush:
    push rax
    push rdi
    push rsi
    push rdx

    mov rdx, [rel cg_outpos]
    cmp rdx, 0
    jle cg_flush_done

    mov rdi, STDOUT
    lea rsi, [rel cg_outbuf]
    mov rax, SYS_WRITE
    syscall

    xor rax, rax
    mov [rel cg_outpos], rax

cg_flush_done:
    pop rdx
    pop rsi
    pop rdi
    pop rax
    ret

; cg_itoa — convert unsigned integer in eax to decimal at [rdi]
; Returns: rcx = length
cg_itoa:
    push rbx
    push rdx
    push rsi
    mov rsi, rdi
    xor ecx, ecx

    cmp eax, 0
    jne cg_itoa_loop
    mov byte [rdi], '0'
    mov ecx, 1
    jmp cg_itoa_done

cg_itoa_loop:
    cmp eax, 0
    je cg_itoa_reverse
    xor edx, edx
    mov ebx, 10
    div ebx
    add dl, '0'
    mov byte [rdi + rcx], dl
    inc ecx
    jmp cg_itoa_loop

cg_itoa_reverse:
    xor edx, edx
    mov ebx, ecx
    dec ebx
cg_itoa_rev:
    cmp edx, ebx
    jge cg_itoa_done
    movzx eax, byte [rsi + rdx]
    movzx r8d, byte [rsi + rbx]
    mov byte [rsi + rdx], r8b
    mov byte [rsi + rbx], al
    inc edx
    dec ebx
    jmp cg_itoa_rev

cg_itoa_done:
    pop rsi
    pop rdx
    pop rbx
    ret

; cg_write_int — write integer eax as decimal to output buffer
cg_write_int:
    push rdi
    push rcx
    lea rdi, [rel cg_itoa_buf]
    call cg_itoa                    ; rcx = length
    lea rsi, [rel cg_itoa_buf]
    mov rdx, rcx
    call cg_write
    pop rcx
    pop rdi
    ret
