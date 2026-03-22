# Loon — Stage 3 Status

## Stage 2 — Complete (2026-03-21)

Self-hosting compiler with 9/11 safety checks. 48/50 gauntlet. Assembly retired.

## Stage 3 — In Progress

### LLVM Backend: 25/30 tests pass

Working through LLVM IR → llc → gcc pipeline:
- Arithmetic, let bindings, variable references
- User function calls, recursive functions (simple cases)
- Print + string literals, string concatenation
- Match expressions with join blocks (phi nodes)
- For loops with alloca counters
- Arrays (malloc, GEP, load/store)
- ADTs: variant construction (malloc + tag + fields)
- ADT match: split into ll_amcmp + ll_ambod + ll_amphi (avoids frame clobbering)
- Bool literals (fixed: extra field, not sub_type)
- Pipe operator (desugared by parser)

### 5 Remaining LLVM Failures

All same root cause: **return value clobbering in cg_aryset**

When `ll_stmt` or `ll_builtin` calls `ll_expr` and the expression is a match, the return value (rax) is clobbered before being stored. This is a Stage 1 NASM codegen bug in how `arr[i] = fn_call()` patterns handle the push/pop sequence around function calls.

Affected tests:
- `bool_both_ok` — ret uses wrong SSA temp after match (LLC_FAIL)
- `string_match` — same LLC error (LLC_FAIL)
- `nested_match` — inner match result not propagated (wrong result)
- `nested_adt_match` — same (wrong result)
- `recursive_fn` — recursive call result lost (returns 0)

### Stage 1 Fixes Applied

- `cg_assign_let_slots`: FOR nodes at block level now walk children via `cg_als_walk_self` (was skipped entirely — root cause of many earlier bugs)
- Token buffer increased from 512KB to 1MB (52K tokens max)
- `MAX_TOKENS` constant updated in `token_reader.asm`

### What's Done
- `cg_emit_llvm` with full function walker
- `--target llvm file.loon` dispatches correctly
- `gs[915]` = target backend selector (0=nasm, 1=llvm)
- All LLVM helper functions: ll_expr, ll_stmt, ll_block, ll_fn, ll_match, ll_amatch, ll_vnew, ll_builtin, ll_call, ll_binop, ll_ident, ll_for, ll_arynew, ll_aryget, ll_aryset, ll_amphi, ll_ambod, ll_amcmp
- Join blocks (m{N}_j{I}) fix phi predecessor mismatch for nested matches
- Bool literal handler (type 9, extra field)
- ADT detection in ll_match dispatches to ll_amatch

### Key files
- `stage2/compiler.loon` — the compiler (~2500 lines, ~145 functions)
- `stage1/codegen.asm` — Stage 1 walker (FOR fix applied)
- `stage1/compiler.asm` — token buffer size
- `stage1/token_reader.asm` — MAX_TOKENS constant
- `gauntlet/run.sh` — integrity gauntlet runner
- `docs/known-issues.md` — issues documented

### Gauntlet baseline
- NASM: 48/50 pass, 0 failures, 2 known gaps
- LLVM: 25/30 COMPILES OK tests pass, 5 failures (all same root cause)

### Next steps
1. Fix cg_aryset return value clobbering in Stage 1 assembly → 30/30 LLVM
2. Cross-platform (change target triple, test on macOS/Windows)
3. Float type via LLVM
4. WASM target

### Boot binary rebuild procedure
```bash
# If /tmp/s2_new2 is lost, self-compile from git:
# (Stage 1 can no longer compile the full compiler.loon due to size)
# Use the last known working binary or rebuild chain:
# 1. Build Stage 1 from assembly
cd stage1 && nasm -f elf64 -o /tmp/s1.o compiler.asm && ld -o /tmp/s1 /tmp/s1.o
cd ..
# 2. Compile a SMALLER version of compiler.loon that Stage 1 can handle
# (may require temporarily reducing the source)
# 3. Self-compile to get the full binary
```

### Git state
Branch: main
Latest: `45f5b56 fix: Stage 1 walker + Bool literal + token buffer`
