#!/bin/bash
# Build the Akvila compiler from source.
#
# Two build paths:
#   1. Quick (default): Use the bootstrap binary to compile compiler.akvila
#   2. Full:  Build from Stage 0 assembly → Stage 1 → Stage 2 bootstrap → full
#
# The bootstrap binary is a prebuilt Akvila compiler checked into the repo.
# It was produced by the same bootstrap chain and is verifiable:
#   ./akvila stage2/compiler.akvila should produce identical output.
#
# Requires: nasm, ld (binutils)
# Produces: ./akvila (the compiler binary)
set -e

BOOT="stage2/akvila-bootstrap-linux-x86_64"

echo "Building Akvila compiler..."

# Check prerequisites
command -v nasm >/dev/null 2>&1 || { echo "error: nasm not found. Install with: sudo apt install nasm"; exit 1; }
command -v ld >/dev/null 2>&1 || { echo "error: ld not found. Install binutils."; exit 1; }

if [ "$1" = "--full" ]; then
    # Full bootstrap from assembly
    echo "  [1/4] Stage 0: lexer (assembly)"
    cd stage0 && nasm -f elf64 -o lexer.o lexer.asm && ld -o lexer lexer.o && cd ..

    echo "  [2/4] Stage 1: compiler (assembly)"
    cd stage1 && nasm -f elf64 -o compiler.o compiler.asm && ld -o compiler compiler.o && cd ..

    echo "  [3/4] Bootstrap compiler (via Stage 1)"
    # Stage 1 compiles a minimal bootstrap source
    ./stage0/lexer stage2/compiler-bootstrap.akvila | ./stage1/compiler > /tmp/akvila_boot.asm
    nasm -f elf64 -o /tmp/akvila_boot.o /tmp/akvila_boot.asm
    ld -o /tmp/akvila_boot /tmp/akvila_boot.o

    echo "  [4/4] Full compiler (via bootstrap)"
    /tmp/akvila_boot stage2/compiler.akvila > /tmp/akvila_full.asm 2>/dev/null
    nasm -f elf64 -o /tmp/akvila_full.o /tmp/akvila_full.asm
    ld -o akvila /tmp/akvila_full.o
    rm -f /tmp/akvila_boot.asm /tmp/akvila_boot.o /tmp/akvila_boot /tmp/akvila_full.asm /tmp/akvila_full.o
else
    # Quick build using bootstrap binary
    if [ ! -f "$BOOT" ]; then
        echo "error: bootstrap binary not found at $BOOT"
        echo "Run: ./build.sh --full  (requires Stage 0 + Stage 1 to build from scratch)"
        exit 1
    fi

    echo "  [1/2] Compiling compiler.akvila (via bootstrap binary)"
    "$BOOT" stage2/compiler.akvila > /tmp/akvila_build.asm 2>/dev/null
    nasm -f elf64 -o /tmp/akvila_build.o /tmp/akvila_build.asm
    ld -o akvila /tmp/akvila_build.o

    echo "  [2/2] Verifying self-hosting"
    ./akvila stage2/compiler.akvila > /tmp/akvila_verify.asm 2>/dev/null
    if diff -q /tmp/akvila_build.asm /tmp/akvila_verify.asm >/dev/null 2>&1; then
        echo "  Fixed point verified — binary is reproducible"
    else
        echo "  Warning: not a fixed point (bootstrap binary may be from a different version)"
    fi
    rm -f /tmp/akvila_build.asm /tmp/akvila_build.o /tmp/akvila_verify.asm
fi

# Quick smoke test
echo 'module t; fn main() [IO] -> Unit { do exit(0); }' > /tmp/akvila_smoke.akvila
./akvila /tmp/akvila_smoke.akvila > /tmp/akvila_smoke.asm 2>/dev/null
nasm -f elf64 -o /tmp/akvila_smoke.o /tmp/akvila_smoke.asm
ld -o /tmp/akvila_smoke /tmp/akvila_smoke.o
/tmp/akvila_smoke
rm -f /tmp/akvila_smoke.akvila /tmp/akvila_smoke.asm /tmp/akvila_smoke.o /tmp/akvila_smoke

echo ""
echo "Build successful: ./akvila"
echo ""
echo "Quick start:"
echo "  ./akvila examples/akvila_call.akvila > out.asm"
echo "  nasm -f elf64 -o out.o out.asm && ld -o out out.o"
echo "  ./out"
echo ""
echo "Run the test suite:"
echo "  AKVILA_COMPILER=./akvila ./gauntlet/run.sh"
