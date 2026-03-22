# Loon Privacy Type Guide

## Why privacy types exist

Every data breach follows the same pattern: sensitive data ends up somewhere it shouldn't. A password in a log file. An API key in an error message. A social security number in an analytics event.

The developer didn't intend to leak the data. The code reviewer didn't catch it. The linter didn't flag it. The data leaked because nothing in the system enforced the constraint "this value must not be logged."

Loon makes that constraint part of the type system. `Sensitive<String>` is not `String`. The compiler treats them as different types. Operations that are safe for `String` (logging, serialization, display) are compile errors for `Sensitive<String>`.

## The privacy levels

Every value in Loon has a privacy level. The default is Raw (unclassified).

| Level | Type Syntax | Meaning |
|-------|-------------|---------|
| Raw | `String` | Default. No privacy restrictions. |
| Public | `Public<String>` | Explicitly safe to log, display, transmit. |
| Sensitive | `Sensitive<String>` | Cannot be logged. Cannot be downcast. |
| ZeroOnDrop | `Sensitive<String, ZeroOnDrop>` | Like Sensitive, plus zeroed from memory at scope exit. |
| Hashed | `Hashed<String>` | Output of a hash function. Not reversible. |
| Encrypted | `Encrypted<String>` | Encrypted payload. Safe to transmit. |

Privacy levels form a hierarchy. Values can be upgraded (Raw → Sensitive) freely. Downgrades (Sensitive → Raw) require the `expose()` escape hatch.

## Rule 1: Cannot log Sensitive values

```loon
fn bad() [IO] -> Unit {
    let pw: Sensitive<String> = "hunter2";
    do print(pw);  // COMPILE ERROR
}
```

```
error: cannot log Sensitive value — use expose() with audit context
```

This applies to `print()` and `print_raw()`. There is no way to make a Sensitive value printable without going through `expose()`.

## Rule 2: Cannot downcast Sensitive values

```loon
fn bad() [IO] -> Unit {
    let pw: Sensitive<String> = "hunter2";
    let raw: String = pw;  // COMPILE ERROR
}
```

```
error: cannot assign Sensitive value to less restrictive type — use expose()
```

This also applies to function arguments:

```loon
fn log_it(msg: String) [IO] -> Unit { do print(msg); }

fn bad() [IO] -> Unit {
    let pw: Sensitive<String> = "hunter2";
    do log_it(pw);  // COMPILE ERROR
}
```

```
error: cannot pass Sensitive value to less restrictive parameter — use expose()
```

Upcasting is always safe:

```loon
let raw: String = "hello";
let safe: Sensitive<String> = raw;  // OK — upgrading is always allowed
```

## Rule 3: The escape hatch — expose()

When you genuinely need to cross the privacy boundary:

```loon
fn show_hint(pw: Sensitive<String>) [IO, Audit] -> Unit {
    let visible: Public<String> = expose(pw, "user requested password hint");
    do print(visible);  // OK — it's Public now
}
```

`expose()` requires three things:
1. The caller must declare the `[Audit]` effect
2. A reason string must be provided (documents why the exposure happened)
3. An audit record is written to stderr at runtime

The `[Audit]` effect propagates through the call chain — every function in the chain must declare it. This means the audit trail is visible in the type signature of every function that participates in an exposure.

### expose() on non-Sensitive values is an error

```loon
fn bad(s: String) [IO, Audit] -> Unit {
    let p: Public<String> = expose(s, "not sensitive");  // COMPILE ERROR
}
```

```
error: expose() argument must be Sensitive — only use with Sensitive values
```

## Rule 4: ZeroOnDrop

For values that shouldn't linger in memory after use:

```loon
fn use_key() [IO] -> Unit {
    let key: Sensitive<String, ZeroOnDrop> = "encryption_key_256";
    // ... use the key ...
}  // key is zeroed from memory here
```

The compiler emits zeroing instructions at every scope exit for ZeroOnDrop variables. This is not a garbage collector hint — it's a deterministic instruction in the generated machine code.

Use ZeroOnDrop for:
- Passwords
- Encryption keys
- Session tokens
- API keys
- Any value that shouldn't survive past its immediate use

## Rule 5: Forbidden algorithms

Certain cryptographic algorithms are known to be broken. Loon doesn't provide them:

```loon
let h: String = md5("data");   // COMPILE ERROR: forbidden algorithm
let h: String = sha1("data");  // COMPILE ERROR: forbidden algorithm
```

```
error: forbidden algorithm — MD5 is broken, not available in Loon
```

The forbidden list: MD5, SHA1, DES, RC4.

Use instead:
- Password hashing: `hash_password()` (Argon2id)
- Data integrity: SHA-256, SHA-512
- Encryption: AES-256

## The crypto package

```loon
// hash_password takes Sensitive, returns Hashed — types enforce the contract
fn hash_password(password: Sensitive<String>) [IO] -> Hashed<String>

// verify_password compares Sensitive against Hashed — returns plain Bool
fn verify_password(password: Sensitive<String>, hash: Hashed<String>) [IO] -> Bool

// generate_token returns Sensitive + ZeroOnDrop — auto-zeroed when done
fn generate_token() [IO] -> Sensitive<String, ZeroOnDrop>
```

## The design principle

**Make the safe path easy. Make the unsafe path possible but visible.**

```
Safe operation       → just works, no extra syntax
Sensitive operation  → works, requires explicit acknowledgment
Dangerous operation  → works, leaves mandatory audit trail
Prohibited operation → compile error, no escape hatch
```

The unsafe path is not impossible. It's visible, documented, and audited. This is intentional — every language that makes the unsafe path impossible eventually fails because reality is more complex than the type system anticipated.

## Worked example: authentication

```loon
module auth;

fn authenticate(pw: Sensitive<String>) [IO] -> Bool {
    let hash: Hashed<String> = hash_password(pw);
    let stored: Hashed<String> = load_stored_hash();
    verify_password(hash, stored)
}

fn main() [IO] -> Unit {
    let pw: Sensitive<String> = read_password();
    let ok: Bool = authenticate(pw);
    do print(match ok { true -> "Access granted", false -> "Access denied" });
    // do print(pw);  ← COMPILE ERROR: cannot log Sensitive value
}
```

The happy path compiles without friction. The dangerous path doesn't compile. The developer doesn't need to remember to not log the password — the type system remembers for them.
