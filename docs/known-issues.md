# Loon Known Issues — 2026-03-21

## Compiler Bugs

### 1. Parser corruption with complex match patterns in main()

**Status:** Open — blocks `--target` flag implementation
**Severity:** Medium (workaround exists)

Adding 3+ variables with nested match expressions to `main()` causes the parser to generate IDENT_REF nodes with corrupt string table offsets. The type checker then reports spurious "undefined variable" errors with garbage names.

**Reproduces when:** Adding `--target` command-line flag parsing to `main()` in compiler.loon. The same code compiles fine in a standalone test file or in a helper function — only fails when added to the already-complex `main()`.

**Root cause:** Unknown. Likely a string table offset overflow or node buffer corruption when the function body exceeds a certain AST node count. The parser's string table region (`gn[130000+]`) may collide with node data at high node counts.

**Workaround:** Keep `main()` minimal. Move complex logic to helper functions. For LLVM backend, use a separate `compiler_llvm.loon` or set `gs[915] = 1` manually during development.

---

### 2. Name collision in function dispatch (chk_bi pattern)

**Status:** Fixed (3 times) — root cause remains
**Severity:** Low (full string comparison now used)

The original `chk_bi` used character sampling (length + char[0] + char[5]) to identify builtin functions. User functions with matching patterns were misidentified as builtins. Fixed by replacing with full string comparison via `str_eq`.

**History:**
- Collision #1: unknown (early M2.3)
- Collision #2: `parse_expr` (10 chars, 'p', char[5]='_') matched `print_byte`
- Collision #3: 9-char 'p' functions matched `print_raw`

**Current status:** Full string comparison prevents future collisions. The underlying fragility is gone.

---

### 3. Walker stack overflow on deeply nested programs

**Status:** Fixed — increased to 900 entries
**Severity:** Low

The iterative AST walker (`cg_walk_slots`) uses an explicit stack at `g[220..920]`. Programs with 8+ levels of nested match/for/block can overflow this stack. Increased from 700 to 900 entries. A recursive walker would handle arbitrary depth but requires ADT-based AST (Stage 3).

---

## Gauntlet Known Gaps (2/50)

### 4. Call argument type mismatch not detected

**Status:** Known gap — needs type inference
**Severity:** High (common AI agent mistake)
**Gauntlet test:** `type/call_arg_wrong_type.loon`

`takes_int("wrong")` compiles silently. The type checker verifies literal types in `let` bindings and return expressions, but does not propagate types through function call arguments.

**Fix requires:** Type inference through call chains — knowing that `f(x)` where `f: (Int) -> Int` and `x: String` is a type error. This needs the function table to store parameter types (currently stores only param count).

**Target:** Stage 3 (S3.6)

---

### 5. Bool exhaustive match not checked

**Status:** Known gap — needs discriminant type tracking
**Severity:** Medium
**Gauntlet test:** `exhaustive/bool_missing_true.loon`

`match b { false -> 0 }` compiles silently. The exhaustiveness checker only handles ADT types (checks variant coverage). Bool matches are not verified because the checker can't distinguish `match bool_var { ... }` from `match int_expr { ... }` without knowing the discriminant's type.

**Fix requires:** Propagating type information to the match discriminant expression. If the discriminant is a Bool-typed variable or expression, verify both `true` and `false` are covered (or a wildcard exists).

**Target:** Stage 3 (S3.6)

---

## Runtime Limitations (deferred to Stage 3)

### 6. No division by zero protection

**Status:** Deferred
**Severity:** Medium

Division by zero causes a hardware SIGFPE (crash). No compiler check or runtime trap.

**Target:** Stage 3 (S3.5) — emit runtime check before `idiv`, or trap via signal handler.

---

### 7. No array bounds checking

**Status:** Deferred
**Severity:** Medium

Array access with out-of-bounds index reads/writes garbage memory silently.

**Target:** Stage 3 (S3.5) — emit bounds check before array access, trap on violation.

---

## Missing Features (deferred)

### 8. Float type

**Status:** Deferred to Stage 3
**Reason:** SSE2 codegen on NASM is throwaway work — LLVM handles it correctly.

### 9. Automatic import resolution

**Status:** Deferred to Stage 3
**Reason:** Requires runtime string construction from bytes (path concatenation). Better with proper string handling in Stage 3.

### 10. `--target` command-line flag

**Status:** Blocked by issue #1
**Workaround:** `gs[915]` slot exists, dispatch works. Flag parsing blocked by parser corruption bug. Use separate binary or hardcode during LLVM development.

---

## Score Summary

```
Gauntlet:   48/50 pass, 0 failures, 2 known gaps
Self-host:  Verified (fixed point)
Safety:     9/11 compile-time checks working

Checks working:
  ✓ Effect violations
  ✓ Type mismatch (literals)
  ✓ Non-exhaustive ADT match
  ✓ Undefined variables
  ✓ Wrong argument count
  ✓ Immutable reassignment
  ✓ Return type mismatch
  ✓ Undefined functions
  ✓ read_file/get_arg effect tracking

Checks missing:
  · Call argument types (needs type inference)
  · Bool exhaustive match (needs type propagation)
  · Division by zero (runtime)
  · Array bounds (runtime)
```

### 12. Source complexity limit — compiler at self-compilation boundary

**Status:** Known limitation — Stage 5.0 rewrite eliminates it
**Severity:** Blocks adding any non-trivial code to compiler.loon

The self-compiled binary's type checker has a variable scope limit.
When compiler.loon exceeds ~235KB / 55,000 tokens / 150+ functions,
adding new functions or complex match patterns triggers "undefined
variable" errors during self-compilation.

**Root cause:** The type checker's variable table at g[920..999]
(40 names max per function) and the match nesting depth (15 levels)
are both near capacity for the largest functions in the compiler.

**Impact:**
- Cannot add negative match patterns (fix requires new parser code)
- Cannot fix chained string concat (fix requires new codegen code)
- Cannot fix >3 Array param limit (fix requires new calling convention)

**Workarounds:**
- Negative patterns: use `match x > 0 { ... }` instead of `match x { -1 -> ... }`
- Chained concat: use intermediate variables `let s1 = a + b; let s2 = s1 + c;`
- Array params: restructure functions to take max 3 Array parameters

**Permanent fix:** Stage 5.0 compiler rewrite in full Loon eliminates
g[] slots, increases the type checker capacity, and removes the match
nesting limit entirely. This is the highest-priority technical work.
