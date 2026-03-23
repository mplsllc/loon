#!/bin/bash
# LLM Agent Gauntlet — measures what Loon catches when AI writes security-critical code
#
# Two variants per prompt:
#   *_untyped.loon — naive implementation, no privacy types (simulates Python/Go-like code)
#   *_typed.loon   — using Sensitive<String> but still making mistakes
#
# Results: COMPILED (vulnerability shipped) or CAUGHT (compiler stopped it)

COMPILER="${LOON_COMPILER:-/tmp/s2_new2}"
CAUGHT=0
COMPILED=0
TOTAL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  LLM AGENT GAUNTLET — BASELINE MEASUREMENT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

DIR="$(dirname "$0")"

for test in "$DIR"/prompt*.loon; do
    TOTAL=$((TOTAL + 1))
    name=$(basename "$test" .loon)

    # Extract the prompt from the first comment line
    prompt=$(head -1 "$test" | sed 's|^// PROMPT: ||' | tr -d '"')
    variant=$(head -2 "$test" | tail -1 | sed 's|^// SIMULATED AI OUTPUT — ||')

    # Compile
    $COMPILER "$test" > /dev/null 2>/tmp/llm_err.txt
    rc=$?

    if [ $rc -eq 0 ]; then
        COMPILED=$((COMPILED + 1))
        printf "${RED}SHIPPED${NC}  %-40s %s\n" "$name" "(vulnerability compiles — NOT caught)"
    else
        CAUGHT=$((CAUGHT + 1))
        error=$(cat /tmp/llm_err.txt | strings | grep "error:" | head -1)
        printf "${GREEN}CAUGHT ${NC}  %-40s %s\n" "$name" "$error"
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  RESULTS"
echo "────────────────────────────────────────"
echo ""
printf "  Total tests:       %d\n" "$TOTAL"
printf "  ${GREEN}Caught:            %d${NC} (compiler stopped the vulnerability)\n" "$CAUGHT"
printf "  ${RED}Shipped:           %d${NC} (vulnerability would reach production)\n" "$COMPILED"
echo ""

if [ $TOTAL -gt 0 ]; then
    pct=$((CAUGHT * 100 / TOTAL))
    printf "  Catch rate:        ${GREEN}%d%%${NC}\n" "$pct"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  INTERPRETATION"
echo "────────────────────────────────────────"
echo ""
echo "  'SHIPPED' = this code compiles in Loon. If an AI agent wrote it,"
echo "  the vulnerability reaches production unless a human catches it."
echo ""
echo "  'CAUGHT' = the Loon compiler rejected this code. The AI agent"
echo "  gets a structured error and must fix the vulnerability before"
echo "  the code can ship."
echo ""
echo "  Programs without privacy types (plain String for passwords)"
echo "  compile because Loon's privacy system is opt-in at the type"
echo "  level. An AI agent must USE Sensitive<String> to get protection."
echo ""
echo "  Programs WITH privacy types that still try to log sensitive"
echo "  data are caught — the compiler enforces what the type promises."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
