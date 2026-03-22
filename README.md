# Loon

**A programming language where the compiler catches what AI agents forget to check.**

Loon is built for a world where AI writes most of the code and humans describe what they want — without specifying what they don't want. The vibe coder says "connect to the database and return the user." They don't say "don't log the password, don't expose the SSN, don't leak the API key."

Loon's type system says it for them.

---

## What other languages miss

This compiles in Python, Go, TypeScript, and Rust:

```python
logging.info(f"Login attempt: user={username} password={password}")
```

This doesn't compile in Loon:

```loon
fn login(username: Public<String>, password: Sensitive<String>) [IO] -> Unit {
    do print("Login: " + username);   // ✓ Public values can be logged
    do print("Pass: " + password);    // ✗ COMPILE ERROR
}
```

```
error: cannot log Sensitive value — use expose() with audit context
```

The compiler caught what the developer forgot to say and the AI didn't know to check.

---

## What makes Loon different

- **Privacy types enforced by the compiler** — `Sensitive<String>` cannot be logged, printed, or silently downcast. Not a warning. A compile error.

- **Effect verification** — every function declares what it does to the world. `fn pure() [] -> Int` cannot call IO functions. The compiler verifies the entire call chain.

- **Exhaustive match** — every ADT variant must be handled. Missing a case is a compile error, not a runtime crash.

- **Bootstrapped from bare metal** — no borrowed toolchain. The compiler was built from x86-64 assembly with no external dependencies. Every byte traceable to a deliberate choice.

- **Designed for AI authorship** — structured JSON errors that AI agents can parse and fix. The feedback loop is a first-class feature, not an afterthought.

---

## Quick start

### Build from source (Linux x86-64)

```bash
# Prerequisites
sudo apt install nasm

# Build the compiler
cd stage0 && make && cd ../stage1 && make && cd ..
./stage0/lexer stage2/compiler.loon | ./stage1/compiler > /tmp/loon.asm
nasm -f elf64 -o /tmp/loon.o /tmp/loon.asm && ld -o loon /tmp/loon.o
```

### Hello world

```loon
// hello.loon
module main;

fn main() [IO] -> Unit {
    do print("Hello, Loon!");
    do exit(0);
}
```

```bash
./loon hello.loon > hello.asm
nasm -f elf64 -o hello.o hello.asm && ld -o hello hello.o
./hello
# Hello, Loon!
```

### The privacy example

```loon
// auth.loon
module auth;

fn authenticate(password: Sensitive<String>) [IO] -> Unit {
    // do print(password);
    // ^ error: cannot log Sensitive value

    let hint: Public<String> = expose(password, "user hint display");
    // ^ requires [Audit] effect — compile error without it

    do print("authenticated");
}

fn main() [IO] -> Unit {
    let pw: Sensitive<String> = "hunter2";
    // let raw: String = pw;
    // ^ error: cannot assign Sensitive value to less restrictive type
    do exit(0);
}
```

### LLVM backend (cross-platform)

```bash
# Compile to LLVM IR
./loon --target llvm hello.loon > hello.ll
llc --relocation-model=pic -filetype=obj hello.ll -o hello.o
gcc -no-pie hello.o -o hello

# Cross-compile for macOS
./loon --target llvm --arch macos hello.loon > hello.ll

# Compile to WebAssembly
./loon --target llvm --arch wasm hello.loon > hello.ll
```

---

## The safety gauntlet

68 tests. Zero failures. Zero known gaps.

```
$ ./gauntlet/run.sh
Pass:        68
Fail:        0
Known gaps:  0
```

Every safety claim is tested automatically on every commit:
- 9 compile-time checks (effects, types, exhaustive match, privacy)
- 2 runtime traps (division by zero, array bounds)
- 18 privacy-specific tests

---

## Language features

| Feature | Status |
|---------|--------|
| Algebraic data types | ✓ Exhaustive match checking |
| Effect system | ✓ IO, Audit, Crypto effects |
| Privacy types | ✓ Sensitive, Public, Hashed, Encrypted |
| ZeroOnDrop | ✓ Memory zeroed at scope exit |
| LLVM backend | ✓ 5 target platforms |
| WebAssembly | ✓ WASI target |
| Float type | ✓ IEEE 754 via LLVM |
| Pipe operator | ✓ `data \|> transform \|> filter` |
| String matching | ✓ `match s { "hello" -> ... }` |
| Type inference | ✓ Literal and call-site types |
| LSP server | ✓ VS Code extension |
| Package manager | ✓ `loon-pkg` with crypto package |

---

## Documentation

- **[Getting Started](docs/getting-started.md)** — Write your first Loon program in 15 minutes
- **[Building from Source](docs/building.md)** — Build instructions for all platforms
- **[Language Specification](spec/loon-spec.md)** — Complete language reference
- **[Privacy Type Design](spec/privacy-type-system-notes.md)** — Why privacy types exist and how they work
- **[Bootstrap Story](BOOTSTRAP.md)** — How Loon was built from bare metal assembly

---

## The bootstrap story

Loon was bootstrapped from x86-64 assembly in four stages:

```
Stage 0  Hand-written assembly lexer        1,198 lines
Stage 1  Hand-written assembly compiler     6,542 lines
Stage 2  Loon compiler written in Loon      self-hosting
Stage 3  LLVM backend, WASM, Float, LSP     cross-platform
Stage 4  Privacy types                      the mission
```

No Rust. No C. No existing language toolchain. Every line traceable from the first `mov` instruction to the privacy type checker that now enforces data safety at compile time.

The full story: [BOOTSTRAP.md](BOOTSTRAP.md)

---

## License

[MPLS Principled Libre Software License v1.0](LICENSE)

Free for commercial use under $1M revenue / 100K users. Prohibited uses: surveillance, weapons, oppression, manipulation. Values committed to git before code could run.

---

## Contributing

Loon is developed by [MPLS LLC](https://mp.ls). Contributions welcome under the MPLS License.

```bash
# Run the test suite
./gauntlet/run.sh

# Self-hosting verification
./loon stage2/compiler.loon > /tmp/s2.asm
nasm -f elf64 -o /tmp/s2.o /tmp/s2.asm && ld -o /tmp/s2 /tmp/s2.o
/tmp/s2 stage2/compiler.loon > /tmp/s2b.asm
diff /tmp/s2.asm /tmp/s2b.asm  # must be empty — fixed point
```

Report issues at [github.com/mplsllc/loon/issues](https://github.com/mplsllc/loon/issues).
