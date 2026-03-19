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

    ; Get node pointer
    mov rax, rdi
    imul rax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax                    ; rbx = fn_decl node
    mov r12, rbx                    ; r12 = fn_decl node pointer

    ; Emit label: fn_NAME:
    lea rsi, [rel cg_fn_prefix]
    mov rdx, cg_fn_prefix_len
    call cg_write
    ; Function name from string table
    mov ecx, [r12 + 4]             ; string_ref
    mov edx, [r12 + 8]             ; string_len
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

    ; Reserve stack space: 256 bytes for now (enough for locals)
    ; TODO: calculate actual space needed per function
    lea rsi, [rel cg_sub_rsp]
    mov rdx, cg_sub_rsp_len
    call cg_write
    mov eax, 256
    lea rdi, [rel cg_itoa_buf]
    call cg_itoa
    lea rsi, [rel cg_itoa_buf]
    mov rdx, rcx
    call cg_write
    lea rsi, [rel cg_newline]
    mov rdx, 1
    call cg_write

    ; Get body block node index from extra field
    mov r13d, [r12 + 28]           ; extra = body node index
    cmp r13d, NO_CHILD
    je cg_ef_epilogue

    ; Emit body block
    mov edi, r13d
    call cg_emit_block

cg_ef_epilogue:
    ; Emit epilogue
    lea rsi, [rel cg_epilogue]
    mov rdx, cg_epilogue_len
    call cg_write
    lea rsi, [rel cg_newline]
    mov rdx, 1
    call cg_write

    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

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
    ; TODO: M1.6 handles let bindings with stack slots
    ; For now just emit the initializer (value in rax, discarded)
    mov edi, [rbx + 16]            ; first_child = initializer
    cmp edi, NO_CHILD
    je cg_eb_next
    call cgx_emit_expr
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
