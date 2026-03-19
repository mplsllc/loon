# Loon — CLAUDE.md

## What this is

Loon is a programming language bootstrapped from x86-64 assembly.
AI agents are the primary intended author of Loon code.
Every design decision optimizes for machine-verifiable intent.

## Current stage

Stage 1 — writing the parser + codegen in assembly.
Stage 0 (lexer) is complete and tested.
The spec is in spec/loon-spec.md. The bootstrap subset is in spec/loon-0-spec.md.
No Rust. No C. No existing language toolchain.

## What is absolutely banned

- Suggesting Rust, Go, or any existing language for implementation
- Null (use Option<T>)
- Exceptions (use Result<T, E>)
- Global mutable state
- Implicit type coercion
- Inheritance
- Operator overloading
- Multiple ways to express the same construct
- Significant whitespace as structure

## The token format (Stage 0 output)

Each token on its own line: `TYPE [value] line:col`

### Complete token types

```
# Keywords
KW_FN KW_LET KW_TYPE KW_MATCH KW_FOR KW_IN KW_DO KW_MODULE
KW_IMPORTS KW_EXPORTS KW_SEQUENTIAL KW_TRUE KW_FALSE

# Literals (always have a quoted value)
LIT_INT "42"
LIT_FLOAT "3.14"
LIT_STRING "hello world"

# Identifiers (always have a quoted value)
IDENT "name"

# Delimiters
LBRACE RBRACE LPAREN RPAREN LBRACKET RBRACKET

# Operators
ASSIGN       =
PLUS MINUS STAR SLASH PERCENT
EQ NEQ LT GT LTE GTE
AND OR NOT

# Punctuation
ARROW        ->
PIPE         |>
COLON        :
SEMICOLON    ;
COMMA        ,
DOT          .

# Special
EOF
```

### Token format rules

- Comments (`//` to end of line) are silently dropped
- String values use source characters, no re-escaping
- Line and column are 1-indexed
- Invalid character: print `ERROR "unexpected character 'X'" line:col` to stderr, exit code 1
- EOF token is always the last token emitted
- `=>` is NOT a token (not used in Loon syntax)

## Assembly conventions

- NASM, Intel syntax, x86-64 Linux
- Syscalls via `syscall` instruction, AMD64 System V ABI
- No external libraries, no C runtime, no libc
- Static buffer in .bss for file I/O (8KB)
- Comments on every non-obvious instruction

## Build commands

```bash
# Assemble and link any stage0 program
nasm -f elf64 -o out.o stage0/FILE.asm && ld -o out out.o

# Test lexer against expected output
./lexer examples/hello.loon | diff - expected/hello.tokens

# Stage 1: compile a Loon-0 program
./stage0/lexer input.loon | ./stage1/compiler > output.asm
nasm -f elf64 -o output.o output.asm && ld -o output output.o

# Stage 1: dump AST (diagnostic mode — no stdout output)
./stage0/lexer input.loon | ./stage1/compiler --dump-ast
```

`--dump-ast` produces no stdout output and no output.asm — diagnostic mode only.

## Project structure

```
loon/
├── CLAUDE.md              # This file
├── spec/
│   ├── loon-spec.md       # Complete language specification
│   └── loon-0-spec.md     # Bootstrap subset specification
├── stage0/
│   ├── Makefile
│   ├── echo.asm           # M0.0: file echo
│   ├── lexer.asm          # M0.3: full token emitter
│   └── tests/
├── stage1/
│   ├── Makefile
│   ├── ast-format.md      # Token/node enum contract (locked)
│   ├── compiler.asm       # %include all below, _start entry point
│   ├── token_reader.asm   # tok_*: stdin → token array
│   ├── parser.asm         # par_*: tokens → AST nodes
│   ├── expr_parser.asm    # expr_*: expression precedence climbing
│   ├── match_parser.asm   # mpar_*: match arms
│   ├── codegen.asm        # cg_*: AST → NASM output
│   ├── codegen_expr.asm   # cgx_*: expression codegen
│   ├── codegen_match.asm  # cgm_*: match codegen
│   ├── codegen_io.asm     # cgio_*: string/print codegen
│   ├── strings.asm        # str_*: string runtime
│   ├── tests/
│   └── expected/
├── examples/              # .loon source files
├── expected/              # Expected token output (ground truth)
```

## Stage 1 label prefix table

Every internal label is prefixed by file abbreviation. No exceptions.

| File | Prefix |
|------|--------|
| compiler.asm | `main_` |
| token_reader.asm | `tok_` |
| parser.asm | `par_` |
| expr_parser.asm | `expr_` |
| match_parser.asm | `mpar_` |
| codegen.asm | `cg_` |
| codegen_expr.asm | `cgx_` |
| codegen_match.asm | `cgm_` |
| codegen_io.asm | `cgio_` |
| strings.asm | `str_` |

## Stage 1 compiler.asm argv handling

```
; At _start, the stack contains:
;   [rsp]     = argc (8 bytes, load with mov rax, [rsp])
;   [rsp+8]   = argv[0] (program name pointer)
;   [rsp+16]  = argv[1] (first argument pointer, if argc >= 2)
;
; To check --dump-ast:
;   1. Load argc with: mov rax, [rsp]  (NOT mov eax, [rsp])
;   2. If argc >= 2, load argv[1] pointer from [rsp+16]
;   3. Inline byte-by-byte comparison against "--dump-ast" (10 bytes + null)
;   4. Self-contained — does NOT call str_equals
```
