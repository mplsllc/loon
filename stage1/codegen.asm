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

cg_start_code:
    db "_start:", 10
    db "    mov rax, [rsp]", 10             ; argc
    db "    mov [_argc], rax", 10
    db "    lea rax, [rsp+8]", 10           ; pointer to argv array
    db "    mov [_argv], rax", 10
    db "    lea rsp, [_big_stack + 8388608]", 10  ; switch to 8MB stack
    db "    and rsp, -16", 10               ; align
    db "    call fn_main", 10
    db "    xor rdi, rdi", 10
    db "    mov rax, 60", 10
    db "    syscall", 10
cg_start_code_len equ $ - cg_start_code

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

; Array operations
cg_as_load_r10:     db "    mov r10, qword [rbp-"
cg_as_load_r10_len  equ $ - cg_as_load_r10
cg_as_load_r11:     db "    mov r11, qword [rbp-"
cg_as_load_r11_len  equ $ - cg_as_load_r11
cg_as_store:
    db "    pop rcx", 10
    db "    mov qword [r10 + rcx*8], rax", 10
cg_as_store_len     equ $ - cg_as_store
cg_as_push_r10:     db "    push r10", 10
cg_as_push_r10_len  equ $ - cg_as_push_r10
cg_as_store_full:
    db "    pop r10", 10
    db "    pop rcx", 10
    db "    mov qword [r10 + rcx*8], rax", 10
cg_as_store_full_len equ $ - cg_as_store_full
cg_as_store_idx_ptr:
    db "    pop rcx", 10
    db "    pop r10", 10
    db "    mov qword [r10 + rcx*8], rax", 10
cg_as_store_idx_ptr_len equ $ - cg_as_store_idx_ptr

; Section headers
cg_section_data:    db "section .data", 10
cg_section_data_len equ $ - cg_section_data
cg_section_bss:     db "section .bss", 10
cg_section_bss_len  equ $ - cg_section_bss

; String literal labels
cg_str_label:       db "    _s"
cg_str_label_len    equ $ - cg_str_label
cg_str_db:          db '    db "'
cg_str_db_len       equ $ - cg_str_db
cg_str_db_end:      db '"', 10
cg_str_db_end_len   equ $ - cg_str_db_end
cg_str_len_label:   db "    _s"
cg_str_len_lbl_len  equ $ - cg_str_len_label
cg_str_len_equ:     db "_len equ "
cg_str_len_equ_len  equ $ - cg_str_len_equ

; Bump heap in compiled output
cg_bump_heap_decl:  db "    _bump_heap resb 16777216", 10
cg_bump_heap_len    equ $ - cg_bump_heap_decl
cg_bump_pos_decl:   db "    _bump_pos  dq _bump_heap", 10
cg_bump_pos_len     equ $ - cg_bump_pos_decl
cg_newline_byte:    db "    _newline_byte db 10", 10
cg_newline_byte_len equ $ - cg_newline_byte

; Big stack for deep recursion in compiled programs
cg_big_stack_decl: db "    _big_stack resb 8388608", 10
cg_big_stack_len   equ $ - cg_big_stack_decl

; Argv globals in compiled output
cg_argv_decl:
    db "    _argc resq 1", 10
    db "    _argv resq 1", 10
cg_argv_decl_len equ $ - cg_argv_decl

; Runtime function labels
cg_rt_print_label:      db "fn_print:", 10
cg_rt_print_label_len   equ $ - cg_rt_print_label
cg_rt_print_raw_label:  db "fn_print_raw:", 10
cg_rt_print_raw_label_len equ $ - cg_rt_print_raw_label
cg_rt_int_to_string_label: db "fn_int_to_string:", 10
cg_rt_int_to_string_label_len equ $ - cg_rt_int_to_string_label
cg_rt_string_length_label: db "fn_string_length:", 10
cg_rt_string_length_label_len equ $ - cg_rt_string_length_label
cg_rt_string_equals_label: db "fn_string_equals:", 10
cg_rt_string_equals_label_len equ $ - cg_rt_string_equals_label
cg_rt_string_concat_label: db "fn_string_concat:", 10
cg_rt_string_concat_label_len equ $ - cg_rt_string_concat_label

section .bss
cg_outbuf   resb 65536     ; output buffer (64KB)
cg_outpos   resq 1         ; current write position in output buffer
cg_itoa_buf resb 32        ; scratch for number→string
cg_str_lit_count resq 1    ; number of string literals emitted in .data
; Map: string literal node index → str_lit label number
; (we assign label numbers sequentially as we encounter STR_LIT nodes)
cg_str_lit_map resb 65536  ; 16384 nodes * 4 bytes = node_index → label_number
cg_fn_boundary resq 1     ; boundary: next FN_DECL node index (for slot walker)

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

    ; Initialize output buffer and string literal counter
    xor rax, rax
    mov [rel cg_outpos], rax
    mov [rel cg_str_lit_count], rax

    ; Emit: section .data (string literals + runtime data)
    call cg_emit_data_section

    ; Emit: section .bss (bump heap)
    call cg_emit_bss_section

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

    ; Find boundary: next FN_DECL node or node_count
    push r12
    push r13
    mov r13, r12
    inc r13
.cg_find_boundary:
    cmp r13, [rel node_count]
    jge .cg_boundary_found
    mov rax, r13
    imul rax, NODE_SIZE
    lea rcx, [rel nodes]
    movzx eax, byte [rcx + rax]
    cmp eax, NODE_FN_DECL
    je .cg_boundary_found
    inc r13
    jmp .cg_find_boundary
.cg_boundary_found:
    mov [rel cg_fn_boundary], r13   ; store boundary globally
    pop r13
    pop r12

    ; Emit this function
    mov rdi, r12                    ; pass node index
    call cg_emit_fn

cg_ep_next:
    inc r12
    jmp cg_ep_walk

cg_ep_funcs_done:
    ; Emit _start (saves argc/argv, aligns stack, calls main, exits 0)
    lea rsi, [rel cg_start_code]
    mov rdx, cg_start_code_len
    call cg_write

    ; Emit runtime builtins
    call cg_emit_runtime

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
    mov [rel cur_fn_index], rdi    ; store current function index
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
    mov eax, r13d
    mov [rel cur_fn_body], rax     ; store for scoped var lookup
    cmp r13d, NO_CHILD
    je cg_ef_prepass_done
    mov edi, r13d
    ; boundary already set in cg_fn_boundary by caller
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

    ; 8-byte param: mov [rbp - offset], REG (first of the pair)
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
    add r14d, 2                     ; skip pair (caller pushes 16 bytes per arg)
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
; cg_assign_let_slots — walk block children, assign stack offsets
; Handles: NODE_LET, NODE_FOR (loop var + end temp), NODE_ARRAY_SET
; Recurses into nested blocks (for bodies, match arms)
; Input: edi = block node index, r14d = current offset
; Output: r14d updated
; ============================================================
; ============================================================
; cg_assign_let_slots — walk a BLOCK's children via sibling chain
; For each child: if LET → assign slot. If it contains a nested
; BLOCK (via FOR body, MATCH arm), recurse into that BLOCK.
; Input: edi = BLOCK node index
; Uses r14d as the running stack offset (shared across calls)
; ============================================================
cg_assign_let_slots:
    push rbx
    push r12

    ; Get the BLOCK node
    mov eax, edi
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax
    mov r12d, [rbx + 16]           ; first_child of BLOCK

cg_als_loop:
    cmp r12d, NO_CHILD
    je cg_als_done
    cmp r12, [rel cg_fn_boundary] ; boundary check
    jge cg_als_done

    mov eax, r12d
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax
    movzx eax, byte [rbx]

    cmp eax, NODE_LET
    je cg_als_let
    cmp eax, NODE_EXPR_STMT
    je cg_als_walk_child
    cmp eax, NODE_RETURN_EXPR
    je cg_als_walk_child
    cmp eax, NODE_ARRAY_SET
    je cg_als_next
    jmp cg_als_next

cg_als_let:
    mov eax, [rbx + 24]
    cmp eax, TYPE_STRING
    je cg_als_let_16
    cmp eax, TYPE_ARRAY
    je cg_als_let_16
    add r14d, 8
    mov [rbx + 28], r14d
    ; Also walk the initializer for nested blocks
    jmp cg_als_walk_child
cg_als_let_16:
    add r14d, 16
    mov [rbx + 28], r14d
    jmp cg_als_walk_child

cg_als_walk_child:
    ; Depth-first walk of this node's subtree to find nested FOR/MATCH/BLOCK
    mov edi, [rbx + 16]            ; first_child
    call cg_als_walk_expr
    jmp cg_als_next

cg_als_next:
    mov eax, r12d
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    mov r12d, [rbx + rax + 20]     ; next_sibling
    jmp cg_als_loop

cg_als_done:
    pop r12
    pop rbx
    ret

; ============================================================
; cg_als_walk_expr — walk an expression tree depth-first
; Finds FOR, MATCH, BLOCK nodes and handles them
; Does NOT follow next_sibling (to avoid escaping into the
; parent's sibling chain). Only follows first_child.
; Input: edi = node index
; ============================================================
cg_als_walk_expr:
    push rbx
    push r12

    mov r12d, edi
    cmp r12d, NO_CHILD
    je cg_alw_done
    cmp r12, [rel cg_fn_boundary] ; boundary check
    jge cg_alw_done

    mov eax, r12d
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax
    movzx eax, byte [rbx]

    cmp eax, NODE_FOR
    je cg_alw_for
    cmp eax, NODE_MATCH
    je cg_alw_match
    cmp eax, NODE_BLOCK
    je cg_alw_block

    ; Walk first_child only for expression nodes
    ; (next_sibling handled by parent block/for/match iteration)
    mov edi, [rbx + 16]
    call cg_als_walk_expr
    jmp cg_alw_done

cg_alw_for:
    ; Assign 2 slots for FOR
    add r14d, 8
    mov [rbx + 28], r14d           ; loop var
    add r14d, 8                    ; end value cache
    ; Walk FOR children: start, end, body
    ; Children linked via first_child → next_sibling chain
    mov edi, [rbx + 16]            ; first_child = start expr
    call cg_als_walk_expr          ; walk start (probably no nested blocks)
    ; Get end expr (start.next_sibling)
    mov eax, [rbx + 16]
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    mov eax, [rdi + rax + 20]      ; end expr index
    push rax                       ; save end index
    mov edi, eax
    call cg_als_walk_expr          ; walk end
    ; Get body (end.next_sibling)
    pop rax
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    mov edi, [rdi + rax + 20]      ; body BLOCK index
    cmp edi, NO_CHILD
    je cg_alw_done
    ; Recurse into body BLOCK
    call cg_assign_let_slots
    jmp cg_alw_done

cg_alw_match:
    ; Walk match arms — each arm's body might contain blocks
    ; Match discriminant is in extra field, arms are in child chain
    mov r12d, [rbx + 16]           ; first arm
cg_alw_match_arm:
    cmp r12d, NO_CHILD
    je cg_alw_done
    mov eax, r12d
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax
    ; Arm body is first_child
    mov edi, [rbx + 16]
    push r12
    call cg_als_walk_expr          ; walk arm body (may find BLOCK)
    pop r12
    ; Next arm
    mov eax, r12d
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    mov r12d, [rbx + rax + 20]
    jmp cg_alw_match_arm

cg_alw_block:
    ; Found a nested BLOCK — recurse with the BLOCK walker
    mov edi, r12d
    call cg_assign_let_slots
    jmp cg_alw_done

cg_alw_done:
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
    cmp eax, NODE_ARRAY_SET
    je cg_eb_array_set

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
    ; For Array/String types, also store rdx (len) at offset-8
    mov eax, [rbx + 24]            ; type_info
    cmp eax, TYPE_ARRAY
    je cg_eb_let_store_rdx
    cmp eax, TYPE_STRING
    je cg_eb_let_store_rdx
    jmp cg_eb_next
cg_eb_let_store_rdx:
    mov ecx, [rbx + 28]            ; offset
    sub ecx, 8                     ; len goes at offset-8
    push rbx
    lea rsi, [rel cg_mov_rbp_neg]
    mov rdx, cg_mov_rbp_neg_len
    call cg_write
    mov eax, ecx
    call cg_write_int
    lea rsi, [rel cg_comma_space]
    mov rdx, cg_comma_space_len
    call cg_write
    lea rsi, [rel cg_reg_rdx]
    mov rdx, 3
    call cg_write
    lea rsi, [rel cg_newline]
    mov rdx, 1
    call cg_write
    pop rbx
    jmp cg_eb_next

cg_eb_array_set:
    ; NODE_ARRAY_SET: string_ref = array name
    ; first_child = index expr, second child = value expr
    ; 1. Load array (ptr, len) from stack
    ; 2. Evaluate index expr → push index
    ; 3. Evaluate value expr → value in rax
    ; 4. Pop index → compute address → store
    push rbx

    ; Load array ptr and len from named variable
    mov edi, [rbx + 4]             ; array name string_ref
    mov esi, [rbx + 8]             ; array name string_len
    call cgx_find_var_offset        ; eax = offset, r11d = type

    ; Emit: mov r10, [rbp - offset]  (array ptr)
    push rax
    lea rsi, [rel cg_as_load_r10]
    mov rdx, cg_as_load_r10_len
    call cg_write
    pop rax
    push rax
    call cg_write_int
    lea rsi, [rel cg_close_bracket]
    mov rdx, cg_close_bracket_len
    call cg_write

    ; Emit: mov r11, [rbp - (offset-8)]  (array len, for bounds check)
    lea rsi, [rel cg_as_load_r11]
    mov rdx, cg_as_load_r11_len
    call cg_write
    pop rax
    sub eax, 8
    call cg_write_int
    lea rsi, [rel cg_close_bracket]
    mov rdx, cg_close_bracket_len
    call cg_write

    pop rbx                         ; restore ARRAY_SET node

    ; Save r10 (array ptr) BEFORE evaluating index expression
    ; (index expr like g[5] clobbers r10 via ARRAY_GET)
    lea rsi, [rel cg_as_push_r10]
    mov rdx, cg_as_push_r10_len
    call cg_write

    ; Evaluate index expression
    mov edi, [rbx + 16]            ; first_child = index
    push rbx
    call cgx_emit_expr              ; index in rax

    ; Push index
    lea rsi, [rel cgm_push_rax]
    mov rdx, cgm_push_rax_len
    call cg_write

    ; Get second child (value) — sibling of index
    pop rbx
    mov eax, [rbx + 16]            ; first_child = index node
    imul eax, NODE_SIZE
    lea rdi, [rel nodes]
    mov edi, [rdi + rax + 20]      ; index.next_sibling = value node
    push rbx
    call cgx_emit_expr              ; value in rax
    pop rbx

    ; Stack state: [top] index_value, target_ptr [bottom]
    ; Emit: pop rcx (index); pop r10 (target ptr); mov [r10+rcx*8], rax
    lea rsi, [rel cg_as_store_idx_ptr]
    mov rdx, cg_as_store_idx_ptr_len
    call cg_write

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
; cg_emit_data_section — emit .data with string literals
; Walk all AST nodes, find NODE_STR_LIT, emit each as a label
; ============================================================
cg_emit_data_section:
    push rbx
    push r12
    push r13

    lea rsi, [rel cg_section_data]
    mov rdx, cg_section_data_len
    call cg_write

    ; Emit newline byte constant (used by print)
    lea rsi, [rel cg_newline_byte]
    mov rdx, cg_newline_byte_len
    call cg_write

    ; Emit bump_pos (initialized to bump_heap address)
    lea rsi, [rel cg_bump_pos_decl]
    mov rdx, cg_bump_pos_len
    call cg_write

    ; Walk all nodes for STR_LIT
    xor r12d, r12d                  ; node index
    xor r13d, r13d                  ; string literal counter

cg_eds_loop:
    cmp r12, [rel node_count]
    jge cg_eds_done

    mov eax, r12d
    imul eax, NODE_SIZE
    lea rbx, [rel nodes]
    add rbx, rax

    movzx eax, byte [rbx]
    cmp eax, NODE_STR_LIT
    jne cg_eds_next

    ; Found a STR_LIT — emit: _sN db "contents"\n  _sN_len equ N
    ; Store mapping: node index → label number
    mov eax, r12d
    lea rdi, [rel cg_str_lit_map]
    mov dword [rdi + rax*4], r13d

    ; Emit: _sN db "..."
    ; Label: _sN:  (but we use  _sN  db  "..." format for NASM)
    lea rsi, [rel cg_str_label]
    mov rdx, cg_str_label_len
    call cg_write
    mov eax, r13d
    call cg_write_int
    lea rsi, [rel cg_str_db]       ; ' db "'
    mov rdx, cg_str_db_len
    call cg_write

    ; Write the actual string bytes from the string table
    mov ecx, [rbx + 4]             ; string_ref
    mov edx, [rbx + 8]             ; string_len
    lea rsi, [rel strings]
    add rsi, rcx
    call cg_write

    ; Close quote + newline
    lea rsi, [rel cg_str_db_end]
    mov rdx, cg_str_db_end_len
    call cg_write

    ; Emit: _sN_len equ N
    lea rsi, [rel cg_str_label]
    mov rdx, cg_str_label_len
    call cg_write
    mov eax, r13d
    call cg_write_int
    lea rsi, [rel cg_str_len_equ]
    mov rdx, cg_str_len_equ_len
    call cg_write
    mov eax, [rbx + 8]             ; string_len
    call cg_write_int
    lea rsi, [rel cg_newline]
    mov rdx, 1
    call cg_write

    inc r13d                        ; next label number

cg_eds_next:
    inc r12
    jmp cg_eds_loop

cg_eds_done:
    mov [rel cg_str_lit_count], r13
    lea rsi, [rel cg_newline]
    mov rdx, 1
    call cg_write

    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; cg_emit_bss_section — emit .bss with bump heap
; ============================================================
cg_emit_bss_section:
    lea rsi, [rel cg_section_bss]
    mov rdx, cg_section_bss_len
    call cg_write
    lea rsi, [rel cg_bump_heap_decl]
    mov rdx, cg_bump_heap_len
    call cg_write
    lea rsi, [rel cg_big_stack_decl]
    mov rdx, cg_big_stack_len
    call cg_write
    lea rsi, [rel cg_argv_decl]
    mov rdx, cg_argv_decl_len
    call cg_write
    lea rsi, [rel cg_newline]
    mov rdx, 1
    call cg_write
    ret

; ============================================================
; cg_emit_runtime — emit runtime builtin functions
; These are NASM functions included in the compiled output
; ============================================================
cg_emit_runtime:
    push rbx

    ; --- fn_print: write(1, ptr=rdi, len=rsi) then write(1, newline, 1) ---
    lea rsi, [rel cg_rt_print]
    mov rdx, cg_rt_print_len
    call cg_write

    ; --- fn_print_raw: write(1, ptr=rdi, len=rsi) ---
    lea rsi, [rel cg_rt_print_raw]
    mov rdx, cg_rt_print_raw_len
    call cg_write

    ; --- fn_int_to_string: rdi=int, returns rax=ptr, rdx=len ---
    lea rsi, [rel cg_rt_int_to_string]
    mov rdx, cg_rt_int_to_string_len
    call cg_write

    ; --- fn_string_length: rdi=ptr, rsi=len, returns rax=len ---
    lea rsi, [rel cg_rt_string_length]
    mov rdx, cg_rt_string_length_len
    call cg_write

    ; --- fn_string_concat: rdi=ptr1, rsi=len1, rdx=ptr2, rcx=len2 ---
    lea rsi, [rel cg_rt_string_concat]
    mov rdx, cg_rt_string_concat_len
    call cg_write

    ; --- fn_get_arg: rdi=n, returns rax=ptr, rdx=len ---
    lea rsi, [rel cg_rt_get_arg]
    mov rdx, cg_rt_get_arg_len
    call cg_write

    ; --- fn_read_file: rdi=path_ptr, rsi=path_len, returns rax=ptr, rdx=len ---
    lea rsi, [rel cg_rt_read_file]
    mov rdx, cg_rt_read_file_len
    call cg_write

    ; --- fn_print_byte: rdi=byte value, writes one byte to stdout ---
    lea rsi, [rel cg_rt_print_byte]
    mov rdx, cg_rt_print_byte_len
    call cg_write

    ; --- fn_string_char_at: rdi=str_ptr, rsi=str_len, rdx=index, returns rax=byte ---
    lea rsi, [rel cg_rt_string_char_at]
    mov rdx, cg_rt_string_char_at_len
    call cg_write

    ; --- fn_string_equals: rdi=ptr1, rsi=len1, rdx=ptr2, rcx=len2, returns rax=0/1 ---
    lea rsi, [rel cg_rt_string_equals]
    mov rdx, cg_rt_string_equals_len
    call cg_write

    pop rbx
    ret

section .data
; Runtime function implementations as literal NASM text
; Each is a complete function emitted into the compiled binary

cg_rt_print:
    db "fn_print:", 10
    db "    push rdi", 10
    db "    push rsi", 10
    db "    mov rdx, rsi", 10       ; len
    db "    mov rsi, rdi", 10       ; ptr
    db "    mov rdi, 1", 10         ; stdout
    db "    mov rax, 1", 10         ; write
    db "    syscall", 10
    db "    mov rdi, 1", 10
    db "    lea rsi, [rel _newline_byte]", 10
    db "    mov rdx, 1", 10
    db "    mov rax, 1", 10
    db "    syscall", 10
    db "    pop rsi", 10
    db "    pop rdi", 10
    db "    ret", 10, 10
cg_rt_print_len equ $ - cg_rt_print

cg_rt_print_raw:
    db "fn_print_raw:", 10
    db "    mov rdx, rsi", 10
    db "    mov rsi, rdi", 10
    db "    mov rdi, 1", 10
    db "    mov rax, 1", 10
    db "    syscall", 10
    db "    ret", 10, 10
cg_rt_print_raw_len equ $ - cg_rt_print_raw

cg_rt_int_to_string:
    db "fn_int_to_string:", 10
    db "    push rbp", 10
    db "    mov rbp, rsp", 10
    db "    sub rsp, 32", 10        ; local buffer
    db "    mov r8, rdi", 10        ; save original value
    db "    lea r9, [rbp-1]", 10    ; write position (end of buffer, backwards)
    db "    xor ecx, ecx", 10      ; digit count
    db "    cmp rdi, 0", 10
    db "    jge .its_pos", 10
    db "    neg rdi", 10
    db ".its_pos:", 10
    db "    cmp rdi, 0", 10
    db "    jne .its_loop", 10
    db "    mov byte [r9], '0'", 10
    db "    inc ecx", 10
    db "    dec r9", 10
    db "    jmp .its_sign", 10
    db ".its_loop:", 10
    db "    cmp rdi, 0", 10
    db "    je .its_sign", 10
    db "    xor edx, edx", 10
    db "    mov rax, rdi", 10
    db "    mov rbx, 10", 10
    db "    div rbx", 10
    db "    add dl, '0'", 10
    db "    mov byte [r9], dl", 10
    db "    dec r9", 10
    db "    inc ecx", 10
    db "    mov rdi, rax", 10
    db "    jmp .its_loop", 10
    db ".its_sign:", 10
    db "    cmp r8, 0", 10
    db "    jge .its_done", 10
    db "    mov byte [r9], '-'", 10
    db "    dec r9", 10
    db "    inc ecx", 10
    db ".its_done:", 10
    db "    ; Copy to bump heap", 10
    db "    mov rsi, [rel _bump_pos]", 10
    db "    lea rdi, [r9+1]", 10    ; start of digits
    db "    mov rdx, rcx", 10       ; length
    db "    push rcx", 10           ; save length
    db "    ; memcpy rsi=src→rdi=dst? No: rdi=dest, rsi=src for rep movsb", 10
    db "    mov rdi, [rel _bump_pos]", 10
    db "    lea rsi, [r9+1]", 10
    db "    mov rcx, rdx", 10
    db "    rep movsb", 10
    db "    pop rcx", 10
    db "    mov rax, [rel _bump_pos]", 10  ; return ptr
    db "    mov rdx, rcx", 10       ; return len
    db "    add qword [rel _bump_pos], rcx", 10
    db "    mov rsp, rbp", 10
    db "    pop rbp", 10
    db "    ret", 10, 10
cg_rt_int_to_string_len equ $ - cg_rt_int_to_string

cg_rt_string_length:
    db "fn_string_length:", 10
    db "    mov rax, rsi", 10       ; len is in rsi (second part of String param)
    db "    ret", 10, 10
cg_rt_string_length_len equ $ - cg_rt_string_length

cg_rt_string_concat:
    db "fn_string_concat:", 10
    db "    ; rdi=ptr1, rsi=len1, rdx=ptr2, rcx=len2", 10
    db "    push rbp", 10
    db "    mov rbp, rsp", 10
    db "    push rdi", 10           ; save ptr1
    db "    push rsi", 10           ; save len1
    db "    push rdx", 10           ; save ptr2
    db "    push rcx", 10           ; save len2
    db "    ; Total length", 10
    db "    mov rax, rsi", 10
    db "    add rax, rcx", 10       ; total = len1 + len2
    db "    ; Allocate from bump heap", 10
    db "    mov r8, [rel _bump_pos]", 10
    db "    add [rel _bump_pos], rax", 10
    db "    ; Copy first string", 10
    db "    mov rdi, r8", 10        ; dest
    db "    mov rsi, [rbp-8]", 10   ; ptr1
    db "    mov rcx, [rbp-16]", 10  ; len1
    db "    rep movsb", 10
    db "    ; Copy second string", 10
    db "    mov rsi, [rbp-24]", 10  ; ptr2
    db "    mov rcx, [rbp-32]", 10  ; len2
    db "    rep movsb", 10
    db "    ; Return (ptr, total_len)", 10
    db "    mov rax, r8", 10
    db "    pop rcx", 10            ; len2
    db "    pop rdx", 10            ; ptr2
    db "    pop rsi", 10            ; len1
    db "    pop rdi", 10            ; ptr1
    db "    add rsi, rcx", 10       ; total_len = len1 + len2
    db "    mov rdx, rsi", 10       ; rdx = total length
    db "    mov rsp, rbp", 10
    db "    pop rbp", 10
    db "    ret", 10, 10
cg_rt_string_concat_len equ $ - cg_rt_string_concat

cg_rt_get_arg:
    db "fn_get_arg:", 10
    db "    ; get_arg(n: Int) -> String: returns (ptr, len) from argv[n]", 10
    db "    push rbp", 10
    db "    mov rbp, rsp", 10
    db "    mov rax, [_argv]", 10           ; base of argv array
    db "    mov rax, [rax + rdi*8]", 10     ; argv[n] pointer
    db "    ; compute strlen", 10
    db "    xor rdx, rdx", 10
    db ".ga_len:", 10
    db "    cmp byte [rax + rdx], 0", 10
    db "    je .ga_done", 10
    db "    inc rdx", 10
    db "    jmp .ga_len", 10
    db ".ga_done:", 10
    db "    ; rax=ptr, rdx=len", 10
    db "    mov rsp, rbp", 10
    db "    pop rbp", 10
    db "    ret", 10, 10
cg_rt_get_arg_len equ $ - cg_rt_get_arg

cg_rt_print_byte:
    db "fn_print_byte:", 10
    db "    ; print_byte(byte=rdi): write one byte to stdout", 10
    db "    push rdi", 10
    db "    mov rsi, rsp", 10       ; rsi = pointer to byte on stack
    db "    mov rdx, 1", 10         ; len = 1
    db "    mov rdi, 1", 10         ; stdout
    db "    mov rax, 1", 10         ; write
    db "    syscall", 10
    db "    pop rdi", 10
    db "    ret", 10, 10
cg_rt_print_byte_len equ $ - cg_rt_print_byte

cg_rt_string_char_at:
    db "fn_string_char_at:", 10
    db "    ; string_char_at(str_ptr=rdi, str_len=rsi, index=rdx) -> byte", 10
    db "    movzx rax, byte [rdi + rdx]", 10
    db "    ret", 10, 10
cg_rt_string_char_at_len equ $ - cg_rt_string_char_at

cg_rt_string_equals:
    db "fn_string_equals:", 10
    db "    ; string_equals(ptr1=rdi, len1=rsi, ptr2=rdx, len2=rcx) -> 0/1", 10
    db "    cmp rsi, rcx", 10
    db "    jne .seq_false", 10
    db "    xor r8, r8", 10
    db ".seq_loop:", 10
    db "    cmp r8, rsi", 10
    db "    jge .seq_true", 10
    db "    movzx rax, byte [rdi + r8]", 10
    db "    cmp al, byte [rdx + r8]", 10
    db "    jne .seq_false", 10
    db "    inc r8", 10
    db "    jmp .seq_loop", 10
    db ".seq_true:", 10
    db "    mov rax, 1", 10
    db "    ret", 10
    db ".seq_false:", 10
    db "    xor rax, rax", 10
    db "    ret", 10, 10
cg_rt_string_equals_len equ $ - cg_rt_string_equals

cg_rt_read_file:
    db "fn_read_file:", 10
    db "    ; read_file(path: String) -> String", 10
    db "    ; rdi=path_ptr, rsi=path_len", 10
    db "    ; returns rax=data_ptr, rdx=data_len", 10
    db "    push rbp", 10
    db "    mov rbp, rsp", 10
    db "    push rdi", 10               ; save path_ptr
    db "    push rsi", 10               ; save path_len
    db "    ; Copy path to bump heap and null-terminate for open()", 10
    db "    mov rcx, rsi", 10           ; path_len
    db "    mov r8, [rel _bump_pos]", 10
    db "    mov rdi, r8", 10            ; dest
    db "    ; rsi already points to source (path_ptr was in rdi, but we need rsi=src)", 10
    db "    pop rsi", 10                ; path_len
    db "    pop rdi", 10                ; path_ptr -> now rdi=path_ptr
    db "    push rsi", 10               ; re-save len
    db "    mov rsi, rdi", 10           ; src = path_ptr
    db "    mov rdi, r8", 10            ; dest = bump pos
    db "    pop rcx", 10                ; len
    db "    push rcx", 10               ; save again
    db "    rep movsb", 10
    db "    mov byte [rdi], 0", 10      ; null terminate
    db "    pop rcx", 10                ; path_len
    db "    lea rax, [rcx+1]", 10
    db "    add [rel _bump_pos], rax", 10   ; advance past path+null
    db "    ; open(path, O_RDONLY)", 10
    db "    mov rdi, r8", 10            ; null-terminated path
    db "    xor rsi, rsi", 10           ; O_RDONLY = 0
    db "    xor rdx, rdx", 10
    db "    mov rax, 2", 10             ; SYS_OPEN
    db "    syscall", 10
    db "    cmp rax, 0", 10
    db "    jl .rf_err", 10
    db "    mov r9, rax", 10            ; fd
    db "    ; read into bump heap", 10
    db "    mov r8, [rel _bump_pos]", 10
    db "    mov rdi, r9", 10            ; fd
    db "    mov rsi, r8", 10            ; buffer
    db "    mov rdx, 1048576", 10       ; max read (1MB)
    db "    mov rax, 0", 10             ; SYS_READ
    db "    syscall", 10
    db "    mov r10, rax", 10           ; bytes read
    db "    add [rel _bump_pos], rax", 10
    db "    ; close(fd)", 10
    db "    mov rdi, r9", 10
    db "    mov rax, 3", 10             ; SYS_CLOSE
    db "    syscall", 10
    db "    ; return (ptr, len)", 10
    db "    mov rax, r8", 10
    db "    mov rdx, r10", 10
    db "    mov rsp, rbp", 10
    db "    pop rbp", 10
    db "    ret", 10
    db ".rf_err:", 10
    db "    mov rdi, 1", 10
    db "    mov rax, 60", 10
    db "    syscall", 10, 10
cg_rt_read_file_len equ $ - cg_rt_read_file

section .text

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
    cmp rax, 65536
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
    push rcx                       ; save rcx — write syscall clobbers it
    push rdi
    push rsi
    push rdx
    push r11                       ; save r11 — write syscall clobbers it

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
    pop r11
    pop rdx
    pop rsi
    pop rdi
    pop rcx
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
