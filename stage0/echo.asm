; echo.asm — Milestone 0.0
; Read a file (path from argv[1]), write contents to stdout, exit cleanly.
; No libc. Direct Linux syscalls via syscall instruction.
;
; Build: nasm -f elf64 -o echo.o echo.asm && ld -o echo echo.o
; Usage: ./echo <filename>
;
; Syscall numbers (x86-64 Linux):
;   read  = 0    (rdi=fd, rsi=buf, rdx=count)
;   write = 1    (rdi=fd, rsi=buf, rdx=count)
;   open  = 2    (rdi=path, rsi=flags, rdx=mode)
;   close = 3    (rdi=fd)
;   exit  = 60   (rdi=status)
;
; AMD64 System V ABI:
;   syscall args: rdi, rsi, rdx, r10, r8, r9
;   return value in rax
;   On program entry: [rsp]=argc, [rsp+8]=argv[0], [rsp+16]=argv[1], ...

section .bss
    buf resb 8192               ; 8KB read buffer

section .data
    err_usage db "usage: echo <filename>", 10
    err_usage_len equ $ - err_usage
    err_open db "error: could not open file", 10
    err_open_len equ $ - err_open

section .text
    global _start

_start:
    ; argc is at [rsp], argv[1] is at [rsp+16]
    mov rax, [rsp]              ; rax = argc
    cmp rax, 2                  ; need exactly 2 args (program name + filename)
    jl .usage_error             ; too few args

    ; Open the file
    mov rdi, [rsp + 16]         ; rdi = argv[1] (filename pointer)
    xor rsi, rsi                ; rsi = O_RDONLY (0)
    xor rdx, rdx                ; rdx = mode (unused for O_RDONLY)
    mov rax, 2                  ; syscall: open
    syscall
    cmp rax, 0                  ; check for error (negative = errno)
    jl .open_error
    mov r12, rax                ; r12 = file descriptor (callee-saved)

.read_loop:
    ; Read a chunk from the file
    mov rdi, r12                ; rdi = fd
    lea rsi, [rel buf]          ; rsi = buffer address
    mov rdx, 8192               ; rdx = max bytes to read
    mov rax, 0                  ; syscall: read
    syscall
    cmp rax, 0                  ; 0 = EOF, negative = error
    jle .done_reading           ; EOF or error — stop
    mov r13, rax                ; r13 = bytes actually read

    ; Write that chunk to stdout
    mov rdi, 1                  ; rdi = stdout (fd 1)
    lea rsi, [rel buf]          ; rsi = buffer address
    mov rdx, r13                ; rdx = number of bytes to write
    mov rax, 1                  ; syscall: write
    syscall

    jmp .read_loop              ; read next chunk

.done_reading:
    ; Close the file
    mov rdi, r12                ; rdi = fd
    mov rax, 3                  ; syscall: close
    syscall

    ; Exit successfully
    xor rdi, rdi                ; rdi = 0 (exit code)
    mov rax, 60                 ; syscall: exit
    syscall

.usage_error:
    ; Write usage message to stderr
    mov rdi, 2                  ; rdi = stderr (fd 2)
    lea rsi, [rel err_usage]
    mov rdx, err_usage_len
    mov rax, 1                  ; syscall: write
    syscall
    mov rdi, 1                  ; exit code 1
    mov rax, 60                 ; syscall: exit
    syscall

.open_error:
    ; Write error message to stderr
    mov rdi, 2                  ; rdi = stderr (fd 2)
    lea rsi, [rel err_open]
    mov rdx, err_open_len
    mov rax, 1                  ; syscall: write
    syscall
    mov rdi, 1                  ; exit code 1
    mov rax, 60                 ; syscall: exit
    syscall
