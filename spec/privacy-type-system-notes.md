# Privacy Type System — Design Notes
## Status: Pre-specification — captured for Stage 4 planning
## Do not implement until Stage 2 is complete

These notes capture design decisions and failure modes identified
during early planning. Turn this into a full spec before Stage 4
begins. The privacy type system is the most important and most
complex feature in Loon. Getting it wrong means developers route
around it. Getting it right means the compiler is a security
engineer that never sleeps.

---

## The Core Design Principle

**Make the safe path easy. Make the unsafe path possible but visible.**

Not impossible. Visible.

Every language that makes the unsafe path impossible eventually
fails because reality is more complex than the type system
anticipated. Developers find workarounds. The workarounds become
conventions. The conventions defeat the purpose.
```
Safe operation       → just works, no extra syntax
Sensitive operation  → works, requires explicit acknowledgment  
Dangerous operation  → works, leaves mandatory audit trail
Prohibited operation → compile error, no escape hatch
```

Prohibited operations are those in the MPLS License: surveillance,
weapons, oppression. Everything else has a path — it just has to
be walked deliberately.

---

## The Type State Model

Sensitive data moves through states. The compiler tracks the state
at every point. Operations are permitted based on the current state.

### States
```
String<Raw>                    — unclassified, default
String<Public>                 — safe to log, transmit, display
String<Sensitive>              — cannot be logged, must be handled carefully
String<Sensitive, ZeroOnDrop>  — zeroed from memory when out of scope
String<Hashed<Argon2id>>       — password hash, not reversible
String<Hashed<SHA256>>         — data integrity hash (NOT for passwords)
String<Encrypted[AES256]>      — encrypted, transmittable
String<Validated>              — passed validation, safe for use as ID
```

### Permitted Transitions
```
Password (Sensitive)
    → Crypto.hash_password()  → PasswordHash (Hashed<Argon2id>)
    → Crypto.verify_password() → Bool (comparison, no new sensitive data)

Sensitive
    → Crypto.encrypt(key)     → Sensitive<Encrypted[AES256]>
    → Sensitive.expose(...)   → Public (with mandatory audit trail)

Sensitive<Encrypted[AES256]>
    → transmittable over network
    → storable to disk
    → Crypto.decrypt(key)     → Sensitive (back to raw sensitive)

Public
    → loggable
    → transmittable
    → displayable
    → returnable from API endpoints
```

### What Transitions Do NOT Exist
```
Sensitive → String (no implicit downcast)
Sensitive → loggable (ever, under any circumstance)
SHA256    → PasswordHash (wrong algorithm — different types)
MD5       → anything security-related (does not exist in Loon stdlib)
```

---

## Approved Cryptographic Operations

The standard library only exposes cryptographically sound operations.
Broken or misused algorithms do not exist.

### Password Hashing (produces PasswordHash type)
```
Crypto.hash_password(pwd: Password) [] -> PasswordHash
    — uses Argon2id internally
    — PasswordHash is not String<Hashed<SHA256>>
    — these are different types, not interchangeable

Crypto.verify_password(input: Password, stored: PasswordHash) [] -> Bool
    — timing-safe comparison built in
    — no way to call a non-timing-safe comparison
```

### Encryption (produces Encrypted type)
```
Crypto.encrypt(data: Sensitive, key: EncryptionKey<AES256>) 
    [] -> Sensitive<Encrypted[AES256]>

Crypto.decrypt(data: Sensitive<Encrypted[AES256]>, key: EncryptionKey<AES256>)
    [] -> Result<Sensitive, CryptoError>
```

### Hashing (for data integrity, NOT passwords)
```
Crypto.sha256(data: String) [] -> String<Hashed<SHA256>>
Crypto.sha512(data: String) [] -> String<Hashed<SHA512>>

// These return String<Hashed<SHA256>> — NOT PasswordHash
// Using them where PasswordHash is required is a compile error
```

### What Does Not Exist in Loon Standard Library
```
Crypto.md5()      — broken, not available
Crypto.sha1()     — broken for security use, not available
Crypto.des()      — broken, not available
Crypto.rc4()      — broken, not available
```

If a developer needs these for legacy compatibility they must
use the FFI trust boundary (see below) with explicit acknowledgment.

---

## The Escape Hatch Design

Some operations legitimately need to expose sensitive data.
These are permitted but impossible to do silently.

### Sensitive.expose()
```loon
// Exposes a sensitive value as Public
// Requires: explicit reason string
// Requires: audit context
// Effect: emits mandatory audit event — cannot be suppressed
// Returns: String<Public> — safe for logging/display

let display: String<Public> = Sensitive.expose(
    card.last_four,
    reason: "user identity confirmation during checkout",
    audit: audit_context,
);
```

The audit event is emitted by the runtime regardless of what
the calling code does afterward. You cannot call Sensitive.expose()
without leaving a record. The security reviewer finds every
exposure by querying the audit log.

### Permitted use cases for Sensitive.expose()
```
- Displaying last N digits of card/SSN for user confirmation
- Including username (but not password) in error messages
- Security audit reporting with proper authorization
- Debugging in development environments (see testing context)
```

### What Sensitive.expose() does NOT permit
```
- Logging raw passwords (reason string doesn't make this acceptable)
- Returning sensitive data in API responses without encryption
- Bypassing encryption requirements for transmission
```

The compiler knows the difference. Some patterns are rejected
even with Sensitive.expose() — the reason string makes intent
visible but does not override type safety for prohibited patterns.

---

## The Testing Context

Test code needs to inspect sensitive values to verify correctness.
Production code does not.
```loon
// Only available in test builds — compile error in production
#[test_only]
fn inspect_sensitive(value: Password) [] -> String {
    value.raw_value()
}

// Test usage
#[test]
fn test_password_hashing() [] -> Unit {
    let pwd: Password = Password.from_test_string("test_password_123");
    let hash: PasswordHash = Crypto.hash_password(pwd);
    let valid: Bool = Crypto.verify_password(pwd, hash);
    match valid {
        true -> 0,  // pass
        false -> do exit(1),  // fail
    }
}
```

`#[test_only]` functions and `#[test]` blocks are stripped from
production builds. The compiler rejects any attempt to call
test-only functions from non-test code.

`Password.from_test_string()` is a test-only constructor.
In production, passwords only come from user input via secure
input channels. You cannot construct a Password from a raw
string literal in production code.

---

## The FFI Trust Boundary

Loon integrates with external systems that don't know about
privacy types. This is permitted but requires explicit
acknowledgment.
```loon
// Declaring an external function — requires Unsafe:TrustBoundary effect
extern fn legacy_auth_store(
    data: RawBytes
) [IO, Unsafe:TrustBoundary] -> Result<(), Error>;

// Calling it — the trust boundary effect propagates
fn store_encrypted_credential(
    payload: String<Encrypted[AES256]>
) [IO, Unsafe:TrustBoundary] -> Result<(), Error> {
    let bytes: RawBytes = payload.to_bytes();
    do legacy_auth_store(bytes)
}
```

Any function with `Unsafe:TrustBoundary` in its effects:
- Appears in the audit trail
- Requires explicit acknowledgment in code review tooling
- Cannot be called from pure or standard-effect functions
  without propagating the trust boundary effect upward

The trust boundary is visible in every call chain that crosses it.
You cannot hide the fact that you're calling untrusted external code.

---

## ZeroOnDrop Semantics

Sensitive values declared with ZeroOnDrop are zeroed from memory
when they go out of scope. This is guaranteed by the runtime,
not the developer.
```loon
// Password is String<Sensitive, ZeroOnDrop>
fn authenticate(username: Username, password: Password) [IO] -> Result<Session, Error> {
    // password lives here
    let result = do verify(username, password);
    result
    // function returns — password bytes are zeroed immediately
    // not "eventually garbage collected" — immediately, guaranteed
}
```

An attacker doing a memory dump after this function returns finds
zeroed bytes where the password was. Not the password.

ZeroOnDrop applies to:
```
Password
SessionToken  
EncryptionKey
PrivateKey
Any type declared with ZeroOnDrop attribute
```

---

## The Validation Suite

Before the privacy type system ships, all six of these programs
must compile and run without workarounds. If any require fighting
the compiler the design is wrong.
```loon
// 1. Store a password securely
fn create_account(
    username: Username,
    password: Password
) [IO] -> Result<UserId, Error>

// 2. Verify a password
fn verify_login(
    input: Password,
    stored: PasswordHash
) [] -> Bool

// 3. Issue a session token
fn create_session(
    user_id: UserId
) [IO] -> Result<SessionToken, Error>

// 4. Display partial card number for confirmation
fn confirm_card_identity(
    card: CardNumber,
    audit: AuditContext
) [IO, Audit] -> String<Public>

// 5. Send encrypted payload over network
fn transmit_medical_record(
    record: MedicalRecord,
    destination: Endpoint<TLS<1.3>>
) [IO, Network, Privacy:Transmit] -> Result<(), Error>

// 6. Write audit log with context but without secrets
fn log_auth_attempt(
    username: Username,
    success: Bool,
    ip: IpAddress<Public>
) [IO, Audit] -> Unit
```

All six must compile cleanly. All six must run correctly.
Any that require workarounds indicate a design flaw to fix
before shipping.

---

## Known Design Tensions

These are unresolved questions to address during Stage 4 planning:

**1. Granularity of Sensitive**
Is `String<Sensitive>` enough or do we need
`String<Sensitive<PII>>`, `String<Sensitive<Financial>>`,
`String<Sensitive<Medical>>`? Finer granularity enables
more precise access control but increases complexity.

**2. Sensitive in collections**
`List<Password>` — does the List inherit Sensitive semantics?
What about `Map<UserId, Password>`? The collection type
needs to propagate sensitivity correctly.

**3. Partial exposure**
`card.last_four` — how does extracting a public subset of
a sensitive type work? Does CardNumber have typed fields
with different sensitivity levels? This needs a clean answer.

**4. Cross-module privacy**
When a Loon module imports from another module, how do
privacy types cross the module boundary? Does the importing
module need to declare what sensitivity levels it handles?

**5. Interop with non-Loon systems**
When a Python service calls a Loon service via HTTP, the
Python side doesn't have privacy types. How does Loon
validate that what it receives is what it expects? Input
validation at the boundary needs to be typed.

---

## References

- Conversation: privacy type system design and failure modes
- Jif: Java Information Flow — academic work on information
  flow type systems, relevant prior art
- FlowCaml: OCaml with information flow types
- Rust's type system for inspiration on ZeroOnDrop semantics
- HIPAA, PCI-DSS, GDPR as real-world compliance targets
  the type system should address

---

*Status: Notes only. Not a spec. Not implemented.*
*Revisit when Stage 2 is complete and Stage 4 planning begins.*
*The design principle is locked. The details are not.*