# Security Policy

Loon is pre-1.0. The language exists because security should be structural, not aspirational — privacy types, effect declarations, and exhaustive matching are core to the compiler, not bolted on. If any of that is broken, I want to know immediately.

## Reporting a vulnerability

Email **patrick@mplsllc.com** with:

- A description of the issue
- Steps to reproduce (a `.loon` file that triggers it is ideal)
- What you expected vs. what happened
- Any suggested fix, if you have one

Do **not** open a public GitHub issue for security vulnerabilities. Email first.

## What counts as a security issue

- Compiler bugs that allow privacy-typed data (`Sensitive<T>`, `Hashed<T>`, `Encrypted<T>`) to leak into unrestricted contexts
- Effect system bypasses — code performing IO, network, or filesystem operations without declaring the effect
- Codegen that produces unsafe x86-64 output (buffer overflows, stack corruption, arbitrary write primitives)
- Runtime trap bypasses (division by zero, out-of-bounds access not caught when it should be)
- Any path where the compiler silently accepts code that violates the spec's safety guarantees

## What does NOT count

- Feature requests — use [GitHub Issues](https://github.com/mplsllc/loon/issues)
- Non-security bugs (wrong output, crashes, bad error messages) — also GitHub Issues
- Anything in `stage0/` assembly that requires physical access or a debugger to exploit
- Disagreements about language design

## Scope

The following are in scope:

- The Loon compiler (all stages)
- The privacy type system and its enforcement
- The effect system and its enforcement
- Runtime traps and bounds checking
- Codegen correctness as it relates to memory safety

## Response timeline

I'm a solo developer. Here's what I can commit to:

- **Acknowledge your report**: within 48 hours
- **Initial assessment**: within a week
- **Critical fixes** (privacy type bypass, unsafe codegen): I'll drop what I'm doing. Aim for a fix within a week.
- **Non-critical security issues**: addressed in the next release

If I'm going to miss these timelines, I'll tell you.

## Credit

There's no bug bounty program. What I can offer is credit in the release notes and changelog. If you want to be credited under a specific name or handle, include that in your report.

## PGP

No PGP key yet. Plaintext email to patrick@mplsllc.com is fine for now.
