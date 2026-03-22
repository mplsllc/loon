# Validation Programs — Gap Analysis

Written before any Stage 4 code. These programs are the spec made executable.
Every gap identified here must be resolved before Stage 4 is complete.

## Gap List

### Builtins needed (not yet implemented)
- `hash_password(Sensitive<String>) -> Hashed<String>` — programs 1, 2
- `verify_password(Sensitive<String>, Hashed<String>) -> Bool` — program 2
- `generate_token() -> Sensitive<String>` — program 3
- `expose(Sensitive<T>, String) -> Public<T>` — program 4
- `encrypt(Sensitive<String>, Sensitive<String>) -> Encrypted<String>` — program 5

### Effects needed (not yet implemented)
- `Crypto` — programs 1, 2, 3, 5
- `Audit` — program 4

### Type features needed
- `Sensitive<String>` parsing — all programs
- `Public<String>` parsing — programs 4, 6
- `Hashed<String>` parsing — programs 1, 2
- `Encrypted<String>` parsing — program 5
- Privacy level enforcement on print — programs 1, 3, 5
- Privacy level enforcement on function args — program 6
- `expose()` returning Public<T> — program 4

### Observations

1. **Program 4 simplified.** Original spec had `card.last_four` which needs string slicing.
   Simplified to `expose(card, "reason")` which returns the full value as Public.
   String slicing can be added later as `string_slice` builtin.

2. **Program 5 simplified.** `transmit(encrypted)` removed — the type safety is proven
   by the `encrypt()` call returning `Encrypted<String>`. Actual network I/O is Stage 5.

3. **Program 6 uses function arg types for enforcement.** `log_login(pw, true)` should
   fail because `pw: Sensitive<String>` doesn't match `username: Public<String>`.
   This is the S4.2 downcast check applied to function arguments — same as S3.6's
   `tc_check_args` but comparing privacy levels, not just base types.

4. **All programs are natural.** No workarounds needed. The syntax reads like what a
   developer would write. The safe path IS the easy path.

## Milestone Coverage

| Program | S4.0 | S4.1 | S4.2 | S4.3 | S4.4 | S4.5 |
|---------|------|------|------|------|------|------|
| 1. store_password | parse | log check | — | — | — | crypto |
| 2. verify_password | parse | — | — | — | — | crypto |
| 3. session_token | parse | log check | — | — | — | crypto |
| 4. partial_card | parse | — | — | expose | — | — |
| 5. encrypted_payload | parse | log check | — | — | — | crypto |
| 6. audit_log | parse | — | arg check | — | — | — |
