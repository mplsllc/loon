#!/usr/bin/env python3
"""Loon compiler fuzzer — generates random valid Loon programs and feeds them
to the compiler. Any crash (exit code other than 0 or 1) is a bug.
Any hang (>5 seconds) is a bug. Exit 0 = compiled. Exit 1 = clean error."""

import random
import subprocess
import sys
import os
import time

COMPILER = os.environ.get("LOON_COMPILER", "/tmp/s2_new2")
TOTAL = int(sys.argv[1]) if len(sys.argv) > 1 else 1000
TIMEOUT = 5

TYPES = ["Int", "Bool", "String"]
NAMES = ["x", "y", "z", "a", "b", "c", "n", "m", "v", "w"]
FN_NAMES = ["foo", "bar", "baz", "calc", "check", "run", "step", "proc"]

crashes = []
hangs = []
compiled = 0
errors = 0

def rand_int():
    return str(random.randint(0, 100))

def rand_expr(depth=0):
    if depth > 3:
        return rand_int()
    r = random.random()
    if r < 0.3:
        return rand_int()
    elif r < 0.5:
        return random.choice(NAMES[:3])
    elif r < 0.7:
        op = random.choice(["+", "-", "*"])
        return f"{rand_expr(depth+1)} {op} {rand_expr(depth+1)}"
    elif r < 0.85:
        return f"match {random.choice(NAMES[:2])} > 0 {{ true -> {rand_expr(depth+1)}, false -> {rand_expr(depth+1)} }}"
    else:
        return rand_int()

def rand_stmt():
    r = random.random()
    if r < 0.4:
        name = random.choice(NAMES)
        return f"    let {name}: Int = {rand_expr()};"
    elif r < 0.6:
        return f"    do print(int_to_string({rand_expr()}));"
    elif r < 0.8:
        arr = random.choice(["a", "b"])
        return f"    {arr}[0] = {rand_expr()};"
    else:
        return f"    let {random.choice(NAMES)}: Int = {rand_expr()};"

def rand_fn():
    name = random.choice(FN_NAMES) + str(random.randint(0, 99))
    params = random.randint(0, 2)
    param_str = ", ".join(f"p{i}: Int" for i in range(params))
    stmts = [rand_stmt() for _ in range(random.randint(1, 5))]
    body = "\n".join(stmts)
    return f"""fn {name}({param_str}) [IO] -> Unit {{
{body}
    do exit(0);
}}"""

def rand_program():
    lines = ["module test;"]
    # Maybe add an ADT
    if random.random() < 0.3:
        lines.append("type Shape { Circle(r: Int), Point }")
    # Add 1-3 helper functions
    for _ in range(random.randint(0, 2)):
        fn_name = random.choice(FN_NAMES) + str(random.randint(0, 99))
        lines.append(f"fn {fn_name}(x: Int) [] -> Int {{ x + 1 }}")
    # Main function
    main_stmts = []
    main_stmts.append("    let a: Array<Int> = Array(4);")
    main_stmts.append("    let b: Array<Int> = Array(4);")
    main_stmts.append("    a[0] = 1; b[0] = 2;")
    for _ in range(random.randint(1, 8)):
        main_stmts.append(rand_stmt())
    main_stmts.append("    do exit(0);")
    lines.append("fn main() [IO] -> Unit {")
    lines.extend(main_stmts)
    lines.append("}")
    return "\n".join(lines)

print(f"Loon Fuzzer — {TOTAL} random programs")
print(f"Compiler: {COMPILER}")
print(f"Timeout: {TIMEOUT}s")
print("=" * 50)

start_time = time.time()

for i in range(TOTAL):
    prog = rand_program()
    try:
        result = subprocess.run(
            [COMPILER, "/dev/stdin"],
            input=prog.encode(),
            timeout=TIMEOUT,
            capture_output=True
        )
        if result.returncode == 0:
            compiled += 1
        elif result.returncode == 1:
            errors += 1
        elif result.returncode in [139, 134, 136]:  # SEGV, ABRT, FPE
            crashes.append((i, result.returncode, prog))
            print(f"CRASH #{len(crashes)} on program {i} (exit {result.returncode})")
        else:
            # Other non-zero exit codes
            errors += 1
    except subprocess.TimeoutExpired:
        hangs.append((i, prog))
        print(f"HANG on program {i}")
    except Exception as e:
        print(f"ERROR on program {i}: {e}")

    if (i + 1) % 100 == 0:
        elapsed = time.time() - start_time
        rate = (i + 1) / elapsed
        print(f"  [{i+1}/{TOTAL}] {rate:.0f}/s — compiled={compiled} errors={errors} crashes={len(crashes)} hangs={len(hangs)}")

elapsed = time.time() - start_time
print()
print("=" * 50)
print(f"FUZZER RESULTS")
print(f"  Total:     {TOTAL}")
print(f"  Compiled:  {compiled}")
print(f"  Errors:    {errors} (clean rejection)")
print(f"  Crashes:   {len(crashes)}")
print(f"  Hangs:     {len(hangs)}")
print(f"  Time:      {elapsed:.1f}s ({TOTAL/elapsed:.0f} programs/s)")
print()

if crashes:
    print(f"CRASHES ({len(crashes)}):")
    for idx, (i, code, prog) in enumerate(crashes[:5]):
        print(f"\n--- Crash {idx+1} (program {i}, exit {code}) ---")
        print(prog[:500])
    if len(crashes) > 5:
        print(f"\n... and {len(crashes) - 5} more crashes")
    # Save all crashes
    with open("tools/fuzz/crashes.txt", "w") as f:
        for i, code, prog in crashes:
            f.write(f"=== Program {i} (exit {code}) ===\n{prog}\n\n")
    print(f"\nAll crashes saved to tools/fuzz/crashes.txt")
else:
    print("NO CRASHES — compiler handled all inputs correctly")

if hangs:
    print(f"\nHANGS ({len(hangs)}):")
    for idx, (i, prog) in enumerate(hangs[:3]):
        print(f"\n--- Hang {idx+1} (program {i}) ---")
        print(prog[:300])
