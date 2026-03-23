; Loon WASM Runtime — linked with compiler output for WASM self-hosting
; Provides: _loon_i64_to_str, _loon_print_byte, _loon_read_file, _loon_get_arg
target triple = "wasm32-wasi"
target datalayout = "e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-n32:64-S128-ni:1:10:20"

; WASI imports
declare i32 @fd_read(i32, i32, i32, i32) #0
attributes #0 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="fd_read" }
declare i32 @args_sizes_get(i32, i32) #1
attributes #1 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="args_sizes_get" }
declare i32 @args_get(i32, i32) #2
attributes #2 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="args_get" }

; WASI fd_write for our write() implementation
declare i32 @fd_write(i32, i32, i32, i32) #3
attributes #3 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="fd_write" }
; WASI proc_exit for exit()
declare void @proc_exit(i32) #4
attributes #4 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="proc_exit" }

; --- Bump allocator (malloc) ---
@_heap = global [33554432 x i8] zeroinitializer  ; 32MB heap
@_heap_pos = global i64 0

define i8* @malloc(i64 %size) {
entry:
  %pos = load i64, i64* @_heap_pos
  %ptr = getelementptr [33554432 x i8], [33554432 x i8]* @_heap, i64 0, i64 %pos
  ; Align to 8 bytes
  %aligned = add i64 %size, 7
  %mask = and i64 %aligned, -8
  %new_pos = add i64 %pos, %mask
  store i64 %new_pos, i64* @_heap_pos
  ret i8* %ptr
}

; --- strlen ---
define i64 @strlen(i8* %s) {
entry:
  br label %loop
loop:
  %i = phi i64 [0, %entry], [%next, %loop]
  %p = getelementptr i8, i8* %s, i64 %i
  %c = load i8, i8* %p
  %done = icmp eq i8 %c, 0
  %next = add i64 %i, 1
  br i1 %done, label %end, label %loop
end:
  ret i64 %i
}

; --- write(fd, ptr, len) via WASI fd_write ---
@_wiov = global [2 x i32] zeroinitializer
@_wnw = global i32 0

define i64 @write(i32 %fd, i8* %ptr, i64 %len) {
entry:
  %p32 = ptrtoint i8* %ptr to i32
  %l32 = trunc i64 %len to i32
  store i32 %p32, i32* getelementptr ([2 x i32], [2 x i32]* @_wiov, i32 0, i32 0)
  store i32 %l32, i32* getelementptr ([2 x i32], [2 x i32]* @_wiov, i32 0, i32 1)
  %ip = ptrtoint [2 x i32]* @_wiov to i32
  %np = ptrtoint i32* @_wnw to i32
  call i32 @fd_write(i32 %fd, i32 %ip, i32 1, i32 %np)
  %nw = load i32, i32* @_wnw
  %nw64 = zext i32 %nw to i64
  ret i64 %nw64
}

; --- exit(code) via WASI proc_exit ---
define void @exit(i32 %code) {
entry:
  call void @proc_exit(i32 %code)
  unreachable
}

; --- sprintf stub (used by int_to_string/float_to_string) ---
; For WASM, int_to_string uses _loon_i64_to_str instead
define i32 @sprintf(i8* %buf, i8* %fmt, ...) {
entry:
  ; Stub — returns 0 (no formatting in WASM mode)
  store i8 48, i8* %buf  ; '0'
  %p1 = getelementptr i8, i8* %buf, i64 1
  store i8 0, i8* %p1    ; null terminate
  ret i32 1
}

; --- strcmp ---
define i32 @strcmp(i8* %a, i8* %b) {
entry:
  br label %loop
loop:
  %i = phi i64 [0, %entry], [%next, %cont]
  %pa = getelementptr i8, i8* %a, i64 %i
  %pb = getelementptr i8, i8* %b, i64 %i
  %ca = load i8, i8* %pa
  %cb = load i8, i8* %pb
  %eq = icmp eq i8 %ca, %cb
  br i1 %eq, label %same, label %diff
same:
  %za = icmp eq i8 %ca, 0
  br i1 %za, label %equal, label %cont
cont:
  %next = add i64 %i, 1
  br label %loop
diff:
  %ai = zext i8 %ca to i32
  %bi = zext i8 %cb to i32
  %r = sub i32 %ai, %bi
  ret i32 %r
equal:
  ret i32 0
}

; --- _loon_i64_to_str: convert i64 to null-terminated decimal string ---
define i8* @_loon_i64_to_str(i64 %val) {
entry:
  %buf = call i8* @malloc(i64 24)
  %is_neg = icmp slt i64 %val, 0
  br i1 %is_neg, label %neg, label %pos
neg:
  %neg_val = sub i64 0, %val
  br label %pos
pos:
  %abs = phi i64 [%val, %entry], [%neg_val, %neg]
  %neg2 = phi i1 [false, %entry], [true, %neg]
  br label %dloop
dloop:
  %n = phi i64 [%abs, %pos], [%nn, %dloop]
  %i = phi i64 [0, %pos], [%ni, %dloop]
  %d = urem i64 %n, 10
  %nn = udiv i64 %n, 10
  %dc = add i64 %d, 48
  %d8 = trunc i64 %dc to i8
  %si = sub i64 22, %i
  %sp = getelementptr i8, i8* %buf, i64 %si
  store i8 %d8, i8* %sp
  %ni = add i64 %i, 1
  %dn = icmp eq i64 %nn, 0
  br i1 %dn, label %fin, label %dloop
fin:
  %st = sub i64 23, %ni
  br i1 %neg2, label %minus, label %cp
minus:
  %mp = sub i64 %st, 1
  %mpp = getelementptr i8, i8* %buf, i64 %mp
  store i8 45, i8* %mpp
  br label %cp
cp:
  %fs = phi i64 [%st, %fin], [%mp, %minus]
  %src = getelementptr i8, i8* %buf, i64 %fs
  %tl = sub i64 23, %fs
  br label %cl
cl:
  %ci = phi i64 [0, %cp], [%cn, %cl]
  %fr = getelementptr i8, i8* %src, i64 %ci
  %to = getelementptr i8, i8* %buf, i64 %ci
  %bv = load i8, i8* %fr
  store i8 %bv, i8* %to
  %cn = add i64 %ci, 1
  %cd = icmp uge i64 %cn, %tl
  br i1 %cd, label %nt, label %cl
nt:
  %np = getelementptr i8, i8* %buf, i64 %tl
  store i8 0, i8* %np
  ret i8* %buf
}

; --- _loon_print_byte: write single byte to stdout ---
@_pb = global [1 x i8] zeroinitializer
define void @_loon_print_byte(i64 %ch) {
  %c8 = trunc i64 %ch to i8
  store i8 %c8, i8* getelementptr ([1 x i8], [1 x i8]* @_pb, i32 0, i32 0)
  %p = getelementptr [1 x i8], [1 x i8]* @_pb, i32 0, i32 0
  call i64 @write(i32 1, i8* %p, i64 1)
  ret void
}

; --- _loon_read_file: read stdin into buffer, return ptr ---
; In WASM mode, ignores the filename argument and reads from stdin (fd 0)
@_riov = global [2 x i32] zeroinitializer
@_rnr = global i32 0
define i8* @_loon_read_file(i64 %ignored) {
entry:
  %buf = call i8* @malloc(i64 524288)
  br label %rl
rl:
  %off = phi i64 [0, %entry], [%noff, %rl]
  %cp = getelementptr i8, i8* %buf, i64 %off
  %c32 = ptrtoint i8* %cp to i32
  store i32 %c32, i32* getelementptr ([2 x i32], [2 x i32]* @_riov, i32 0, i32 0)
  store i32 4096, i32* getelementptr ([2 x i32], [2 x i32]* @_riov, i32 0, i32 1)
  %rp = ptrtoint [2 x i32]* @_riov to i32
  %np = ptrtoint i32* @_rnr to i32
  %rc = call i32 @fd_read(i32 0, i32 %rp, i32 1, i32 %np)
  %nr = load i32, i32* @_rnr
  %nr64 = zext i32 %nr to i64
  %noff = add i64 %off, %nr64
  %eof = icmp eq i32 %nr, 0
  br i1 %eof, label %done, label %rl
done:
  ; Null-terminate for strlen compatibility
  %endp = getelementptr i8, i8* %buf, i64 %noff
  store i8 0, i8* %endp
  ret i8* %buf
}

; --- _loon_get_arg: get CLI argument by index ---
@_wargc = global i32 0
@_wargsz = global i32 0
@_waloaded = global i32 0
@_waptrs = global [64 x i32] zeroinitializer
@_wabuf = global [4096 x i8] zeroinitializer
define i8* @_loon_get_arg(i64 %idx) {
entry:
  %ld = load i32, i32* @_waloaded
  %nl = icmp eq i32 %ld, 0
  br i1 %nl, label %la, label %ga
la:
  %ap = ptrtoint i32* @_wargc to i32
  %bp = ptrtoint i32* @_wargsz to i32
  call i32 @args_sizes_get(i32 %ap, i32 %bp)
  %avp = ptrtoint [64 x i32]* @_waptrs to i32
  %abp = ptrtoint [4096 x i8]* @_wabuf to i32
  call i32 @args_get(i32 %avp, i32 %abp)
  store i32 1, i32* @_waloaded
  br label %ga
ga:
  %ac = load i32, i32* @_wargc
  %i32 = trunc i64 %idx to i32
  %ok = icmp ult i32 %i32, %ac
  br i1 %ok, label %valid, label %empty
valid:
  %sp = getelementptr [64 x i32], [64 x i32]* @_waptrs, i32 0, i32 %i32
  %so = load i32, i32* %sp
  %sptr = inttoptr i32 %so to i8*
  ret i8* %sptr
empty:
  %eb = call i8* @malloc(i64 1)
  store i8 0, i8* %eb
  ret i8* %eb
}

; --- _start entry point for WASI ---
declare i32 @main()
define void @_start() {
entry:
  call i32 @main()
  call void @proc_exit(i32 0)
  unreachable
}
