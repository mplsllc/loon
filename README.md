<p align="center">
  <img src="web/media/aquilalogomedium.png" alt="Aquila" height="72">
</p>

<p align="center">
  <strong>A security-first programming language where the compiler catches what AI agents forget to check.</strong>
</p>

<p align="center">
  <a href="https://aquila-lang.org">Website</a> · <a href="https://aquila-lang.org/docs/getting-started">Getting Started</a> · <a href="https://aquila-lang.org/docs/reference">Reference</a> · <a href="https://aquila-lang.org/roadmap">Roadmap</a> · <a href="https://github.com/mplsllc/aquila">GitHub</a>
</p>

---

## What other languages miss

This compiles in Python, Go, TypeScript, and Rust:

```python
logging.info(f"Login attempt: user={username} password={password}")
```

This doesn't compile in Aquila:

```aquila
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

## What makes Aquila different

- **Privacy types enforced by the compiler** — `Sensitive<String>` cannot be logged, printed, or silently downcast. Not a warning. A compile error.

- **Effect verification** — every function declares what it does. `fn pure() [] -> Int` cannot call IO functions. The compiler verifies the entire call chain.

- **Exhaustive match** — every ADT variant must be handled. Missing a case is a compile error, not a runtime crash.

- **Bootstrapped from bare metal** — no borrowed toolchain. Built from x86-64 assembly. Every byte traceable.

- **Designed for AI authorship** — structured JSON errors that AI agents can parse and fix automatically.

---

## Current status

**Stages 0–4 complete.** Self-hosting compiler with privacy types, LLVM backend, WASM target.

```
Gauntlet:     78/78 tests, 0 failures, 0 known gaps
LLVM:         50/50 COMPILES OK tests pass
Platforms:    Linux, macOS (x86 + ARM), Windows, WebAssembly
Self-hosting: fixed point verified
```

**Now building Stage 5** — compiler rewrite in full Aquila, standard library, generics, closures. See the [full roadmap](https://aquila-lang.org/roadmap).

---

## Quick start

### Build from source (Linux x86-64)

```bash
git clone https://github.com/mplsllc/aquila.git && cd aquila
./build.sh
```

Or manually:

```bash
sudo apt install nasm
cd stage0 && make && cd ../stage1 && make && cd ..
./stage0/lexer stage2/compiler.aquila | ./stage1/compiler > /tmp/aquila.asm
nasm -f elf64 -o /tmp/aquila.o /tmp/aquila.asm && ld -o aquila /tmp/aquila.o
```

### Hello world

```aquila
module main;

fn main() [IO] -> Unit {
    do print("Hello, Aquila!");
    do exit(0);
}
```

```bash
./aquila hello.aquila > hello.asm
nasm -f elf64 -o hello.o hello.asm && ld -o hello hello.o
./hello
# Hello, Aquila!
```

### Privacy types in action

```aquila
module auth;

fn authenticate(password: Sensitive<String>) [IO] -> Unit {
    // do print(password);        ← COMPILE ERROR: cannot log Sensitive
    // let raw: String = password; ← COMPILE ERROR: cannot downcast

    let hint: Public<String> = expose(password, "user hint");
    // ^ requires [Audit] effect — leaves mandatory audit trail

    do print("authenticated");
}
```

### LLVM backend

```bash
./aquila --target llvm hello.aquila > hello.ll          # LLVM IR
./aquila --target llvm --arch macos hello.aquila > hello.ll   # macOS
./aquila --target llvm --arch wasm hello.aquila > hello.ll    # WebAssembly
```

---

## Language features

| Feature | Status |
|---------|--------|
| Algebraic data types | ✓ Exhaustive match checking |
| Effect system | ✓ IO, Audit, Crypto effects |
| Privacy types | ✓ Sensitive, Public, Hashed, Encrypted, ZeroOnDrop |
| LLVM backend | ✓ 5 target platforms |
| WebAssembly | ✓ WASI target, compiler runs in browser |
| Float type | ✓ IEEE 754 double precision |
| Pipe operator | ✓ `data \|> transform \|> filter` |
| String matching | ✓ `match s { "hello" -> ... }` |
| Type inference | ✓ Literal and call-site types checked |
| Division by zero | ✓ Runtime trap |
| Array bounds | ✓ Runtime trap |

**Coming in Stage 5:** Generics, closures, standard library, GC, parallel execution, FFI.

---

## The bootstrap story

```
Stage 0  Hand-written assembly lexer        1,198 lines
Stage 1  Hand-written assembly compiler     6,542 lines
Stage 2  Aquila compiler written in Aquila      self-hosting
Stage 3  LLVM backend, WASM, Float, LSP     cross-platform
Stage 4  Privacy types                      the mission
Stage 5  Compiler rewrite, stdlib, generics ← now
```

No Rust. No C. No existing language toolchain.

[Read the full bootstrap story →](https://aquila-lang.org/docs/bootstrap)

---

## Documentation

- **[Getting Started](https://aquila-lang.org/docs/getting-started)** — Write your first Aquila program in 15 minutes
- **[Language Reference](https://aquila-lang.org/docs/reference)** — Every keyword, type, and operator
- **[Effect System](https://aquila-lang.org/docs/effects)** — Why every side effect is declared
- **[Privacy Types](https://aquila-lang.org/docs/privacy-guide)** — The security type system explained
- **[Building from Source](https://aquila-lang.org/docs/building)** — All platforms
- **[Roadmap](https://aquila-lang.org/roadmap)** — What's next

---

## License

[MPLS Principled Libre Software License v1.0](LICENSE)

Free for commercial use under $1M revenue / 100K users. Prohibited uses: surveillance, weapons, oppression, manipulation.

---

## Contributing

Aquila is developed by [MPLS LLC](https://mp.ls). Contributions welcome under the [MPLS License](LICENSE).

**Website:** [aquila-lang.org](https://aquila-lang.org) · **Security:** [Report a vulnerability](https://aquila-lang.org/security)

```bash
# Run the test suite
./gauntlet/run.sh

# Self-hosting verification
./aquila stage2/compiler.aquila > /tmp/s2.asm
nasm -f elf64 -o /tmp/s2.o /tmp/s2.asm && ld -o /tmp/s2 /tmp/s2.o
/tmp/s2 stage2/compiler.aquila > /tmp/s2b.asm
diff /tmp/s2.asm /tmp/s2b.asm  # must be empty — fixed point
```
