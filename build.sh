#!/bin/bash
# Build the Aquila compiler from source.
#
# Two build paths:
#   1. Quick (default): Use the bootstrap binary to compile compiler.aquila
#   2. Full:  Build from Stage 0 assembly → Stage 1 → Stage 2 bootstrap → full
#
# The bootstrap binary is a prebuilt Aquila compiler checked into the repo.
# It was produced by the same bootstrap chain and is verifiable:
#   ./aquila stage2/compiler.aquila should produce identical output.
#
# Requires: nasm, ld (binutils)
# Produces: ./aquila (the compiler binary)
set -e

BOOT="stage2/aquila-bootstrap-linux-x86_64"

echo "Building Aquila compiler..."

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
    ./stage0/lexer stage2/compiler-bootstrap.aquila | ./stage1/compiler > /tmp/aquila_boot.asm
    nasm -f elf64 -o /tmp/aquila_boot.o /tmp/aquila_boot.asm
    ld -o /tmp/aquila_boot /tmp/aquila_boot.o

    echo "  [4/4] Full compiler (via bootstrap)"
    /tmp/aquila_boot stage2/compiler.aquila > /tmp/aquila_full.asm 2>/dev/null
    nasm -f elf64 -o /tmp/aquila_full.o /tmp/aquila_full.asm
    ld -o aquila /tmp/aquila_full.o
    rm -f /tmp/aquila_boot.asm /tmp/aquila_boot.o /tmp/aquila_boot /tmp/aquila_full.asm /tmp/aquila_full.o
else
    # Quick build using bootstrap binary
    if [ ! -f "$BOOT" ]; then
        echo "error: bootstrap binary not found at $BOOT"
        echo "Run: ./build.sh --full  (requires Stage 0 + Stage 1 to build from scratch)"
        exit 1
    fi

    echo "  [1/2] Compiling compiler.aquila (via bootstrap binary)"
    "$BOOT" stage2/compiler.aquila > /tmp/aquila_build.asm 2>/dev/null
    nasm -f elf64 -o /tmp/aquila_build.o /tmp/aquila_build.asm
    ld -o aquila /tmp/aquila_build.o

    echo "  [2/2] Verifying self-hosting"
    ./aquila stage2/compiler.aquila > /tmp/aquila_verify.asm 2>/dev/null
    if diff -q /tmp/aquila_build.asm /tmp/aquila_verify.asm >/dev/null 2>&1; then
        echo "  Fixed point verified — binary is reproducible"
    else
        echo "  Warning: not a fixed point (bootstrap binary may be from a different version)"
    fi
    rm -f /tmp/aquila_build.asm /tmp/aquila_build.o /tmp/aquila_verify.asm
fi

# Quick smoke test
echo 'module t; fn main() [IO] -> Unit { do exit(0); }' > /tmp/aquila_smoke.aquila
./aquila /tmp/aquila_smoke.aquila > /tmp/aquila_smoke.asm 2>/dev/null
nasm -f elf64 -o /tmp/aquila_smoke.o /tmp/aquila_smoke.asm
ld -o /tmp/aquila_smoke /tmp/aquila_smoke.o
/tmp/aquila_smoke
rm -f /tmp/aquila_smoke.aquila /tmp/aquila_smoke.asm /tmp/aquila_smoke.o /tmp/aquila_smoke

echo ""
echo "Build successful: ./aquila"
echo ""
echo "Quick start:"
echo "  ./aquila examples/aquila_call.aquila > out.asm"
echo "  nasm -f elf64 -o out.o out.asm && ld -o out out.o"
echo "  ./out"
echo ""
echo "Run the test suite:"
echo "  AQUILA_COMPILER=./aquila ./gauntlet/run.sh"
