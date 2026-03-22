#!/bin/bash
# Build the Loon compiler from source.
#
# Two build paths:
#   1. Quick (default): Use the bootstrap binary to compile compiler.loon
#   2. Full:  Build from Stage 0 assembly → Stage 1 → Stage 2 bootstrap → full
#
# The bootstrap binary is a prebuilt Loon compiler checked into the repo.
# It was produced by the same bootstrap chain and is verifiable:
#   ./loon stage2/compiler.loon should produce identical output.
#
# Requires: nasm, ld (binutils)
# Produces: ./loon (the compiler binary)
set -e

BOOT="stage2/loon-bootstrap-linux-x86_64"

echo "Building Loon compiler..."

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
    ./stage0/lexer stage2/compiler-bootstrap.loon | ./stage1/compiler > /tmp/loon_boot.asm
    nasm -f elf64 -o /tmp/loon_boot.o /tmp/loon_boot.asm
    ld -o /tmp/loon_boot /tmp/loon_boot.o

    echo "  [4/4] Full compiler (via bootstrap)"
    /tmp/loon_boot stage2/compiler.loon > /tmp/loon_full.asm 2>/dev/null
    nasm -f elf64 -o /tmp/loon_full.o /tmp/loon_full.asm
    ld -o loon /tmp/loon_full.o
    rm -f /tmp/loon_boot.asm /tmp/loon_boot.o /tmp/loon_boot /tmp/loon_full.asm /tmp/loon_full.o
else
    # Quick build using bootstrap binary
    if [ ! -f "$BOOT" ]; then
        echo "error: bootstrap binary not found at $BOOT"
        echo "Run: ./build.sh --full  (requires Stage 0 + Stage 1 to build from scratch)"
        exit 1
    fi

    echo "  [1/2] Compiling compiler.loon (via bootstrap binary)"
    "$BOOT" stage2/compiler.loon > /tmp/loon_build.asm 2>/dev/null
    nasm -f elf64 -o /tmp/loon_build.o /tmp/loon_build.asm
    ld -o loon /tmp/loon_build.o

    echo "  [2/2] Verifying self-hosting"
    ./loon stage2/compiler.loon > /tmp/loon_verify.asm 2>/dev/null
    if diff -q /tmp/loon_build.asm /tmp/loon_verify.asm >/dev/null 2>&1; then
        echo "  Fixed point verified — binary is reproducible"
    else
        echo "  Warning: not a fixed point (bootstrap binary may be from a different version)"
    fi
    rm -f /tmp/loon_build.asm /tmp/loon_build.o /tmp/loon_verify.asm
fi

# Quick smoke test
echo 'module t; fn main() [IO] -> Unit { do exit(0); }' > /tmp/loon_smoke.loon
./loon /tmp/loon_smoke.loon > /tmp/loon_smoke.asm 2>/dev/null
nasm -f elf64 -o /tmp/loon_smoke.o /tmp/loon_smoke.asm
ld -o /tmp/loon_smoke /tmp/loon_smoke.o
/tmp/loon_smoke
rm -f /tmp/loon_smoke.loon /tmp/loon_smoke.asm /tmp/loon_smoke.o /tmp/loon_smoke

echo ""
echo "Build successful: ./loon"
echo ""
echo "Quick start:"
echo "  ./loon examples/loon_call.loon > out.asm"
echo "  nasm -f elf64 -o out.o out.asm && ld -o out out.o"
echo "  ./out"
echo ""
echo "Run the test suite:"
echo "  LOON_COMPILER=./loon ./gauntlet/run.sh"
