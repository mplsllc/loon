# Building Aquila

## Prerequisites

### Required (all targets)
- NASM (Netwide Assembler) — for the NASM backend
- GNU ld — for linking NASM output
- Python 3 — for the LSP server and package manager

### Required (LLVM targets)
- LLVM 18+ (`llc` command)
- GCC or Clang — for linking LLVM object files

### Optional (WebAssembly)
- wasm-ld (from LLVM/LLD)
- wasmtime — WASI runtime for testing
- wasi-sysroot — for clang --target=wasm32-wasi linking

## Installing Dependencies

### Ubuntu/Debian
```bash
sudo apt-get install nasm llvm clang gcc lld
# For WASM:
curl https://wasmtime.dev/install.sh -sSf | bash
```

### macOS
```bash
brew install nasm llvm
# llc and clang come with Xcode Command Line Tools
# For WASM:
brew install wasmtime
```

### Windows
Install LLVM from https://releases.llvm.org/ and NASM from https://www.nasm.us/

## Building the Compiler

The Aquila compiler is self-hosting. Build from the pre-compiled boot binary:

```bash
# If you have a working aquila binary:
./aquila stage2/compiler.aquila > compiler.asm
nasm -f elf64 -o compiler.o compiler.asm
ld -o aquila compiler.o

# Bootstrap from Stage 1 (assembly):
./stage0/lexer stage2/compiler.aquila | ./stage1/compiler > compiler.asm
nasm -f elf64 -o compiler.o compiler.asm
ld -o aquila compiler.o
```

## Compiling Aquila Programs

### NASM backend (default, Linux x86-64)
```bash
./aquila program.aquila > program.asm
nasm -f elf64 -o program.o program.asm
ld -o program program.o
./program
```

### LLVM backend (cross-platform)
```bash
./aquila --target llvm program.aquila > program.ll
llc --relocation-model=pic -filetype=obj program.ll -o program.o
gcc -no-pie program.o -o program
./program
```

### Cross-compilation
```bash
# macOS x86-64
./aquila --target llvm --arch macos program.aquila > program.ll

# macOS ARM64 (Apple Silicon)
./aquila --target llvm --arch macos-arm program.aquila > program.ll

# Windows
./aquila --target llvm --arch windows program.aquila > program.ll

# WebAssembly (WASI)
./aquila --target llvm --arch wasm program.aquila > program.ll
```

### WebAssembly Build Pipeline

```bash
# Generate WASM-targeted LLVM IR
./aquila --target llvm --arch wasm program.aquila > program.ll

# Option 1: Using llc + wasm-ld
llc -march=wasm32 -filetype=obj program.ll -o program.o
wasm-ld program.o -o program.wasm --no-entry --export=_start

# Option 2: Using clang (requires wasi-sysroot)
clang --target=wasm32-wasi program.ll -o program.wasm

# Run with wasmtime
wasmtime program.wasm
```

#### Installing wasi-sysroot

The wasi-sysroot provides libc headers and libraries for WASM targets:

**Ubuntu/Debian:**
```bash
sudo apt-get install wasi-libc
# sysroot at /usr/share/wasi-sysroot or /usr/lib/wasi
```

**Manual installation:**
```bash
# Download from https://github.com/WebAssembly/wasi-sdk/releases
wget https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-24/wasi-sysroot-24.0.tar.gz
tar xzf wasi-sysroot-24.0.tar.gz
clang --target=wasm32-wasi --sysroot=./wasi-sysroot program.ll -o program.wasm
```

## Running the Test Suite

```bash
# NASM gauntlet (50 tests)
./gauntlet/run.sh

# LLVM test sweep
for f in gauntlet/tests/*/*.aquila; do
    expect=$(grep "^// EXPECT:" "$f" | head -1 | sed 's|^// EXPECT: ||')
    [[ "$expect" == "COMPILES OK, exit "* ]] || continue
    expected_exit="${expect#COMPILES OK, exit }"
    ./aquila --target llvm "$f" > /tmp/t.ll 2>/dev/null && \
    llc --relocation-model=pic -filetype=obj /tmp/t.ll -o /tmp/t.o 2>/dev/null && \
    gcc -no-pie /tmp/t.o -o /tmp/t 2>/dev/null && \
    timeout 5 /tmp/t >/dev/null 2>/dev/null
    [ "$?" = "$expected_exit" ] && echo "PASS $(basename $f .aquila)" || echo "FAIL $(basename $f .aquila)"
done
```

## Editor Support

### VS Code
1. Copy `tools/vscode/` to `~/.vscode/extensions/aquila-language/`
2. Set `AQUILA_COMPILER` environment variable to point to your aquila binary
3. Restart VS Code
4. Open a `.aquila` file — syntax highlighting and error diagnostics will appear
