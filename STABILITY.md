# Loon Stability Policy

## Current Status

Loon is pre-1.0 software. It works. It self-hosts. It passes its full test
suite. It is not yet stable in the semver sense of that word.

This document describes what you can rely on today, what you cannot, and what
guarantees will exist when 1.0 ships.

## Versioning

Loon uses [Semantic Versioning](https://semver.org/) with the following
interpretation:

- **0.x.y** (now): No backwards compatibility guarantees between minor
  versions. Patch versions fix bugs without changing semantics. Minor versions
  may break your code.
- **1.0.0** (future): The language specification, privacy type system, effect
  system, and compiler error format are frozen. Breaking changes require a major
  version bump.

Until 1.0, treat every minor release as potentially breaking.

## What Is Stable Today

These components exist, work, and are tested. "Stable" here means they function
correctly against their current specifications. It does not mean their
interfaces are frozen.

**Test suite.** 68 gauntlet tests pass on every commit. CI runs the full suite
on push. If a test passes today, a regression will be caught before it ships.

**Self-hosting.** The compiler compiles itself. The bootstrap chain from x86-64
assembly through Stage 1 to the self-hosted compiler is intact and reproducible.

**Privacy type system.** `Public<T>`, `Sensitive<T>`, `Hashed<T>`, and
`Encrypted<T>` privacy wrapper types are enforced at compile time. The compiler
rejects code that leaks sensitive data through logging or implicit downcast. The
forbidden-algorithm checks in the crypto package are operational.

**Effect system.** Effect declarations (`[IO]`, `[Audit]`, `[Crypto]`) are
tracked and enforced. Functions that perform effects must declare them. The
compiler catches undeclared effects.

**Exhaustive match.** Pattern matching requires exhaustive coverage. The
compiler rejects incomplete match expressions.

**Structured errors.** The compiler emits JSON-formatted errors with source
location, error code, and fix suggestion. Tooling can parse these
programmatically.

**Null safety.** There is no null. `Option<T>` is the only way to represent
absence. This is a permanent design decision, not subject to change.

## What Is Not Stable

**Syntax.** The concrete syntax of Loon may change before 1.0. Keyword names,
operator precedence, and expression forms are all subject to revision. If you
write Loon code today, expect to update it.

**Standard library.** There is no standard library yet. Built-in functions
exist for bootstrapping (`print`, `int_to_string`, `string_concat`, `read_file`)
but a designed, documented stdlib has not been built.

**Module system.** The module system exists and functions but its final form is
not decided. Import syntax and visibility rules may change.

**Error codes.** The structured error format is stable in shape (JSON with
defined fields), but specific error codes and messages may change.

**Compiler CLI.** Command-line flags and invocation patterns may change. The
current pipeline (`lexer input.loon | compiler > output.asm`) reflects the
bootstrap architecture and will evolve.

**Performance.** No optimization work has been done. The compiler prioritizes
correctness. Performance improvements will come, but no benchmarks are published
and none should be expected yet.

## Platform Support

**Linux x86-64 (native).** This is the primary target. The bootstrap compiler
emits x86-64 assembly directly. This platform receives the most testing and is
the only platform with the full bootstrap chain.

**macOS, Windows, WebAssembly (LLVM backend).** The LLVM IR backend enables
these targets. They are functional but receive less testing than the native
Linux target. Platform-specific bugs should be expected and reported.

## The 1.0 Commitment

When Loon reaches 1.0, the following guarantees will apply:

1. **Language specification is frozen.** Code that compiles under 1.0 will
   compile under all 1.x releases with identical semantics.

2. **Privacy types are permanent.** The privacy type system is a core design
   commitment. It will not be weakened, removed, or made optional.

3. **Effect system is permanent.** Effect tracking will not be removed or made
   optional. New effects may be added in minor versions.

4. **Error format is stable.** The JSON error format will maintain backwards
   compatibility. New fields may be added; existing fields will not be removed
   or change meaning.

5. **Deprecation before removal.** No feature will be removed in a minor
   release. Deprecated features will emit compiler warnings for at least one
   minor version before removal in a major version.

## Breaking Changes Before 1.0

Breaking changes are communicated through:

- **Release notes.** Every release that changes behavior documents what changed
  and why.
- **Changelog.** A running changelog tracks all changes with migration guidance
  where applicable.
- **Git tags.** Every release is tagged. If you depend on a specific version,
  pin to a tag.

There is no deprecation cycle before 1.0. Changes ship when they are ready.
The project is small enough that this is manageable. If it becomes unmanageable,
the policy will be revised before the community needs it.

## Reporting Issues

If you find a case where the compiler accepts code it should reject, or rejects
code it should accept, that is a bug. File it. Privacy type violations that
escape the compiler are treated as security-critical bugs.

## License

Loon is released under the MPLS Principled Libre Software License.
See [LICENSE](LICENSE) for terms.

---

*This document is maintained by MPLS LLC. Last updated: 2026-03-22.*
