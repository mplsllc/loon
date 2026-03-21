#!/bin/bash
# Loon Integrity Gauntlet — automated runner
# Compiles each test, checks expected outcome, reports results.

COMPILER="${LOON_COMPILER:-/tmp/s2_new2}"
PASS=0; FAIL=0; GAP=0; DEFER=0; TOTAL=0
UNEXPECTED_CATCH=0

GREEN='\033[0;32m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'
NC='\033[0m'

for test in gauntlet/tests/*/*.loon; do
    TOTAL=$((TOTAL + 1))
    name=$(basename "$test" .loon)
    expect=$(grep "^// EXPECT:" "$test" | head -1 | sed 's|^// EXPECT: ||')

    $COMPILER "$test" > /tmp/g_out.asm 2>/tmp/g_err.txt
    compile_rc=$?

    if [[ "$expect" == "ERROR" ]]; then
        if [[ $compile_rc -ne 0 ]]; then
            PASS=$((PASS + 1))
            printf "${GREEN}PASS${NC}  %s\n" "$name"
        else
            FAIL=$((FAIL + 1))
            printf "${RED}FAIL${NC}  %s (expected error, compiled ok)\n" "$name"
        fi

    elif [[ "$expect" == "COMPILES OK" ]]; then
        if [[ $compile_rc -eq 0 ]]; then
            PASS=$((PASS + 1))
            printf "${GREEN}PASS${NC}  %s\n" "$name"
        else
            FAIL=$((FAIL + 1))
            printf "${RED}FAIL${NC}  %s (%s)\n" "$name" "$(head -1 /tmp/g_err.txt)"
        fi

    elif [[ "$expect" == "COMPILES OK, exit "* ]]; then
        expected_exit="${expect#COMPILES OK, exit }"
        if [[ $compile_rc -eq 0 ]]; then
            nasm -f elf64 -o /tmp/g_out.o /tmp/g_out.asm 2>/dev/null \
              && ld -o /tmp/g_bin /tmp/g_out.o 2>/dev/null
            timeout 5 /tmp/g_bin >/dev/null 2>/dev/null
            actual_exit=$?
            if [[ "$actual_exit" == "$expected_exit" ]]; then
                PASS=$((PASS + 1))
                printf "${GREEN}PASS${NC}  %s (exit %s)\n" "$name" "$actual_exit"
            else
                FAIL=$((FAIL + 1))
                printf "${RED}FAIL${NC}  %s (expected exit %s, got %s)\n" "$name" "$expected_exit" "$actual_exit"
            fi
        else
            FAIL=$((FAIL + 1))
            printf "${RED}FAIL${NC}  %s (compile failed: %s)\n" "$name" "$(head -1 /tmp/g_err.txt)"
        fi

    elif [[ "$expect" == "KNOWN GAP" ]]; then
        GAP=$((GAP + 1))
        if [[ $compile_rc -ne 0 ]]; then
            UNEXPECTED_CATCH=$((UNEXPECTED_CATCH + 1))
            printf "${YELLOW}GAP+${NC}  %s (now produces error — gap may be fixed)\n" "$name"
        else
            printf "${YELLOW}GAP ${NC}  %s (compiles silently — known gap)\n" "$name"
        fi

    elif [[ "$expect" == "DEFERRED" ]]; then
        DEFER=$((DEFER + 1))
        printf "${BLUE}DEFER${NC} %s\n" "$name"
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "LOON INTEGRITY GAUNTLET"
echo "Date:   $(date +%Y-%m-%d)"
echo "Commit: $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
echo "────────────────────────────────────────"
printf "Total:       %d\n" "$TOTAL"
printf "${GREEN}Pass:        %d${NC}\n" "$PASS"
printf "${RED}Fail:        %d${NC}\n" "$FAIL"
printf "${YELLOW}Known gaps:  %d${NC}\n" "$GAP"
printf "${BLUE}Deferred:    %d${NC}\n" "$DEFER"
if [[ $UNEXPECTED_CATCH -gt 0 ]]; then
    printf "${GREEN}Gaps fixed:  %d (previously known gaps now caught)${NC}\n" "$UNEXPECTED_CATCH"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $FAIL -eq 0 ]]; then
    printf "${GREEN}0 unexpected failures. Every test behaves as documented.${NC}\n"
else
    printf "${RED}%d unexpected failures. See above.${NC}\n" "$FAIL"
fi
