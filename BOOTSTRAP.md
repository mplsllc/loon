# How Loon Bootstrapped from Bare Metal

A technical account of building a self-hosting programming language from x86-64 assembly in two days, with no borrowed toolchain.

---

## The premise

Loon is a programming language designed for a world where AI writes most of the code. The insight: when an LLM generates code from a natural language prompt, it produces what was asked for — but not what wasn't asked for. It doesn't add bounds checks the prompt didn't mention. It doesn't verify effects the specification didn't require. It doesn't catch the security violation the developer didn't think of.

Loon's type system catches what the human forgot to say and the AI didn't know to check.

To build that language, we needed a compiler. To trust that compiler, we needed to build it from scratch — every byte traceable to a deliberate choice. No Rust. No C. No existing language toolchain. Just Linux syscalls and x86-64 instructions.

This is the story of that bootstrap.

---

## Stage 0 — The assembly lexer

**Goal:** Read a `.loon` source file and emit tokens to stdout.

The first program was `echo.asm` — 47 lines of x86-64 assembly that read a file using the `read` syscall and wrote it back using `write`. It proved we could do I/O without libc.

The lexer grew from there. Character-by-character dispatch: letters become identifiers, digits become numbers, `//` starts a comment, `"` starts a string. Each token emitted as one line to stdout: `KW_FN 3:1` or `LIT_INT "42" 5:12`.

The lexer was 1,198 lines of hand-written NASM assembly. Every label prefixed with `lex_` to avoid collisions. Every buffer statically allocated in `.bss`. No heap. No malloc. No runtime.

**What we learned:** The token format became the interface contract between stages. Getting it right mattered more than getting the lexer fast. We wrote `ast-format.md` and locked it before writing a single line of parser code.

---

## Stage 1 — The assembly compiler

**Goal:** Read tokens from stdin, parse into an AST, emit NASM x86-64 assembly to stdout.

Stage 1 was the real compiler — 7,355 lines of hand-written assembly across 10 files:

```
compiler.asm       — entry point, _start, .bss buffers
token_reader.asm   — tok_*: stdin → token array
parser.asm         — par_*: tokens → AST nodes
expr_parser.asm    — expr_*: expression precedence climbing
match_parser.asm   — mpar_*: match arms
codegen.asm        — cg_*: AST → NASM output
codegen_expr.asm   — cgx_*: expression codegen
codegen_match.asm  — cgm_*: match codegen
codegen_io.asm     — cgio_*: string/print codegen
strings.asm        — str_*: string runtime
```

Every function followed a strict prefix convention. Every register usage was documented. The calling convention: 16 bytes per parameter (ptr + len for strings and arrays, value + unused for integers).

The AST was a flat array of 10-integer nodes. No pointers, no dynamic allocation, no garbage collector. Just index arithmetic: `node[i*10 + 5]` is the first child of node `i`.

**The hardest bug in Stage 1:** The slot walker (`cg_walk_slots`) assigned stack offsets to LET and FOR nodes before codegen. It used an iterative explicit-stack traversal because recursive traversal in assembly was too error-prone. Getting the traversal order right — depth-first with sibling chaining — took three attempts.

**Build pipeline:**
```bash
./stage0/lexer input.loon | ./stage1/compiler > output.asm
nasm -f elf64 -o output.o output.asm && ld -o output output.o
```

Five syscalls to run a compiled Loon program: `open`, `read`, `close`, `write`, `exit`. That's it. The entire runtime is five Linux system calls.

---

## Stage 2 — Loon written in Loon

**Goal:** Rewrite the compiler in Loon-0 (the bootstrap subset), compile it with Stage 1, then compile itself.

### M2.0–M2.2: Translation

The first three milestones were direct translation — the same lexer, parser, and codegen logic rewritten in Loon-0 instead of assembly. Each line of Loon-0 replaced 3-5 lines of assembly. The compiler shrank from 7,355 lines of assembly to ~1,200 lines of Loon-0.

Loon-0 is deliberately minimal: `fn`, `let`, `match` on Int/Bool, `for`, arrays, strings. No ADTs, no generics, no closures. The compiler used flat integer arrays with manual offset arithmetic — the same pattern as Stage 1, just readable.

The internal representation: a global state array `gs[]` with 1,024+ entries holding everything from the token position to the variable table to the match nesting depth. Functions communicated through `gs[]` slots:

```
gs[0]    = source length
gs[1]    = lexer position
gs[12]   = node count
gs[13]   = token position
gs[31]   = current expression node
gs[32]   = label counter
gs[33]   = stack offset accumulator
gs[50]   = variable count
gs[51+]  = variable table (name_off, name_len, offset, type) × 4
gs[115-120] = match codegen state
gs[220+] = walker explicit stack
```

### M2.3: Self-hosting

The most satisfying commit in the project:

```
804d4a8 M2.3 COMPLETE — Stage 2 is self-hosting
```

Four bugs found during self-compilation:

1. **Sequential match clobbering** — `cg_call4` used three sequential match statements on `gs[140]`. Between matches, `cg_expr` modified `gs[140]`. The second and third matches saw clobbered values. Fix: nested matches.

2. **Array access r10 clobbering** — `s[g[1]]` clobbered the outer array pointer in r10 when evaluating the nested index. Fix: push/pop r10 around index evaluation.

3. **Builtin name collision** — `por_parse` (9 chars, 'p') matched `print_raw` by length + first character. Fix: additional character checks. (This bug class appeared three times before being permanently fixed with full string comparison.)

4. **String type propagation** — Binary `+` on strings was compiled as integer addition because BINOP nodes never got `type_info=2`. Fix: propagate type from left operand through `mkbin`.

Each bug was invisible on test files and only surfaced when the compiler compiled itself. This is the bootstrap working exactly as designed — the seed compiler gets battle-tested by compiling something real.

After the fix: `diff /tmp/stage2_s2.asm /tmp/stage2_s3.asm` — empty. Fixed point reached. The compiler writes itself. Assembly is history.

### M2.4: Algebraic data types

The first genuinely new feature:

```loon
type Shape {
    Circle(radius: Int),
    Rectangle(width: Int, height: Int),
    Point,
}
```

Runtime representation: tagged unions on the bump heap. Tag at offset 0 (8 bytes), fields following. Variant constructors bump-allocate and initialize. Match reads the tag, dispatches, extracts fields.

Exhaustive match checking: if any variant is missing from a match and there's no wildcard `_`, compilation fails.

**Bug found:** The lexer never had a case for `/` (division operator). First use was `tag / 256` for variant tag extraction. Latent since day one. The first real program to use division.

**Bug found:** The string table overflowed at ~88KB source files. The source bytes + token string values exceeded the 131,072-entry buffer. Fix: expand to 262,144.

### M2.5: Effect verification

```loon
fn pure_function() [] -> Int {
    do print("side effect!");  // ← COMPILE ERROR
    42
}
```

The effect checker scans each function declared `[]` (pure) for `do` calls to IO functions. If found: structured error with function name.

**What it found on first run:** Five functions in the compiler itself were declared `[]` but called `print`/`exit` for error handling. The effect checker caught its own compiler's violations.

The `--json` flag outputs structured errors:
```json
{"error":"undeclared_effect","function":"pure_fn"}
```

### M2.6: Pipe, string match, type checking

Three features in one commit:

- **Pipe operator:** `5 |> double |> increment` desugars to `increment(double(5))`
- **String match:** `match s { "fn" -> 0, "let" -> 1, _ -> 99 }`
- **Type mismatch:** `let x: Int = "hello"` → compile error

### The calculator — Option B pays off

Before rewriting the compiler, we wrote a real program: an arithmetic calculator with lexer, recursive descent parser, and tree evaluator.

It found two bugs that 14 test files couldn't reach:

1. **Name collision #3:** `parse_expr` (10 chars, 'p', char[5]='_') matched `print_byte`. The character sampling approach for builtin detection was fundamentally fragile.

2. **Walker stack overflow:** The lexer's 8 levels of nested match exceeded the 700-entry explicit stack.

The permanent fix for #1: full byte-by-byte string comparison against every builtin name. No more sampling. No more collisions.

### M2.7 partial + Security gauntlet

The security gauntlet tested every class of violation Loon promises to prevent:

```
CAUGHT:  7/11
  ✓ Effect violation
  ✓ Type mismatch (literals)
  ✓ Non-exhaustive match
  ✓ Undefined variable
  ✓ Wrong argument count
  ✓ Immutable reassignment
  ✓ Return type mismatch

MISSED:  2/11
  · Call argument types (needs type inference)
  · Division by zero (runtime)

DEFERRED: 2/11
  · Division by zero (Stage 3 runtime)
  · Array bounds (Stage 3 runtime)
```

Seven compile-time safety checks. The seven most common mistakes AI agents make when generating code.

---

## The numbers

```
Stage 0:  1,198 lines of x86-64 assembly (lexer)
Stage 1:  7,355 lines of x86-64 assembly (compiler)
Stage 2:  ~1,800 lines of Loon-0 (self-hosting compiler)

Total assembly written:     8,553 lines
Total assembly still used:  0 lines (retired at M2.3)

Bugs found during bootstrap:  20+
Bugs found by real programs:  5 (that tests couldn't reach)
Bugs in chk_bi name collision: 3 (same class, finally fixed permanently)

Safety checks:  7/11 compile-time
Test programs:  14 (all passing)
Real programs:  3 (loon_call, calculator, security_gauntlet)

Time: ~2 days
People: 1 human + 1 AI collaborator
Lines of code borrowed: 0
```

---

## What the bootstrap proved

**Self-hosting finds bugs tests can't reach.** Every self-compilation milestone (M2.3, M2.4, M2.5, M2.6) found bugs that the test suite missed. The compiler compiling itself exercises code paths that toy programs never touch.

**Real programs find bugs self-hosting can't reach.** The calculator found two bugs (name collision, walker overflow) that the compiler never triggered because the compiler doesn't use division or 8-level match nesting.

**Character sampling is not string comparison.** The `chk_bi` name collision appeared three times across three milestones before being permanently fixed. Each time, adding one more character check delayed the next collision. The permanent fix was obvious in retrospect: compare the full string. Don't sample.

**The assembly seed compiled itself out of relevance.** At M2.5, Stage 1's token buffer (26,214 max tokens) couldn't hold the compiler's 26,789 tokens. The bootstrap chain became: Stage 1 → M2.4 → M2.5 → current. Stage 1 can never compile the full compiler again. The assembly is archaeology.

**Effect verification works.** The effect checker's first run caught five real violations in the compiler itself. Functions that called `print` and `exit` for error handling but declared themselves pure. The system works.

**7/11 is a meaningful number.** The seven caught violations are the ones that cause the most damage in AI-generated code: wrong types, missing match arms, undefined variables, undeclared side effects, wrong argument counts, immutable reassignment, return type mismatches. An AI agent writing Loon gets precise, machine-readable feedback for each one.

---

## What comes next

Stage 3 replaces the hand-rolled NASM codegen with LLVM IR emission. Real optimization. Cross-platform compilation. WebAssembly target. Float type. Runtime safety checks. The package manager and LSP server.

The foundation is solid. The safety story is real. The bootstrap is complete.

Now make it fast.

---

*Built 2026. No borrowed toolchain. Every byte traceable to a deliberate choice.*
