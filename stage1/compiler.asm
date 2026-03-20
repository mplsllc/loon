; stage1/compiler.asm — Loon-0 compiler
; Main entry point. Reads token stream from stdin, parses, emits NASM.
;
; Build: nasm -f elf64 -o compiler.o compiler.asm && ld -o compiler compiler.o
; Usage: ./stage0/lexer input.loon | ./stage1/compiler > output.asm
;        ./stage0/lexer input.loon | ./stage1/compiler --dump-ast

%define SYS_WRITE 1
%define SYS_EXIT 60
%define STDERR 2

; ============================================================
; Global buffers and state — shared by all components
; ============================================================
section .bss
    tokens      resb 524288         ; 512KB — token array (20 bytes each, ~26K max)
    nodes       resb 1048576        ; 1MB — AST node array (32 bytes each, ~32K max)
    strings     resb 131072         ; 128KB — string table
    bump_heap   resb 1048576        ; 1MB — runtime bump allocator

    ; Function table — populated by parser first pass for forward calls
    ; Each entry (32 bytes): name_offset(4), name_len(4), param_count(4),
    ;                         node_index(4), return_type(4), padding(12)
    func_table  resb 8192          ; 256 entries × 32 bytes
    func_count  resq 1             ; number of functions found

    tok_count       resq 1          ; number of tokens read
    tok_pos         resq 1          ; parser's current token index
    node_count      resq 1          ; number of AST nodes allocated
    str_pos         resq 1          ; write position in string table
    bump_pos        resq 1          ; write position in bump heap
    label_counter   resq 1          ; codegen: unique label IDs
    dump_ast_flag   resq 1          ; 1 if --dump-ast was passed
    cur_fn_index    resq 1          ; codegen: current FN_DECL node index
    cur_fn_body     resq 1          ; codegen: current body BLOCK node index

section .data
    ; --dump-ast flag string for argv comparison
    main_dump_ast_str: db "--dump-ast", 0
    main_dump_ast_len equ 10

    ; Debug output
    main_tok_count_msg: db "tokens: "
    main_tok_count_msg_len equ $ - main_tok_count_msg
    main_node_count_msg: db "nodes: "
    main_node_count_msg_len equ $ - main_node_count_msg
    main_func_count_msg: db "funcs: "
    main_func_count_msg_len equ $ - main_func_count_msg
    main_newline: db 10

    ; Temp buffer for integer-to-string conversion
section .bss
    main_itoa_buf resb 32

section .text
    global _start

; ============================================================
; _start — entry point
;
; Stack at entry:
;   [rsp]   = argc (8 bytes, load with mov rax, [rsp])
;   [rsp+8] = argv[0] (program name pointer)
;   [rsp+16] = argv[1] (first argument, if argc >= 2)
; ============================================================
_start:
    ; Check for --dump-ast flag
    mov rax, [rsp]                  ; argc
    cmp rax, 2
    jl .no_dump_flag

    ; Compare argv[1] against "--dump-ast" byte by byte
    mov rsi, [rsp + 16]            ; argv[1] pointer
    lea rdi, [rel main_dump_ast_str]
    xor ecx, ecx
.cmp_flag:
    cmp ecx, main_dump_ast_len
    jge .check_null
    movzx eax, byte [rsi + rcx]
    cmp al, byte [rdi + rcx]
    jne .no_dump_flag
    inc ecx
    jmp .cmp_flag
.check_null:
    ; Verify argv[1] is exactly "--dump-ast" (null-terminated)
    movzx eax, byte [rsi + rcx]
    cmp al, 0
    jne .no_dump_flag
    mov qword [rel dump_ast_flag], 1

.no_dump_flag:
    ; Phase 1: Read token stream from stdin
    call tok_read_all

    ; Phase 2: Parse tokens into AST
    call par_parse_program

    ; If --dump-ast, print diagnostics to stderr and exit
    cmp qword [rel dump_ast_flag], 1
    je .dump_ast

    ; Phase 3: Emit NASM assembly to stdout
    call cg_emit_program

    ; Exit 0
    xor rdi, rdi
    mov rax, SYS_EXIT
    syscall

.dump_ast:
    ; Print "tokens: N\n" to stderr
    mov rdi, STDERR
    lea rsi, [rel main_tok_count_msg]
    mov rdx, main_tok_count_msg_len
    mov rax, SYS_WRITE
    syscall
    mov rax, [rel tok_count]
    lea rdi, [rel main_itoa_buf]
    call main_itoa
    mov rdi, STDERR
    lea rsi, [rel main_itoa_buf]
    mov rdx, rcx
    mov rax, SYS_WRITE
    syscall
    mov rdi, STDERR
    lea rsi, [rel main_newline]
    mov rdx, 1
    mov rax, SYS_WRITE
    syscall

    ; Print "nodes: N\n" to stderr
    mov rdi, STDERR
    lea rsi, [rel main_node_count_msg]
    mov rdx, main_node_count_msg_len
    mov rax, SYS_WRITE
    syscall
    mov rax, [rel node_count]
    lea rdi, [rel main_itoa_buf]
    call main_itoa
    mov rdi, STDERR
    lea rsi, [rel main_itoa_buf]
    mov rdx, rcx
    mov rax, SYS_WRITE
    syscall
    mov rdi, STDERR
    lea rsi, [rel main_newline]
    mov rdx, 1
    mov rax, SYS_WRITE
    syscall

    ; Print "funcs: N\n" to stderr
    mov rdi, STDERR
    lea rsi, [rel main_func_count_msg]
    mov rdx, main_func_count_msg_len
    mov rax, SYS_WRITE
    syscall
    mov rax, [rel func_count]
    lea rdi, [rel main_itoa_buf]
    call main_itoa
    mov rdi, STDERR
    lea rsi, [rel main_itoa_buf]
    mov rdx, rcx
    mov rax, SYS_WRITE
    syscall
    mov rdi, STDERR
    lea rsi, [rel main_newline]
    mov rdx, 1
    mov rax, SYS_WRITE
    syscall

    ; Call par_dump_ast to print AST nodes
    call par_dump_ast

    ; Exit 0
    xor rdi, rdi
    mov rax, SYS_EXIT
    syscall

; ============================================================
; main_itoa — convert unsigned integer in rax to decimal at [rdi]
; Returns: rcx = length of string
; ============================================================
main_itoa:
    push rbx
    push rdx
    push rsi
    mov rsi, rdi                   ; save output pointer
    xor ecx, ecx                   ; digit count

    cmp rax, 0
    jne .main_itoa_loop
    mov byte [rdi], '0'
    mov ecx, 1
    jmp .main_itoa_done

.main_itoa_loop:
    cmp rax, 0
    je .main_itoa_reverse
    xor edx, edx
    mov rbx, 10
    div rbx
    add dl, '0'
    mov byte [rdi + rcx], dl
    inc ecx
    jmp .main_itoa_loop

.main_itoa_reverse:
    xor edx, edx                  ; left index
    mov ebx, ecx
    dec ebx                        ; right index
.main_itoa_rev_loop:
    cmp edx, ebx
    jge .main_itoa_done
    movzx eax, byte [rsi + rdx]
    movzx r8d, byte [rsi + rbx]
    mov byte [rsi + rdx], r8b
    mov byte [rsi + rbx], al
    inc edx
    dec ebx
    jmp .main_itoa_rev_loop

.main_itoa_done:
    pop rsi
    pop rdx
    pop rbx
    ret

; ============================================================
; Include components
; ============================================================
%include "token_reader.asm"
%include "parser.asm"
%include "expr_parser.asm"
%include "codegen.asm"
%include "codegen_expr.asm"
%include "codegen_match.asm"
