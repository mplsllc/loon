# Loon FFI — Stage 5.6 Specification

## Overview

The Foreign Function Interface allows Loon programs to call C libraries. The FFI boundary is explicitly marked with the `Unsafe:TrustBoundary` effect — every call across the boundary is visible in the type signature.

## Syntax

```loon
// Declare an external C function
extern fn sqlite3_open(path: String) [IO, Unsafe:TrustBoundary] -> Int;
extern fn sqlite3_close(db: Int) [IO, Unsafe:TrustBoundary] -> Int;

// Use it
fn open_database(path: String) [IO, Unsafe:TrustBoundary] -> Int {
    sqlite3_open(path)
}
```

## The TrustBoundary effect

`Unsafe:TrustBoundary` is a new effect that must be declared by any function that calls extern functions. It propagates through the call chain — any function that calls a function with `TrustBoundary` must also declare it.

This makes FFI usage visible at every level of the program:

```loon
fn process_data(data: Array<Int>) [IO, Unsafe:TrustBoundary] -> Unit {
    // The signature tells you: this function calls C code somewhere
}
```

## Type marshaling

| Loon type | C type | Notes |
|-----------|--------|-------|
| Int | int64_t | 64-bit integer |
| Float | double | 64-bit IEEE 754 |
| Bool | int64_t | 0 or 1 |
| String | char* + size_t | Pointer + length pair |
| Array<Int> | int64_t* + size_t | Pointer + length |

Strings are passed as (pointer, length) — NOT null-terminated by default. Use `string_to_cstr(s)` to get a null-terminated copy for C APIs that expect it.

## Privacy types at the boundary

Values crossing the FFI boundary lose their privacy type:

```loon
let pw: Sensitive<String> = get_password();
extern fn legacy_hash(s: String) [IO, Unsafe:TrustBoundary] -> String;
// legacy_hash(pw) — COMPILE ERROR: cannot pass Sensitive to Unsafe boundary
// Must expose() first with audit trail
```

This ensures sensitive data doesn't silently leak through C library calls.

## Implementation Plan

### Phase 1: Parser

1. Recognize `extern fn` declarations (new keyword)
2. Store in function table with `is_extern = true` flag
3. No body — just the signature

### Phase 2: Codegen

1. NASM: emit `extern fn_name` directive, generate call with AMD64 C ABI
2. LLVM: emit `declare` for the extern function, call with correct ABI
3. String marshaling: emit ptr+len extraction before call

### Phase 3: Linker integration

1. User provides the C library at link time: `ld -o output output.o -lsqlite3`
2. LLVM backend: `clang output.ll -lsqlite3 -o output`

### Phase 4: Type checker

1. Verify `Unsafe:TrustBoundary` is declared
2. Verify no `Sensitive` values cross the boundary without `expose()`
3. Verify return types are assigned appropriate privacy levels
