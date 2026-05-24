#!/bin/bash
# Stage 1 test runner
# Usage: ./stage1/tests/run_tests.sh
# Run from the aquila/ project root.

LEXER=./stage0/lexer
COMPILER=./stage1/compiler
TESTS_DIR=./stage1/tests
EXPECTED_DIR=./stage1/expected

PASS=0
FAIL=0
ERRORS=""

for aquila_file in "$TESTS_DIR"/test_*.aquila; do
    test_name=$(basename "$aquila_file" .aquila)

    # Compile: lex → parse/codegen → assemble → link
    if ! "$LEXER" "$aquila_file" | "$COMPILER" > /tmp/aquila_test.asm 2>/tmp/aquila_compile.stderr; then
        FAIL=$((FAIL + 1))
        ERRORS="$ERRORS\n  FAIL $test_name — compiler error (see /tmp/aquila_compile.stderr)"
        continue
    fi

    if ! nasm -f elf64 -o /tmp/aquila_test.o /tmp/aquila_test.asm 2>/tmp/aquila_nasm.stderr; then
        FAIL=$((FAIL + 1))
        ERRORS="$ERRORS\n  FAIL $test_name — nasm error (see /tmp/aquila_nasm.stderr)"
        continue
    fi

    if ! ld -o /tmp/aquila_test /tmp/aquila_test.o 2>/tmp/aquila_ld.stderr; then
        FAIL=$((FAIL + 1))
        ERRORS="$ERRORS\n  FAIL $test_name — linker error (see /tmp/aquila_ld.stderr)"
        continue
    fi

    # Run the compiled program — capture exit code explicitly
    /tmp/aquila_test > /tmp/aquila_actual.stdout 2>/tmp/aquila_actual.stderr
    echo $? > /tmp/aquila_actual.exit

    # Compare stdout
    if ! diff -q /tmp/aquila_actual.stdout "$EXPECTED_DIR/${test_name}.stdout" > /dev/null 2>&1; then
        FAIL=$((FAIL + 1))
        ERRORS="$ERRORS\n  FAIL $test_name — stdout mismatch"
        diff /tmp/aquila_actual.stdout "$EXPECTED_DIR/${test_name}.stdout" || true
        continue
    fi

    # Compare exit code
    if ! diff -q /tmp/aquila_actual.exit "$EXPECTED_DIR/${test_name}.exit" > /dev/null 2>&1; then
        FAIL=$((FAIL + 1))
        ERRORS="$ERRORS\n  FAIL $test_name — exit code mismatch (got $(cat /tmp/aquila_actual.exit), expected $(cat "$EXPECTED_DIR/${test_name}.exit"))"
        continue
    fi

    # Compare stderr (empty for clean programs)
    if [ -f "$EXPECTED_DIR/${test_name}.stderr" ]; then
        if ! diff -q /tmp/aquila_actual.stderr "$EXPECTED_DIR/${test_name}.stderr" > /dev/null 2>&1; then
            FAIL=$((FAIL + 1))
            ERRORS="$ERRORS\n  FAIL $test_name — stderr mismatch"
            diff /tmp/aquila_actual.stderr "$EXPECTED_DIR/${test_name}.stderr" || true
            continue
        fi
    fi

    PASS=$((PASS + 1))
    echo "  PASS $test_name"
done

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ $FAIL -gt 0 ]; then
    echo -e "\nFailures:$ERRORS"
    exit 1
fi
