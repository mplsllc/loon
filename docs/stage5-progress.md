# Stage 5 Progress

## Implemented

### 5.1 — Standard Library (partial)
- `substring(str, start, count)` → String ✓
- `string_starts_with(str, prefix)` → Bool ✓
- `string_index_of(str, char_code)` → Int ✓
- `string_contains(str, sub)` → Bool ✓
- `string_trim(str)` → String ✓
- `Option<Int/String/Bool>` concrete types ✓
- `Result<Int/String>` concrete types ✓

## Specified (design documents complete)

### 5.2 — Generics
Monomorphization. `Option<T>`, `Result<T,E>`, generic functions.
See: `spec/stage5/generics.md`

### 5.3 — Closures
Anonymous functions with capture by value. Effect inference for closures.
See: `spec/stage5/closures.md`

### 5.4 — Garbage Collector
Mark-and-sweep with ZeroOnDrop zeroing. Object headers. Root scanning.
See: `spec/stage5/gc.md`

### 5.5 — Parallel by Default
Pure functions run in parallel. Sequential blocks for IO.
See: `spec/stage5/parallel.md`

### 5.6 — FFI
`extern fn` declarations. TrustBoundary effect. C ABI marshaling.
See: `spec/stage5/ffi.md`

## Stage 6 Specified

### 6.0 — Device Types
GPU/TPU type annotations. Transfer operations. Compute effects.
See: `spec/stage6/device-types.md`

### 6.2 — Package Registry
Two-tier registry. MPLS license enforcement. CLI integration.
See: `spec/stage6/registry.md`
