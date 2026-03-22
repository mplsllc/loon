# Loon — Stage 3 Status

## S3.1 LLVM IR Backend — COMPLETE (2026-03-22)

LLVM backend: 30/30 COMPILES OK tests pass through llc → gcc pipeline.
NASM backend: 48/50 gauntlet, self-hosting verified.
Both backends produce identical behavior on all tests.

### What the LLVM backend handles
- Arithmetic, let bindings, variable references (alloca/load/store)
- User function calls, recursive functions
- Print + string literals, string concatenation
- Match expressions with join blocks (phi nodes)
- For loops with alloca counters
- Arrays (malloc, GEP, load/store)
- ADTs: variant construction + ADT match (split into ll_amcmp/ll_ambod/ll_amphi)
- Bool literals, pipe operator
- All comparison operators via icmp

### Bugs found and fixed during S3.1
1. **g[115..122] match state vs variable table** — functions with 16+ variables had late-declared variables' offsets overwritten by match codegen state. Fix: relocated match state to g[850+].
2. **Walker stack at g[221..1120] overlapping type table at g[1024..2047]** — moved walker to g[2048..4095].
3. **FOR nodes at block level skipped by Stage 1 walker** — added cg_als_walk_self handler.
4. **Bool literal used sub_type (field 1) instead of extra (field 8)** — parser stores true/false in extra.
5. **Token buffer too small** — doubled from 512KB to 1MB for large programs.

### g[] slot allocation map
Documented at top of compiler.loon. Prevents future slot collision bugs.

### Build pipeline
```bash
# NASM (default, bootstrap)
./loon file.loon > output.asm
nasm -f elf64 -o output.o output.asm && ld -o output output.o

# LLVM (production)
./loon --target llvm file.loon > output.ll
llc --relocation-model=pic -filetype=obj output.ll -o output.o
gcc -no-pie output.o -o output
```

### Key files
- `stage2/compiler.loon` — the compiler (~2600 lines, ~145 functions)
- `stage1/codegen.asm` — Stage 1 walker (FOR fix applied)
- `gauntlet/run.sh` — integrity gauntlet runner

### Boot binary
`/tmp/s2_new2` = latest self-compiled Stage 2 binary
If lost: self-compile from `stage2/compiler.loon` using any working Stage 2 binary

### Git state
Branch: main
Latest: `f54b7a0 docs: g[] slot allocation map in compiler.loon`

## S3.2 Cross-platform — NEXT

### Plan
1. Add --arch flag (linux/macos/windows)
2. Emit correct target triple per arch
3. Platform-specific write/exit wrappers
4. macOS first (libc compatible, smallest delta)
5. GitHub Actions CI: matrix build Linux + macOS

### Stage 3 roadmap
```
S3.1  LLVM IR backend    ████████████████████  DONE
S3.2  Cross-platform     ░░░░░░░░░░░░░░░░░░░░  next
S3.3  WebAssembly        ░░░░░░░░░░░░░░░░░░░░
S3.4  Float type         ░░░░░░░░░░░░░░░░░░░░
S3.5  Runtime checks     ░░░░░░░░░░░░░░░░░░░░
S3.6  Type inference     ░░░░░░░░░░░░░░░░░░░░
S3.7  LSP server         ░░░░░░░░░░░░░░░░░░░░
S3.8  Package manager    ░░░░░░░░░░░░░░░░░░░░
```
