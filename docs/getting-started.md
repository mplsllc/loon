# Getting Started with Loon

Write your first Loon program in 15 minutes. By the end, you'll see the compiler catch a security violation that every other language misses.

## 1. Install the compiler

### Linux (x86-64)

```bash
# Install NASM
sudo apt install nasm

# Build the Loon compiler from source
git clone https://github.com/mplsllc/loon.git
cd loon
cd stage0 && make && cd ../stage1 && make && cd ..
./stage0/lexer stage2/compiler.loon | ./stage1/compiler > /tmp/loon.asm
nasm -f elf64 -o /tmp/loon.o /tmp/loon.asm
ld -o loon /tmp/loon.o
```

You now have a `loon` binary. Move it somewhere on your PATH:

```bash
sudo mv loon /usr/local/bin/
```

### macOS / Windows / WebAssembly

See [Building from Source](building.md) for LLVM-based cross-platform compilation.

## 2. Hello world

Create `hello.loon`:

```loon
module main;

fn main() [IO] -> Unit {
    do print("Hello, Loon!");
    do exit(0);
}
```

Compile and run:

```bash
loon hello.loon > hello.asm
nasm -f elf64 -o hello.o hello.asm
ld -o hello hello.o
./hello
```

Output: `Hello, Loon!`

**What you just saw:**
- `module main;` — every Loon file declares a module
- `fn main() [IO] -> Unit` — the main function declares `[IO]` effects and returns `Unit`
- `do print(...)` — `do` is required for calling functions with effects
- `do exit(0)` — explicit exit with code 0

## 3. Functions and effects

```loon
module math;

fn add(a: Int, b: Int) [] -> Int {
    a + b
}

fn main() [IO] -> Unit {
    let result: Int = add(10, 32);
    do print(int_to_string(result));
    do exit(0);
}
```

**The effect system:** `add` declares `[]` — no effects. It's a pure function. It cannot call `print`, `exit`, or any IO function. The compiler verifies this:

```loon
fn bad() [] -> Int {
    do print("side effect!");  // COMPILE ERROR
    42
}
```

```
error: undeclared effect: function bad uses IO but declares []
```

Pure functions are guaranteed safe to call anywhere. The compiler proves it.

## 4. Types and ADTs

Loon has algebraic data types with exhaustive pattern matching:

```loon
module shapes;

type Shape {
    Circle(radius: Int),
    Rectangle(width: Int, height: Int),
    Point,
}

fn area(s: Shape) [] -> Int {
    match s {
        Circle(r) -> r * r,
        Rectangle(w, h) -> w * h,
        Point -> 0,
    }
}

fn main() [IO] -> Unit {
    let c: Shape = Circle(5);
    do print(int_to_string(area(c)));
    do exit(0);
}
```

Miss a variant and the compiler tells you:

```loon
fn bad(s: Shape) [] -> Int {
    match s {
        Circle(r) -> r * r,
        // missing Rectangle and Point!
    }
}
```

```
error: non-exhaustive match
```

## 5. Privacy types — this is why Loon exists

Here's where it gets interesting. Loon has privacy-aware types that the compiler enforces:

```loon
module auth;

fn main() [IO] -> Unit {
    let username: Public<String> = "alice";
    let password: Sensitive<String> = "hunter2";

    do print("User: " + username);     // ✓ Public values can be logged
    // do print("Pass: " + password);  // ✗ COMPILE ERROR
    do exit(0);
}
```

Uncomment the second print and compile:

```
error: cannot log Sensitive value — use expose() with audit context
```

**This is not a warning. This is not a linter. The type system makes it impossible.**

Try to sneak the password out through a variable:

```loon
let raw: String = password;
// error: cannot assign Sensitive value to less restrictive type — use expose()
```

Pass it to a function that doesn't expect sensitive data:

```loon
fn log_it(msg: String) [IO] -> Unit { do print(msg); }
do log_it(password);
// error: cannot pass Sensitive value to less restrictive parameter — use expose()
```

The compiler blocks every path. The only way through is the escape hatch.

## 6. The escape hatch: expose()

When you genuinely need to cross the privacy boundary, `expose()` lets you — but it requires declaring the `[Audit]` effect and providing a reason:

```loon
module auth;

fn show_hint(pw: Sensitive<String>) [IO, Audit] -> Unit {
    let visible: Public<String> = expose(pw, "user requested password hint");
    do print(visible);
}

fn main() [IO, Audit] -> Unit {
    let pw: Sensitive<String> = "hunter2";
    do show_hint(pw);
    do exit(0);
}
```

This compiles. The `expose()` call writes the reason to stderr as an audit record. The password is now `Public<String>` and can be printed.

Three things happened:
1. The caller declared `[Audit]` — visible in every call chain
2. A reason string was required — documents why the exposure happened
3. An audit record was written — impossible to suppress at runtime

The unsafe path is possible. But it's visible, documented, and audited.

## 7. ZeroOnDrop

Sensitive values that shouldn't linger in memory:

```loon
fn use_key() [IO] -> Unit {
    let key: Sensitive<String, ZeroOnDrop> = "encryption_key_256";
    // ... use the key ...
    // key is zeroed from memory when this function returns
}
```

The compiler emits zeroing instructions at every scope exit. The key doesn't survive past its usefulness.

## What's next

- **[Language Specification](../spec/loon-spec.md)** — every keyword, operator, and type
- **[Privacy Type Design](../spec/privacy-type-system-notes.md)** — the full privacy type system design
- **[Building from Source](building.md)** — all platforms including LLVM and WebAssembly
- **[Examples](../examples/)** — real Loon programs including the calculator and loon call
- **[Bootstrap Story](../BOOTSTRAP.md)** — how the language was built from bare metal assembly
