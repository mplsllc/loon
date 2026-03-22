# Contributing to Loon

## Quick Start

```bash
git clone https://github.com/mplsllc/loon.git
cd loon
./build.sh
LOON_COMPILER=./loon ./gauntlet/run.sh
```

If the gauntlet shows 74/74 pass, 0 failures — you're ready.

## Project Structure

```
loon/
├── stage0/             Assembly lexer (1,198 lines)
├── stage1/             Assembly compiler (6,542 lines)
├── stage2/
│   ├── compiler.loon   The Loon compiler in Loon (~2,800 lines)
│   └── loon-bootstrap-linux-x86_64   Bootstrap binary
├── gauntlet/
│   ├── run.sh          Test runner
│   └── tests/          74 test files across 6 categories
├── examples/           Example Loon programs
├── spec/               Language specification
├── docs/               Documentation
├── tools/
│   ├── lsp/            Language server (Python)
│   ├── vscode/         VS Code extension
│   └── pkg/            Package manager
└── packages/
    └── crypto/         First official package
```

## Building

```bash
# Quick build (uses bootstrap binary)
./build.sh

# Full build from assembly (for verification)
./build.sh --full
```

## Running Tests

```bash
# Full gauntlet (74 tests)
LOON_COMPILER=./loon ./gauntlet/run.sh

# Single test
./loon gauntlet/tests/effect/pure_calls_print.loon
# Should produce: error: undeclared effect...
```

## Self-Hosting Verification

The compiler compiles itself. After any change to `stage2/compiler.loon`:

```bash
./loon stage2/compiler.loon > /tmp/a.asm
nasm -f elf64 -o /tmp/a.o /tmp/a.asm && ld -o /tmp/loon_new /tmp/a.o
/tmp/loon_new stage2/compiler.loon > /tmp/b.asm
diff /tmp/a.asm /tmp/b.asm  # must be empty — fixed point
```

If the diff is not empty, iterate one more self-compile until it stabilizes.

## Making Changes

1. **Write the test first.** Add a `.loon` file to `gauntlet/tests/` with the header format:
   ```loon
   // TEST: my_test_name
   // EXPECT: ERROR           (or COMPILES OK, exit N)
   // CATEGORY: type          (effect, type, scope, exhaustive, structural, privacy, edge)
   module test;
   // ... test code ...
   ```

2. **Make the change** in `stage2/compiler.loon`.

3. **Build and verify:**
   ```bash
   ./build.sh
   LOON_COMPILER=./loon ./gauntlet/run.sh
   ```

4. **Update the bootstrap binary** if the change affects the bootstrap chain:
   ```bash
   cp loon stage2/loon-bootstrap-linux-x86_64
   ```

## What NOT to Change

- `stage0/` and `stage1/` — the assembly seed is frozen. Only change for critical bug fixes.
- `spec/loon-0-spec.md` — the bootstrap subset spec is historical.
- The MPLS License — the values are not negotiable.

## Code Style

- Function names: `snake_case`, prefixed by file abbreviation (`ll_` for LLVM, `cg_` for NASM, `tc_` for type checker)
- Variables: `prefix_descriptive_name` (e.g., `lm_arm` for ll_match's arm variable)
- `g[]` slots: document in the slot map at the top of `compiler.loon`
- One function per concern. Keep functions under 30 lines where possible.
- No `arr[i] = fn_call()` — use `g[]` slots instead (known codegen limitation)

## License

All contributions must be under the [MPLS License](LICENSE). By submitting a pull request, you agree to license your contribution under these terms.

The MPLS License prohibits use for surveillance, weapons, oppression, and manipulation. Contributions that enable these uses will not be accepted.
