# Loon — CLAUDE.md

## What this is

Loon is a programming language bootstrapped from x86-64 assembly.
AI agents are the primary intended author of Loon code.
Every design decision optimizes for machine-verifiable intent.

## Current stage

Stage 0 — writing the assembly seed.
The spec is in spec/loon-spec.md.
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
```

## Project structure

```
loon/
├── CLAUDE.md              # This file
├── spec/
│   └── loon-spec.md       # Complete language specification
├── stage0/
│   ├── Makefile
│   ├── echo.asm           # M0.0: file echo
│   ├── classify.asm       # M0.1: character classifier
│   ├── keywords.asm       # M0.2: keyword recognizer
│   ├── lexer.asm          # M0.3: full token emitter
│   └── tests/
├── examples/              # .loon source files
├── expected/              # Expected token output (ground truth)
```
