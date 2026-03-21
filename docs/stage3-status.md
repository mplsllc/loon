# Loon — Stage 3 Status

## Stage 2 — Complete (2026-03-21)

Self-hosting compiler with 9/11 safety checks. 48/50 gauntlet. Assembly retired.

## Stage 3 — In Progress

### What's done
- `cg_emit_llvm` stub function exists in compiler.loon
- `--target llvm file.loon` dispatches to stub (prints LLVM IR header)
- `gs[915]` = target backend selector (0=nasm, 1=llvm)
- `--target` flag detection works via `mf` array pattern in main()
- Default path (`./loon file.loon`) unchanged — NASM output
- `ptarg` helper function declared but not called (ready for future use)
- Boot binary: `/tmp/s2_new2` (copy of `/tmp/stage2_tgt`)

### What's blocked
- `--target nasm file.loon` doesn't shift source file arg position. Adding extra variables to main() triggers type checker `g[920..999]` name table collision. Workaround: use default path for nasm.
- Source file position for `--target llvm file.loon` is hardcoded to arg3. No `--json` support with `--target` yet.

**Why:** The type checker stores declared names at `g[920..999]` (40 name slots). Adding variables + nested matches to main() pushes the name count or causes the type checker to see stale data. Not a parser corruption bug — it's a g[] slot collision between the target flag (`gs[915]`) and the undef checker's name table (`g[920+]`).

**How to apply:** gs[915] is safe (below 920). The issue is purely about main() complexity hitting the undef checker's scanning limits.

### Next step
Fill in `cg_emit_llvm` with actual LLVM IR. Start with hello world that `llc` accepts.

### Key files
- `stage2/compiler.loon` — the compiler (2004 lines, 129 functions)
- `gauntlet/run.sh` — integrity gauntlet runner
- `docs/known-issues.md` — 10 issues documented
- `docs/BOOTSTRAP.md` — bootstrap story writeup

### Gauntlet baseline
48/50 pass, 0 failures, 2 known gaps (call arg types, bool exhaustive)

### Git state
Branch: main, 20 commits ahead of origin
Latest: `03893ae feat: dual backend scaffolding`

### Boot binary rebuild procedure
```bash
# If /tmp/s2_new2 is lost, rebuild from git:
./stage0/lexer stage2/compiler.loon | ./stage1/compiler > /tmp/stage2.asm
nasm -f elf64 -o /tmp/stage2.o /tmp/stage2.asm && ld -o /tmp/s2_boot /tmp/stage2.o
# Then self-compile:
/tmp/s2_boot stage2/compiler.loon > /tmp/s2_self.asm
nasm -f elf64 -o /tmp/s2_self.o /tmp/s2_self.asm && ld -o /tmp/s2_new2 /tmp/s2_self.o
# NOTE: Stage 1 may no longer compile the full compiler.loon.
# If it fails, use the last known working boot binary from a backup.
```

### Stage 3 roadmap
```
S3.1  LLVM IR backend    — replace NASM codegen with LLVM IR
S3.2  Cross-platform     — Linux, macOS, Windows
S3.3  WebAssembly        — browsers, edge, serverless
S3.4  Float type         — Float64 via LLVM
S3.5  Runtime checks     — div/zero, array bounds → 50/50
S3.6  Type inference     — call arg types → closes last gap
S3.7  LSP server         — editor support, inline errors
S3.8  Package manager    — official tier, community tier
```
